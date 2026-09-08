    MACRO EspSend Text
    ld hl, .txtB
    ld e, (.txtE - .txtB)
    call Wifi.espSend
    jr .txtE
.txtB 
    db Text
.txtE 
    ENDM

    MACRO EspCmd Text
    ld hl, .txtB
    ld e, (.txtE - .txtB)
    call Wifi.espSend
    jr .txtE
.txtB 
    db Text
    db 13, 10 
.txtE
    ENDM

    MACRO EspCmdOkErr text
    EspCmd text
    call Wifi.checkOkErr
    ENDM

    module Wifi

; ============================================
; UART lock (prevents contention with UI.checkAsyncWifi)
; ============================================
uartLock:
    ld a, 1
    ld (uart_busy), a
    ret

uartUnlock:
    xor a
    ld (uart_busy), a
    ret

; Config constants (MAX_NETWORKS, MAX_SSID_LEN, BUFFER_* defined in main.asm)
MAX_RETRIES     = 3           ; Init retries
SCAN_FRAMES     = 30 * 50     ; Whole scan deadline at 50 Hz
SCAN_GAP_FRAMES = 2 * 50      ; End a raw capture after UART silence
SCAN_RX_SIZE    = 12000       ; Existing parser hard limit
JOIN_FRAMES     = 20 * 50     ; ESP default join can take 15 seconds
    IFDEF AY
FLUSH_SILENCE   = 1           ; AY probe already waits ~4.5ms
    ELSE
FLUSH_SILENCE   = 10000
    ENDIF

checkConnection:
    xor a
    ld (connected_bssid_valid), a
    call flushInput

    ; Wake up ESP and consume full response.
    ; This avoids stray "OK" bytes remaining in RX and contaminating the next query.
    ld hl, S_AT : call espSendZCheckOk
    ret c
    call flushInput

    ; Try different query variants for maximum AT firmware compatibility
    ld hl, S_AT_CWJAP_Q : call espSendZ_CRLF
    call .waitCwJAP
    jr nc, .connected

    call flushInput
    ld hl, S_AT_CWJAP_CUR : call espSendZ_CRLF
    call .waitCwJAP
    jr nc, .connected

    call flushInput
    ld hl, S_AT_CWJAP_DEF : call espSendZ_CRLF
    call .waitCwJAP
    jr nc, .connected

    ; SSID query failed — return CF=1 without clearing state
    ; (callers decide whether to mark disconnected)
    scf
    ret

.connected
    ; SSID found — update state
    ld a, 1
    ld (is_connected), a
    ret

; ============================================
; .waitCwJAP
;   Waits for a +CWJAP... line and extracts SSID.
;   Returns: CF=0 if connected (SSID extracted), CF=1 otherwise.
; ============================================
.waitCwJAP
    xor a
    ld (connected_bssid_valid), a
    ld (use_long_timeout), a
    ld hl, 1024
    ld (byte_limit), hl
    ld b, 8                      ; allow several initial timeouts
.loop
    push bc
    call readReplyStart
    pop bc
    jr c, .got
    djnz .loop
    scf
    ret

.got
    jr z, .plusFound
    cp 'N' : jr z, .noAP
    cp 'E' : jr z, .errorLine
    cp 'O' : jr z, .okLine
    jp .discardLine

.okLine
    ; OK can appear (e.g., from a previous command). Do not treat it as definitive.
    call .flushToLF
    jr .loop

.errorLine
    ; ERROR can also be stale. Ignore and keep waiting for +CWJAP / No AP.
    call .flushToLF
    jr .loop

.noAP
    ; Consume rest of line ("No AP")
    call .flushToLF
    scf
    ret

.plusFound
    ; Expect CWJAP (possibly with _CUR/_DEF suffix).
    ; All ".fail" jumps use jp nc (3 B) instead of jr nc (2 B): the block
    ; is long enough that future edits could trip jr's ±127 B limit.
    cp 'C' : jp nz, .discardLine
    call .readCwJAPByte : jp nc, .fail
    cp 'W' : jp nz, .discardLine
    call .readCwJAPByte : jp nc, .fail
    cp 'J' : jp nz, .discardLine
    call .readCwJAPByte : jp nc, .fail
    cp 'A' : jp nz, .discardLine
    call .readCwJAPByte : jp nc, .fail
    cp 'P' : jp nz, .discardLine

    ; Accept ':' directly, or skip suffix until ':'
.readUntilColon
    call .readCwJAPByte : jp nc, .fail
    cp ':' : jr z, .afterColon
    jr .readUntilColon

.afterColon
    ; Find opening quote
.findQuote
    call .readCwJAPByte : jp nc, .fail
    cp '"' : jr nz, .findQuote

    ; Read and unescape SSID until closing quote (bounded)
    ld hl, connected_ssid
    ld b, MAX_SSID_LEN
.readSSID
    call .readCwJAPByte : jp nc, .clearRejectedSSID
    cp #5C : jr z, .readSSIDescape
    cp '"' : jr z, .gotSSID
    cp 13 : jr z, .rejectSSID
    cp 10 : jr z, .rejectSSID
.storeSSID
    ld (hl), a
    inc hl
    djnz .readSSID

    ; Buffer full: only accept if the very next char closes the quote
.waitClosingQuote
    call .readCwJAPByte : jp nc, .clearRejectedSSID
    cp '"' : jr z, .gotSSID
    jr .rejectSSID

.readSSIDescape
    call .readCwJAPByte : jp nc, .clearRejectedSSID
    call isSSIDescape
    jr z, .storeSSID
.rejectSSID
    ; Drop malformed/overlong names without consuming the next line.
    cp 10 : jr z, .clearRejectedSSID
    call .flushToLF
.clearRejectedSSID
    xor a
    ld (connected_ssid), a
    ld (connected_bssid_valid), a
    scf
    ret

.gotSSID
    xor a
    ld (hl), a
    ld (connected_bssid_valid), a
    ; Current firmware follows SSID with the selected BSSID. Older or
    ; malformed replies still establish SSID state with unknown identity.
    call .readCwJAPByte
    jr nc, .finishConnected
    cp ',' : jr nz, .finishConnected
    call .readCwJAPByte
    jr nc, .finishConnected
    cp '"' : jr nz, .finishConnected
    ld hl, connected_bssid
    ld b, 6
.readBssid
    call .readCwJAPByte
    jr nc, .finishConnected
    call loadList.hexNibble
    jr nc, .finishConnected
    rlca
    rlca
    rlca
    rlca
    ld c, a
    call .readCwJAPByte
    jr nc, .finishConnected
    call loadList.hexNibble
    jr nc, .finishConnected
    or c
    ld (hl), a
    inc hl
    djnz .bssidSeparator
    call .readCwJAPByte
    jr nc, .finishConnected
    cp '"' : jr nz, .finishConnected
    ld a, 1
    ld (connected_bssid_valid), a
    jr .finishConnected
.bssidSeparator
    call .readCwJAPByte
    jr nc, .finishConnected
    cp ':' : jr z, .readBssid
