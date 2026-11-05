; Cold UI routines for NetManZX.
; Classic targets include this inline (resident). The Next target assembles it
; at #6000 into 16K bank 16 and maps it into MMU slot 3, keeping the resident
; image within its #C000 ceiling. Do not add module wrappers: this file is
; included inside 'module UI'.

    include "modules/password-input.asm"

sti_buf  = #5B56  ; dw, in printer buffer (set before use)
sti_max  = #5B58
sti_mode = #5B1D  ; 0=IP, 1=date/time, 2=signed number
sti_len  = #5B30     ; In printer buffer (set before use)
sti_line = #5B31

; Print string at row A, column 0
; Input: A = row, HL = string (zero-terminated)
; Destroys: all (via gotoXY0 + putStr)

manualSSID:
    call hideCursor
    call topClean
    
    ; Clear manual SSID buffer
    ld hl, manual_ssid_buffer
    ld b, 33
    xor a
.clearSSID
    ld (hl), a
    inc hl
    djnz .clearSSID
    xor a
    ld (manual_ssid_len), a
    ld (manual_ssid_cursor), a
    
    ; Show title in double-height green
    ld hl, .msg_manual_title
    ld c, Display.ATTR_SSID_INPUT
    call showBigMessage

    ld a, 6 : ld hl, .msg_enter_ssid : call printAt0

    ; Show cancel message
    ld a, 11 : ld hl, .msg_ssid_help : call printAt0

    call setPassRows8

; The line is already blank after topClean; draw only the live suffix.
.drawSSIDFull
.drawSSID
    halt
.drawSSIDTail
    ld a, (manual_ssid_cursor)
    ld l, a : ld h, 8
    ld (Display.coords), hl
    ld a, 127
    call Display.putCBig

    ; Chars after cursor
    ld a, (manual_ssid_len)
    ld b, a
    ld a, (manual_ssid_cursor)
    cp b
    jr nc, .ssidClearRest
    
    ; Count = len - cursor
    ld c, a
    ld a, b
    sub c
    jr z, .ssidClearRest
    ld b, a
    call getSSIDAtCursor
    
.ssidDrawAfter
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidDrawAfter

.ssidClearRest
    ld a, ' ' : call Display.putCBig
    ld a, ' ' : call Display.putCBig
    jr .ssidFinishDraw

; Draw the changed character, then the shifted suffix.
.drawSSIDInsert
    call .drawSSIDChanged
    jp .drawSSIDTail

; Append and cursor-right change the same two cells.
.drawSSIDEnd
    call .drawSSIDChanged
    ld a, 127 : call Display.putCBig
    jp .waitSSIDKey

.drawSSIDChanged
    halt
    ld a, (manual_ssid_cursor) : dec a
    ld e, a : ld l, a : ld h, 8
    ld (Display.coords), hl
    ld hl, manual_ssid_buffer : ld d, 0 : add hl, de
    ld a, (hl)
    jp Display.putCBig

; End deletion leaves the following cell blank from the prior render.
.drawSSIDDeleteEnd
    halt
    ld a, (manual_ssid_cursor) : ld l, a : ld h, 8
    ld (Display.coords), hl
    ld a, 127 : call Display.putCBig
    ld a, ' ' : call Display.putCBig
    jp .waitSSIDKey

