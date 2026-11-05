; Diagnostics UI for NetManZX: the D menu and every screen under it, plus the
; single-line text editor. TAP loads this at #6000 next to the fonts (and
; clock on UNO). Next pages it with cold-ui in bank 16; UNO +3DOS relocates
; it at startup. The AY TAP byte reader stays
; resident in diag-rx.asm. This file is included inside 'module UI'.

diagHeaderMuted:
    xor a
    ld (Uart.log_enabled), a
diagHeader:
    push hl
    call topClean
    pop hl
    ld c, Display.ATTR_SSID_INPUT              ; Green BRIGHT on black
    jp showBigMessage

showDiagnostics:
    call Keyboard.waitBreakRelease
    ld hl, .msg_diag_title
    call diagHeader             ; diagHeader already calls topClean
    ld hl, .diagPtrs
    call printRowTable
    ; Separator line below items
    ld a, 14 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline
    ld a, 15 : ld hl, .msg_diag_exit : call printAt0
    ; Restore cursor (persists across sub-screen visits)
    ld a, (diag_cursor)
    cp DIAG_ITEMS
    jr c, .cursorOk
    xor a
.cursorOk:
    jr .diagSet

.diagLoop
    ld b, 3
.diagWait
    halt : djnz .diagWait
    call Keyboard.checkBreak : jp z, .exitDiag
    call Keyboard.inKeyNoWait
    and a : jr z, .diagLoop
    call Keyboard.keyClick
    cp Keyboard.KEY_UP : jr z, .diagUp
    cp 'q' : jr z, .diagUp
    cp 'Q' : jr z, .diagUp
    cp Keyboard.KEY_DN : jr z, .diagDown
    cp 'a' : jr z, .diagDown
    cp 'A' : jr z, .diagDown
    cp Keyboard.KEY_LEFT : jr z, .diagFirst
    cp Keyboard.KEY_RIGHT : jr z, .diagLast
    cp 'l' : jr z, .diagLog : cp 'L' : jr z, .diagLog
    cp 13 : jr z, .diagSelect
    jr .diagLoop
.diagLog
    call toggleLogQuiet : jr .diagLoop

.diagUp
    ld a, (diag_cursor)
    and a : jr z, .diagLoop
    dec a
    jr .diagSet

.diagDown
    ld a, (diag_cursor)
    cp DIAG_ITEMS - 1 : jr z, .diagLoop
    inc a
    jr .diagSet

.diagFirst
    xor a
    jr .diagSet

.diagLast
    ld a, DIAG_ITEMS - 1

.diagSet
    push af
    call .hideDiagCursor
    pop af
    ld (diag_cursor), a
    call .showDiagCursor
    jr .diagLoop

.diagSelect
    ld a, (diag_cursor)
    and a : jp z, doPing
    cp 1 : jp z, doModuleInfo
    cp 2 : jp z, doNetworkInfo
    cp 3 : jp z, doBaudRate
    cp 4 : jp z, doStaticIP
    cp 5 : jp z, doHostname
    cp 6 : jp z, doConfigSummary
    jp .diagLoop

.showDiagCursor:
    ld c, Display.ATTR_HIGHLIGHT
    jr .diagCursorAttr
.hideDiagCursor:
    ld c, Display.ATTR_NORMAL
.diagCursorAttr:
    ld a, (diag_cursor)
    add a, DIAG_FIRST_LINE
    jp Display.setAttrPartial

.exitDiag
    ; Restore UART log to match debug_log setting
    ld a, (Wifi.debug_log)
    ld (Uart.log_enabled), a
    jp renderListAndLoop

    IFNDEF DIAG_RX_RESIDENT
    include "modules/diag-rx.asm"
    ENDIF

; Set diagnostic output coordinates if a visible row remains.
setDiagCoords:
    ld a, (diag_line)
    cp DIAG_ROW_LIMIT
    ret nc
    push hl
    call Display.gotoXY0
    pop hl
    scf
    ret

; Show diag_buffer on current line and advance
showDiagLine:
    call setDiagCoords
    ret nc
    ld a, (diag_line)
    cp DIAG_ROW_LIMIT - 1
    jr nz, .showLine
    xor a
    ld (diag_buffer + 42), a
.showLine
    ld hl, diag_buffer
    push bc
    call Display.putStr
    pop bc
    ld hl, (Display.coords)
    ld a, l
    and a
    ld a, h
    jr z, .saveNextLine
    inc a
.saveNextLine
    ld (diag_line), a
    ret

; ============================================
; Ping test
; ============================================
MAX_IP_LEN = 15                 ; xxx.xxx.xxx.xxx

; IP buffer (persistent between calls)
    RTVAR ping_ip_buffer, MAX_IP_LEN + 1
    RTVAR ping_ip_len, 1

; Initialize default IP (called once)
initPingIP:
    ld hl, .default_ip
    ld de, ping_ip_buffer
    ld bc, 8                    ; "8.8.8.8" + null
    ldir
    ld a, 7
    ld (ping_ip_len), a
    ret
.default_ip db "8.8.8.8", 0

doPing:
    ; Initialize default IP if empty
    ld a, (ping_ip_len)
    cp MAX_IP_LEN + 1
    jr nc, .initDefault
    and a
    jr nz, .skipInit
.initDefault
    call initPingIP
