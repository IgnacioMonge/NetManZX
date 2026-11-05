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
    jp UI.resetAsyncWifi        ; The transaction consumed the previous RX stream.

; Config constants (MAX_NETWORKS, MAX_SSID_LEN, BUFFER_* defined in main.asm)
MAX_RETRIES     = 3           ; Init retries
SCAN_FRAMES     = 30 * 50     ; Deadline per scan pass at 50 Hz
SCAN_GAP_FRAMES = 2 * 50      ; End a raw capture after UART silence
SCAN_RX_SIZE    = 10500       ; One pass's raw reply; ~130 rows of the longest firmware format
SCAN_BYTE_LIMIT = 12000       ; Parser hard limit per pass
; Retry the plain command only if the firmware rejects or ignores scan parameters.
SCAN_PHASE_ACTIVE = 0
SCAN_PHASE_BASIC  = 1
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
    ret z                           ; A complete "No AP" needs no fallback.

    call flushInput
    ld hl, S_AT_CWJAP_CUR : call espSendZ_CRLF
    call .waitCwJAP
    jr nc, .connected
    ret z

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
;   On failure, Z=1 only for a complete No AP response (no fallback needed).
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
    dec b                           ; NZ distinguishes timeout/unsupported.
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
    call flushReplyLine
    jr .loop

.errorLine
    ld hl, dbg_rx_error + 4
    call checkOkErrCommon.matchSuffix
    jr nc, .loop
    jp nz, .discardLine
    ; ERROR can be stale, so permit one normal interbyte timeout of grace.
    ld b, 1
    jr .loop

.noAP
    ld hl, .noApSuffix
    call checkOkErrCommon.matchSuffix
    jr nc, .loop
    jp nz, .discardLine
    xor a                           ; Z marks a definitive disconnected reply.
    scf
    ret

.plusFound
    ; Expect CWJAP (possibly with _CUR/_DEF suffix).
    cp 'C' : jp nz, .discardLine
    ld hl, .cwjapSuffix
    call checkOkErrCommon.matchSuffix
    jp nc, .fail
    jp nz, .discardLine

    ; Accept ':' directly, or skip suffix until ':'
.readUntilColon
    call readResponseByte : jp nc, .fail
    cp ':' : jr z, .afterColon
    cp 13 : jp z, .discardLine
    cp 10 : jp z, .loop
    jr .readUntilColon

.afterColon
    ; Find opening quote
.findQuote
    call readResponseByte : jp nc, .fail
    cp 13 : jp z, .discardLine
    cp 10 : jp z, .loop
    cp '"' : jr nz, .findQuote

    ; Read and unescape SSID until closing quote (bounded)
    ld hl, connected_ssid
    ld b, MAX_SSID_LEN
.readSSID
    call readResponseByte : jp nc, .clearRejectedSSID
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
    call readResponseByte : jp nc, .clearRejectedSSID
    cp '"' : jr z, .gotSSID
    jr .rejectSSID

.readSSIDescape
    call readResponseByte : jp nc, .clearRejectedSSID
    call isSSIDescape
    jr z, .storeSSID
.rejectSSID
    ; Drop malformed/overlong names without consuming the next line.
    cp 10 : jr z, .clearRejectedSSID
    call flushReplyLine
.clearRejectedSSID
    xor a
    ld (connected_ssid), a
    ld (connected_bssid_valid), a
    jp .fail

.gotSSID
    xor a
    ld (hl), a
    ld (connected_bssid_valid), a
    ; Current firmware follows SSID with the selected BSSID. Older or
    ; malformed replies still establish SSID state with unknown identity.
    call readResponseByte
    jr nc, .clearRejectedSSID
    cp ',' : jr nz, .finishConnected
    call readResponseByte
    jr nc, .clearRejectedSSID
    cp '"' : jr nz, .finishConnected
    ld hl, connected_bssid
    ld b, 6