; Max SSID length reached: red border flash feedback
.ssidMaxLen
    ld a, 2 : out (#FE), a
    halt : halt
    xor a : out (#FE), a

.ssidFinishDraw
.waitSSIDKey
    ld b, 4
.waitSSIDLoop
    halt
    call Keyboard.checkBreak : jp z, .cancelManual
    djnz .waitSSIDLoop
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitSSIDKey
    call Keyboard.keyClick

    ; Cursor left
    cp 8 : jr z, .ssidCursorLeft

    ; Cursor right
    cp 9 : jp z, .ssidCursorRight

    ; Delete
    cp Keyboard.KEY_BS : jp z, .removeSSIDChar

    ; Enter = proceed to password
    cp 13 : jp z, .ssidEntered
    
    ; Filter valid characters (32-126)
    cp 32 : jr c, .waitSSIDKey
    cp 127 : jr nc, .waitSSIDKey
    
    ; === Insert character ===
    ld c, a                         ; Save char
    ld a, (manual_ssid_len)
    cp 32                           ; Max 32 chars
    jr nc, .ssidMaxLen
    
    ; Check if inserting at end or in the middle
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    cp b
    jr z, .ssidInsertAtEnd
    
    ; Insert in middle: shift characters right
    ld a, (manual_ssid_len)
    ld b, a
    ld a, (manual_ssid_cursor)
    ld e, a
    ; HL = manual_ssid_buffer + len (maintain across loop)
    ld hl, manual_ssid_buffer
    ld d, 0
    push de
    ld e, b
    add hl, de
    pop de
.ssidShiftRight
    ld a, b
    cp e
    jr z, .ssidDoInsert
    dec b
    dec hl
    ld a, (hl)
    inc hl
    ld (hl), a
    dec hl
    jr .ssidShiftRight

.ssidInsertAtEnd
.ssidDoInsert
    ; Insert character
    call getSSIDAtCursor
    ld (hl), c
    
    ; Increment length
    ld a, (manual_ssid_len)
    inc a
    ld (manual_ssid_len), a
    
    ; Set null terminator
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    
    ; Increment cursor
    ld a, (manual_ssid_cursor)
    inc a
    ld (manual_ssid_cursor), a
    ld b, a
    ld a, (manual_ssid_len) : cp b
    jp z, .drawSSIDEnd
    jp .drawSSIDInsert

.ssidCursorLeft
    ld a, (manual_ssid_cursor)
    and a
    jp z, .waitSSIDKey
    dec a
    ld (manual_ssid_cursor), a
    halt
    ld l, a : ld h, 8 : ld (Display.coords), hl
    ld a, 127 : call Display.putCBig
    call getSSIDAtCursor
    ld a, (hl) : call Display.putCBig
    jp .waitSSIDKey

.ssidCursorRight
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    cp b
    jp z, .waitSSIDKey
    ld a, (manual_ssid_cursor)
    inc a
    ld (manual_ssid_cursor), a
    jp .drawSSIDEnd

.removeSSIDChar
    ld a, (manual_ssid_cursor)
    and a
    jp z, .waitSSIDKey
    
    ; Check if deleting at end or in the middle
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    cp b
    jr z, .ssidDeleteAtEnd
    
    ; Delete in middle: shift characters left
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    ld c, a
    ; HL = manual_ssid_buffer + cursor (maintain across loop)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, b
    add hl, de
.ssidShiftLeft
    ld a, b
    cp c
    jr z, .ssidFinishDelete
    ld a, (hl)
    dec hl
    ld (hl), a
    inc hl
    inc hl
    inc b
    jr .ssidShiftLeft

.ssidDeleteAtEnd
.ssidFinishDelete
    ; Decrement length
    ld a, (manual_ssid_len)
    dec a
    ld (manual_ssid_len), a
    
    ; Set null terminator
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    
    ; Decrement cursor
    ld a, (manual_ssid_cursor)
    dec a
    ld (manual_ssid_cursor), a
    ld b, a
    ld a, (manual_ssid_len) : cp b
    jp z, .drawSSIDDeleteEnd
    jp .drawSSID

.cancelManual
    setLineColor 8, Display.ATTR_NORMAL
    jp renderListAndLoop

.msg_ssid_help db "BREAK=cancel, L/R=move cursor", 0

.ssidEntered
    ; Check there is an SSID
    ld a, (manual_ssid_len)
    and a
    jp z, .waitSSIDKey              ; Empty SSID, keep waiting
    
    ; Now request password
    setLineColor 6, Display.ATTR_NORMAL
    call topClean
    
    ; Show selected SSID
    ld a, 3 : ld hl, msg_ssid : call printAt0
    ; SSID in double-height green (rows 4-5)
    ld a, 4 : ld hl, manual_ssid_buffer : call printAt0
    call Display.stretchRows45
    ld a, 4 : ld c, Display.ATTR_SSID_INPUT : call setDoubleAttr

    ; Prepare password input
    xor a
    ld (is_open_network), a         ; Assume closed network
    call clearPassBuffer

    ld a, 6 : ld hl, msg_pass : call printAt0

    ld a, 7 : ld b, 2 : ld c, Display.ATTR_PASS_INPUT : call setRowsColor
    xor a
    ld (show_password), a
    ld (pass_cursor), a

    ; Password input using shared routine (pass_line=7 = default)
    call passwordInput
    jr c, .cancelManual

.connectManual
    ; Show final asterisks
    gotoXY 1, 7
    ld a, (pass_len)
    and a
    jr z, .noAsterManual
    ld b, a
.showConnAsterManual
    push bc
    ld a, '*'
    call Display.putC
    pop bc
    djnz .showConnAsterManual
.noAsterManual
    ld a, ' ' : call Display.putC
    
    ; manual_ssid_buffer and pass_buffer already set
    xor a : ld (is_reconnect), a
    dec a : ld (selected_real_idx), a
    jp connectAndReturn

.msg_manual_title db "Hidden Network (Manual SSID)", 0
.msg_enter_ssid   db "Enter network SSID:", 0

    RTVAR manual_ssid_buffer, 33
; In printer buffer (set before use)
manual_ssid_len    = #5B2E
manual_ssid_cursor = #5B2F

; Diagnostics and the text editor live in diag-ui.asm so the TAP builds can
; page them; see the include sites in ui.asm and main.asm.