.skipInit
    
    ld hl, .msg_ping_title
    call diagHeaderMuted

    ld a, 6 : ld hl, .msg_ip_prompt : call printAt0
    call setPassRows8

    ld a, 11 : ld hl, .msg_ping_help : call printAt0

.drawIP
    ; Draw current IP directly in double-height
    halt
    di
    ld a, 8 : call Display.gotoXY0
    ld hl, ping_ip_buffer
    call Display.putStrBig

    ; Clear rest of line (MAX_IP_LEN - len spaces)
    ld a, MAX_IP_LEN
    ld hl, ping_ip_len
    sub (hl)
    jr z, .noSpaces
    inc a
    ld b, a
.clearSpaces
    push bc
    ld a, ' ' : call Display.putCBig
    pop bc
    djnz .clearSpaces
.noSpaces

    ; Show cursor
    ld a, (ping_ip_len)
    ld l, a
    ld h, 8
    ld (Display.coords), hl
    ld a, 127               ; same block cursor as passwordInput
    call Display.putCBig
    ei

.waitIPKey
    ld b, 4
.waitIPLoop
    halt
    call Keyboard.checkBreak : jp z, .pingCancel
    djnz .waitIPLoop
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitIPKey
    call Keyboard.keyClick

    ; ENTER = execute ping
    cp 13 : jp z, .doPingNow
    
    ; Backspace = delete
    cp Keyboard.KEY_BS : jp z, .ipBackspace
    
    ; Manual dot
    cp '.'
    jr z, .ipTryAddDot
    
    ; Only allow digits (0-9)
    cp '0'
    jr c, .waitIPKey            ; < '0'
    cp '9' + 1
    jr nc, .waitIPKey           ; > '9'
    
    ; It's a digit - check if it fits
    ld b, a                     ; Save digit
    ld a, (ping_ip_len)
    cp MAX_IP_LEN
    jr nc, .waitIPKey           ; Buffer full
    
    ; Count digits in current octet
    push bc
    call .countOctetDigits
    pop bc
    cp 3
    jr c, .ipAddDigit           ; < 3 digits, add normally
    
    ; Already 3 digits - need dot first
    ; Check if we can add a dot (max 3 dots)
    push bc
    call .countDots
    pop bc
    cp 3
    jr nc, .waitIPKey           ; Already 3 dots, no more digits
    
    ; Check room for 2 characters (dot + digit)
    ld a, (ping_ip_len)
    cp MAX_IP_LEN - 1
    jr nc, .waitIPKey           ; No room for 2 chars
    
    ; Add automatic dot
    push bc
    ld a, '.'
    call .addCharToIP
    pop bc
    
.ipAddDigit
    ; Add the digit
    ld a, b
    call .addCharToIP
    jp .drawIP

.ipTryAddDot
    ; Don't allow dot at start
    ld a, (ping_ip_len)
    and a
    jr z, .waitIPKey
    
    ; Don't allow consecutive dots
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    dec hl                      ; Last character
    ld a, (hl)
    cp '.'
    jr z, .waitIPKey            ; Last is dot, don't add another
    
    ; Check max 3 dots
    push bc
    call .countDots
    pop bc
    cp 3
    jr nc, .waitIPKey           ; Already 3 dots
    
    ; Check room
    ld a, (ping_ip_len)
    cp MAX_IP_LEN
    jr nc, .waitIPKey
    
    ; Add dot
    ld a, '.'
    call .addCharToIP
    jp .drawIP

; Add a character to the IP buffer
.addCharToIP
    push af
    ld a, (ping_ip_len)
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    pop af
    ld (hl), a
    inc hl
    xor a
    ld (hl), a                  ; Null terminator
    ld a, (ping_ip_len)
    inc a
    ld (ping_ip_len), a
    ret

; Count digits in current octet (from last dot)
; Output: A = number of digits
.countOctetDigits
    ld a, (ping_ip_len)
    and a
    ret z                       ; Empty, 0 digits
    
    ; Walk backwards from end
    ld b, a                     ; B = length
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    dec hl                      ; HL points to last character
    ld c, 0                     ; Digit counter
    
.countLoop
    ld a, (hl)
    cp '.'
    jr z, .countDone            ; Found dot, done
    inc c                       ; Count digit
    dec b
    jr z, .countDone            ; Reached start
    dec hl
    jr .countLoop
    
.countDone
    ld a, c
    ret

; Count dots in the buffer
; Output: A = number of dots
.countDots
    ld hl, ping_ip_buffer
    ld c, 0                     ; Dot counter
.dotsLoop
    ld a, (hl)
    and a
    jr z, .dotsDone             ; End of string
    cp '.'
    jr nz, .dotsNext
    inc c
.dotsNext
    inc hl
    jr .dotsLoop
.dotsDone
    ld a, c
    ret

.ipBackspace
    ld a, (ping_ip_len)
    and a
    jp z, .waitIPKey            ; Already empty
    dec a
    ld (ping_ip_len), a
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    jp .drawIP

.pingCancel
    jp showDiagnostics

.doPingNow
    ; Check there is something typed
    ld a, (ping_ip_len)
    and a
    jp z, .waitIPKey            ; Don't allow empty IP
    
    call topClean
    ; "Pinging IP..." double-height on rows 4-5
    ld a, 4 : ld hl, .msg_pinging : call printAt0
    ld hl, ping_ip_buffer
    call Display.putStr
    ld hl, .msg_dots
    call Display.putStr
    call Display.stretchRows45
    ; Row 4: "Pinging " white BRIGHT (cells 0-5), IP green BRIGHT (cells 6-31)
    ld hl, #5880            ; Row 4 attr
    ld a, Display.ATTR_NORMAL
    ld b, 6