.readBssid
    call readResponseByte
    jr nc, .clearRejectedSSID
    call loadList.hexNibble
    jr nc, .finishConnected
    rlca
    rlca
    rlca
    rlca
    ld c, a
    call readResponseByte
    jr nc, .clearRejectedSSID
    call loadList.hexNibble
    jr nc, .finishConnected
    or c
    ld (hl), a
    inc hl
    djnz .bssidSeparator
    call readResponseByte
    jr nc, .clearRejectedSSID
    cp '"' : jr nz, .finishConnected
    ld a, 1
    ld (connected_bssid_valid), a
    jr .finishConnected
.bssidSeparator
    call readResponseByte
    jr nc, .clearRejectedSSID
    cp ':' : jr z, .readBssid
.finishConnected
    cp 10 : jr z, .lineComplete
    call flushReplyLine
    jr nc, .clearRejectedSSID
.lineComplete
    call checkOkErr
    jr c, .clearRejectedSSID
    ret

.fail
    or 1                            ; NZ marks timeout/unsupported/malformed.
    scf
    ret

.discardLine
    call flushReplyLine
    jp .loop

.cwjapSuffix db "WJAP", 0
.noApSuffix db "o AP", 13, 10, 0

; Drain UART until silence (capped at 2048 bytes to prevent lockup)
; Flush until sustained silence (NextSync flush_uart_hard pattern)
flushInput:
.drainStart
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
    ld a, (.recovering)
    and a
    jr z, .flushDone          ; Preserve normal capped-drain behavior.
    ld a, 1
    ld (Uart.io_error), a
    scf
    ret
.flushQuiet
    dec de
    ld a, d : or e
    jr nz, .flushLoop
.flushDone
    ld a, (Uart.tx_pending)
    and a
    jr nz, .abortLine
    xor a
    ld (.recovering), a
    ld (Uart.io_error), a
    ret
.abortLine
    ; Make every project AT prefix invalid before terminating the damaged line.
    xor a
    ld (Uart.io_error), a
    ld hl, .abortBytes
    ld b, 3
.abortLoop
    ld a, (hl)
    call UartImpl.write
    ld a, (Uart.io_error)
    and a
    jr nz, .abortFailed
    inc hl
    djnz .abortLoop
    xor a
    ld (Uart.tx_pending), a
    inc a
    ld (.recovering), a
    jr .drainStart             ; Consume ERROR before another transaction.
.abortFailed
    scf
    ret
.recovering db 0
.abortBytes db '#', 13, 10

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

    xor a
    ld (scan_overflow), a
    ; Don't clear buffers yet — preserve old data until the scan delivers rows
    ld (seen_cwlap), a
    ld (Uart.break_hit), a
    ld (use_long_timeout), a
    ld (scan_phase), a          ; SCAN_PHASE_ACTIVE
    ld hl, loadList.readScan
    ld (readResponseByte.reader), hl
    ; fall through to the active scan