.finishConnected
    call .flushToLF
    ld a, (Uart.io_error)
    and a
    jr nz, .clearRejectedSSID
    ret

.fail
    scf
    ret

.discardLine
    call .flushToLF
    jp .loop

.readCwJAPByte
    jp readResponseByte

.flushToLF
    jp flushReplyLine

; Drain UART until silence (capped at 1024 bytes to prevent lockup)
; Flush until sustained silence (NextSync flush_uart_hard pattern)
flushInput:
    ld bc, 2048               ; Hard byte cap — bail if ESP sends continuous garbage
    ld de, FLUSH_SILENCE       ; Sustained silence counter
.flushLoop
    push bc, de
    call UartImpl.uartRead
    pop de, bc
    jr nc, .flushQuiet
    ; Byte received — reset silence timer, decrement hard cap
    ld de, FLUSH_SILENCE
    dec bc
    ld a, b : or c
    jr nz, .flushLoop
    jr .flushDone             ; Cap exhausted — bail to prevent infinite hang
.flushQuiet
    dec de
    ld a, d : or e
    jr nz, .flushLoop
.flushDone
    xor a
    ld (Uart.io_error), a
    ret

; Exit transparent mode (+++, guard time, flush)
; Safe to call even if ESP is not in transparent mode.
exitTransparent:
    EspSend "+++"
    ld b, 75               ; ~1.5s guard time
.etp_wait
    halt
    djnz .etp_wait
    call flushInput         ; Discard response (may be "NO CHANGE" etc.)
    ; +++ keeps the socket in passthrough receive mode. Normalize framing
    ; without closing the socket or changing persistent configuration.
    ld hl, S_AT_CIPMODE_NORMAL
    call espSendZCheckOk
    jp flushInput

init:
    call flushInput

    ; Reset old-firmware flag so SYSSTORE probe re-runs on every init
    ; (WPS recovery, ESP hot-swap, etc.)
    xor a
    ld (old_fw), a

    ld a, MAX_RETRIES
    ld (retry_count), a

.retryReset
    call reset
    jr nc, .resetOk
    
    ld a, (retry_count)
    dec a
    ld (retry_count), a
    jr z, .resetFailed
    
    ld b, 100
.retryWait
    halt
    djnz .retryWait
    jr .retryReset

.resetFailed
    scf
    ret
    
.resetOk
    ld hl, S_ATE0 : call espSendZCheckOk
    ld hl, S_AT_SYSSTORE : call espSendZCheckOk
    jr c, .oldFwDetect
    ld hl, S_AT_CWMODE : call espSendZCheckOk
    jr .checkMode

.oldFwDetect
    ld a, 1
    ld (old_fw), a
    ld hl, S_AT_CWMODE_DEF : call espSendZCheckOk

.checkMode
    jr c, .err
    ld hl, S_AT_CWAUTOCONN : call espSendZCheckOk
    jr c, .err
    ; Optional on old firmware; defaults already contain these five fields.
    ld hl, S_AT_CWLAPOPT : call espSendZCheckOk
    ld a, (Uart.io_error)
    and a
    jr nz, .err
    ret

.err
    ld hl, .err_msg
    call Display.putStrLog
    ld b, 100
.wait_err
    halt
    djnz .wait_err
    ei                  
    scf                 
    ret
.err_msg db 13, "ESP error!", 0

reset:
    call flushInput     

    ld hl, S_AT : call espSendZCheckOk
    jr c, .timeout_err
    ld hl, S_AT_RST : call espSendZ_CRLF

    ld a, (Uart.io_error)
    and a
    jr nz, .timeout_err

    IFDEF NEXT
    jp UartImpl.recoverAfterReset
    ELSE
    ; Bounded number of readTimeout misses while waiting for "ready"
    ld de, 200
    ld bc, 4096
.loop
    call readBcTimeout
    jr nc, .check_timeout
    
    cp 'r' : jr nz, .loop
    call readBcTimeout : jr nc, .timeout_err
    cp 'e' : jr nz, .loop
    call readBcTimeout : jr nc, .timeout_err
    cp 'a' : jr nz, .loop
    call readBcTimeout : jr nc, .timeout_err
    cp 'd' : jr nz, .loop
    call readBcTimeout : jr nc, .timeout_err
    cp 'y' : jr nz, .loop
    or a                
    ret

.check_timeout
    dec de
    ld a, d
    or e
    jr nz, .loop
    ENDIF
.timeout_err
    ld hl, .timeout_msg
    call Display.putStrLog
    scf
    ret
.timeout_msg db 13, "ESP timeout!", 0

readBcTimeout:
    ld a, b
    or c
    ret z
    call Uart.readTimeout
    ret nc
    dec bc
    scf
    ret