.pa4w
    ld (hl), a : inc hl : djnz .pa4w
    ld a, Display.ATTR_SSID_INPUT   ; Bright green on black
    ld b, 26
.pa4g
    ld (hl), a : inc hl : djnz .pa4g
    ; Row 5: same but without BRIGHT
    ld hl, #58A0            ; Row 5 attr
    ld a, Display.ATTR_NORMAL_DIM              ; White on black, no bright
    ld b, 6
.pa5w
    ld (hl), a : inc hl : djnz .pa5w
    ld a, Display.ATTR_RSSI              ; Green on black, no bright
    ld b, 26
.pa5g
    ld (hl), a : inc hl : djnz .pa5g

    ; Initialize output line
    ld a, 7
    ld (diag_line), a
    
    ; Drain buffer before sending command
    call flushUartBuffer
    
    ; Build and send command: AT+PING="ip"
    ld hl, .cmd_ping_start
    call Wifi.espSendZ
    ld hl, ping_ip_buffer
    call Wifi.espSendZ
    ld hl, at_quote_crlf
    call Wifi.espSendZ_CRLF
    
    ; Read responses
    ld c, 20                    ; Max 20 timeouts
    ld b, 100                   ; Absolute limit: 100 lines
.pingLoop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call readDiagLineBC
    jr nc, .pingTimeout         ; CF=0 = timeout real
    
    ; Decrement absolute limit
    dec b
    jr z, .pingDone             ; Limit reached
    
    ; CF=1 = got line
    ld a, (diag_buffer)
    and a
    jr z, .pingLoop             ; Empty line
    
    ; Check if it is "OK" or "ERROR" -> end
    cp 'O'
    jr z, .pingDone
    cp 'E'
    jr z, .pingDone             ; ERROR also terminates
    
    ; Filter noise and echo
    cp 'A' : jr z, .pingLoop    ; Echo AT...
    cp '0' : jr z, .pingLoop
    cp '1' : jr z, .pingLoop
    cp 'C' : jr z, .pingLoop    ; CONNECT, CLOSED
    cp 'L' : jr z, .pingLoop    ; LAIN
    cp 'S' : jr z, .pingLoop    ; SEND OK
    
    ; If starts with +, check if it is +IPD
    cp '+'
    jr nz, .pingShow
    ld a, (diag_buffer + 1)
    cp 'I'                      ; +IPD -> ignore
    jr z, .pingLoop
    
    ; Check if +timeout (error) or +number (success)
    cp 't'                      ; +timeout
    jr z, .pingShowTimeout
    
    ; Format successful ping: Response time: XX ms
    call setDiagCoords
    jr nc, .pingDone
    push bc
    ld hl, .msg_time_lbl
    call Display.putStr
    ld hl, diag_buffer + 1      ; Skip the '+'
    call Display.putStr
    ld hl, .msg_time_ms
    call Display.putStr
    pop bc
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .pingLoop

.pingShowTimeout
    ; Show "Request timed out"
    call setDiagCoords
    jr nc, .pingDone
    push bc
    ld hl, .msg_timeout
    call Display.putStr
    pop bc
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .pingLoop

.pingShow
    call showDiagLine
    jr .pingLoop
    
.pingTimeout
    call abortDiagOnBreak
    dec c
    jp nz, .pingLoop

.pingDone
    jp pressKeyReturnDiag



; ============================================
; Module info (firmware version)
; ============================================
doModuleInfo:
    ld hl, .msg_module_title
    call diagHeaderMuted

    ; Initialize output line
    ld a, 6
    ld (diag_line), a

    ; Drain buffer before sending command
    call flushUartBuffer

    ; Send AT+GMR
    ld hl, .cmd_gmr
    call Wifi.espSendZ_CRLF
    
    ; Read and show responses
    ld c, 20                    ; Max 20 timeouts
    ld b, 100                   ; Absolute limit: 100 lines
.gmrLoop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call readDiagLineBC
    jr nc, .gmrTimeout          ; CF=0 = timeout real
    
    ; Decrement absolute limit
    dec b
    jr z, .gmrDone              ; Limit reached
    
    ; CF=1 = got line
    ld a, (diag_buffer)
    and a
    jr z, .gmrLoop              ; Empty line, doesn't count as timeout
    
    ; Check if it is "OK" -> end
    cp 'O'
    jr z, .gmrDone
    
    ; Filter network noise and echo (AT+GMR vs AT version...)
    cp 'A' 
    jr nz, .checkOther
    ; Starts with A. Check if it is "AT+" (Echo) or "AT v..." (Info)
    ld a, (diag_buffer + 1)
    cp 'T'
    jr nz, .showInfo      ; Not AT...
    ld a, (diag_buffer + 2)
    cp '+'
    jr z, .gmrLoop        ; Is AT+... (Echo) -> Ignore
    jr .showInfo          ; Is AT ... (Info) -> Show

.checkOther
    cp '+' : jr z, .gmrLoop     ; +IPD, etc
    cp '0' : jr z, .gmrLoop     ; 0,CONNECT
    cp '1' : jr z, .gmrLoop     ; 1,CONNECT
    cp 'C' : jr z, .gmrLoop     ; CONNECT, CLOSED
    cp 'L' : jr z, .gmrLoop     ; LAIN
    cp 'S' : jr nz, .showInfo
    ld a, (diag_buffer + 1)
    cp 'E' : jr z, .gmrLoop     ; SEND..., but retain SDK version