; The compatibility fallback gets a fresh capture, deadline and byte budget.
startPass:
    call flushInput
    ld hl, (#5C78)
    ld (scan_started), hl
    ld hl, SCAN_BYTE_LIMIT
    ld (byte_limit), hl
    ld hl, scan_rx_buffer
    ld (scan_rx_read), hl
    ld (scan_rx_write), hl
    ld a, (scan_phase)
    ld hl, S_AT_CWLAP_ACTIVE
    and a
    jr z, .send
    ld hl, S_AT_CWLAP
.send
    call espSendZ_CRLF
    jp loadList

; Reset the slot cursor + count ONLY. Old SSID bytes remain in buffer but
; are masked by networks_count; as new APs arrive they overwrite slot 0,
; 1, ... If the scan fails partway, partial data shows (better than the
; previous behavior of wiping old data on first +CWLAP, which left the
; list empty on mid-scan timeout).
resetScanPointers:
    ld hl, buffer
    ld (buff_ptr), hl
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
    ; Share the command parser's line and +IPD framing over captured bytes.
    call readReplyStart
    jp nc, .scanTimeout
    jr z, .plusStart
    cp 'O' : jr z, .okStart
    cp 'E' : jp z, .errStart
.discardLine
    cp 10 : jr z, loadList
.flushLine
    call flushReplyLine
    jp nc, .scanTimeout
    jr loadList

.plusStart
    cp 'C' : jr nz, .discardLine
    ld hl, .cwlapSuffix
    call checkOkErrCommon.matchSuffix
    jp nc, .scanTimeout
    jr nz, .discardLine
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
    ld hl, dbg_rx_ok + 4
    call checkOkErrCommon.matchSuffix
    jp nc, .scanTimeout
    jr nz, .discardLine

    ld a, (scan_overflow)
    and a
    jp nz, .scanTimeoutClean

    ; A successful scan with rows finishes without another command.
    ld a, (seen_cwlap)
    and a
    jr nz, .okReturn

    ; No +CWLAP yet. A parameterized pass may be silently ignored (older
    ; ESP returns OK with no results instead of ERROR): try the plain command.
    ld a, (scan_phase)
    cp SCAN_PHASE_BASIC
    jr z, .okReturn             ; Basic scan: OK w/o +CWLAP == 0 networks
    jr .nextPass

.okReturn
    ; If OK arrived without any +CWLAP, clear old data (0-result scan)
    ld a, (seen_cwlap)
    and a
    jr nz, .okAlreadyClear
    call clearScanBuffers
.okAlreadyClear
    call initDisplayIndices     ; Initialize display indices
    call sortNetworks           ; Auto-sort by RSSI
    jp .scanUnlock

.errStart
    ld hl, dbg_rx_error + 4
    call checkOkErrCommon.matchSuffix
    jp nc, .scanTimeout
    jr nz, .discardLine
    ; Rows received before ERROR remain usable.
    ld a, (seen_cwlap)
    and a
    jr nz, .okReturn
    ; Parameters rejected: fall back to plain AT+CWLAP.
    ld a, (scan_phase)
    cp SCAN_PHASE_BASIC
    jr z, .scanFail
.nextPass
    ld hl, scan_phase
    inc (hl)
    jp startPass

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
    ld a, (Uart.break_hit)
    and a
    jp nz, .scanCancelled
    ld a, (scan_overflow)
    and a
    jr z, .scanTimeoutNormal
    ; The capture buffer filled: the rows it held are committed and the rest
    ; of the reply was drained, so the list is complete up to that point.
    ld hl, .truncMsg
    call Display.putStrLog
    jp .okReturn
.truncMsg db 13, "Scan list cut!", 0
.scanTimeoutNormal
    ld hl, .timeout_msg
    call Display.putStrLog
.finishPartialScan
    call .finalizePartialScan
    call .scanUnlock
    scf
    ret
.timeout_msg db 13, "Scan timeout!", 0

.scanCancelled
    call .finalizePartialScan
    call .scanUnlock
    inc a                       ; A=1 distinguishes BREAK from failure
    scf
    ret

.scanUnlock
    ld hl, readResponseByte.uart
    ld (readResponseByte.reader), hl
    jp uartUnlock
.cwlapSuffix db "WLAP:", 0

.finalizePartialScan
    ld a, (seen_cwlap)
    and a
    ret z
    call initDisplayIndices
    jp sortNetworks

.loadAp
    ; The candidate's fields stay in scratch until its BSSID proves unique and
    ; a slot is chosen; its name parses into the slot buff_ptr addresses, which
    ; is the next free one or the scratch slot once the list is full.
.skipToEcn
    call .readOrTimeout
    cp '(' : jp nz, .discardLine
    
    call .readOrTimeout
    sub '0'
    ld (cand_ecn), a

.findQuote
    call .readOrTimeout
    cp ',' : jp nz, .discardLine
    call .readOrTimeout
    cp '"' : jp nz, .discardLine

    ld de, (buff_ptr)
    ld b, MAX_SSID_LEN

.loadName
    call .readOrTimeout
    cp #5C : jr z, .loadNameEscape
    cp '"' : jr z, .loadedName
    cp 13 : jr z, .rejectName
    cp 10 : jr z, .rejectName
.storeName
    ld (de), a
    inc de
    djnz .loadName

.waitNameQuote
    call .readOrTimeout
    cp '"' : jr z, .loadedName
    jr .rejectName

.loadNameEscape
    call .readOrTimeout
    call isSSIDescape
    jr z, .storeName
.rejectName
    cp 10 : jp z, loadList
.flushRejectedName
    call .readOrTimeout
    cp 10 : jr nz, .flushRejectedName
    jp loadList

.loadedName
    xor a
    ld (de), a

.findRssi
    call .readOrTimeout
    cp ',' : jp nz, .discardLine
    
    call .readOrTimeout
    cp '-' : jr nz, .skipRssi   
    
    ld de, 0            
.readRssiDigit
    call .readOrTimeout
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
    ld a, (cand_ecn)
    and a
    ld a, e
    jr nz, .notOpen
    or #80              ; Open network flag rides on the RSSI magnitude
.notOpen
    ld (cand_rssi), a

    ; Capture a normalized six-byte BSSID. Nonstandard fields remain unique.
    call .readOrTimeout
    cp '"' : jr nz, .invalidMac
    ld hl, bssid_temp
    ld b, 6
.readMac
    call .readOrTimeout
    call .hexNibble
    jp nc, .invalidMac
    rlca
    rlca
    rlca
    rlca
    ld c, a
    call .readOrTimeout
    call .hexNibble
    jp nc, .invalidMac
    or c
    ld (hl), a
    inc hl
    djnz .macSeparator
    call .readOrTimeout
    cp '"' : jr nz, .invalidMac
    ld a, 1
    ld (mac_valid), a
    jr .validMac
.macSeparator
    call .readOrTimeout
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
    cp 10 : jp z, loadList
    call .readOrTimeout
    cp ',' : jr nz, .skipMac
    jr .macDone
.validMac
    call .readOrTimeout
    cp ',' : jp nz, .discardLine
.macDone

    ; Parse channel number (1-14)
    ld e, 0
.readChanDigit
    call .readOrTimeout
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
    cp 15 : jp nc, .discardLine
    ld e, a
    jr .readChanDigit
.chanDone
    cp ')' : jr z, .channelEnd
    cp ',' : jp nz, .discardLine
.channelEnd
    ld a, e
    and a : jp z, .discardLine
.saveChannel
    ld (cand_chan), a

    call .deduplicate
    jp c, .flushLine

    ; Commit only after the BSSID is known unique: append while there is a
    ; free slot, otherwise keep the strongest MAX_NETWORKS by replacing the
    ; weakest committed AP when the candidate beats it.
    ld a, (networks_count)
    cp MAX_NETWORKS
    jr c, .commitAppend
    call .weakestSlot           ; A = weakest index, C = its RSSI magnitude
    ld b, a
    ld a, (cand_rssi)
    and #7F
    cp c
    jp nc, .flushLine           ; Not stronger than anything kept
    ; The name waits in the scratch slot: move it into the replaced slot.
    ld a, b
    push bc
    call getSSIDPointer         ; HL = slot B
    ex de, hl
    ld hl, (buff_ptr)
    ld bc, SSID_SLOT_SIZE
    ldir
    pop bc
    ld a, b
    jr .commitFields
.commitAppend
    ld c, a                     ; C = new index; its slot already holds the name
    ld hl, ssid_ptr_table
    add a, a
    add a, l
    ld l, a
    jr nc, .appendEntry
    inc h
.appendEntry
    ld de, (buff_ptr)
    ld (hl), e
    inc hl
    ld (hl), d
    ld hl, SSID_SLOT_SIZE
    add hl, de
    ld (buff_ptr), hl           ; Next slot; the scratch slot follows the last one
    ld hl, networks_count
    inc (hl)
    ld a, c
.commitFields
    ; A = slot index: store the candidate's RSSI, ECN, channel and BSSID.
    ld c, a
    ld b, 0
    ld hl, rssi_buffer
    add hl, bc
    ld a, (cand_rssi)
    ld (hl), a
    ld hl, ecn_buffer
    add hl, bc
    ld a, (cand_ecn)
    ld (hl), a
    ld hl, channel_buffer
    add hl, bc
    ld a, (cand_chan)
    ld (hl), a
    ld l, c
    ld h, b
    add hl, hl                  ; x2
    add hl, bc                  ; x3
    add hl, hl                  ; x6
    ld de, bssid_buffer
    add hl, de
    ex de, hl
    ld hl, bssid_temp
    ld bc, 6
    ldir
    jp .flushLine

; Output: A = index of the weakest committed AP, C = its RSSI magnitude.
; Ties keep the earliest entry. Destroys B, DE, HL.
.weakestSlot
    ld hl, rssi_buffer
    ld a, (networks_count)
    ld b, a
    ld c, 0
    ld d, 0                     ; D = weakest index so far
    ld e, 0                     ; E = current index
.weakestLoop
    ld a, (hl)
    and #7F
    cp c
    jr z, .weakestNext
    jr c, .weakestNext
    ld c, a
    ld d, e
.weakestNext
    inc hl
    inc e
    djnz .weakestLoop
    ld a, d
    ret

.hexNibble
    ld d, a                     ; Recovery needs the raw delimiter on failure.
    sub '0'
    cp 10
    ret c
    or #20                      ; Keep control bytes out of the digit fast path.
    sub 'a' - '0'
    cp 6
    jr nc, .invalidHex
    add a, 10
    scf
    ret
.invalidHex
    ld a, d
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

; Read one byte or abandon the scan. The parser needs that pair at 29 sites,
; so it is a thunk rather than 29 copies of call/jp. Silence ends the scan, so
; the caller's return address is dropped instead of returned to; INC SP twice
; does that without touching a register, and .readScan preserves BC/DE/HL.
.readOrTimeout
    call .readScan
    ret c
    inc sp
    inc sp
    jp .scanTimeout

; Capture at wire speed, then let the parser work from RAM after a quiet gap.
.captureBurst
    ld a, (scan_overflow)
    and a
    jp nz, .drainOverflow
    ld hl, scan_rx_buffer
    ld (scan_rx_read), hl
    ld (scan_rx_write), hl
    ld (.capturePtr), hl
    xor a
    ld (silence_started), a
.captureLoop
    call UartImpl.uartRead
    jp c, .captureByte
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
    ; A terminal-looking tail yields a provisional burst immediately. Check only
    ; when the UART first goes idle, so the 115200-baud ready-byte path stays
    ; within its one-character budget on UNO.
    call .captureComplete
    jr c, .captureDone
    ld a, 1
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
.captureDone
    ld hl, (.capturePtr)
    ld (scan_rx_write), hl
    scf
    ret

; Input: HL = captured byte count. CF=1 yields a possible terminal burst.
; Only loadList may finish the scan, after excluding framed +IPD payloads.
; Destroys: AF, BC, DE, HL.
.captureComplete
    ld b, h
    ld c, l
    ld a, h
    and a
    jr nz, .captureTail
    ld a, l
    cp 4
    jr c, .captureIncomplete
.captureTail
    ld hl, (.capturePtr)
    dec hl
    ld a, (hl)
    cp 10
    jr nz, .captureIncomplete
    dec hl
    ld a, (hl)
    cp 13
    jr nz, .captureIncomplete
    dec hl
    ld a, (hl)
    cp 'K'
    jr z, .captureOk
    cp 'R'
    jr nz, .captureIncomplete
    ld a, b
    and a
    jr nz, .captureError
    ld a, c
    cp 7
    jr c, .captureIncomplete
.captureError
    dec hl
    ld a, (hl)
    cp 'O'
    jr nz, .captureIncomplete
    dec hl
    ld a, (hl)
    cp 'R'
    jr nz, .captureIncomplete
    dec hl
    ld a, (hl)
    cp 'R'
    jr nz, .captureIncomplete
    dec hl
    ld a, (hl)
    cp 'E'
    jr nz, .captureIncomplete
    jr .captureLineStart
.captureOk
    dec hl
    ld a, (hl)
    cp 'O'
    jr nz, .captureIncomplete
.captureLineStart
    ld de, scan_rx_buffer
    ld a, h
    cp d
    jr nz, .capturePrevious
    ld a, l
    cp e
    jr z, .captureTerminal
.capturePrevious
    dec hl
    ld a, (hl)
    cp 10
    jr nz, .captureIncomplete
.captureTerminal
    scf
    ret
.captureIncomplete
    or a
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
    jp .captureLoop
.captureCancelled
    ld a, 1
    ld (Uart.break_hit), a
    or a
    ret
.captureFull
    ; Hand the full buffer to the parser; the next capture drains the rest of
    ; the reply and ends the scan with the rows that fit.
    ld (.capturePtr), hl
    ld (scan_rx_write), hl
    ld a, 1
    ld (scan_overflow), a
    scf
    ret

; Discard the remainder of an overflowed reply until the UART stays quiet,
; then report no burst so the parser finishes. Destroys AF, DE, HL.
.drainOverflow
    ld hl, (#5C78)
    ld (silence_frame), hl
    ld a, 1
    ld (.drainPoll), a
.drainLoop
    call UartImpl.uartRead
    jr c, .drainByte
    ld a, (Uart.io_error)
    and a
    ret nz                      ; CF already clear
    call Keyboard.checkBreak
    jp z, .captureCancelled
    call .scanBudgetLeft
    ret nc
    ld hl, (#5C78)
    ld de, (silence_frame)
    or a
    sbc hl, de
    ld de, SCAN_GAP_FRAMES
    or a
    sbc hl, de
    jr c, .drainLoop
    or a
    ret
.drainByte
    ld hl, (#5C78)
    ld (silence_frame), hl
    ; Bound continuous discarded traffic without slowing every byte's poll.
    ld a, 0
.drainPoll = $ - 1
    dec a
    ld (.drainPoll), a
    jr nz, .drainLoop
    call Keyboard.checkBreak
    jp z, .captureCancelled
    call .scanBudgetLeft
    ret nc
    jr .drainLoop

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
    ; Diagnostics mute byte logging, so terminate the direct TX line here.
    ld a, (debug_log)
    and a
    jr z, sendCRLF
    ld a, (Uart.log_enabled)
    and a
    jr nz, sendCRLF
    push hl
    ld hl, dbg_eol
    call Display.putStrLog
    pop hl
sendCRLF:
    ld a, 13
    call Uart.write
    ld a, 10
    call Uart.write
    ld a, (Uart.io_error)
    and a
    ret z
    call flushInput
    ld a, 1                     ; Preserve the failed transaction result.
    ld (Uart.io_error), a
    ret

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
    jp .uart
.reader = $ - 2
.uart
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
    xor a
    ld hl, ip_buffer
    ld de, ip_buffer + 1
    ld bc, 68
    ld (hl), a
    ldir
    call flushInput
    ld hl, S_AT_CIFSR
    ld de, .cifsrFields
    call .query
    ld a, (Uart.break_hit)
    and a
    jr nz, .unlock
    call flushInput
    ld hl, S_AT_CIPSTA
    ld de, .cipstaFields
    call .query
    jr nc, .done
    ld a, (Uart.break_hit)
    and a
    jr nz, .unlock
    call flushInput
    ld hl, S_AT_CIPSTA_CUR
    ld de, .cipstaFields
    call .query
.done
    ld a, (Uart.break_hit)
    and a
    jr nz, .unlock
    call flushInput
.unlock
    jp uartUnlock

; Both queries share framing, exact field prefixes and bounded quoted copies.
; DE points to the common prefix followed by tag/destination/limit/suffix rows.
.query
    ld a, (Uart.break_hit)
    and a
    ret nz
    ld (.fields), de
    call espSendZ_CRLF
    xor a
    ld (use_long_timeout), a
    ld hl, 4096
    ld (byte_limit), hl
.loop
    call readReplyStart : jr nc, .fail
    jr z, .plus
    cp 'O' : jp z, .ok
    cp 'E' : jr nz, .discard
    ld hl, dbg_rx_error + 4
    call checkOkErrCommon.matchSuffix
    jr nc, .fail
    jr z, .fail
    jr .discard
.plus
    cp 'C' : jr nz, .discard
    ld hl, 0
.fields = $ - 2
    call checkOkErrCommon.matchSuffix
    jr nc, .fail
    jr nz, .discard
    inc hl
    ld a, (hl)
    cp ':'
    jr nz, .field
    inc hl
    push hl
    call readResponseByte
    jr nc, .prefixFail
    cp ':'
    jr z, .prefixDone
    cp '_'
    jr nz, .prefixFail
    ld hl, .curSuffix
    call checkOkErrCommon.matchSuffix
    jr nc, .prefixFail
    jr nz, .prefixFail
.prefixDone
    pop hl
.field
    call readResponseByte : jr nc, .fail
    ld c, a
.findField
    ld a, (hl)
    and a
    jr z, .discard
    cp c
    inc hl
    ld e, (hl) : inc hl
    ld d, (hl) : inc hl
    ld b, (hl) : inc hl
    jr z, .suffix
.skipSuffix
    ld a, (hl)
    inc hl
    and a
    jr nz, .skipSuffix
    jr .findField
.prefixFail
    pop hl
.fail
    xor a
    ld (ci_gateway), a
    ld (ci_netmask), a
    scf
    ret
.discard
    call flushReplyLine
    jr c, .loop
    jr .fail
.suffix
    push bc, de
    call checkOkErrCommon.matchSuffix
    pop de, bc
    jr nc, .fail
    jr nz, .discard
    ex de, hl
.copy
    call readResponseByte
    jr nc, .copyFail
    cp '"'
    jr z, .copied
    ld (hl), a
    inc hl
    djnz .copy
.copied
    ld (hl), 0
    jr .discard
.copyFail
    ld (hl), 0
    jr .fail
.ok
    ld hl, dbg_rx_ok + 4
    call checkOkErrCommon.matchSuffix
    jr nc, .fail
    jr nz, .discard
    ; CIFSR's caller ignores this result; CIPSTA must supply a valid gateway.
    ld hl, ci_gateway
    call UI.validateIP.fromHL
    ret nc
    jr .fail

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
    call flushInput
    ret c
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
    ; AT answered, so the modem is in command mode and the caller's question
    ; is settled. Normalizing the framing is best effort: firmwares that
    ; reject CIPMODE when no passthrough socket exists used to make this
    ; report "No AT response" on a perfectly responsive ESP.
    ld hl, S_AT_CIPMODE_NORMAL
    call espSendZCheckOk
    or a
    ret

.msg_escape db 13, "-- Escape +++ (trying to exit pass-through)", 13, 10, 0

; Re-establish an explicit AT transaction boundary after a failed attempt.
prepareRetry:
    call flushInput
    jr c, .retryFailed
    ld a, 13
    call UartImpl.write
    ld a, 10
    call UartImpl.write
    ld a, (Uart.io_error)
    and a
    jr nz, .retryFailed
    call flushInput
    jr c, .retryFailed
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
buff_ptr        dw buffer     ; Slot receiving the next candidate name

; Flags in printer buffer (all set before first read)
seen_cwlap      = #5B12
; #5B13 owned by Uart.break_hit
scan_phase      = #5B14     ; SCAN_PHASE_* of the pass in progress
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
    RTVAR cand_ecn, 1            ; Candidate row fields until it is committed
    RTVAR cand_rssi, 1
    RTVAR cand_chan, 1
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