getList:
    ; Failure returns A=1 for BREAK cancellation, A=0 otherwise.
    call uartLock
    ld hl, (#5C78)
    ld (scan_started), hl
    call flushInput
    ld hl, 12000
    ld (byte_limit), hl

    ; Runtime capture RAM is undefined and may contain an old response.
    ld hl, scan_rx_buffer
    ld de, scan_rx_buffer + 1
    ld bc, SCAN_RX_SIZE - 1
    xor a
    ld (hl), a
    ldir
    ld (scan_overflow), a
    ld hl, scan_rx_buffer
    ld (scan_rx_read), hl
    ld (scan_rx_write), hl
    ; Don't clear buffers yet — preserve old data until scan succeeds
    xor a
    ld (seen_cwlap), a
    ld (Uart.break_hit), a

    ; Try extended scan with longer dwell time per channel
    ld a, 1
    ld (scan_extended), a
    ld hl, S_AT_CWLAP_EXT : call espSendZ_CRLF
    ; fall through to loadList
    jr loadList

; Reset scan pointers + count ONLY. Old SSID bytes remain in buffer but
; are masked by networks_count; as new APs arrive they overwrite slot 0,
; 1, ... If the scan fails partway, partial data shows (better than the
; previous behavior of wiping old data on first +CWLAP, which left the
; list empty on mid-scan timeout).
resetScanPointers:
    ld hl, buffer
    ld (buff_ptr), hl
    ld hl, rssi_buffer
    ld (rssi_ptr), hl
    ld hl, ecn_buffer
    ld (ecn_ptr), hl
    ld hl, channel_buffer
    ld (chan_ptr), hl
    ld hl, bssid_buffer
    ld (bssid_ptr), hl
    ld hl, ssid_ptr_table
    ld (ssid_table_ptr), hl
    ld hl, bssid_buffer
    ld de, bssid_buffer + 1
    ld bc, BSSID_STATE_SIZE - 1
    xor a
    ld (hl), a
    ldir
    ld (networks_count), a
    ret

; Full wipe: LDIR-clear SSID buffer + reset pointers. Used only on the
; confirmed 0-networks success path (OK with no +CWLAP).
clearScanBuffers:
    ld hl, buffer
    ld de, buffer + 1
    ld bc, BUFFER_SIZE - 1
    xor a
    ld (hl), a
    ldir
    jr resetScanPointers

loadList:
.waitFirstResponse
    call .readScan
    jr c, .gotFirstChar
    ld a, (Uart.break_hit)
    and a
    jp nz, .scanCancelled
    call .scanBudgetLeft
    jr c, .waitFirstResponse
    jp .scanTimeout             ; No response after timeout
    
.gotFirstChar
.dispatchChar
    cp '+' : jr z, .plusStart
    cp 'O' : jr z, .okStart
    cp 'E' : jp z, .errStart
    cp 13  : jr z, loadList          ; CR — back to long timeout
    cp 10  : jr z, loadList          ; LF — back to long timeout
    jr .continueLoad

.continueLoad
    call .readScan
    jp nc, .scanTimeout
    jr .dispatchChar

.plusStart
    call .readScan : jp nc, .scanTimeout
    cp 'C' : jr nz, loadList
    call .readScan : jp nc, .scanTimeout
    cp 'W' : jr nz, loadList
    call .readScan : jp nc, .scanTimeout
    cp 'L' : jr nz, loadList
    ; First +CWLAP: reset pointers only (don't wipe buffer). Old SSID
    ; bytes beyond networks_count stay put; new APs overwrite from slot 0.
    ; On mid-scan timeout, partial new data is shown instead of a wipe.
    ld a, (seen_cwlap)
    and a
    jr nz, .skipClear
    call resetScanPointers
.skipClear
    ld a, 1
    ld (seen_cwlap), a
    jp .loadAp

.okStart
    call .readScan : jp nc, .scanTimeout
    cp 'K' : jr nz, loadList
    call .readScan : jp nc, .scanTimeout
    cp 13  : jp nz, loadList

    ; OK received. If +CWLAP lines were seen, scan is complete.
    ld a, (seen_cwlap)
    and a
    jr nz, .okReturn

    ; No +CWLAP. If extended scan, firmware may not support the params
    ; (older ESP returns OK with no results instead of ERROR).
    ; Fall back to basic AT+CWLAP immediately instead of waiting.
    ld a, (scan_extended)
    and a
    jr z, .okReturn             ; Basic scan: OK w/o +CWLAP == 0 networks
    jr .basicScanFallback

.okReturn
    ; If OK arrived without any +CWLAP, clear old data (0-result scan)
    ld a, (seen_cwlap)
    and a
    jr nz, .okAlreadyClear
    call clearScanBuffers
.okAlreadyClear
    call initDisplayIndices     ; Initialize display indices
    call sortNetworks           ; Auto-sort by RSSI
    jp uartUnlock

.errStart
    call .readScan : jr nc, .scanTimeout
    cp 'R' : jp nz, loadList
    call .readScan : jr nc, .scanTimeout
    cp 'R' : jp nz, loadList
    call .readScan : jr nc, .scanTimeout
    cp 'O' : jp nz, loadList
    call .readScan : jr nc, .scanTimeout
    cp 'R' : jp nz, loadList
    ; Extended scan not supported? Fallback to basic AT+CWLAP
    ld a, (scan_extended)
    and a
    jr z, .scanFail
.basicScanFallback
    xor a
    ld (scan_extended), a
    ld (seen_cwlap), a
    call flushInput
    ld hl, 12000
    ld (byte_limit), hl
    ld hl, scan_rx_buffer
    ld (scan_rx_read), hl
    ld (scan_rx_write), hl
    ld hl, S_AT_CWLAP : call espSendZ_CRLF
    jp loadList

.scanFail
    ld hl, .scanErrMsg
    call Display.putStrLog
    jr .finishPartialScan
.scanErrMsg db 13, "Scan fail!", 0

.scanTimeout
    ld a, (Uart.io_error)
    and a
    jr z, .scanTimeoutClean
    call flushInput
    call clearScanBuffers
    jr .scanFail
.scanTimeoutClean
    ld a, (scan_overflow)
    and a
    jr z, .scanTimeoutNormal
    call flushInput
    call clearScanBuffers
    jr .scanFail
.scanTimeoutNormal
    ld a, (Uart.break_hit)
    and a
    jp nz, .scanCancelled
    ld hl, .timeout_msg
    call Display.putStrLog
.finishPartialScan
    call .finalizePartialScan
    jp uartUnlockFail
.timeout_msg db 13, "Scan timeout!", 0

.scanCancelled
    call .finalizePartialScan
    call uartUnlock
    inc a                       ; A=1 distinguishes BREAK from failure
    scf
    ret

.finalizePartialScan
    ld a, (seen_cwlap)
    and a
    ret z
    call initDisplayIndices
    jp sortNetworks

.loadAp
    ld a, (networks_count)
    cp MAX_NETWORKS
    jr c, .skipToEcn
    ; Flush rest of line before returning (prevents desync)
.flushMax
    call .readScan
    jr nc, .scanTimeout
    cp 10
    jr nz, .flushMax
    jp loadList

.skipToEcn
    call .readScan : jr nc, .scanTimeout
    cp '(' : jr nz, .skipToEcn
    
    call .readScan : jr nc, .scanTimeout
    sub '0'
    ; Save ECN to its own buffer and also to rssi_ptr (open flag, overwritten later)
    ld hl, (ecn_ptr)
    ld (hl), a
    ld hl, (rssi_ptr)
    ld (hl), a

.findQuote
    call .readScan : jp nc, .scanTimeout
    cp '"' : jr nz, .findQuote

    ld de, (buff_ptr)
    ld hl, (ssid_table_ptr)
    ld (hl), e
    inc hl
    ld (hl), d
    ld b, MAX_SSID_LEN

.loadName
    call .readScan : jp nc, .scanTimeout
    cp #5C : jr z, .loadNameEscape
    cp '"' : jr z, .loadedName
    cp 13 : jr z, .rejectName
    cp 10 : jr z, .rejectName
.storeName
    ld (de), a
    inc de
    djnz .loadName

.waitNameQuote
    call .readScan : jp nc, .scanTimeout
    cp '"' : jr z, .loadedName
    jr .rejectName

.loadNameEscape
    call .readScan : jp nc, .scanTimeout
    call isSSIDescape
    jr z, .storeName
.rejectName
    cp 10 : jp z, loadList
.flushRejectedName
    call .readScan : jp nc, .scanTimeout
    cp 10 : jr nz, .flushRejectedName
    jp loadList

.loadedName
    xor a
    ld (de), a : inc de : ld (buff_ptr), de

.findRssi
    call .readScan : jp nc, .scanTimeout
    cp ',' : jr nz, .findRssi
    
    call .readScan : jp nc, .scanTimeout
    cp '-' : jr nz, .skipRssi   
    
    ld de, 0            
.readRssiDigit
    call .readScan : jp nc, .scanTimeout
    cp '0' : jr c, .rssiDone
    cp '9'+1 : jr nc, .rssiDone
    
    sub '0'
    ld b, a
    ld a, e
    add a, a            
    ld e, a
    add a, a            
    add a, a            
    add a, e            
    add a, b            
    ld e, a
    jr .readRssiDigit

.skipRssi
    ld e, 99            
.rssiDone
    ld hl, (rssi_ptr)
    ld a, (hl)          
    and a
    ld a, e
    jr nz, .notOpen
    or #80              
.notOpen
    ld (hl), a

    ; Capture a normalized six-byte BSSID. Nonstandard fields remain unique.
    call .readScan : jp nc, .scanTimeout
    cp '"' : jr nz, .invalidMac
    ld hl, bssid_temp
    ld b, 6
.readMac
    call .readScan : jp nc, .scanTimeout
    call .hexNibble
    jp nc, .invalidMac
    rlca
    rlca
    rlca
    rlca
    ld c, a
    call .readScan : jp nc, .scanTimeout
    call .hexNibble
    jp nc, .invalidMac
    or c
    ld (hl), a
    inc hl
    djnz .macSeparator
    call .readScan : jp nc, .scanTimeout
    cp '"' : jr nz, .invalidMac
    ld a, 1
    ld (mac_valid), a
    jr .validMac
.macSeparator
    call .readScan : jp nc, .scanTimeout
    cp ':' : jr z, .readMac
.invalidMac
    push af
    xor a
    ld (mac_valid), a
    ld a, #FF
    ld (bssid_temp), a
    pop af
    cp ',' : jr z, .macDone
.skipMac
    call .readScan : jp nc, .scanTimeout
    cp ',' : jr nz, .skipMac
    jr .macDone
.validMac
    call .readScan : jp nc, .scanTimeout
    cp ',' : jp nz, loadList
.macDone

    ; Parse channel number (1-14)
    ld e, 0
.readChanDigit
    call .readScan : jp nc, .scanTimeout
    cp '0' : jr c, .chanDone
    cp '9'+1 : jr nc, .chanDone
    sub '0'
    ld b, a
    ld a, e
    add a, a            ; x2
    ld e, a
    add a, a            ; x4
    add a, a            ; x8
    add a, e            ; x10
    add a, b            ; x10 + digit
    ld e, a
    jr .readChanDigit
.chanDone
    ld a, e
.saveChannel
    ld hl, (chan_ptr)
    ld (hl), a

    call .deduplicate
    jp c, loadList

    ; Commit all parallel arrays only after the BSSID is known unique.
    ld hl, bssid_temp
    ld de, (bssid_ptr)
    ld bc, 6
    ldir
    ld (bssid_ptr), de
    ld hl, (ssid_table_ptr)
    inc hl
    inc hl
    ld (ssid_table_ptr), hl
    ld hl, (rssi_ptr)
    inc hl
    ld (rssi_ptr), hl
    ld hl, (ecn_ptr)
    inc hl
    ld (ecn_ptr), hl
    ld hl, (chan_ptr)
    inc hl
    ld (chan_ptr), hl
    ld hl, networks_count
    inc (hl)
    jp loadList

.hexNibble
    or #20
    sub '0'
    cp 10
    ret c
    sub 'a' - '0' - 10
    cp 16
    ret

; CF=1 when this exact normalized BSSID is already committed.
.deduplicate
    ld a, (mac_valid)
    and a
    jr z, .uniqueBssid
    ld a, (networks_count)
    ld c, a
    and a
    jr z, .uniqueBssid
    ld hl, bssid_buffer
.nextBssid
    push hl
    ld de, bssid_temp
    ld b, 6
.compareBssid
    ld a, (de)
    cp (hl)
    jr nz, .differentBssid
    inc de
    inc hl
    djnz .compareBssid
    pop hl
    ld hl, (ssid_table_ptr)
    ld e, (hl)
    inc hl
    ld d, (hl)
    ld (buff_ptr), de
    scf
    ret
.differentBssid
    pop hl
    ld de, 6
    add hl, de
    dec c
    jr nz, .nextBssid
.uniqueBssid
    or a
    ret

.readScan
    push bc, de, hl
    call .scanBudgetLeft
    jr nc, .readScanFail
    ld hl, (scan_rx_read)
    ld de, (scan_rx_write)
    or a
    sbc hl, de
    jr nz, .haveCaptured
    call .captureBurst
    jr nc, .readScanFail
.haveCaptured
    ld hl, (scan_rx_read)
.captured
    ld a, (hl)
    inc hl
    ld (scan_rx_read), hl
    push af
    ld hl, (byte_limit)
    dec hl
    ld (byte_limit), hl
    ld a, (Uart.log_enabled)
    and a
    jr z, .scanLogDone
    pop af
    push af
    call Uart.log_char
.scanLogDone
    pop af
    pop hl, de, bc
    scf
    ret
.readScanFail
    pop hl, de, bc
    or a
    ret

; Capture at wire speed, then let the parser work from RAM after a quiet gap.
.captureBurst
    ld hl, scan_rx_buffer
    ld (scan_rx_read), hl
    ld (scan_rx_write), hl
    ld (.capturePtr), hl
    xor a
    ld (silence_started), a
.captureLoop
    call UartImpl.uartRead
    jr c, .captureByte
    ld a, (Uart.io_error)
    and a
    ret nz
    call Keyboard.checkBreak
    jr nz, .captureNotCancelled
    ld a, 1
    ld (Uart.break_hit), a
    or a
    ret
.captureNotCancelled
    call .scanBudgetLeft
    ret nc
    ld hl, (.capturePtr)
    ld de, scan_rx_buffer
    or a
    sbc hl, de
    jr z, .captureLoop
    ld a, (silence_started)
    and a
    jr nz, .checkSilence
    inc a
    ld (silence_started), a
    ld hl, (#5C78)
    ld (silence_frame), hl
    jr .captureLoop
.checkSilence
    ld hl, (#5C78)
    ld de, (silence_frame)
    or a
    sbc hl, de
    ld de, SCAN_GAP_FRAMES
    or a
    sbc hl, de
    jr c, .captureLoop
    ld hl, (.capturePtr)
    ld (scan_rx_write), hl
    scf
    ret

.captureByte
    ld hl, 0
.capturePtr = $ - 2
    ld (hl), a
    inc hl
    ld a, l
    cp low (scan_rx_buffer + SCAN_RX_SIZE)
    jr nz, .captureMore
    ld a, h
    cp high (scan_rx_buffer + SCAN_RX_SIZE)
    jr z, .captureFull
.captureMore
    ld (.capturePtr), hl
    ; Check cancellation/deadline once per 256 ready bytes. The common path
    ; remains below one 115200-baud frame on UNO.
    ld a, l
    and a
    jr nz, .captureFast
    call Keyboard.checkBreak
    jr z, .captureCancelled
    call .scanBudgetLeft
    ret nc
.captureFast
    xor a
    ld (silence_started), a
    jr .captureLoop
.captureCancelled
    ld a, 1
    ld (Uart.break_hit), a
    or a
    ret
.captureFull
    ld (.capturePtr), hl
    ld (scan_rx_write), hl
    ld a, 1
    ld (scan_overflow), a
    ld (Uart.io_error), a
    or a
    ret

.scanBudgetLeft
    ld hl, (byte_limit)
    ld a, h
    or l
    ret z
    ld hl, (#5C78)
    ld de, (scan_started)
    or a
    sbc hl, de
    ld de, SCAN_FRAMES
    or a
    sbc hl, de
    ret

espSend:
    ld a, (Uart.io_error)
    and a
    ret nz
    ld a, (hl)
    push hl, de
    call Uart.write
    pop de, hl
    inc hl
    dec e
    jr nz, espSend
    ret

; espSendZCheckOk - Send Z-terminated string + check OK/ERROR
; Input: HL = pointer to Z-terminated AT command (with CRLF)
espSendZCheckOk:
    call espSendZ_CRLF
    jp checkOkErr

; Send Z-string then CR/LF (complete AT commands)
espSendZ_CRLF:
    call espSendZ
sendCRLF:
    ld a, 13
    call Uart.write
    ld a, 10
    jp Uart.write

espSendZ:
    ; TX log only when debug enabled (protects passwords sent in parts)
    ld a, (debug_log)
    and a
    jr z, .sendLoop
    push hl
    call logTxMasked
    pop hl
.sendLoop
    ld a, (Uart.io_error)
    and a
    ret nz
    ld a, (hl) : and a : ret z
    push hl
    call Uart.write
    pop hl
    inc hl
    jr .sendLoop

; ============================================
; espSendQuotedZ - Send Z-string inside an already open AT quote.
; Escapes quote, comma and backslash for ESP-AT quoted parameters.
espSendQuotedZ:
    ld a, (Uart.io_error)
    and a
    ret nz
    ld a, (hl)
    and a
    ret z
    call isSSIDescape
    jr nz, .send
.escape
    push hl
    push af
    ld a, #5C
    call Uart.write
    pop af
    call Uart.write
    pop hl
    inc hl
    jr espSendQuotedZ
.send
    push hl
    call Uart.write
    pop hl
    inc hl
    jr espSendQuotedZ

isSSIDescape:
    cp '"'
    ret z
    cp ','
    ret z
    cp #5C
    ret

; logTxMasked
;   HL -> Z-terminated command string (usually includes CR/LF)
;   Logs to on-screen UART log as:
;       >> <command>
;   but masks AT+CWJAP payload.
; ============================================
logTxMasked:
    push hl
    ld hl, dbg_prefix
    call Display.putStrLog
    pop hl

    ; Check prefix "AT+CWJAP" (8 chars)
    push hl
    ld de, S_AT_CWJAP_Q
    ld b, 8
.chk
    ld a, (hl)
    ld c, a
    ld a, (de)
    cp c
    jr nz, .notCw
    inc hl
    inc de
    djnz .chk
    pop hl
    ; If this is a query (AT+CWJAP? / _CUR? / _DEF?), suppress TX log to avoid spam.
    push hl
    ld b, 16
.qscan
    ld a, (hl)
    cp '?' : jr z, .skipLog
    cp '=' : jr z, .doMask
    cp 13  : jr z, .doMask
    inc hl
    djnz .qscan
.doMask
    pop hl
    ld hl, dbg_tx_cwjap
    jp Display.putStrLog
.skipLog
    pop hl
    ret
.notCw
    pop hl
    jp Display.putStrLog

dbg_prefix       db ">> ", 0
dbg_tx_cwjap     db "AT+CWJAP=<hidden>", 13, 10, 0
dbg_rx_ok       db "<< OK", 13, 10, 0
dbg_rx_error    db "<< ERROR", 13, 10, 0
dbg_rx_fail     db "<< FAIL", 13, 10, 0


; checkOkErr - Uses normal timeout
REPLY_OK      = 0
REPLY_ERROR   = 1
REPLY_TIMEOUT = 2
REPLY_UART    = 3
REPLY_BREAK   = 4
REPLY_FAIL    = 5

checkOkErr:
    xor a
    ld (use_long_timeout), a
    jr checkOkErrCommon

; checkOkErrLong - Uses long timeout for AT+CWJAP
checkOkErrLong:
    ld hl, (#5C78)
    ld (joinBudgetLeft.started), hl
    ld a, 1
    ld (use_long_timeout), a
    ; Fall through

checkOkErrCommon:
    xor a
    ld (last_error), a
    ld (Uart.break_hit), a
    ld a, REPLY_TIMEOUT
    ld (reply_status), a
    call uartLock
    ; Byte limit to prevent infinite loop with network traffic
    ld hl, 4096
    ld (byte_limit), hl

.mainLoop
    call readReplyStart
    jp nc, .timeout
    jp z, .plusStart
    cp 'O' : jr z, .okStart
    cp 'E' : jr z, .errStart
    cp 'F' : jp z, .failStart
    call flushReplyLine
    jr nc, .timeout
    jr .mainLoop

.timeout
    ld a, (Uart.break_hit)
    and a
    ld a, REPLY_BREAK
    jr nz, .failed
    ld a, (Uart.io_error)
    and a
    ld a, REPLY_TIMEOUT
    jr z, .failed
    ld a, 5
    ld (last_error), a
    ld a, REPLY_UART
.failed
    ld (reply_status), a
    jp uartUnlockFail

.okStart
    ld hl, dbg_rx_ok + 4
    ld e, REPLY_OK
    jr .terminal
.errStart
    ld hl, dbg_rx_error + 4
    ld e, REPLY_ERROR
    jr .terminal
.failStart
    ld hl, dbg_rx_fail + 4
    ld e, REPLY_FAIL
.terminal
    ; Match the remaining word and CRLF using the existing log text.
    push hl
    call .matchSuffix
    pop hl
    jp nc, .timeout
    jp nz, .discardLine
    ld a, (Uart.io_error)
    and a
    jp nz, .timeout
    ld bc, -4
    add hl, bc
    ld a, e
    ld (reply_status), a
    and a
    jr z, .logOk
    ld a, (last_error)
    and a
    jr nz, .negativeLog
    ld a, 6
    ld (last_error), a
.negativeLog
    call logIfEnabled
    jp uartUnlockFail
.logOk
    call logIfEnabled
    jp uartUnlock

.discardLine
    call flushReplyLine
    jp nc, .timeout
    jp .mainLoop

; Detect +CWJAP:X error codes
.plusStart
    cp 'C' : jr nz, .discardLine
    ld hl, .cwjapSuffix
    call .matchSuffix
    jp nc, .timeout
    jr nz, .discardLine
    ; Read error code (1-4)
    call readResponseByte : jp nc, .timeout
    sub '0'                     ; ASCII to number
    ld (last_error), a          ; Store error code
    call flushReplyLine
    jp nc, .timeout
    jp .mainLoop                ; Keep waiting for ERROR/FAIL

; CF=0: read failed; CF=1/Z=0: mismatch; CF=1/Z=1: full suffix.
.matchSuffix
    ld a, (hl)
    and a
    jr z, .matched
    ld c, a
    call readResponseByte
    ret nc
    cp c
    jr nz, .matched
    inc hl
    jr .matchSuffix
.matched
    scf
    ret
.cwjapSuffix db "WJAP:", 0

; Read one in-progress response byte with the interbyte timeout.
readResponseByte:
    push bc, de, hl
    ld hl, (byte_limit)
    ld a, h
    or l
    jr z, .fail                 ; Limit reached
    ld a, (use_long_timeout)
    and a
    jr z, .read
    call joinBudgetLeft
    jr nc, .fail
.read
    call Uart.readTimeout
    jr nc, .fail
    push af
    ld hl, (byte_limit)
    dec hl
    ld (byte_limit), hl
    pop af
    pop hl, de, bc
    scf
    ret
.fail
    pop hl, de, bc
    or a
    ret

; Between complete lines, repeat bounded interbyte polls within the same
; absolute operation budget.
readLongResponseByte:
    push bc, de, hl
.retry
    ld hl, (byte_limit)
    ld a, h
    or l
    jr z, .fail
    call readResponseByte
    jr c, .success
    ld a, (Uart.break_hit)
    ld hl, Uart.io_error
    or (hl)
    jr nz, .fail
    call joinBudgetLeft
    jr c, .retry
.fail
    pop hl, de, bc
    or a
    ret
.success
    pop hl, de, bc
    scf
    ret

joinBudgetLeft:
    ld hl, (#5C78)
    ld de, 0
.started = $ - 2
    or a
    sbc hl, de
    ld de, JOIN_FRAMES
    or a
    sbc hl, de
    ret

; Return the first byte of a complete non-payload line. Z=1 means a '+' line
; and A is the byte after '+'. Framed +IPD payloads are consumed by length.
readReplyStart:
.wait
    ld a, (use_long_timeout)
    and a
    jr nz, .long
    call readResponseByte
    jr .got
.long
    call readLongResponseByte
.got
    ret nc
    cp 13 : jr z, .wait
    cp 10 : jr z, .wait
    cp '+' : jr z, .plus
.plain
    ld d, a
    or 1                         ; NZ marks an ordinary line
    ld a, d
    scf
    ret

.plus
    call readResponseByte : ret nc
    cp 'I' : jr nz, .plusResult
    call readResponseByte : ret nc
    cp 'P' : jr nz, .dropLine
    call readResponseByte : ret nc
    cp 'D' : jr nz, .dropLine
    call readResponseByte : ret nc
    cp ',' : jr nz, .ipdFail
    call readReplyNumber : ret nc
    ld d, b
    ld e, c                      ; First field: length or link ID
    cp ':' : jr z, .useFirst
    cp 13 : jr z, .wait
    cp 10 : jr z, .wait
    cp ',' : jr nz, .ipdFail
    call readReplyNumber
    jr c, .secondNumber
    ret z
    ld b, d                      ; Quoted/non-decimal peer address: single mode
    ld c, e
    jr .findColon
.secondNumber
    cp ':' : jr z, .skipPayload  ; Multiplexed form
    cp 13 : jr z, .wait          ; Passive receive notification
    cp 10 : jr z, .wait
    cp ',' : jr z, .findColon    ; Multiplexed form with peer info
    ld b, d                      ; Single connection with peer info
    ld c, e
    jr .findColon
.useFirst
    ld b, d
    ld c, e
    jr .skipPayload
.findColon
    cp ':' : jr z, .skipPayload
    call readResponseByte : ret nc
    cp 13 : jr z, .ipdFail
    cp 10 : jr z, .ipdFail
    jr .findColon
.skipPayload
    ld a, b
    or c
    jp z, .wait
.skipByte
    call readResponseByte : ret nc
    dec bc
    ld a, b
    or c
    jr nz, .skipByte
    jp .wait

.ipdFail
    or a
    ret

.dropLine
    call flushReplyLine
    jp .wait
.plusResult
    ld d, a
    xor a                        ; Z marks a non-IPD '+' response
    ld a, d
    scf
    ret

; Parse an unsigned decimal field. Returns BC=value, A=delimiter.
readReplyNumber:
    push de
    ld bc, 0
    ld e, 0
.digit
    call readResponseByte
    jr nc, .fail
    cp '0'
    jr c, .done
    cp '9' + 1
    jr nc, .done
    sub '0'
    ld e, 1
    ld h, b
    ld l, c
    add hl, hl
    add hl, hl
    add hl, bc
    add hl, hl
    ld b, h
    ld c, l
    add a, c
    ld c, a
    jr nc, .noCarry
    inc b
.noCarry
    call .withinLimit
    jr z, .digit
.fail
    pop de
    xor a                        ; Z/NC distinguishes an invalid field
    ret
.done
    ld h, a
    ld a, e
    and a
    ld a, h
    pop de
    jr z, .noDigits
    scf
    ret
.noDigits
    ld h, a
    or 1                         ; NZ/NC lets caller classify peer info
    ld a, h
    ret
.withinLimit
    ld a, b
    cp high (2048)
    jr c, .valid
    ret nz
    ld a, c
    and a
    ret
.valid
    xor a
    ret

flushReplyLine:
    call readResponseByte
    ret nc
    cp 10
    jr nz, flushReplyLine
    scf
    ret

; Variables in printer buffer (set before each use, no init needed)
use_long_timeout = #5B18
byte_limit       = #5B19    ; dw
last_error       = #5B1B    ; 0=none/timeout, 1-4=CWJAP, 5=UART, 6=AT rejection
reply_status     db REPLY_TIMEOUT ; Complete result of checkOkErr[Long].

; ============================================
; getIP - Gets the current ESP IP address
; Output: ip_buffer, CF=0 success, CF=1 error
; ============================================
getIP:
    call uartLock
    ; Clear buffer first
    ld hl, ip_buffer
    ld b, 17
    xor a
.clear
    ld (hl), a
    inc hl
    djnz .clear

    ld hl, S_AT_CIFSR : call espSendZ_CRLF
    xor a
    ld (use_long_timeout), a
    ld hl, 4096
    ld (byte_limit), hl
.loop
    call readReplyStart
    jr nc, .timeout
    jr nz, .discardLine
    cp 'C' : jr nz, .discardLine
    ld hl, .staIpSuffix
    call checkOkErrCommon.matchSuffix
    jr nc, .timeout
    jr nz, .discardLine
    ld hl, ip_buffer
    ld b, 16                    ; IP char limit
.copyIpLoop
    push hl
    push bc
    call readResponseByte
    pop bc
    pop hl
    jr nc, .timeout
    cp '"' : jr z, .finishIP
    and a : jr z, .timeout       ; Embedded NUL must not shorten validation
    ld (hl), a
    inc hl
    djnz .copyIpLoop
    jr .timeout                 ; IPv4 is at most 15 characters
.finishIP
    xor a
    ld (hl), a
    ; A parsed field is not complete until CIFSR's terminal OK is consumed.
    call checkOkErr
    jr c, .timeout
    ld hl, ip_buffer
    call UI.validateIP.fromHL
    jr c, .noIP
    ; An unspecified station address is not usable.
    ld a, (ip_buffer)
    cp '0'
    jr nz, .ok
    ld a, (ip_buffer + 1)
    cp '.'
    jr z, .noIP
.ok
    jp uartUnlock
.discardLine
    call flushReplyLine
    jr .loop
.staIpSuffix db "IFSR:STAIP,\"", 0
.timeout
.noIP
    jp uartUnlockFail

; ============================================
; getConnectionInfo - Query IP, gateway, netmask, MAC
;   Fills: ip_buffer (from CIFSR), ci_gateway, ci_netmask (from CIPSTA),
;          ci_mac (from CIFSR)
;   Graceful fallback: fields left empty if query fails
; ============================================
getConnectionInfo:
    call uartLock

    ; Clear all connection info buffers (69 contiguous RTVAR bytes)
    xor a
    ld hl, ip_buffer
    ld de, ip_buffer + 1
    ld bc, 68
    ld (hl), a
    ldir

    ; --- Phase 1: AT+CIFSR for IP + MAC ---
    call flushInput
    ld hl, S_AT_CIFSR : call espSendZ_CRLF
    ld bc, 500                  ; Byte limit

.cifrLoop
    call readBcTimeout : jr nc, .cifrDone

    ; Look for 'M' (start of MAC,"...)
    cp 'M' : jr nz, .cifrNotM
    call readBcTimeout : jr nc, .cifrDone
    cp 'A' : jr nz, .cifrLoop
    call readBcTimeout : jr nc, .cifrDone
    cp 'C' : jr nz, .cifrLoop
    ; Skip to opening quote
.cifrFindQ
    call readBcTimeout : jr nc, .cifrDone
    cp '"' : jr nz, .cifrFindQ
    ; Copy MAC until closing quote
    ld hl, ci_mac
    ld d, 17                    ; Max MAC chars (aa:bb:cc:dd:ee:ff)
.cifrCopyMac
    call readBcTimeout : jr nc, .cifrMacDone
    cp '"' : jr z, .cifrMacDone
    ld (hl), a : inc hl
    dec d : jr nz, .cifrCopyMac
.cifrMacDone
    xor a : ld (hl), a
    jr .cifrLoop

.cifrNotM
    ; Also catch STAIP for ip_buffer (reuse existing parser logic)
    cp 'P' : jr nz, .cifrLoop
    call readBcTimeout : jr nc, .cifrDone
    cp ',' : jr nz, .cifrLoop
    call readBcTimeout : jr nc, .cifrDone
    cp '"' : jr nz, .cifrLoop
    ; Copy IP
    ld hl, ip_buffer
    ld d, 16
.cifrCopyIP
    call readBcTimeout : jr nc, .cifrIPDone
    cp '"' : jr z, .cifrIPDone
    ld (hl), a : inc hl
    dec d : jr nz, .cifrCopyIP
.cifrIPDone
    xor a : ld (hl), a
    jr .cifrLoop

.cifrDone
    call flushInput

    ; --- Phase 2: AT+CIPSTA? / AT+CIPSTA_CUR? for gateway + netmask ---
    ld hl, S_AT_CIPSTA : call espSendZ_CRLF
    call .parseCipsta
    jr nc, .ciDone              ; Success

    ; Fallback: try _CUR variant
    call flushInput
    ld hl, S_AT_CIPSTA_CUR : call espSendZ_CRLF
    call .parseCipsta
    ; Ignore result — if both fail, buffers stay empty

.ciDone
    call flushInput
    jp uartUnlock

; Parse +CIPSTA response: look for gateway:"..." and netmask:"..."
; Output: CF=0 if at least gateway found, CF=1 if not
.parseCipsta
    ld bc, 600                  ; Byte limit
.pcLoop
    call readBcTimeout : jr nc, .pcFail

    ; Look for 'g' (gateway) or 'n' (netmask) or 'O' (OK = done)
    cp 'O' : jr z, .pcOk
    cp 'g' : jr z, .pcGateway
    cp 'n' : jr z, .pcNetmask
    jr .pcLoop

.pcGateway
    ; Skip to opening quote
.pcGwQ  call readBcTimeout : jr nc, .pcFail
    cp '"' : jr nz, .pcGwQ
    ld hl, ci_gateway
    jr .pcCopy

.pcNetmask
    ; Skip to opening quote
.pcNmQ  call readBcTimeout : jr nc, .pcFail
    cp '"' : jr nz, .pcNmQ
    ld hl, ci_netmask
    ; Fall through to .pcCopy

.pcCopy
    ld d, 16                    ; Max IP-like string length
.pcCopyLoop
    call readBcTimeout : jr nc, .pcCopyDone
    cp '"' : jr z, .pcCopyDone
    ld (hl), a : inc hl
    dec d : jr nz, .pcCopyLoop
.pcCopyDone
    xor a : ld (hl), a
    jr .pcLoop

.pcOk
    ; Check if gateway was found
    ld a, (ci_gateway)
    and a
    jr z, .pcFail
    or a                        ; CF=0
    ret
.pcFail
    scf
    ret

S_AT_CIPSTA     db "AT+CIPSTA?", 0
S_AT_CIPSTA_CUR db "AT+CIPSTA_CUR?", 0

; ============================================
; ensureCommandMode
;   Best-effort attempt to ensure the ESP is in AT command mode.
;   1) Send AT and expect OK.
;   2) If not OK, send escape sequence +++ with guard times and retry AT.
;   3) Select normal framing without closing an existing socket.
;
;   Returns: CF=0 if OK received, CF=1 otherwise.
;
;   Notes:
;   - Mutes UART byte-log while sending raw +++/CRLF to avoid polluting the UART log buffer.
; ============================================
ensureCommandMode:
    ; Fast path
    call flushInput
    ld hl, S_AT : call espSendZCheckOk
    jr nc, .normalize

    ; Slow path: try to exit a possible transparent/pass-through mode
    call uartLock

    ; Optional hint in the log (only if UART log is enabled)
    ld a, (Uart.log_enabled)
    and a
    jr z, .noLog
    ld hl, .msg_escape
    call Display.putStrLog
.noLog

    ; Guard time before +++ (about 1 second)
    ld b, 50
.preGuard
    halt
    djnz .preGuard

    ; Mute UART byte log during raw escape transmission
    ld a, (Uart.log_enabled)
    push af
    xor a
    ld (Uart.log_enabled), a

    ; IMPORTANT: per ESP-AT docs, the escape sequence to quit passthrough mode
    ; is exactly three '+' characters with *no* CR/LF appended.
    ; Any extra characters around it may be forwarded as passthrough data and
    ; can also prevent the escape sequence from being recognized.
    ld a, '+'
    call UartImpl.write
    ld a, '+'
    call UartImpl.write
    ld a, '+'
    call UartImpl.write

    pop af
    ld (Uart.log_enabled), a
    call Uart.logReset

    ; Guard time after +++ (about 1 second)
    ld b, 50
.postGuard
    halt
    djnz .postGuard

    call uartUnlock

    ; Clear any response noise and retry AT
    call flushInput
    ld hl, S_AT : call espSendZCheckOk
    ret c
.normalize
    ld hl, S_AT_CIPMODE_NORMAL
    jp espSendZCheckOk

.msg_escape db 13, "-- Escape +++ (trying to exit pass-through)", 13, 10, 0

; Re-establish an explicit AT transaction boundary after a failed attempt.
prepareRetry:
    call flushInput
    ld a, 13
    call UartImpl.write
    ld a, 10
    call UartImpl.write
    ld a, (Uart.io_error)
    and a
    jr nz, .retryFailed
    call flushInput
    ld hl, S_AT
    call espSendZCheckOk
    ret nc
.retryFailed
    ld a, 5
    ld (last_error), a
    scf
    ret

; ============================================
; initDisplayIndices - Initialize indices to 0,1,2,...,n-1
; Call after each scan
; ============================================
initDisplayIndices:
    ld hl, display_indices
    xor a
.initLoop
    ld (hl), a
    inc hl
    inc a
    cp MAX_NETWORKS
    jr nz, .initLoop
    xor a
    ld (is_sorted), a
    ret

; ============================================
; sortNetworks - Toggle sort by signal strength
; If unsorted: sort indices by RSSI
; If sorted: restore original order
; ============================================
sortNetworks:
    ld a, (is_sorted)
    and a
    jr nz, .unsort
    
    ; Stable bubble sort with a shrinking bound and early exit.
    ld a, (networks_count)
    cp 2
    ret c                       ; 0 or 1 networks, nothing to sort
    
    dec a
    ld (sort_passes), a

.outerLoop
    xor a
    ld (sort_swapped), a
    ld a, (sort_passes)
    ld (sort_compares), a

    ld hl, display_indices      ; HL maintained across inner loop

.innerLoop
    ; HL = &display_indices[i] (maintained)
    ld b, (hl)                  ; B = display_indices[i]
    inc hl
    ld c, (hl)                  ; C = display_indices[i+1]

    ; Get RSSI for actual networks
    push hl                     ; Save &display_indices[i+1]
    push bc

    ; RSSI of network B
    ld hl, rssi_buffer
    ld e, b
    ld d, 0
    add hl, de
    ld a, (hl)
    and #7F
    ld d, a                     ; D = RSSI[indices[i]] & 0x7F

    ; RSSI of network C
    pop bc
    push de                     ; Save D (RSSI of i)
    ld hl, rssi_buffer
    ld e, c
    ld d, 0
    add hl, de
    ld a, (hl)
    and #7F                     ; A = RSSI[indices[i+1]] & 0x7F

    pop de                      ; D = RSSI of i

    ; Compare: if RSSI[i+1] < RSSI[i], swap indices
    cp d
    pop hl                      ; HL = &display_indices[i+1]
    jr nc, .noSwap

    ; Swap display_indices[i] and display_indices[i+1]
    ld (hl), b                  ; display_indices[i+1] = old indices[i]
    dec hl
    ld (hl), c                  ; display_indices[i] = old indices[i+1]
    inc hl                      ; Restore HL to &display_indices[i+1]
    ld a, 1
    ld (sort_swapped), a

.noSwap
    ld a, (sort_compares)
    dec a
    ld (sort_compares), a
    jr nz, .innerLoop
    
    ld a, (sort_swapped)
    and a
    jr z, .sorted
    ld hl, sort_passes
    dec (hl)
    jr nz, .outerLoop
.sorted
    ld a, 1
    ld (is_sorted), a
    ret

.unsort
    ; Restore original order
    jr initDisplayIndices

; ============================================
; getDisplayIndex - Gets actual network index
; Input: A = screen position (0-19)
; Output: A = actual network index
; ============================================
getDisplayIndex:
    ld hl, display_indices
    ld e, a
    ld d, 0
    add hl, de
    ld a, (hl)
    ret

; Input A = actual network index. Output HL = zero-terminated SSID.
getSSIDPointer:
    add a, a
    ld e, a
    ld d, 0
    ld hl, ssid_ptr_table
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
    ret

; Sort variables in printer buffer (set before use in sortNetworks)
sort_passes     = #5B0D
sort_compares   = #5B0E
is_sorted       = #5B0F
sort_swapped    = #5B15

    RTVAR display_indices, MAX_NETWORKS

; Module variables - pointers need binary init, kept in code section
buff_ptr        dw buffer
rssi_ptr        dw rssi_buffer
ecn_ptr         dw ecn_buffer
chan_ptr         dw channel_buffer
bssid_ptr        dw bssid_buffer
ssid_table_ptr   dw ssid_ptr_table

; Flags in printer buffer (all set before first read)
seen_cwlap      = #5B12
; #5B13 owned by Uart.break_hit
scan_extended   = #5B14
retry_count     = #5B16
; networks_count and is_connected migrated to RTVAR (see bottom of module):
; esxDOS rst $08 corrupts the printer buffer, and renderListAndLoop reads
; both right after Config.load/save without re-deriving them.

; In printer buffer (set by uartLock/unlock)
uart_busy       = #5B1C
; debug_log migrated to RTVAR (see bottom of module): UI.toggleDebugLog and
; multiple log-mute paths read it after esxDOS file I/O. Keeping it in the
; printer buffer risked the L indicator state surviving file ops.

; Log message if debug_log is enabled (HL = message)
logIfEnabled:
    ld a, (debug_log)
    and a
    ret z
    jp Display.putStrLog

; Unlock UART and return with CF=1 (error)
uartUnlockFail:
    call uartUnlock
    scf
    ret

    RTVAR rssi_buffer, MAX_NETWORKS
    RTVAR ecn_buffer, MAX_NETWORKS      ; Encryption type per network (0-5)
    RTVAR channel_buffer, MAX_NETWORKS  ; WiFi channel per network (1-14)
    RTVAR bssid_buffer, MAX_NETWORKS * 6
    RTVAR ssid_ptr_table, MAX_NETWORKS * 2
    RTVAR bssid_temp, 6
BSSID_STATE_SIZE = bssid_temp + 6 - bssid_buffer
    RTVAR scan_rx_buffer, SCAN_RX_SIZE
    RTVAR scan_rx_read, 2
    RTVAR scan_rx_write, 2
    RTVAR scan_started, 2
    RTVAR silence_frame, 2
    RTVAR silence_started, 1
    RTVAR scan_overflow, 1
    RTVAR mac_valid, 1
    RTVAR connected_ssid, MAX_SSID_LEN + 1
    RTVAR connected_bssid, 6
    RTVAR connected_bssid_valid, 1
    RTVAR ip_buffer, 17
    RTVAR ci_gateway, 17
    RTVAR ci_netmask, 17
    RTVAR ci_mac, 18             ; "aa:bb:cc:dd:ee:ff" + null

    ; Hot state read after esxDOS file I/O — moved out of printer buffer
    ; so divMMC rst $08 cannot corrupt it. Zero-initialised by main.asm
    ; start: before any read.
    RTVAR networks_count, 1
    RTVAR is_connected,   1
    RTVAR debug_log,      1
    RTVAR old_fw,         1

    endmodule