.showInfo
    ; Valid line - show
    call showDiagLine
    jr .gmrLoop                 ; Continue without decrementing
    
.gmrTimeout
    call abortDiagOnBreak
    dec c
    jr nz, .gmrLoop

.gmrDone
    jp pressKeyReturnDiag

.msg_module_title db "MODULE INFO", 0
.cmd_gmr          db "AT+GMR", 0

; A tail call from a read helper must discard its return before changing screens.
abortDiagOnBreak:
    ld a, (Uart.break_hit)
    and a
    ret z
    pop hl
    jp showDiagnostics

; ============================================
; Network info
; ============================================
doNetworkInfo:
    xor a
    ld (Uart.log_enabled), a
    call topClean

    ; Show connected network details
    ld a, (Wifi.is_connected)
    and a
    jr z, .ni_no_idx
    call connectedSSIDPresentInList
    jr nc, .ni_no_idx
    ld (selected_real_idx), a       ; Index for ECN/Channel/Signal
    ld hl, Wifi.connected_ssid
    ld (selected_ssid_ptr), hl
    call showNetDetail
    jr .ni_detail_done
.ni_no_idx
    ; SSID not in list: show only name, without fake Security/Channel/Signal
    ld a, 4 : ld hl, .ni_ssid_lbl : call printAt0
    ld hl, Wifi.connected_ssid
    ld a, (Wifi.is_connected)
    and a
    jr nz, .ni_name
    ld hl, doConfigSummary.cs_none
.ni_name
    call Display.putStr
.ni_detail_done
    ld a, 10 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline
    ld a, 11
    ld (diag_line), a

    call flushUartBuffer
    ld hl, Wifi.S_AT_CIFSR
    call Wifi.espSendZ_CRLF
    ld c, 20
    ld b, 100
.cifsrLoop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call readDiagLineBC
    jr nc, .cifsrTimeout
    dec b
    jr z, .cifsrDone
    ld a, (diag_buffer)
    and a
    jr z, .cifsrLoop
    cp 'O' : jr z, .cifsrDone
    cp 'A' : jr z, .cifsrLoop
    cp '0' : jr z, .cifsrLoop
    cp '1' : jr z, .cifsrLoop
    cp 'C' : jr z, .cifsrLoop
    cp 'L' : jr z, .cifsrLoop
    cp 'S' : jr z, .cifsrLoop
    cp '+' : jr nz, .cifsrLoop
    ld a, (diag_buffer + 1)
    cp 'C' : jr nz, .cifsrLoop
    ld a, (diag_buffer + 10)
    cp 'I' : jr z, .isIP
    cp 'M' : jr z, .isMAC
    jr .cifsrLoop

.isIP
    ld hl, .lbl_ip
    jr .printFmt
.isMAC
    ld hl, .lbl_mac
.printFmt
    call setDiagCoords
    jr nc, .cifsrDone
    push bc
    call Display.putStr
    pop bc
    ld hl, diag_buffer
    call .findQuote
    call printClean             ; CR/LF tolerated; IP/MAC values have neither
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .cifsrLoop

.cifsrTimeout
    call abortDiagOnBreak
    dec c
    jr nz, .cifsrLoop

.cifsrDone
    jp pressKeyReturnDiag

.findQuote
    ld a, (hl)
    cp '"' : jr z, .foundQ
    and a : ret z
    inc hl
    jr .findQuote
.foundQ
    inc hl : ret

.lbl_ip        db "IP:  ", 0
.lbl_mac       db "MAC: ", 0
.ni_ssid_lbl   db "Connected: ", 0

; ============================================
; UART Baud rate
; ============================================
doBaudRate:
    ld hl, msg_baud_title
    call diagHeaderMuted

    ; Initialize output line
    ld a, 6
    ld (diag_line), a
    xor a
    ld (baud_have_value), a
    ld (baud_saw_error), a
    ld (baud_recover_tried), a

    ; Drain buffer before sending command
    call flushUartBuffer

    ; Ensure the ESP is in AT command mode (not in pass-through/data mode)
    call Wifi.ensureCommandMode
    jr nc, doBaudRate_cmode_ok
    ld a, 6 : ld hl, msg_no_at : call printAt0
    jp waitKeyReturnDiag

doBaudRate_cmode_ok:
    ld hl, cmd_uart_cur
    ld de, lbl_baud_cur
    call baudQueryValue
    jp nz, showDiagnostics

    ld hl, cmd_uart_def
    ld de, lbl_baud_def
    call baudQueryValue
    jp nz, showDiagnostics

    ld a, (baud_have_value)
    and a
    jr nz, .baudDone

    ld hl, cmd_uart_plain
    ld de, lbl_baud_plain
    call baudQueryValue
    jp nz, showDiagnostics

.baudDone
    ; If no +UART line could be obtained, warn
    ld a, (baud_have_value)
    and a
    jr nz, .baudDoneHasValue
    ld a, 6 : call Display.gotoXY0
    ld a, (baud_saw_error)
    and a
    jr z, .noErrMsg
    ld hl, msg_uart_error
    call Display.putStr
    jr .afterErrMsg
.noErrMsg
    ld hl, msg_uart_none
    call Display.putStr
.afterErrMsg
.baudDoneHasValue
    call showPressKey
.waitBaudKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitBaudKey
    jp showDiagnostics

baudSkipToColon:
    call doConfigSummary.cs_find_colon
    ret nc
    inc hl
    ret


baudPrintUntilComma:
    ld a, (hl)
    and a : ret z
    cp ',' : ret z
    cp 13  : ret z
    push hl
    call Display.putC
    pop hl
    inc hl
    jr baudPrintUntilComma

baudQueryValue:
    ld (baud_cmd_ptr), hl
    ex de, hl
    ld (baud_lbl_ptr), hl
    ld hl, (baud_cmd_ptr)
    call flushUartBuffer
    call Wifi.espSendZ_CRLF
    ld c, 4                     ; Max 4 timeouts (each one is long)
    ld b, 100                   ; Absolute limit: 100 lines
.loop
    push bc
    call readDiagLineLong
    pop bc
    jr c, .gotLine
    ld a, (Uart.break_hit)
    and a
    ret nz
    jr .timeout
.gotLine

    dec b
    jr z, .done                 ; Limit reached

    ld a, (diag_buffer)
    and a
    jr z, .loop                 ; Empty line, doesn't count

    cp 'O'
    jr z, .done
    cp 'E'
    jr nz, .checkLine

    ld a, 1
    ld (baud_saw_error), a

    ; Retry once after forcing AT command mode again.
    ld a, (baud_recover_tried)
    and a
    jr nz, .done
    ld a, 1
    ld (baud_recover_tried), a
    call Wifi.ensureCommandMode
    call flushUartBuffer
    ld hl, (baud_cmd_ptr)
    call Wifi.espSendZ_CRLF
    ld c, 4
    ld b, 100
    jr .loop

.checkLine
    ; Filter noise and echo.
    cp 'A' : jr z, .loop        ; Ignore echo AT...
    cp '0' : jr z, .loop
    cp 'C' : jr z, .loop

    ; If starts with +, check it is not +IPD.
    cp '+'
    jr nz, .loop
    ld a, (diag_buffer + 1)
    cp 'I'                      ; +IPD -> ignore
    jr z, .loop
    cp 'U'                      ; Check +UART
    jr nz, .loop

    ld a, (diag_line) : ld h, a : ld l, 0 : ld (Display.coords), hl
    ld hl, (baud_lbl_ptr)
    call Display.putStr
    ld hl, diag_buffer
    call baudSkipToColon        ; Skip to ':' (supports +UART and +UART_CUR)
    call baudPrintUntilComma
    ld a, 1
    ld (baud_have_value), a
    ld a, (diag_line) : inc a : ld (diag_line), a
    xor a
    scf
    ret

.timeout
    dec c
    jp nz, .loop
.done
    xor a
    ret



; In printer buffer (set before use in doBaudRate).
; baud_have_value deliberately unions with conn_result (#5B21): the two
; code paths (connectAndReturn vs doBaudRate) are mutually exclusive modal
; screens, so the byte is always reinitialized before use in each flow.
baud_have_value = #5B21
baud_saw_error  = #5B22
baud_recover_tried = #5B23
baud_cmd_ptr    = #5B24
baud_lbl_ptr    = #5B26

; ============================================
; doStaticIP - Static IP configuration (option 5)
; ============================================
doStaticIP:
    ld hl, .sip_title
    call diagHeaderMuted
    ld a, 6 : ld hl, .sip_prompt : call printAt0
    call setPassRows8
    ld a, 11 : ld hl, .sip_help : call printAt0

    ; IP input (digits and dots only)
    ld hl, sip_buf
    ld b, 15                    ; Max IP length (xxx.xxx.xxx.xxx)
    ld a, 8 : ld (sti_line), a
    xor a : ld (sti_len), a
    ld (sti_mode), a
    ld (sip_buf), a
    call ipTextInput
    jp c, showDiagnostics       ; Cancelled

    ; Check there is something
    ld a, (sti_len) : and a : jp z, showDiagnostics

    ; Validate IP format
    call validateIP
    jr nc, .sip_valid
    ld a, 9 : ld hl, .sip_badformat : call printAt0
    jp waitKeyReturnDiag

.sip_valid
    ; Send AT+CIPSTA_CUR="ip"
    call flushUartBuffer
    ld hl, .sip_cmd : call Wifi.espSendZ
    ld hl, sip_buf : call Wifi.espSendZ
    ld hl, at_quote_crlf : call Wifi.espSendZCheckOk
    jr c, .sip_fail
    ; Update IP on screen (ipShowConnected refreshes Wifi.getIP)
    call ipShowConnected
    ld a, 9 : ld hl, .sip_ok : call printAt0
    jr .sip_wait
.sip_fail
    ld a, 9 : ld hl, .sip_err : call printAt0
.sip_wait
    jp waitKeyReturnDiag

.sip_title     db "STATIC IP CONFIG", 0
.sip_prompt    db "Enter IP (empty=cancel):", 0
.sip_help      db "ENTER=accept, BREAK=cancel", 0
.sip_ok        db "IP set OK!", 0
.sip_err       db "Failed to set IP", 0
.sip_badformat db "Invalid IP format!", 0
.sip_cmd       db "AT+CIPSTA_CUR=\"", 0
; IP, hostname and zone editors reinitialize this mutually exclusive scratch.
    RTVAR sip_buf, 21

; ============================================
; ipTextInput - Text input for IPs (digits and dots) or signed numbers
; Input: HL = buffer, B = max_len, A = screen line
; Uses: (sti_len) for current length
; Output: CF=0 if ENTER, CF=1 if CANCEL
; ============================================
ipTextInput:
    ld (sti_buf), hl
    ld a, b : ld (sti_max), a
.itiRedraw
    halt
    di
    ld a, (sti_line)
    ld h, a : ld l, 0 : ld (Display.coords), hl
    ld hl, (sti_buf)
    call Display.putStrBig
    ld a, 127 : call Display.putCBig   ; same block cursor as passwordInput
    ld a, ' ' : call Display.putCBig
    ld a, ' ' : call Display.putCBig
    ei
.itiWait
    ld b, 4
.itiWL  halt
    call Keyboard.checkBreak : jp z, .itiCancel
    djnz .itiWL
    call Keyboard.inKeyNoWait : and a : jr z, .itiWait
    call Keyboard.keyClick
    cp 13 : jp z, .itiEnter
    cp Keyboard.KEY_BS : jr z, .itiBS
    ; Character set depends on the editor mode (IP, date, signed number)
    cp '0' : jr c, .itiSpecial
    cp '9'+1 : jr c, .itiAccept
.itiSpecial
    ld c, a
    ld a, (sti_mode)
    and a
    jr z, .itiIpChars
    ld a, c                 ; signed number: '-' or '+' only
    cp '-'
    jr z, .itiAccept
    cp '+'
    jr z, .itiAccept
    jr .itiWait
.itiIpChars
    ld a, c
    cp '.'
    jr z, .itiAccept
    jr .itiWait
.itiAccept
    ld c, a
    ld a, (sti_len) : ld b, a : ld a, (sti_max) : cp b : jr z, .itiWait
    ld a, (sti_len) : ld hl, (sti_buf) : ld d, 0 : ld e, a : add hl, de
    ld (hl), c : inc hl : ld (hl), 0
    ld a, (sti_len) : inc a : ld (sti_len), a
    halt
    di
    dec a : ld e, a : ld l, a
    ld a, (sti_line) : ld h, a
    ld (Display.coords), hl
    ld hl, (sti_buf) : ld d, 0 : add hl, de
    ld a, (hl) : call Display.putCBig
    ld a, 127 : call Display.putCBig
    ei
    jp .itiWait
.itiBS  ld a, (sti_len) : and a : jp z, .itiWait
    dec a : ld (sti_len), a
    ld hl, (sti_buf) : ld d, 0 : ld e, a : add hl, de : ld (hl), 0
    halt
    di
    ld a, (sti_len) : ld l, a
    ld a, (sti_line) : ld h, a
    ld (Display.coords), hl
    ld a, 127 : call Display.putCBig
    ld a, ' ' : call Display.putCBig
    ei
    jp .itiWait
.itiEnter or a : ret
.itiCancel scf : ret

; ============================================
; validateIP - Validates IP address in sip_buf
; Checks: exactly 3 dots, no leading/trailing/consecutive dots,
;         each octet 0-255, no empty octets
; Returns: CF=0 valid, CF=1 invalid
; ============================================
validateIP:
    ld hl, sip_buf
.fromHL
    ld c, 0                     ; Dot count
    ld d, 0                     ; Current octet value
    ld e, 0                     ; Digits in current octet

.vip_loop
    ld a, (hl)
    and a : jr z, .vip_end      ; End of string
    cp '.'
    jr z, .vip_dot
    ; Digit: accumulate octet value
    sub '0'
    cp 10 : jr nc, .vip_bad
    ld b, a                     ; B = new digit
    ; D = D * 10 + B
    ld a, d
    add a, a                    ; *2
    jr c, .vip_bad
    add a, a                    ; *4
    jr c, .vip_bad
    add a, d                    ; *5
    jr c, .vip_bad
    add a, a                    ; *10
    jr c, .vip_bad
    add a, b                    ; + digit
    jr c, .vip_bad              ; >255
    ld d, a
    inc e                       ; One more digit
    ld a, e : cp 4 : jr nc, .vip_bad  ; Max 3 digits per octet
    inc hl
    jr .vip_loop

.vip_dot
    ; Check no empty octet (no digits before dot)
    ld a, e : and a : jr z, .vip_bad
    inc c                       ; Count dot
    ld a, c : cp 4 : jr nc, .vip_bad  ; Too many dots
    ld d, 0 : ld e, 0          ; Reset octet
    inc hl
    jr .vip_loop

.vip_end
    ; Must have digits in last octet
    ld a, e : and a : jr z, .vip_bad
    ; Must have exactly 3 dots
    ld a, c : cp 3 : jr nz, .vip_bad
    or a : ret                  ; CF=0, valid

.vip_bad
    scf : ret                   ; CF=1, invalid

; ============================================
; doHostname - Set hostname (option 6)
; ============================================
doHostname:
    ld hl, .hn_title
    call diagHeaderMuted
    ld a, 6 : ld hl, .hn_prompt : call printAt0
    call setPassRows8
    ld a, 11 : ld hl, doStaticIP.sip_help : call printAt0

    call clearPassBuffer
    ld a, 1 : ld (show_password), a     ; Show text (not asterisks)
    ld (pass_no_warn), a                ; Blue, not red (not a secret)
    ld a, 8 : ld (pass_line), a
    ld a, 20 : ld (passwordInput.max), a
    call passwordInput
    push af
    ld a, MAX_PASS_LEN : ld (passwordInput.max), a
    ld a, PASS_LINE_DEFAULT : ld (pass_line), a
    xor a : ld (pass_no_warn), a
    pop af
    jp c, showDiagnostics

    ld a, (pass_len) : and a : jp z, showDiagnostics

    ; Copy pass_buffer to hn_buf
    ld hl, pass_buffer
    ld de, hn_buf
    ld a, (pass_len) : ld c, a : ld b, 0
    inc bc
    ldir

    call flushUartBuffer
    ld hl, .hn_cmd : call Wifi.espSendZ
    ld hl, hn_buf : call Wifi.espSendQuotedZ
    ld hl, at_quote_crlf : call Wifi.espSendZCheckOk
    jr c, .hn_fail

    ; Success screen
    call topClean
    ld a, 3 : ld hl, .hn_set_to : call printAt0
    ; Hostname in double-height green (rows 4-5)
    ld a, 4 : ld hl, hn_buf : call printAt0
    call Display.stretchRows45
    ld a, 4 : ld c, Display.ATTR_SSID_INPUT : call setDoubleAttr
    call showPressKey
    jr .hn_wait

.hn_fail
    ; Fail screen
    ld hl, .hn_err : call topCleanAlertMsg
    call showPressKey

.hn_wait
    jp waitKeyReturnDiag

hn_buf = sip_buf

; ============================================
; doConfigSummary - Show all config (option 7)
; ============================================
doConfigSummary:
    ld hl, .cs_title
    call diagHeaderMuted

    ; Fetch gateway/mask (before display, only if connected)
    ld a, (Wifi.is_connected)
    and a
    jr z, .cs_skip_conninfo
    call Wifi.getConnectionInfo
    call abortDiagOnBreak
.cs_skip_conninfo

    ; Connected SSID + band + signal
    ld a, 6 : ld hl, .cs_ssid : call printAt0
    ld a, (Wifi.is_connected) : and a : jr z, .cs_no_ssid
    ld hl, Wifi.connected_ssid : call Display.putStr
    ; Try to get band and signal from scan data
    call connectedSSIDPresentInList
    jr nc, .cs_ip               ; Not in scan list, skip band/signal
    push af                     ; Save index
    ; Band from channel
    ld hl, Wifi.channel_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl)
    cp 15
    ld hl, .cs_band24
    jr c, .cs_showBand
    ld hl, .cs_band5
.cs_showBand
    call Display.putStr
    ; Signal bars on row 7 (same as network detail page)
    pop af
    ld (selected_real_idx), a
    ld a, 7
    call drawSignalLine
    jr .cs_ip
.cs_no_ssid
    xor a
    ld (Wifi.ip_buffer), a
    ld (Wifi.ci_gateway), a
    ld (Wifi.ci_netmask), a
    ld hl, .cs_none : call Display.putStr

.cs_ip
    ; IP - read directly from ip_buffer (already populated in status bar)
    ld a, 8 : ld hl, .cs_ip_lbl
    ld de, Wifi.ip_buffer : ld bc, .cs_none
    call printConnectionField

    ; Gateway
    ld a, 9 : ld hl, .cs_gw_lbl
    ld de, Wifi.ci_gateway : ld bc, .cs_none
    call printConnectionField

    ; Netmask
    ld a, 10 : ld hl, .cs_mask_lbl
    ld de, Wifi.ci_netmask : ld bc, .cs_none
    call printConnectionField

.cs_mac
    ; MAC - send AT+CIPSTAMAC?
    ld a, 11 : ld hl, .cs_mac_lbl : call printAt0
    call .cs_flush
    ld hl, .cs_mac_cmd : call Wifi.espSendZ_CRLF
    ld bc, #0840                 ; B: nonempty lines, C: separate empty-line cap.
.cs_mac_loop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call .cs_read
    jr nc, .cs_mac_done
    cp 'O' : jr z, .cs_mac_done
    cp '+' : jr nz, .cs_mac_next
    ; Find line with ':' (MAC has ':')
    ld hl, diag_buffer
    call .cs_find_colon
    jr nc, .cs_mac_next
    ; Found, look for content after ':'
    inc hl
    ; If first char is '"', skip
    ld a, (hl) : cp '"' : jr nz, .cs_mac_pr
    inc hl
.cs_mac_pr
    call printClean
.cs_mac_next
    djnz .cs_mac_loop
.cs_mac_done

    ; Hostname - AT+CWHOSTNAME?
    ld a, 12 : ld hl, .cs_hn_lbl : call printAt0
    call .cs_flush
    ld hl, .cs_hn_cmd : call Wifi.espSendZ_CRLF
    ld bc, #0640
.cs_hn_loop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call .cs_read
    jr nc, .cs_hn_done
    cp '+' : jr nz, .cs_hn_skip
    ld hl, diag_buffer
    call .cs_find_colon
    jr nc, .cs_hn_skip
    inc hl
    ld a, (hl) : cp '"' : jr nz, .cs_hn_pr
    inc hl
.cs_hn_pr
    call printClean
    jr .cs_hn_done
.cs_hn_skip
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_hn_done
    djnz .cs_hn_loop
.cs_hn_done

    ; Firmware
    ld a, 13 : ld hl, .cs_fw_lbl : call printAt0
    call .cs_flush
    ld hl, doModuleInfo.cmd_gmr : call Wifi.espSendZ_CRLF
    ld bc, #0A40
.cs_fw_loop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call .cs_read
    jr nc, .cs_fw_done
    and a : jr z, .cs_fw_next
    cp 'O' : jr z, .cs_fw_done
    cp 'E' : jr z, .cs_fw_done
    ; Filter echo "AT+GMR": check if 4th char is 'G'
    ld a, (diag_buffer + 3) : cp 'G' : jr z, .cs_fw_next
    ; Skip "AT version:" prefix if present
    ld hl, diag_buffer
    ld a, (hl) : cp 'A' : jr nz, .cs_fw_print
    ld a, (diag_buffer + 2) : cp ' ' : jr nz, .cs_fw_print
    ; Advance HL past "AT version:"
    ld de, 11 : add hl, de
.cs_fw_print
    ld b, 30 : call putStrLimited
    jr .cs_fw_done
.cs_fw_next
    djnz .cs_fw_loop
.cs_fw_done
    call .cs_flush

    IFDEF HAS_ESXDOS
    ; Saved network. Do file I/O FIRST, then rearm printer-buffer state,
    ; then print label + SSID. Order matters: esxDOS can scribble over
    ; Display.coords (#5B37), log indicator and uiLoop tick counters.
    call Config.load
    call restoreAfterFileIo
    push af
    ld a, 15 : ld hl, .cs_saved_lbl : call printAt0
    pop af
    jr c, .cs_no_saved
    ld hl, Config.cfg_buffer + Config.CFG_SSID_OFF
    call Display.putStr
    jr .cs_saved_done
.cs_no_saved
    ld hl, .cs_none : call Display.putStr
.cs_saved_done
    ENDIF

    jp pressKeyReturnDiag

; CRLF's empty tail must not spend the content-line budget; cap blank noise too.
.cs_read
    call readDiagLineBC
    jp nc, abortDiagOnBreak
    ld a, (diag_buffer)
    and a
    jr nz, .cs_read_data
    dec c
    ret z
    inc b                       ; Keep the caller's DJNZ from charging a blank line.
.cs_read_data
    scf
    ret

; Wait and flush - ensures previous AT response has been consumed
.cs_flush
    ld b, 10
.cs_flush_w
    halt
    djnz .cs_flush_w
    jp flushUartBuffer

; Helper: find ':' in string HL. CF=1 if found (HL points to ':')
.cs_find_colon
    ld a, (hl) : and a : ret z  ; CF=0
    cp ':' : jr z, .cs_fc_found
    inc hl : jr .cs_find_colon
.cs_fc_found
    scf : ret

.cs_title   db "CONFIG SUMMARY", 0
.cs_ssid    db "SSID:       ", 0
.cs_ip_lbl  = selectItem.ci_ip_lbl
.cs_gw_lbl   db "GW:         ", 0
.cs_mask_lbl = selectItem.ci_mask_lbl
.cs_mac_lbl  = selectItem.ci_mac_lbl
.cs_hn_lbl  db "Host:       ", 0
.cs_fw_lbl  db "FW:         ", 0
.cs_band24  db " (2.4G)", 0
.cs_band5   db " (5G)", 0
.cs_none    db "(none)", 0
    IFDEF HAS_ESXDOS
.cs_saved_lbl db "Saved:      ", 0
    ENDIF
.cs_mac_cmd db "AT+CIPSTAMAC?", 0
.cs_hn_cmd  db "AT+CWHOSTNAME?", 0

conn_retries = #5B20            ; In printer buffer (set before use)
; conn_result unions with baud_have_value (#5B21). Safe: connectAndReturn
; and doBaudRate are mutually exclusive modal flows that both reinit the
; byte on entry.
conn_result  = #5B21            ; Connection result: 0=OK, 1=fail (temp)
cmd_disconnect db "AT+CWQAP", 0

; Module-scope helper: print string until 0, '"', CR or LF.
; Shared by doConfigSummary and doNetworkInfo (IP/MAC values have no CR/LF).

printRowTable:
.prtLoop
    ld a, (hl)
    cp 255
    ret z
    inc hl
    call printAt0
    inc hl                      ; putStr returns HL at the string terminator.
    jr .prtLoop

showAbout:
    ld hl, .msg_about_title
    call diagHeader
    ld hl, .aboutRows
    call printRowTable
    jp pressKeyReturnList

.msg_about_title db "ABOUT NETMANZX", 0

.aboutRows:
    db 6
.msg_about_ver:
    IFDEF UNO
        db "Version ", VERSION_STRING, " (ZX-Uno)", 0
    ELSE
        IFDEF NEXT
            db "Version ", VERSION_STRING, " (Next)", 0
        ELSE
            db "Version ", VERSION_STRING, " (AY)", 0
        ENDIF
    ENDIF
    db 7
.msg_about_build db "Build: ", BUILD_DATE, 0
    db 9
.msg_about_desc  db "WiFi manager for ZX Spectrum", 0
    db 10
.msg_about_author db "By Ignacio Monge Garcia", 0
    db 11
.msg_about_github db "github.com/IgnacioMonge/NetManZX", 0
    db 12
.msg_about_license db "License: MIT", 0
    db 255

; Clock setup is included by main.asm, not here: the Next build pages it
; into the #6000 overlay, UNO ships it as a separate TAP CODE block.
