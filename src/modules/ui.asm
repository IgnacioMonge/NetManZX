    module UI
PER_PAGE = 10
MAX_PASS_LEN = 40           

init:
    call invalidateRowCache
    call Display.clrscr
    ; Render status bar FIRST to avoid blank white bar flicker
    ld hl, status_scanning_data
    ld a, (hl) : ld (status_color), a
    inc hl : ld (status_text_ptr), hl
    call ipShowScanning         ; Sets IP text + renders full status bar
    ; Double-height banner: rows 0-1
    setLineColor 0, Display.ATTR_BANNER_TOP
    setLineColor 1, Display.ATTR_BANNER_BOT
    xor a : call Display.gotoXY0 : printMsg msg_head
    call Display.stretchRows01
    call drawBadge
    call drawSeparator
    jp clearPassBuffer

; SpectalkZX-style badge: dithered triangle with color transitions
; Row 0 (top): 4 cells at bytes 28-31 (staggered, 1 cell less)
; Row 1 (bot): 5 cells at bytes 27-31 (full)
; Spectrum colors: red, yellow, green, blue

badge_pattern:
    db #00, #01, #03, #07, #0F, #1F, #3F, #7F
badge_attrs:
    db 01000010b, 01010110b, 01110100b, 01100001b, 01001000b

drawBadge:
    ; Pixels: row 0, 4 cells at bytes 28-31
    ld hl, #401C            ; Row 0, scanline 0, byte 28
    ld c, 4
    call .drawCells
    ; Pixels: row 1, 5 cells at bytes 27-31
    ld hl, #403B            ; Row 1, scanline 0, byte 27
    ld c, 5
    call .drawCells
    ; Attributes row 0 (top): 4 cells BRIGHT
    ld hl, #581C            ; Row 0, cell 28
    ld de, badge_attrs
    ld b, 4
    call .drawAttrs
    ; Attributes row 1 (bot): 5 cells BRIGHT
    ld hl, #583B            ; Row 1, cell 27
    ld de, badge_attrs
    ld b, 5
.drawAttrs:
    ld a, (de)
    ld (hl), a
    inc hl
    inc de
    djnz .drawAttrs
    ret

; Draw triangular dither pattern in C consecutive cells
; Input: HL = screen address (scanline 0), C = number of cells
.drawCells:
    ld de, badge_pattern
    ld b, 8
.scanLoop
    push bc
    push hl
    ld a, (de)
    ld b, c                 ; B = number of cells
.byteLoop
    ld (hl), a
    inc l
    djnz .byteLoop
    pop hl
    inc h                   ; next scanline
    inc de
    pop bc
    djnz .scanLoop
    ret

; White 1px separator line below banner (row 2, scanline 0)
drawSeparator:
    ld a, 2
    ld e, 0
    jp Display.draw_hline_only

; Clear pixels of 1 screen row (8 scanlines x 32 bytes)
; Input: A = row number (0-23)
; Destroys: AF, BC, DE, HL
clearRowPixels:
    ld d, a
    ld c, 31                    ; 32 bytes - 1 for LDIR
    ; fall through
; Clear 8 scanlines starting at row D, width C+1 bytes
; Input: D = start row, C = bytes per scanline - 1
; Destroys: AF, BC, DE, HL
clearPixelRows:
    ld e, 0
    call Display.findAddr
    ld b, 8
.lp: push bc : push de
    ld h, d : ld l, e
    ld (hl), 0
    ld d, h : ld e, l : inc de
    ld b, 0                     ; BC = C (width-1)
    ldir
    pop de : pop bc
    inc d
    djnz .lp
    ret

clearRows34Pixels:
    ld a, 3
    call clearRowPixels
    ld a, 4
    jp clearRowPixels

; ============================================
; statusBarFinalize - Render double-height status bar (rows 17-18)
; Reads: ip_line_buffer, status_text_ptr, ip_value_color, status_color
; ============================================
statusBarFinalize:
    ; Render text directly (no clear first = no flicker)
    ld a, 18 : ld hl, ip_line_buffer : call printAt0
    ; Pad with spaces up to column 24 (clear leftover from previous IP)
.padIP
    ld a, (Display.coords)
    cp 24
    jr nc, .padDone
    ld a, ' '
    call Display.putC
    jr .padIP
.padDone
    gotoXY 24, 18
    ld hl, msg_wifi_label
    call Display.putStr
    gotoXY 30, 18
    ld hl, (status_text_ptr)
    call Display.putStr
    call Display.stretchRows1819
    ; Shift text 1px down: clear scanline 0 of row 18
    ld hl, #5040
    ld de, #5041
    xor a : ld (hl), a
    ld bc, 31
    ldir
    setLineColor 18, Display.ATTR_STATUSBAR
    setLineColor 19, Display.ATTR_STATUS_BOT
    ld a, (ip_value_color)
    call colorIpValueBothRows
    ld a, (status_color)
    jp colorStatusAreaBothRows


; Show "IP: Scanning..."
ipShowScanning:
    ld hl, msg_ip_scanning
    jr ipSetPrefixedStatusbar

; Show "IP:Disconnected" in red
ipShowNotConnected:
    ld hl, status_disconn_data + 1
    call ipSetPrefixed
    ld a, Display.ATTR_STATUS_DISC
    ld (ip_value_color), a
    jr statusBarFinalize

; Set IP from Z-string + default status bar color + render
ipSetPrefixedStatusbar:
    call ipSetPrefixed
    ld a, Display.ATTR_STATUSBAR
    ld (ip_value_color), a
    jr statusBarFinalize

; Show "IP: x.x.x.x" in blue, or "IP: ---" if query fails
ipShowConnected:
    call Wifi.getIP
    jr c, .ipUnknown
    ld hl, Wifi.ip_buffer
    call ipSetPrefixed
    ld a, Display.ATTR_PASS_INPUT
    ld (ip_value_color), a
    jp statusBarFinalize
.ipUnknown
    ld hl, msg_ip_unknown
    jr ipSetPrefixedStatusbar

; Color IP value area (cells 3-17) on both rows 18-19
colorIpValueBothRows:
    ld hl, #5A40 + 3        ; Line 18, cell 3
    ld b, 15
.loop18
    ld (hl), a
    inc hl
    djnz .loop18
    res 6, a                ; Remove BRIGHT for row 19
    ld hl, #5A60 + 3        ; Line 19, cell 3
    ld b, 15
.loop19
    ld (hl), a
    inc hl
    djnz .loop19
    ret

; --- helpers to build IP line in ip_line_buffer ---
; HL -> Z-string (0-terminated) to copy into ip_line_buffer
ipSetFromZ:
    ld de, ip_line_buffer
.copy
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    and a
    jr nz, .copy
    ret

; Append Z-string (HL) to the end of ip_line_buffer
ipAppendZ:
    ; find null terminator in buffer
    ld de, ip_line_buffer
.find0
    ld a, (de)
    and a
    jr z, .atEnd
    inc de
    jr .find0
.atEnd
.copyA
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    and a
    jr nz, .copyA
    ret

ipSetPrefixed:
    push hl
    ld hl, msg_ip_prefix
    call ipSetFromZ
    pop hl
    jp ipAppendZ

; Buffers/messages
msg_ip_prefix      db "IP: ", 0
msg_ip_unknown     db "---", 0
msg_ip_scanning    db "Scanning...", 0
    RTVAR ip_line_buffer, 40

; Color status area (cells 22-31) on both rows 18-19
colorStatusAreaBothRows:
    ld hl, #5A40 + 22           ; Line 18, cell 22
    ld b, 10
.loop18
    ld (hl), a
    inc hl
    djnz .loop18
    res 6, a                    ; Remove BRIGHT for row 19
    ld hl, #5A60 + 22           ; Line 19, cell 22
    ld b, 10
.loop19
    ld (hl), a
    inc hl
    djnz .loop19
    ret

; Common routine for status (quiet: variables only, no render)
setStatusCommon_q:
    ld a, (hl)
    ld (status_color), a
    inc hl
    ld (status_text_ptr), hl
    ret

; Common routine for status (with render)
; Input: HL = pointer to data (color, message)
setStatusCommon:
    call setStatusCommon_q
    jp statusBarFinalize

ip_value_color db Display.ATTR_STATUSBAR

; Status data: color (1 byte) + message
status_scanning_data:
    db Display.ATTR_STATUSBAR   ; Black on bright white
    db "Scanning    ", 0
status_connected_data:
    db Display.ATTR_STATUS_CONN
    db "Connected   ", 0
status_disconn_data:
    db Display.ATTR_STATUS_DISC
    db "Disconnected", 0
msg_conn_lost      db "Connection lost!", 13, 10, 0

; Update status from Wifi.is_connected (quiet: no render)
updateWifiStatus_q:
    ld a, (Wifi.is_connected)
    and a
    ld hl, status_disconn_data
    jr z, setStatusCommon_q
    ld hl, status_connected_data
    jr setStatusCommon_q

; Update status from Wifi.is_connected (with render)
updateWifiStatus:
    ld a, (Wifi.is_connected)
    and a
    ld hl, status_disconn_data
    jr z, setStatusCommon
    ld hl, status_connected_data
    jr setStatusCommon

clearPassBuffer:
    ld hl, pass_buffer
    ld de, pass_buffer + 1
    xor a
    ld (hl), a
    ld bc, MAX_PASS_LEN - 1   ; -1 because the first byte is already written
    ldir
    xor a
    ld (pass_len), a
    ld (pass_cursor), a
    ret

; ============================================
; passwordInput - Shared password input routine
; Uses: pass_buffer, pass_len, pass_cursor, show_password
; Output: CF=0 if ENTER, CF=1 if CANCEL (BREAK)
; ============================================
PASS_LINE_DEFAULT = 7
pass_line   db PASS_LINE_DEFAULT   ; Line where password is drawn
pass_no_warn db 0                  ; 1 = force blue even when show_password=1 (hostname, no secret)

passwordInput:
    ; Debounce: wait for previous key release
.piDebounce
    halt
    call Keyboard.inKeyNoWait
    and a
    jr nz, .piDebounce
; --- Full redraw (only for toggle and init) ---
.piRedraw
    ld a, (show_password) : and a
    ld c, Display.ATTR_PASS_INPUT
    jr z, .piAttrOk
    ld a, (pass_no_warn) : and a
    jr nz, .piAttrOk
    ld c, Display.ATTR_PASS_EXPOSED
.piAttrOk
    ld a, (pass_line) : ld b, 2 : call setRowsColor
    halt
    ld a, (pass_line)
    ld h, a : ld l, 0
    ld (Display.coords), hl
    ld a, (pass_cursor) : and a : jr z, .piCursor
    ld b, a : ld hl, pass_buffer
    ld a, (show_password) : and a : jr nz, .piRealB
    ; Masked: decompress '*' once, reuse for all positions
    ld a, '*' : call Display.decompressChar
.piAstB
    push bc : call Display.putCBigGlyph : pop bc : djnz .piAstB
    jr .piCursor
.piRealB
    push bc : push hl : ld a, (hl) : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piRealB
.piCursor
    ld a, 127 : call Display.putCBig
    ld a, (pass_len) : ld b, a : ld a, (pass_cursor) : cp b : jr nc, .piClrTail
    ld c, a : ld a, b : sub c : jr z, .piClrTail : ld b, a
    ld a, (pass_cursor) : ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de
    ld a, (show_password) : and a : jr nz, .piRealA
    ; Masked: re-decompress (cursor draw overwrote glyph_buf)
    ld a, '*' : call Display.decompressChar
.piAstA
    push bc : call Display.putCBigGlyph : pop bc : djnz .piAstA
    jr .piClrTail
.piRealA
    push bc : push hl : ld a, (hl) : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piRealA
.piClrTail
    ; Clear up to 2 trailing cells, clamped to col 41 max
    ld a, (Display.coords) : cp 42 : jr nc, .piWait
    ld a, ' ' : call Display.putCBig
    ld a, (Display.coords) : and a : jr z, .piWait
    ld a, ' ' : call Display.putCBig
    ; putCBig already writes double-height -- do NOT stretch
    jr .piWait

; --- Helpers for incremental rendering ---
; Position screen cursor at column B+1, row pass_line
.piSetPos
    ld a, (pass_line) : ld h, a
    ld l, b
    ld (Display.coords), hl
    ret

; Draw char from buffer at position B (* or real depending on show_password)
.piDrawBufAt
    call .piSetPos
    ld a, (show_password) : and a
    jr nz, .piDrawReal
    ld a, '*'
    jp Display.putCBig
.piDrawReal
    ld hl, pass_buffer : ld d, 0 : ld e, b : add hl, de
    ld a, (hl)
    jp Display.putCBig

; Draw block cursor at position B
.piDrawCurAt
    call .piSetPos
    ld a, 127
    jp Display.putCBig

; Draw space at position B
.piDrawSpcAt
    call .piSetPos
    ld a, ' '
    jp Display.putCBig

; EI + jp .piWait (shared tail for incremental handlers)
.piStretchWait
    ei
    jr .piWait

; Max length reached: red border flash feedback
.piMaxLen
    ld a, 2 : out (#FE), a
    halt : halt
    xor a : out (#FE), a
    jr .piWait

; --- Key wait loop ---
.piWait
    ld b, 4
.piWL   halt
    call Keyboard.checkBreak : jp z, .piCancel
    djnz .piWL
    call Keyboard.inKeyNoWait : and a : jr z, .piWait
    call Keyboard.keyClick
    cp Keyboard.KEY_UP : jp z, .piToggle
    cp 8 : jp z, .piLeft
    cp 9 : jp z, .piRight
    cp Keyboard.KEY_BS : jp z, .piDel
    cp 13 : jp z, .piEnter
    cp 32 : jr c, .piWait
    cp 127 : jr nc, .piWait

    ; --- Insert character ---
    ld c, a
    ld a, (pass_len)
    cp MAX_PASS_LEN
.max = $ - 1
    jr nc, .piMaxLen
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : cp b
    jr nz, .piInsMid                ; Cursor in middle -> full redraw

    ; === APPEND AT END (common case) ===
    ld a, (pass_cursor) : ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de
    ld (hl), c : inc hl : ld (hl), 0
    ld a, (pass_len) : inc a : ld (pass_len), a
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    ; Render: reload B from memory before EACH call (drawCBig destroys regs)
    ld a, (pass_cursor) : dec a : ld b, a      ; B = pos of new char
    call .piDrawBufAt
    ld a, (pass_cursor) : ld b, a              ; B = new cursor pos
    call .piDrawCurAt
    ld a, (pass_cursor) : inc a : ld b, a      ; B = next pos (clear)
    call .piDrawSpcAt
    jr .piWait

    ; Insert in middle -> shift + full redraw
.piInsMid
    ld a, (pass_len) : ld b, a : ld a, (pass_cursor) : ld e, a
    ; HL = pass_buffer + len (maintain across loop)
    ld hl, pass_buffer : ld d, 0 : push de : ld e, b : add hl, de : pop de
.piShR  ld a, b : cp e : jr z, .piIns
    dec b : dec hl
    ld a, (hl) : inc hl : ld (hl), a : dec hl
    jr .piShR
.piIns  ld (hl), c              ; HL = pass_buffer + cursor
    ld a, (pass_len) : inc a : ld (pass_len), a
    ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de : xor a : ld (hl), a
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    jp .piRedraw

; --- Cursor left (drain ghost '5' from ROM, then redraw) ---
.piLeft ld a, (pass_cursor) : and a : jp z, .piWait
    dec a : ld (pass_cursor), a
    halt : call Keyboard.inKeyNoWait
    jp .piRedraw

; --- Cursor right (drain ghost '8' from ROM, then redraw) ---
.piRight
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : cp b : jp z, .piWait
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    halt : call Keyboard.inKeyNoWait
    jp .piRedraw

; --- Toggle show/hide (full redraw, rare) ---
.piToggle ld a, (show_password) : xor 1 : ld (show_password), a : jp .piRedraw

; --- Delete character ---
.piDel  ld a, (pass_cursor) : and a : jp z, .piWait
    ld b, a : ld a, (pass_len) : cp b : jr z, .piDelEnd
    ; Delete in middle -> shift + full redraw
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : ld c, a
    ; HL = pass_buffer + cursor (maintain across loop)
    ld hl, pass_buffer : ld d, 0 : ld e, b : add hl, de
.piShL  ld a, b : cp c : jr z, .piDelEnd
    ld a, (hl) : dec hl : ld (hl), a : inc hl : inc hl
    inc b : jr .piShL
.piDelEnd
    ld a, (pass_len) : dec a : ld (pass_len), a
    ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de : xor a : ld (hl), a
    ld a, (pass_cursor) : dec a : ld (pass_cursor), a
    ; === DELETE AT END (common case): incremental ===
    ld b, a : ld a, (pass_len) : cp b
    jp nz, .piRedraw                ; If cursor != len -> was delete in middle, full redraw
    ; Cursor == len: incremental render (reload B from memory each time)
    ld a, (pass_cursor) : ld b, a
    call .piDrawCurAt
    ld a, (pass_cursor) : inc a : ld b, a
    call .piDrawSpcAt
    ld a, (pass_cursor) : add a, 2 : ld b, a
    call .piDrawSpcAt
    jp .piWait

.piEnter or a : ret
.piCancel scf : ret

sti_buf  = #5B56  ; dw, in printer buffer (set before use)
sti_max  = #5B58
sti_len  = #5B30     ; In printer buffer (set before use)
sti_line = #5B31

; Print string at row A, column 0
; Input: A = row, HL = string (zero-terminated)
; Destroys: all (via gotoXY0 + putStr)
printAt0:
    push hl
    call Display.gotoXY0
    pop hl
    jp Display.putStr

; Show "Press any key", wait, return to list
pressKeyReturnList:
    call showPressKey
    call waitAnyKey
    jp renderListAndLoop

; Show "Press any key", wait, return to diagnostics
pressKeyReturnDiag:
    call showPressKey
; Wait for key, return to diagnostics
waitKeyReturnDiag:
    call waitAnyKey
    jp showDiagnostics

; Debounce: drain 15 frames of key input
debounce15:
    ld b, 15
.loop: halt
    call Keyboard.inKeyNoWait
    djnz .loop
    ret


; Set rows 8-9 to password input color
setPassRows8:
    ld a, 8
    ld b, 2
    ld c, Display.ATTR_PASS_INPUT
    jr setRowsColor

; HL = &manual_ssid_buffer[cursor] (preserves BC)
getSSIDAtCursor:
    ld a, (manual_ssid_cursor)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    ret

; Clear content area, show big alert message
; Input: HL = message string
topCleanAlertMsg:
    push hl
    call topClean
    pop hl
    ld c, Display.ATTR_ALERT
    jp showBigMessage

; Copy zero-terminated string from HL to DE (max MAX_SSID_LEN bytes + null)
copyStringZ:
    ld b, MAX_SSID_LEN
.loop
    ld a, (hl)
    ld (de), a
    and a
    ret z
    inc hl
    inc de
    djnz .loop
    ; Safety: ensure null terminator
    xor a
    ld (de), a
    ret

; Set B consecutive rows starting from row A to color C
; Destroys: all (via Display.setAttr)
setRowsColor:
    push af, bc
    call Display.setAttr
    pop bc, af
    inc a
    djnz setRowsColor
    ret

; Set row A with BRIGHT color C, row A+1 with same color minus BRIGHT
; (double-height text convention). Destroys: all.
setDoubleAttr:
    push af, bc
    call Display.setAttr        ; row A, BRIGHT
    pop bc, af
    inc a
    res 6, c                    ; remove BRIGHT
    jp Display.setAttr          ; row A+1, no BRIGHT (tail call)

; Clear pixel rows with LDIR
; Input: D = start row, C = bytes per scanline - 1
; Destroys: AF, BC, DE, HL

topClean:
    call invalidateRowCache
    call Display.clrListOnly    ; Only clears lines 2-14
    call clearListAttrs
    jp drawSeparator            ; Redraw separator (includes ret)

; Clear only the networks area (lines 6-15) - for sort/rescan
clearNetworksArea:
    call invalidateRowCache
    jp Display.clrNetworksOnly

; renderNetworksOnly - Redraws ONLY the network list (lines 6-15).
; Does not touch indicators/upper menu (scroll/page info).
; Used for disconnect refreshes to avoid flicker/changes above.
renderNetworksOnly:
    jr renderNetworksCommon

; renderListOnly - Redraws only networks + indicators, not the help text
; Used by sort and rescan to avoid flicker
renderListOnly:
    call showPageInfo
    call showScrollIndicators
    jp renderNetworksCommon

; ============================================
; renderNetworksCommon - Common routine to draw network list
; Input: area already cleared
; ============================================
renderNetworksCommon:
    call normalizeListPosition
    ; Position at line 6 to start listing
    ld a, 6 : call Display.gotoXY0

    ; No connected row highlighted on this page yet
    ld a, #FF
    ld (conn_row_found), a

    ; Calculate how many networks to show on this page
    ld a, (Wifi.networks_count)
    ld hl, offset
    sub (hl)
    jp c, .noNetworks
    cp PER_PAGE
    jr c, .gotCount
    ld a, PER_PAGE
.gotCount
    ld b, a

    ; Check there are networks
    and a
    jp z, .noNetworks

    ; Initialize current screen index
    ld a, (offset)
    ld (current_screen_idx), a

    ; Initialize current line (start at 6)
    ld a, 6
    ld (current_line), a

.showLoop
    push bc

    ; Get SSID pointer using findRow (respects display_indices)
    ld a, (current_screen_idx)
    ld d, a
    call findRow                ; HL = pointer to SSID

    ld c, Display.ATTR_NORMAL

    ; Highlight saved/known network (before connected, so connected takes priority)
    IFDEF HAS_ESXDOS
    ld a, (cfg_valid)
    and a
    jr z, .noSavedAttr
    ld a, (hl)
    and a
    jr z, .noSavedAttr              ; Empty SSID -> skip
    push hl
    ld de, Config.cfg_buffer + Config.CFG_SSID_OFF
    call Display.compareStringZ
    pop hl
    jr nz, .noSavedAttr
    ld c, Display.ATTR_SAVED
.noSavedAttr
    ENDIF

    ; Highlight connected SSID if applicable
    ld a, (Wifi.is_connected)
    and a
    jr z, .noConnAttr
    
    ; If we already found the connected network on this page, don't search further
    ld a, (conn_row_found)
    cp #FF
    jr nz, .noConnAttr
    
    ld a, (hl)
    and a
    jr z, .noConnAttr           ; Empty SSID -> don't highlight
    push hl
    ld de, Wifi.connected_ssid
    call Display.compareStringZ
    pop hl
    jr nz, .noConnAttr
    
    ; Store the cursor row (0..PER_PAGE-1) highlighted as connected
    ld a, (current_line)
    sub 6
    ld (conn_row_found), a
    
    ld c, Display.ATTR_CONNECTED
.noConnAttr
    ; Publish the final name attribute once, including the selected row.
    ld a, (current_line)
    sub 6
    ld de, cursor_position
    ld b, a
    ld a, (de)
    cp b
    jr nz, .rowAttrReady
    ld a, c
    ld c, Display.ATTR_HIGHLIGHT
    cp Display.ATTR_CONNECTED
    jr nz, .rowAttrReady
    ld c, Display.ATTR_CONN_CURSOR
.rowAttrReady
    push hl
    ld a, (current_line)
    call Display.setAttrPartial
    pop hl
    ; Check if SSID is empty (hidden network)
    ld a, (hl)
    and a
    jr nz, .printSSID
    ld hl, msg_hidden           ; Empty SSID - show "<hidden>"
.printSSID
    call rowPixelsChanged
    jr z, .rowReady
    ld a, (current_line)
    call Display.beginRow
    ; Print SSID limited to 29 chars (leave room before RSSI)
    ld b, 29
    call putStrLimited

    ; Move cursor to fixed column (30) for RSSI
    ld a, (current_line)
    ld h, a
    ld l, 30
    ld (Display.coords), hl

    ; Show RSSI indicator (uses current_screen_idx)
    call printRssi
    call Display.endRow
.rowReady

    ; Increment screen index
    ld a, (current_screen_idx)
    inc a
    ld (current_screen_idx), a

    ; Increment line
    ld a, (current_line)
    inc a
    ld (current_line), a

    ; Advance coords to next line (X=0, Y++)
    ld hl, Display.coords
    xor a : ld (hl), a
    inc hl : inc (hl)

    pop bc
    dec b
    jp nz, .showLoop
    jr .clearRemaining

.noNetworks
    xor a
    ld (row_cache + 30), a
    ld a, 6
    ld (current_line), a
    call .clearRemaining
    ld a, (skip_footer)
    and a
    ret nz
    ld a, 6 : ld hl, no_net_msg : jp printAt0

.clearRemaining
    ; Publish blank rows only where the new page has fewer entries.
    ld a, (current_line)
    cp 16
    ret nc
    call rowCacheAddress
    ld hl, 30
    add hl, de
    ld a, (hl)
    cp 2
    jr z, .nextBlank
    ld (hl), 2
    ld a, (current_line)
    call Display.beginRow
    call Display.endRow
    ld a, (current_line)
    ld c, Display.ATTR_NORMAL
    call Display.setAttr
.nextBlank
    ld hl, current_line
    inc (hl)
    jr .clearRemaining

 ; Each exact descriptor stores 29 visible chars, RSSI/open bit and validity.
    RTVAR row_cache, PER_PAGE * 32

invalidateRowCache:
    ld hl, row_cache + 30
    ld de, 32
    ld b, PER_PAGE
    xor a
.loop
    ld (hl), a
    add hl, de
    djnz .loop
    ret

; A = screen row (6..15), DE = descriptor; preserves HL.
rowCacheAddress:
    push hl
    sub 6
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, row_cache
    add hl, de
    ex de, hl
    pop hl
    ret

; HL = displayed name; Z = identical pixels. Refresh key; preserve HL.
rowPixelsChanged:
    ld a, (current_line)
    call rowCacheAddress
    push hl
    ld b, 29
    ld c, 0
.name
    ld a, (de)
    xor (hl)
    or c
    ld c, a
    ld a, (hl)
    ld (de), a
    and a
    jr z, .padded
    inc hl
.padded
    inc de
    djnz .name
    push de
    ld a, (current_screen_idx)
    call Wifi.getDisplayIndex
    ld hl, Wifi.rssi_buffer
    ld e, a
    ld d, 0
    add hl, de
    ld b, (hl)
    pop de
    ld a, (de)
    xor b
    or c
    ld c, a
    ld a, b
    ld (de), a
    inc de
    ld a, (de)
    cp 1
    jr z, .valid
    ld c, 1
.valid
    ld a, 1
    ld (de), a
    ld a, c
    or a
    pop hl
    ret

msg_hidden db "<hidden>", 0

; ============================================
; putStrLimited - Print Z-terminated string with limit
; Input: HL = string pointer, B = max characters
; ============================================
putStrLimited:
.loop
    ld a, (hl)
    and a
    ret z               ; End of string
    push hl
    push bc
    call Display.putC
    pop bc
    pop hl
    inc hl
    djnz .loop
    ret

; Clear attributes for lines 2-17 (white on black)
; Optimized with LDIR
clearListAttrs:
    ld hl, #5800 + 64           ; Line 2, column 0
    ld a, Display.ATTR_NORMAL   ; White on black
    ld (hl), a                  ; First byte
    ld de, #5800 + 65           ; Dest = source + 1
    ld bc, 16 * 32 - 1          ; 16 lines (2-17) * 32 - 1 = 511 bytes
    ldir
    ret


; Show double-height text on rows 3-4
; Input: HL = text, C = color with BRIGHT for row 3
; Row 4 = same color without BRIGHT
showBigMessage:
    push bc
    push hl
    ld a, 3 : call Display.gotoXY0
    pop hl
    call Display.putStr
    call Display.stretchRows34
    pop bc
    push bc                     ; Preserve color (setAttr destroys BC)
    ld a, 3
    call Display.setAttr        ; Row 3: BRIGHT
    pop bc
    ld a, c : res 6, a : ld c, a
    ld a, 4
    jp Display.setAttr          ; Row 4: without BRIGHT

; ============================================
; Shorthand: renderListOnly + jp uiLoop (page navigation only)
renderPageAndLoop:
    call renderListOnly
    jp uiLoop

; ============================================
renderPageFromOffsetTop:
    ld (offset), a
    xor a
    ld (cursor_position), a
    jp renderPageAndLoop

; Shorthand: renderList + jp uiLoop
; If no networks (e.g. first entry from diagnostics), trigger a fresh scan
renderListAndLoop:
    ld a, (Wifi.networks_count)
    and a
    jr nz, .hasNetworks
    ; No networks yet — show full menu, then scan to populate
    ld a, 1 : ld (skip_footer), a  ; suppress "no networks" msg and footer
    call renderList
    xor a : ld (skip_footer), a    ; clear flag
    jp rescan
.hasNetworks                    ; and refreshes network list
    call renderList
    jp uiLoop

; renderList - Draw full list with help text
; ============================================
renderList:
    call topClean

    ; Show help on line 3 (depends on connection state)
    ld a, 3 : call Display.gotoXY0
    ld a, (Wifi.is_connected)
    and a
    jr z, .showHelpDisconn
    ld hl, msg_help_conn       ; Connected: includes X:Disconnect
    jr .printHelp
.showHelpDisconn
    ld hl, msg_help            ; Not connected
.printHelp
    call Display.putStr

    ; Show help line 2 on line 4
    ld a, 4 : ld hl, msg_help2 : call printAt0

    ; Separator line below menu
    ld a, 5 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline

    call showPageInfo
    call showScrollIndicators

    ; Use common routine to draw networks
    jp renderNetworksCommon

no_net_msg db "No networks found. Press 'R' to rescan.", 0
; ============================================
; Show scroll arrows on line 17 (same row as page info)
; DOWN at Col 0 (left), UP at Col 41 (right)
; Must be called AFTER showPageInfo (which clears row 17)
; ============================================
showScrollIndicators:
    ; 1. Check DOWN arrow (Offset + PER_PAGE < Count) - LEFT
    ld a, (offset)
    add a, PER_PAGE
    ld b, a
    ld a, (Wifi.networks_count)
    cp b
    jr c, .chkUp            ; No more below
    jr z, .chkUp            ; Equal

    ld a, 17 : call Display.gotoXY0
    ld a, '{'               ; Down arrow glyph
    call Display.putC

.chkUp
    ; 2. Check UP arrow (Offset > 0) - RIGHT
    ld a, (offset)
    and a
    ret z                   ; No more above

    gotoXY 41, 17
    ld a, '}'               ; Up arrow glyph
    jp Display.putC

; ============================================
; clampOffsetToCount
;   Ensures 'offset' doesn't point beyond range after a rescan.
;   If offset >= networks_count, adjusts to start of last page.
;   If networks_count == 0, offset = 0.
; ============================================
clampOffsetToCount:
    ld a, (Wifi.networks_count)
    and a
    jr nz, .have
    xor a
    ld (offset), a
    ret

.have
    ld b, a                      ; B = count
    ld a, (offset)
    cp b
    ret c                        ; offset < count -> OK

    ; Calculate last_start = ((count-1)/PER_PAGE)*PER_PAGE
    ld a, b
    dec a                        ; A = count-1
    ld b, 0                      ; B = last_start
.div
    sub PER_PAGE
    jr c, .done
    ld c, a
    ld a, b
    add a, PER_PAGE
    ld b, a
    ld a, c
    jr .div
.done
    ld a, b
    ld (offset), a
    ret

; Clamp the cursor to the visible items after a scan changed the list.
normalizeListPosition:
    call clampOffsetToCount
    ld a, (Wifi.networks_count)
    and a
    jr z, .zero
    ld b, a
    ld a, (offset)
    ld c, a
    ld a, b
    sub c
    cp PER_PAGE
    jr c, .countOk
    ld a, PER_PAGE
.countOk
    ld b, a
    ld a, (cursor_position)
    cp b
    ret c
    ld a, b
    dec a
    ld (cursor_position), a
    ret
.zero
    xor a
    ld (cursor_position), a
    ret

; ============================================
; printRssi - Print signal indicator
; Uses current_screen_idx to get real index via display_indices
; ============================================
printRssi:
    ; Get real index using display_indices
    ld a, (current_screen_idx)
    call Wifi.getDisplayIndex   ; A = real network index
    
    ; Get RSSI for that network
    ld hl, Wifi.rssi_buffer
    ld e, a
    ld d, 0
    add hl, de
    ld a, (hl)
    
    ; Store value in memory
    ld (rssi_value), a
    
    ; Open/closed network indicator
    and #80
    jr z, .locked
    ld a, '~'               ; Open (hollow circle)
    jr .printLock
.locked
    ld a, '`'               ; Closed (filled circle)
.printLock
    call Display.putC
    
    ; Recover RSSI and calculate bars
    ld a, (rssi_value)
    and #7F                 ; A = RSSI (0-127)
    call drawRssiBars

.colorBars
    ; Color the bars area in green
    ; current_line has the current line (6-15)
    ld a, (current_line)
    ld l, a
    ld h, 0
    add hl, hl              ; x2
    add hl, hl              ; x4
    add hl, hl              ; x8
    add hl, hl              ; x16
    add hl, hl              ; x32
    ld de, #5800 + 22       ; Base + column 22 (covers text cols 30-40)
    add hl, de              ; HL = attribute address
    
    ; Color 10 cells in green (columns 22-31)
    ld a, Display.ATTR_RSSI ; Green on black
    ld b, 10
.colorLoop
    ld (hl), a
    inc hl
    djnz .colorLoop
    
    ret

rssi_value = #5B2A             ; In printer buffer (set in renderList)

; In printer buffer (set in renderList)
current_line = #5B2B
current_screen_idx = #5B2C
conn_row_found = #5B2D         ; #FF = none on page, else cursor row of connected SSID

; ============================================
; Cursor and navigation
; ============================================
hideCursor:
    call cursorIsConnectedRow
    jr nc, .hideNotConn
    ld c, Display.ATTR_CONNECTED
    jr cursor
.hideNotConn
    IFDEF HAS_ESXDOS
    call cursorIsSavedRow
    jr nc, .hideNormal
    ld c, Display.ATTR_SAVED
    jr cursor
.hideNormal
    ENDIF
    ld c, Display.ATTR_NORMAL
    jr cursor
showCursor:
    call cursorIsConnectedRow
    ld c, Display.ATTR_HIGHLIGHT
    jr nc, cursor
    ld c, Display.ATTR_CONN_CURSOR  ; Cursor on connected row: blue on yellow
cursor:
    ld a,(cursor_position) : add a, 6 : jp Display.setAttrPartial

; ============================================
; cursorIsConnectedRow
;   CF=1 if cursor is on the currently connected SSID (and WiFi is connected)
;   CF=0 otherwise
; Destroys: AF,BC,DE,HL
; ============================================
cursorIsConnectedRow:
    ; Must be connected
    ld a, (Wifi.is_connected)
    and a
    ret z

    ; Compare against the row actually highlighted by renderNetworksCommon
    ld a, (conn_row_found)
    cp #FF
    ret z
    ld b, a
    ld a, (cursor_position)
    cp b
    jr z, .connMatch
    or a                        ; No match -> CF=0
    ret
.connMatch
    scf
    ret

; ============================================
; cursorIsSavedRow
;   CF=1 if cursor is on the saved/known SSID (from config file)
;   CF=0 otherwise
; Destroys: AF,BC,DE,HL
; ============================================
    IFDEF HAS_ESXDOS
cursorIsSavedRow:
    ld a, (cfg_valid)
    and a
    ret z                       ; No valid config -> CF=0

    ld a, (cursor_position)
    ld hl, offset
    add a, (hl)
    ld d, a
    call findRow                ; HL = SSID pointer

    ld a, (hl)
    and a
    ret z                       ; Empty SSID -> CF=0

    ld de, Config.cfg_buffer + Config.CFG_SSID_OFF
    call Display.compareStringZ
    jr z, .savedMatch
    or a                        ; No match -> CF=0
    ret
.savedMatch
    scf                         ; Match -> CF=1
    ret
    ENDIF

; ============================================
; connectedSSIDPresentInList
; Output: CF=1 if Wifi.connected_ssid is in the list (buffer), CF=0 if not
; If CF=1, A = real network index (0-based)
; ============================================
connectedSSIDPresentInList:
    ld a, (Wifi.networks_count)
    and a
    jr z, .notFound

    ld b, a
    ld c, 0             ; C = current index
    ld hl, buffer
.loopNet
    ld a, (hl)
    and a
    jr z, .skipEmpty     ; Hidden SSID (empty): skip without aborting

    push hl
    push bc
    ld de, Wifi.connected_ssid
    call Display.compareStringZ
    pop bc
    pop hl
    jr z, .found        ; Z=1 means equal

.skipEmpty
    ; Advance to next SSID (find null terminator)
    inc c               ; Next index
    push bc             ; Preserve B and C
    xor a
    ld bc, BUFFER_SIZE
    cpir                ; HL points past the 0
    pop bc              ; Restore B and C
    djnz .loopNet

.notFound
    or a
    ret

.found
    ld a, c             ; A = real index
    scf
    ret


uiLoop:
    call Keyboard.waitBreakRelease
    call Uart.logFlushPending
    ; Clear keyboard buffer at start (prevents auto-selection from garbage)
    xor a
    ld (Keyboard.BASIC_KEY), a
    ld (hc_fail_count), a       ; Reset debounce on loop entry
    
uiLoopMain:
    halt
    call Keyboard.checkBreak
    jp z, start.exitClean

    ; Increment auto-rescan counter
    ld hl, (autoscan_counter)
    inc hl
    ld (autoscan_counter), hl
    
    ; Check if reached 15000 (5 min x 50 fps)
    ld de, 15000
    or a
    sbc hl, de
    jr nz, .noAutoRescan
    
    ; Auto-rescan: reset counter and do silent rescan
    ld hl, 0
    ld (autoscan_counter), hl
    call doAutoRescan
    call Uart.logFlushPending
    
.noAutoRescan
    ; Periodic health-check (only to invalidate state if connection lost)
    ld hl, (health_counter)
    inc hl
    ld (health_counter), hl
    ld de, 500                   ; ~10s @50fps (less aggressive)
    or a
    sbc hl, de
    jr nz, .noHealthCheck
    ld hl, 0
    ld (health_counter), hl

    ; Only if marked as connected and UART free
    ld a, (Wifi.is_connected)
    and a
    jr z, .noHealthCheck
    ld a, (Wifi.uart_busy)
    and a
    jr nz, .noHealthCheck

    ; Mute UART log during health-check (avoids CWJAP? spam).
    ; Mute BOTH log_enabled (RX log) and debug_log (TX log via logTxMasked):
    ; the initial AT probe is not a CWJAP query, so logTxMasked would print
    ; ">> AT" otherwise.
    call Uart.logReset
    ld a, (Uart.log_enabled) : ld b, a
    ld a, (Wifi.debug_log)   : ld c, a
    push bc
    xor a
    ld (Uart.log_enabled), a
    ld (Wifi.debug_log), a
    call Wifi.checkConnection
    pop bc
    ld a, b : ld (Uart.log_enabled), a
    ld a, c : ld (Wifi.debug_log), a
    push af
    call Uart.logReset
    pop af
    jr nc, .hcOk
    ; Fail: increment debounce counter, need 3 consecutive failures
    ld a, (hc_fail_count)
    inc a
    ld (hc_fail_count), a
    cp 3
    jr c, .noHealthCheck        ; Not enough failures yet
    xor a
    ld (hc_fail_count), a       ; Reset counter
    jp handleDisconnect
.hcOk
    xor a
    ld (hc_fail_count), a       ; Reset on success

.noHealthCheck


    ; Pending rescan after connection loss (only if UART free)
    ld a, (force_rescan)
    and a
    jr z, .noForceRescan
    ld a, (Wifi.uart_busy)
    and a
    jr nz, .noForceRescan
    xor a
    ld (force_rescan), a

    call hideCursor
    call Wifi.getList
    call normalizeListPosition

.forceRescanDone
    call showPageInfo
    call showScrollIndicators
    call renderNetworksOnly
    ld a, (Wifi.networks_count)
    and a
    call nz, showCursor
.noForceRescan

    call Keyboard.inKeyNoWait
    and a
    jp z, .noKey
    call Keyboard.keyClick

    ; Reset counter on user activity
    ld hl, 0
    ld (autoscan_counter), hl
    ld (health_counter), hl

    cp Keyboard.KEY_UP : jp z, cursorUp
    cp 'q'             : jp z, cursorUp
    cp 'Q'             : jp z, cursorUp
    cp Keyboard.KEY_DN : jp z, cursorDown
    cp 'a'             : jp z, cursorDown
    cp 'A'             : jp z, cursorDown

    cp 'o' : jp z, pageUp
    cp 'O' : jp z, pageUp
    cp 'p' : jp z, pageDown
    cp 'P' : jp z, pageDown
    cp Keyboard.KEY_LEFT  : jp z, pageUp
    cp Keyboard.KEY_RIGHT : jp z, pageDown

    cp 'r' : jp z, rescan
    cp 'R' : jp z, rescan
    cp 'd' : jp z, showDiagnostics
    cp 'D' : jp z, showDiagnostics
    cp 'h' : jp z, manualSSID
    cp 'H' : jp z, manualSSID
    cp 'x' : jp z, doDisconnect
    cp 'X' : jp z, doDisconnect
    cp 'l' : jp z, toggleDebugLog
    cp 'L' : jp z, toggleDebugLog
    cp 'w' : jp z, doWPS
    cp 'W' : jp z, doWPS
    cp 'i' : jp z, showAbout
    cp 'I' : jp z, showAbout
    IFDEF HAS_ESXDOS
    cp 'c' : jp z, doReconnect
    cp 'C' : jp z, doReconnect
    ENDIF

    cp 13  : jp z, selectItem      ; ENTER

    jp uiLoopMain

.noKey:
    ld a, (ui_async_div)
    inc a
    ld (ui_async_div), a
    cp 4                           ; 4 frames ≈ 80 ms
    jp nz, uiLoopMain
    xor a
    ld (ui_async_div), a
    call checkAsyncWifi
    ; A = event code
    and a
    jp z, uiLoopMain               ; No event
    cp ASYNC_EVENT_DISCONNECT
    jr z, handleDisconnect
    cp ASYNC_EVENT_GOTIP
    jr z, handleGotIP
    jp uiLoopMain

; ============================================
; doMarkDisconnected
;   Invalidates WiFi state, clears SSID, updates status/IP and warns in log.
;   Does NOT touch cursor or repaint list (caller decides).
; ============================================
doMarkDisconnected:
    xor a
    ld (Wifi.is_connected), a
    ld (Wifi.connected_bssid_valid), a
    ld hl, Wifi.connected_ssid
    ld (hl), a
    ld a, 1
    ld (force_rescan), a
    call updateWifiStatus_q
    call ipShowNotConnected
    ld hl, msg_conn_lost
    jp Display.putStrLog

handleDisconnect
    call doMarkDisconnected
    jp uiLoopMain

handleGotIP
    ld a, 1
    ld (Wifi.is_connected), a
    ; Get the SSID of current connection (may fail if ESP is slow to respond)
    call Wifi.checkConnection
    jr nc, .gotSSID
    ; SSID query failed but GOT IP is authoritative — keep link up
    ld a, 1
    ld (Wifi.is_connected), a
.gotSSID
    call updateWifiStatus_q
    call ipShowConnected         ; Update IP in status bar
    ; Redraw list to apply connected network attribute
    call renderNetworksOnly
    call showCursor
    jp uiLoopMain

rescan:
    call hideCursor
    xor a : ld (cursor_position), a : ld (offset), a
    
    ; Remove the old count/page text before showing the shorter scan message.
    ld a, 17 : call clearRowPixels
    ld a, 17 : ld hl, .scanning_msg : call printAt0
    
    call Wifi.getList
    call renderListOnly         ; Only redraws the list, not the help
    jp uiLoop
.scanning_msg = msg_ip_scanning

; ============================================
; doAutoRescan - Silent automatic rescan
; Does not move cursor or show messages
; ============================================
doAutoRescan:
    push bc
    push de
    push hl

    ; Show hourglass on row 17, col 0
    ld a, 17 : call Display.gotoXY0
    ld a, '^'
    call Display.putC

    ; Save current position
    ld a, (cursor_position)
    ld b, a
    ld a, (offset)
    ld c, a
    push bc

    call hideCursor
    call Wifi.getList
    jr c, .autoScanFail

    ; Restore position, then clamp it to the new list.
    pop bc
    ld a, b
    ld (cursor_position), a
    ld a, c
    ld (offset), a
    call normalizeListPosition
    jr .autoRepaint

.autoScanFail
    pop bc                      ; Discard saved cursor/offset (only when scan FAILED)
    xor a
    ld (cursor_position), a
    ld (offset), a
    jr .autoRepaint

.autoRepaint
    call renderListOnly

    xor a
    ld (Keyboard.BASIC_KEY), a ; Discard input collected against the old list.
    pop hl
    pop de
    pop bc
    ret

; ============================================
; ============================================
; doDisconnect - Disconnect from current network
; ============================================
doDisconnect:
    ; Check if connected
    ld a, (Wifi.is_connected)
    and a
    jp z, uiLoop

    ; Confirmation
    call hideCursor : ld hl, .msg_disc_confirm : call topCleanAlertMsg
    gotoXY 1, 6
    ld hl, msg_yes_anykey
    call Display.putStr
    ; Debounce: drain stale keys from X release
    call debounce15
.waitDiscConfirm
    halt
    call Keyboard.inKey
    and a : jr z, .waitDiscConfirm
    cp 'y' : jr z, .doDiscNow
    cp 'Y' : jr z, .doDiscNow
    ; Any other key cancels
    jp renderListAndLoop

.doDiscNow
    ; Immediate feedback while waiting
    ld hl, .msg_disconnecting : call topCleanAlertMsg

    ; Send disconnect command
    ld hl, cmd_disconnect
    call Wifi.espSendZ_CRLF

    ; Wait for OK/ERROR response
    call Wifi.checkOkErr
    push af                     ; save CF for post-flush branch
    call Wifi.flushInput
    pop af
    jr c, .discFailed

    ; Pause so "Disconnecting..." is visible (~1.5s)
    ld b, 75
.waitDisc:
    halt
    djnz .waitDisc

    ; Overwrite "Disconnecting..." with "Disconnected" (no full clear = no flicker)
    call clearRows34Pixels
    ld hl, .msg_disconnected
    ld c, Display.ATTR_ALERT
    call showBigMessage
    call showPressKey

    ; Update state AFTER screen is already showing "Disconnected"
    xor a
    ld (Wifi.is_connected), a
    ld (Wifi.connected_bssid_valid), a
    call updateWifiStatus_q
    call ipShowNotConnected
    call waitAnyKey
    jp renderListAndLoop

.discFailed
    ; ESP did not ack CWQAP (timeout/ERROR). Leave local state as-is:
    ; another code path (async events, next checkConnection) will resync.
    call clearRows34Pixels
    ld hl, msg_disc_failed
    ld c, Display.ATTR_ALERT
    call showBigMessage
    call showPressKey
    call waitAnyKey
    jp renderListAndLoop

.msg_disc_confirm   db "Disconnect from WiFi?", 0
.msg_disconnecting  db "Disconnecting...", 0
.msg_disconnected   db "Disconnected.", 0
msg_disc_failed     db "Disconnect failed.", 0

; ============================================
; manualSSID - Enter SSID manually
; ============================================
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

; Full SSID redraw (for cursor left)
.drawSSIDFull
    halt
    ld a, 8 : call Display.gotoXY0
    ; Clear full line (double-height)
    ld b, 34
.clearSSIDFull
    ld a, ' '
    push bc
    call Display.putCBig
    pop bc
    djnz .clearSSIDFull

    ld a, 8 : call Display.gotoXY0

    ; Chars before cursor
    ld a, (manual_ssid_cursor)
    and a
    jr z, .ssidFullCursor

    ld b, a
    ld hl, manual_ssid_buffer
.ssidFullBefore
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidFullBefore

.ssidFullCursor
    ld a, 127
    call Display.putCBig

    ; Chars after cursor
    ld a, (manual_ssid_len)
    ld b, a
    ld a, (manual_ssid_cursor)
    cp b
    jr nc, .ssidFinishDraw

    ld c, a
    ld a, b
    sub c
    jr z, .ssidFinishDraw
    ld b, a
    call getSSIDAtCursor

.ssidFullAfter
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidFullAfter
    jr .ssidFinishDraw

; Partial SSID redraw (from cursor, for insert/delete)
.drawSSID
    halt
    ; Position at start of line
    ld a, 8 : call Display.gotoXY0

    ; Draw characters before cursor
    ld a, (manual_ssid_cursor)
    and a
    jr z, .ssidDrawCursor
    
    ld b, a
    ld hl, manual_ssid_buffer
.ssidDrawBefore
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidDrawBefore

.ssidDrawCursor
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
    cp 9 : jr z, .ssidCursorRight

    ; Delete
    cp Keyboard.KEY_BS : jr z, .removeSSIDChar

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
    jp .drawSSID

.ssidCursorLeft
    ld a, (manual_ssid_cursor)
    and a
    jp z, .waitSSIDKey
    dec a
    ld (manual_ssid_cursor), a
    jp .drawSSID                ; Use partial redraw (not Full)

.ssidCursorRight
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    cp b
    jp z, .waitSSIDKey
    ld a, (manual_ssid_cursor)
    inc a
    ld (manual_ssid_cursor), a
    jp .drawSSID

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

; ============================================
; doReconnect - Reconnect to saved network (C key)
; Only compiled for UNO/NEXT (esxDOS required)
; ============================================
    IFDEF HAS_ESXDOS

doReconnect:
    call hideCursor : call topClean
    call Config.load
    call restoreAfterFileIo     ; rearm printer-buffer state (both branches)
    jr c, .rcNoFile

    ; --- Config exists: show saved SSID ---
    ld a, 3 : ld hl, .rc_title : call printAt0
    ld a, 4 : call Display.gotoXY0
    ld hl, Config.cfg_buffer + Config.CFG_SSID_OFF
    call Display.putStrBig
    ld a, 4 : ld b, 2 : ld c, Display.ATTR_SSID_INPUT : call setRowsColor

    ld a, (Wifi.is_connected)
    and a
    jr z, .rcNotConn

    ; Connected + config: offer reconnect
    ld a, 7 : ld hl, .rc_already : call printAt0
    ld a, 8 : ld hl, .rc_reconnect_yn : call printAt0
    jr .rcDoConnect

.rcNotConn
    ; Not connected + config: offer connect
    ld a, 7 : ld hl, .rc_connect_yn : call printAt0

.rcDoConnect
    call .rcYN
    jp nz, renderListAndLoop
    call Config.copyToBuffers
    ld a, 1 : ld (is_reconnect), a
    ld a, #FF : ld (selected_real_idx), a
    jp connectAndReturn

.rcNoFile
    ; No config file
    ld hl, .rc_no_config : ld c, Display.ATTR_ALERT : call showBigMessage
    ld a, (Wifi.is_connected)
    and a
    jr z, .rcNoFileNoConn
    ; Connected but no config: explain how to save
    ld a, 6 : ld hl, .rc_no_pass : call printAt0
    jp pressKeyReturnList
.rcNoFileNoConn
    ; Not connected
    ld a, 6 : ld hl, .rc_no_hint : call printAt0
    jp pressKeyReturnList

; Shared debounce + Y/N wait. Returns Z=1 if Y, Z=0 if other key.
.rcYN
    call debounce15
.rcYNWait
    halt
    call Keyboard.inKey
    and a : jr z, .rcYNWait
    cp 'y' : ret z
    cp 'Y' : ret z
    or 1                        ; Z=0 (cancel)
    ret

.rc_title        db "SAVED NETWORK", 0
.rc_connect_yn   db "(Y) connect (N) cancel", 0
.rc_already      db "Already connected", 0
.rc_reconnect_yn db "Reconnect? (Y/N)", 0
.rc_no_config    db "No saved network", 0
.rc_no_pass      db "Use (S)ave after reconnecting", 0
.rc_no_hint      db "Connect to a network first", 0

    ENDIF ; HAS_ESXDOS

; ============================================
; toggleDebugLog - Toggle UART debug log (L key)
; ============================================
toggleDebugLog:
    ld a, (Wifi.debug_log)
    xor 1
    ld (Wifi.debug_log), a
    ld (Uart.log_enabled), a
    ; Show state in log
    ld hl, .msg_log_on
    and a
    jr nz, .tShow
    ld hl, .msg_log_off
.tShow
    call Display.putStrLog
    call updateLogIndicator
    jp uiLoopMain
.msg_log_on  db "UART log: ON", 13, 0
.msg_log_off db "UART log: OFF", 13, 0

; Quiet toggle - for use in wait loops (no jp uiLoopMain)
; Returns with A=0 so caller can treat it as "no key"
toggleLogQuiet:
    ld a, (Wifi.debug_log)
    xor 1
    ld (Wifi.debug_log), a
    ld (Uart.log_enabled), a
    call updateLogIndicator
    xor a
    ret

; ============================================

; Update log indicator: small red filled circle at row 23 byte 31.
; Updates both the scroll data table (for flicker-free scroll) and
; the actual screen pixels (for immediate toggle feedback).
; Uses bottom 4 bits only (safe: drawC at col 41 only touches top 4 bits).
LOG_IND_ATTR_ON  = 012o     ; Red ink on blue paper
LOG_IND_ATTR_OFF = 014o     ; Green ink on blue paper (normal ATTR_LOG)
    IFDEF HAS_ESXDOS
; Re-initialize volatile printer-buffer state that esxDOS rst $08 can
; scribble over during file I/O. Must be called on every return path
; from Config.load/Config.save before any display render or uiLoop tick
; that relies on these. Preserves AF so callers can branch on the file
; I/O result after invoking.
restoreAfterFileIo:
    push af
    call updateLogIndicator
    xor a
    ld (Wifi.uart_busy), a          ; async UART lock
    ld (Display.putLogC_coord), a   ; log X cursor (row 23 column)
    ld (autoscan_counter), a
    ld (autoscan_counter + 1), a
    ld (health_counter), a
    ld (health_counter + 1), a
    ld (async_buf_idx), a
    ld (async_buf_count), a
    ld (ui_async_div), a
    ld (skip_footer), a
    pop af
    ret
    ENDIF

updateLogIndicator:
    ld a, (Wifi.debug_log)
    and a
    jr z, .off
    ; ON: copy circle data to scroll table + paint pixels + set attr
    ld hl, .circleData
    ld de, Display.log_ind_data
    ld bc, 8
    ldir
    ld a, LOG_IND_ATTR_ON
    jr .apply
.off
    ; OFF: zero scroll table + clear pixels + restore attr
    ld hl, Display.log_ind_data
    xor a
    ld b, 8
.clrTable
    ld (hl), a
    inc hl
    djnz .clrTable
    ld a, LOG_IND_ATTR_OFF
.apply
    ld (#5AFF), a            ; Row 23, cell 31 attr
    ; Paint/clear pixels on screen (immediate feedback)
    ld hl, #50FF             ; Row 23, byte 31, scanline 0
    ld de, Display.log_ind_data
    ld b, 8
.paintLoop
    ld a, (hl)
    and #F0                  ; Preserve top 4 bits (log text)
    ld c, a
    ld a, (de)
    or c
    ld (hl), a
    inc h
    inc de
    djnz .paintLoop
    ret
.circleData
    db #00, #06, #0F, #0F, #0F, #0F, #06, #00

; ============================================
; doWPS - WPS push-button connect (W key)
; ============================================
doWPS:
    ; If connected, ask confirmation before disconnecting
    ld a, (Wifi.is_connected)
    and a
    jr z, .wpsDisconnect

    call hideCursor : call topClean
    ld hl, .msg_wps_warn
    ld c, Display.ATTR_ALERT
    call showBigMessage
    ld a, 6 : ld hl, msg_yes_anykey : call printAt0
    ; Debounce: drain stale keys from W release
    call debounce15
.wpsConfirm
    halt
    call Keyboard.inKey
    and a : jr z, .wpsConfirm
    cp 'y' : jr z, .wpsDisconnect
    cp 'Y' : jr z, .wpsDisconnect
    ; Cancel
    jp renderListAndLoop

.wpsDisconnect
    ; A deliberate disconnect prevents an old association looking like WPS success.
    ld hl, cmd_disconnect
    call Wifi.espSendZCheckOk
    jr c, .wpsDiscFailed
    xor a : ld (Wifi.is_connected), a
    ld (Wifi.connected_bssid_valid), a
    call updateWifiStatus
    ld b, 75
.wpsDiscWait
    halt
    djnz .wpsDiscWait
    jr .wpsStart

.wpsDiscFailed
    call flushUartBuffer
    call topClean
    ld hl, msg_disc_failed
    ld c, Display.ATTR_ALERT
    call showBigMessage
    jp .wpsExit

.wpsStart
    call topClean
    ld hl, .msg_wps_prompt
    ld c, Display.ATTR_CONNECTED    ; Bright yellow on black
    call showBigMessage
    gotoXY 1, 6
    ld hl, msg_break_cancel
    call Display.putStr

    call flushUartBuffer

.wpsSend
    ; Send AT+WPS=1 (ESP acks OK fast, then does WPS async)
    ld hl, .cmd_wps : call Wifi.espSendZCheckOk
    jr c, .wpsFail
    ; Poll connection until WPS completes or timeout.
    ; 40 rounds × ~1.5s = ~60s window (user has to press router button).
    ld b, 40
.wpsPollLoop
    push bc
    ; ~1.5s wait between polls on Next (75 frames)
    ld b, 75
.wpsPollWait
    halt
    call Keyboard.checkBreak : jr z, .wpsPollBrk
    djnz .wpsPollWait
    call flushUartBuffer
    call Wifi.checkConnection
    pop bc
    jr nc, .wpsGotConn
    djnz .wpsPollLoop
    jr .wpsFail
.wpsPollBrk
    pop bc
    jr .wpsCancel

.wpsGotConn
    call flushUartBuffer
    call updateWifiStatus_q
    ; Suppress save-prompt: WPS has no local password, only ESP flash does.
    ld a, 1 : ld (is_reconnect), a
    call connSuccessScreen
    xor a : ld (is_reconnect), a
    jp renderListAndLoop
.wpsCancel
    xor a
    jr .wpsCleanup

.wpsFail
    ld a, 1
.wpsCleanup
    push af
    call flushUartBuffer
    ld hl, .cmd_wps_off : call Wifi.espSendZCheckOk
    ld hl, cmd_disconnect : call Wifi.espSendZCheckOk
    call flushUartBuffer
    xor a : ld (Wifi.is_connected), a
    ld (Wifi.connected_bssid_valid), a
    call ipShowNotConnected
    call updateWifiStatus_q
    pop af
    and a
    jp z, showCancelledScreen
    call topClean
    ld hl, .msg_wps_timeout
    ld c, Display.ATTR_ALERT
    call showBigMessage
.wpsExit
    call showPressKey
.wpsWaitKey
    halt
    call Keyboard.inKeyNoWait
    and a
    jr z, .wpsWaitKey
    cp 'l' : jr z, .wpsLog : cp 'L' : jr z, .wpsLog
    jr .wpsKeyOk
.wpsLog
    call toggleLogQuiet : jr .wpsWaitKey
.wpsKeyOk
    ld b, 100
.wpsScanWait
    halt
    djnz .wpsScanWait
    call flushUartBuffer
    call Wifi.getList
    jp renderListAndLoop

.msg_wps_warn    db "WPS requires disconnecting first.", 0
.msg_wps_prompt  db "Press WPS button on router...", 0
.msg_wps_timeout db "WPS timeout!", 0
.cmd_wps         db "AT+WPS=1", 0
.cmd_wps_off     db "AT+WPS=0", 0

cursorDown:
    call hideCursor
    ; Check if there are more networks below
    ld a, (cursor_position)
    ld hl, offset
    add a, (hl)
    inc a                       ; Next absolute position
    ld hl, Wifi.networks_count
    cp (hl)                     ; More networks?
    jr nc, .atEnd               ; No more, don't move
    
    ld a, (cursor_position)
    inc a
    cp PER_PAGE
    jr c, .store                ; Within the page
    
    ; Scroll down: check there are more networks
    ld a, (offset)
    add a, PER_PAGE
    ld hl, Wifi.networks_count
    cp (hl)
    jr nc, .atEnd               ; No more pages
    
    jp renderPageFromOffsetTop

.store
    ld (cursor_position), a
.atEnd
    call showCursor
    jp uiLoop

cursorUp:
    call hideCursor
    ld a, (cursor_position) : and a : jr z, .page_up
    dec a : ld (cursor_position), a
.back
    call showCursor
    jp uiLoop
.page_up
    ld a, (offset) : and a : jr z, .back
    sub PER_PAGE
    jr nc, .store_offset        ; No underflow
    xor a                       ; Clamp to 0
.store_offset
    ld (offset), a
    ld a, PER_PAGE - 1 : ld (cursor_position), a
    jp renderPageAndLoop

; Page Down - jump one full page
pageDown:
    call hideCursor
    ld a, (offset)
    add a, PER_PAGE
    ld hl, Wifi.networks_count
    cp (hl)
    jr nc, .atEnd               ; Keep the final partial page in place.
    jp renderPageFromOffsetTop
.atEnd
    call showCursor
    jp uiLoop

; Page Up - jump one full page
pageUp:
    call hideCursor
    ld a, (offset)
    and a
    jr z, .firstItem            ; Already on first page
    sub PER_PAGE
    jr nc, .setOffset
    xor a                       ; Clamp to 0
.setOffset
    jp renderPageFromOffsetTop
.firstItem
    xor a : ld (cursor_position), a
    call showCursor
    jp uiLoop

findRow:
    ; d = screen position
    ld a, d
    call Wifi.getDisplayIndex
    jp Wifi.getSSIDPointer

; ============================================
; ============================================
; drawSignalLine - Draw "Signal:   ||||||||.." on the specified line
; Input: A = line number
; Uses: selected_real_idx to get RSSI
; ============================================
drawSignalLine:
    ld h, a : ld l, 0
    ld (Display.coords), hl
    push af
    ld hl, showNetDetail.nd_sig
    call Display.putStr
    ; Color cells 7-16 of the line in yellow
    pop af
    ld l, a : ld h, 0
    add hl, hl : add hl, hl : add hl, hl : add hl, hl : add hl, hl
    ld de, #5800 + 7
    add hl, de
    ld a, Display.ATTR_CONNECTED
    ld b, 10
.clr
    ld (hl), a : inc hl : djnz .clr
    ; Get RSSI and draw bars
    ld a, (selected_real_idx)
    ld hl, Wifi.rssi_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl) : and #7F
    jr drawRssiBars

; Shared routine: calculate and draw RSSI bars
; Input: A = RSSI (0-127). Coords already positioned.
drawRssiBars:
    ld b, a : ld a, 93 : sub b
    jr nc, .calc
    xor a
.calc
    ld b, 0 : ld c, 6
.div
    inc b : sub c : jr nc, .div
    ; B is always >= 1: inc b runs before the first sub.
    ld a, b
    cp 11 : jr c, .bars
    ld a, 10
.bars
    ld b, a : ld c, a
.full
    ld a, b : and a : jr z, .empty
    push bc : ld a, '|' : call Display.putC : pop bc
    dec b : jr .full
.empty
    ld a, 10 : sub c : ret z
    ld b, a
.emptyL
    push bc : ld a, '.' : call Display.putC : pop bc
    dec b : jr nz, .emptyL
    ret

; ============================================
; showNetDetail - Show detailed info for selected network
; Uses: selected_ssid_ptr, selected_real_idx
; Displays on lines 3-8
; ============================================
showNetDetail:
    ; Lines 4-5: "Selected SSID:  NetworkName" double-height
    ; 14 chars + 2 spaces = 16 x 6px = 96px = 12 cells exactly (no clash)
    ld a, 4 : ld hl, msg_ssid : call printAt0
    ld a, ' ' : call Display.putC
    ld a, ' ' : call Display.putC
    ld hl, (selected_ssid_ptr)
    ld a, (hl) : and a : jr nz, .nd_printSSID
    ld hl, msg_hidden
.nd_printSSID
    ld b, 24
    call putStrLimited
    call Display.stretchRows45
    ; Row 4: cells 0-11 white BRIGHT, 12-31 green BRIGHT
    ld hl, #5880
    ld a, Display.ATTR_NORMAL
    ld b, 12
.nd_attr_w4
    ld (hl), a : inc hl : djnz .nd_attr_w4
    ld a, Display.ATTR_SSID_INPUT
    ld b, 20
.nd_attr_g4
    ld (hl), a : inc hl : djnz .nd_attr_g4
    ; Row 5: same colors without BRIGHT (HL already #58A0)
    ld a, Display.ATTR_NORMAL_DIM
    ld b, 12
.nd_attr_w5
    ld (hl), a : inc hl : djnz .nd_attr_w5
    ld a, Display.ATTR_RSSI
    ld b, 20
.nd_attr_g5
    ld (hl), a : inc hl : djnz .nd_attr_g5

    ; Line 7: Security
    ld a, 7 : ld hl, .nd_sec : call printAt0
    ld a, (selected_real_idx)
    ld hl, Wifi.ecn_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl)
    ; ECN: 0=OPEN, 1=WEP, 2=WPA-PSK, 3=WPA2-PSK, 4=WPA/WPA2, 5=Enterprise
    cp 6 : jr c, .nd_ecn_ok
    ld hl, .ecn_unknown     ; Unknown ECN value
    jr .nd_ecn_print
.nd_ecn_ok
    ld hl, .ecn_table
    add a, a               ; x2 (each pointer = 2 bytes)
    ld e, a : ld d, 0 : add hl, de
    ld a, (hl) : inc hl : ld h, (hl) : ld l, a
.nd_ecn_print
    call Display.putStr

    ; Line 8: Channel + band
    ld a, 8 : ld hl, .nd_chan : call printAt0
    ld a, (selected_real_idx)
    ld hl, Wifi.channel_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl)
    and a
    jr z, .nd_chan_unk
    push af
    call printNumber
    pop af
    ; Band: channels 1-14 = 2.4 GHz, 15+ = 5 GHz
    cp 15
    ld hl, .nd_band24
    jr c, .nd_showBand
    ld hl, .nd_band5
.nd_showBand
    call Display.putStr
    jr .nd_signal
.nd_chan_unk
    ld a, '-' : call Display.putC

    ; Line 9: Signal
.nd_signal
    ld a, 9
    jp drawSignalLine              ; Tail call (draws "Signal: ||||..." on line A)

.nd_sec         db "Security: ", 0
.nd_chan        db "Channel:  ", 0
.nd_band24     db " (2.4 GHz)", 0
.nd_band5      db " (5 GHz)", 0
.nd_sig         db "Signal:   ", 0

; Table of pointers to encryption names
.ecn_table
    dw .ecn_open, .ecn_wep, .ecn_wpa, .ecn_wpa2, .ecn_wpa12, .ecn_ent
.ecn_open       db "Open", 0
.ecn_wep        db "WEP", 0
.ecn_wpa        db "WPA-PSK", 0
.ecn_wpa2       db "WPA2-PSK", 0
.ecn_wpa12      db "WPA/WPA2", 0
.ecn_ent        db "WPA2-Ent", 0
.ecn_unknown    db "Unknown", 0

; ============================================
; selectItem and connection
; ============================================
selectItem:
    ld a, (Wifi.networks_count) : and a : jp z, uiLoop
    
    ; Get screen position
    ld a, (cursor_position) : ld hl, offset : add a, (hl)
    jp c, uiLoop
    ld hl, Wifi.networks_count
    cp (hl) : jp nc, uiLoop
    ; Convert to real index using display_indices
    call Wifi.getDisplayIndex   ; A = real network index
    ld (selected_real_idx), a
    ld hl, Wifi.rssi_buffer : ld d, 0 : ld e, a : add hl, de
    ld a, (hl) : and #80 : ld (is_open_network), a
    
    ; Get pointer to selected SSID (findRow already uses display_indices)
    ld a, (cursor_position) : ld hl, offset : add (hl) : ld d, a : call findRow
    ld (selected_ssid_ptr), hl

    ; Hidden network (empty SSID): redirect to manual SSID entry
    ld a, (hl) : and a : jp z, manualSSID

    ; Check if already connected to this network
    ld a, (Wifi.is_connected)
    and a
    jp z, .notConnectedYet
    
    ; Compare selected SSID with connected_ssid
    ld hl, (selected_ssid_ptr)
    ld de, Wifi.connected_ssid
.compareLoop
    ld a, (de)
    ld b, a
    ld a, (hl)
    cp b
    jp nz, .notConnectedYet      ; Different, continue
    and a
    jr z, .sameSSID              ; Both ended at 0, compare AP identity
    inc hl
    inc de
    jr .compareLoop

.sameSSID
    ld a, (Wifi.connected_bssid_valid)
    and a
    jr z, .alreadyConnected
    call getSelectedBSSID
    jr nc, .alreadyConnected
    ld de, Wifi.connected_bssid
    ld b, 6
.compareBSSID
    ld a, (de)
    cp (hl)
    jp nz, .notConnectedYet
    inc de
    inc hl
    djnz .compareBSSID

.alreadyConnected
    call hideCursor : call topClean
    call showNetDetail

    ; Show progress while fetching (yellow, like system messages)
    ld a, 17 : ld c, ATTR_PRESS_KEY : call Display.setAttr
    ld a, 17 : ld hl, .ci_retrieving : call printAt0

    ; Fetch connection details (IP, gateway, mask, MAC)
    call Wifi.getConnectionInfo

    ; Clear the progress message and restore attr
    ld a, 17 : call clearRowPixels
    ld a, 17 : ld c, Display.ATTR_NORMAL : call Display.setAttr

    ; Row 10: IP
    ld a, 10 : ld hl, .ci_ip_lbl : call printAt0
    ld hl, Wifi.ip_buffer
    ld a, (hl) : and a : jr nz, .ciShowIP
    ld hl, .ci_na
.ciShowIP
    call Display.putStr

    ; Row 11: Gateway
    ld a, 11 : ld hl, .ci_gw_lbl : call printAt0
    ld hl, Wifi.ci_gateway
    ld a, (hl) : and a : jr nz, .ciShowGW
    ld hl, .ci_na
.ciShowGW
    call Display.putStr

    ; Row 12: Netmask
    ld a, 12 : ld hl, .ci_mask_lbl : call printAt0
    ld hl, Wifi.ci_netmask
    ld a, (hl) : and a : jr nz, .ciShowNM
    ld hl, .ci_na
.ciShowNM
    call Display.putStr

    ; Row 13: MAC
    ld a, 13 : ld hl, .ci_mac_lbl : call printAt0
    ld hl, Wifi.ci_mac
    ld a, (hl) : and a : jr nz, .ciShowMAC
    ld hl, .ci_na
.ciShowMAC
    call Display.putStr

    ; Set attrs for rows 10-13
    ld a, 10 : ld b, 4 : ld c, Display.ATTR_NORMAL : call setRowsColor

    ; Row 15: message (bright red for visibility)
    ld a, 15 : ld hl, .msg_already_conn : call printAt0
    ld a, 15 : ld b, 1 : ld c, Display.ATTR_ALERT : call setRowsColor
    jp pressKeyReturnList

.ci_retrieving db "Retrieving information...", 0
.ci_ip_lbl   db "IP:       ", 0
.ci_gw_lbl   db "Gateway:  ", 0
.ci_mask_lbl db "Mask:     ", 0
.ci_mac_lbl  db "MAC:      ", 0
.ci_na       db "-", 0
.msg_already_conn db "Already connected to this network!", 0
.msg_connect_yn   db "(Y)es connect / (N)o cancel", 0

.notConnectedYet
    call hideCursor : call topClean
    call showNetDetail

    ld a, (is_open_network) : and a : jr nz, .openConfirm
    call clearPassBuffer
    ld a, 11 : ld hl, msg_pass : call printAt0
    ld a, 12 : ld b, 2 : ld c, Display.ATTR_PASS_INPUT : call setRowsColor
    ld a, 12 : ld (pass_line), a
    xor a
    ld (show_password), a
    ld (pass_cursor), a

    call passwordInput
    ; Restore pass_line to default
    ld a, PASS_LINE_DEFAULT : ld (pass_line), a
    jr nc, .connect
    ; Fall through to cancel

.cancel
    ld a, 12 : ld b, 2 : ld c, Display.ATTR_NORMAL : call setRowsColor
    jp renderListAndLoop

.openConfirm
    ; Open network: show confirmation before connecting
    ld a, 11 : ld hl, msg_open_net : call printAt0
    ld a, 13 : ld hl, .msg_connect_yn : call printAt0
    call debounce15
.openWait
    halt
    call Keyboard.checkBreak
    jr z, .cancel
    call Keyboard.inKeyNoWait
    and a : jr z, .openWait
    cp 'y' : jr z, .connectDirect
    cp 'Y' : jr z, .connectDirect
    cp 'n' : jr z, .cancel
    cp 'N' : jr z, .cancel
    jr .openWait

.connectDirect
    call clearPassBuffer

.connect
    ; Clear password area (rows 10-13) -- fast via LDIR
    ld a, 10 : ld b, 4 : ld c, Display.ATTR_NORMAL : call setRowsColor
    ld d, 10 : ld c, 127 : call clearPixelRows  ; 4 rows pixels

    ; Copy selected SSID to shared buffer and use shared connect routine
    ld hl, (selected_ssid_ptr)
    ld de, manual_ssid_buffer
    call copyStringZ
    xor a : ld (is_reconnect), a
    jr connectAndReturn

; Return the selected scan BSSID in HL, or CF=0 when unavailable.
getSelectedBSSID:
    ld a, (selected_real_idx)
    inc a
    jr z, .invalid
    dec a
    ld e, a
    add a, a
    add a, e
    add a, a
    ld e, a : ld d, 0
    ld hl, Wifi.bssid_buffer
    add hl, de
    ld a, (hl)
    cp #FF
    jr z, .invalid
    push hl
    ld b, 6
    xor a
.check
    or (hl)
    inc hl
    djnz .check
    pop hl
    jr z, .invalid
    scf
    ret
.invalid
    or a
    ret

; ============================================
; connectAndReturn - Full WiFi connection cycle with retries
; Input: manual_ssid_buffer = SSID, pass_buffer = password
; Never returns - always jumps to renderListAndLoop (via success/cancel/fail)
; ============================================
connectAndReturn:
    ld a, 3
    ld (conn_retries), a
    call Wifi.flushInput
    ld hl, cmd_disconnect
    call Wifi.espSendZCheckOk
    jr nc, .carDisconnected
    ld a, (Wifi.reply_status)
    cp Wifi.REPLY_BREAK
    jp z, .carDiscCancelled
    cp Wifi.REPLY_ERROR
    jp nz, .carDiscFailed
    ; A complete ERROR permits a fresh join, without claiming disconnection.
    jr .carRetry
.carDisconnected
    xor a : ld (Wifi.is_connected), a
    ld (Wifi.connected_bssid_valid), a
    call updateWifiStatus_q
    call ipShowNotConnected
    call Wifi.flushInput

.carRetry
    call Wifi.prepareRetry
    jp c, .carFailed
    call topClean
    ld a, (conn_retries) : ld b, a
    ld a, 4 : sub b : add a, '0'
    ld (msg_attempt_suffix + 2), a  ; patch digit in " (x/3)"
    ; Pick big message based on reconnect flag
    ld hl, msg_conn_attempt
    IFDEF HAS_ESXDOS
    ld a, (is_reconnect) : and a
    jr z, .carMsg
    ld hl, msg_reco_attempt
.carMsg
    ENDIF
    ld c, Display.ATTR_SSID_INPUT
    call showBigMessage
    ; Show SSID in double-height on rows 5-6 (max 32 + 6 = 38 < 42 cols)
    ld a, 5 : call Display.gotoXY0
    ld hl, manual_ssid_buffer : call Display.putStrBig
    ; Append attempt suffix if room (putStrBig destroys all regs)
    ld a, (Display.coords) : cp 37 : jr nc, .carNoSuffix
    ld hl, msg_attempt_suffix : call Display.putStrBig
.carNoSuffix
    ; Color rows 5-6 (bright yellow top, yellow bottom)
    ld c, Display.ATTR_CONNECTED
    ld a, 5 : call Display.setAttr
    ld c, Display.ATTR_CONNECTED
    res 6, c
    ld a, 6 : call Display.setAttr
    ld a, 8 : ld hl, msg_break_cancel : call printAt0

    ; Mute log, send AT+CWJAP, unmute
    ld hl, .car_log_masked : call Display.putStrLog
    call Uart.logReset
    ld a, (Uart.log_enabled) : ld b, a
    ld a, (Wifi.debug_log) : ld c, a
    push bc
    xor a : ld (Uart.log_enabled), a : ld (Wifi.debug_log), a

    ; Bind scanned selections to their BSSID; manual/saved routes use #FF.
    ld a, (Wifi.old_fw) : ld hl, at_start : or a : jr z, .carSend : ld hl, at_start_old
.carSend
    call Wifi.espSendZ
    ld hl, manual_ssid_buffer : call Wifi.espSendQuotedZ
    ld hl, at_middle : call Wifi.espSendZ
    ld hl, pass_buffer : call Wifi.espSendQuotedZ
    call getSelectedBSSID
    jr nc, .carCloseCommand
    push hl
    ld hl, at_middle
    call Wifi.espSendZ
    pop hl
    ld b, 6
.carSendMac
    ld a, (hl)
    push hl
    call .carSendHex
    pop hl
    inc hl
    djnz .carSendColon
    jr .carCloseCommand
.carSendColon
    ld a, ':' : call Uart.write
    jr .carSendMac
.carSendHex
    push af
    rrca : rrca : rrca : rrca
    call .carSendNibble
    pop af
.carSendNibble
    and #0F
    add a, '0'
    cp '9' + 1
    jr c, .carWriteNibble
    add a, 'A' - '9' - 1
.carWriteNibble
    jp Uart.write
.carCloseCommand
    ld hl, at_quote_crlf : call Wifi.espSendZ_CRLF

    call Wifi.checkOkErrLong

    ; Restore log flags, store result
    jr nc, .carOk
    ld a, 1 : jr .carSaveRes
.carOk
    xor a
.carSaveRes
    ld (conn_result), a
    pop bc
    ld a, b : ld (Uart.log_enabled), a
    ld a, c : ld (Wifi.debug_log), a
    ld a, 13 : call Display.putLogC
    ld a, (conn_result)
    and a
    jr z, .carSuccess

    ; Check BREAK: latched during readTimeoutLong (caught even if user
    ; released key before we got here), plus live re-read for the edge
    ; case of BREAK pressed AFTER the long read returned.
    ld a, (Uart.break_hit)
    and a
    jr nz, .carCancelled
    call Keyboard.checkBreak
    jr z, .carCancelled

    ; Retry?
    ld a, (conn_retries) : dec a : ld (conn_retries), a
    jr z, .carFailed

    ; Show "Retry..." briefly (clear residual "Press BREAK to cancel" after it)
    ld a, 8 : call Display.gotoXY0 : ld hl, msg_retry_big : call Display.putStrBig
    ld b, 14
.clrRetry
    push bc : ld a, ' ' : call Display.putC : pop bc : djnz .clrRetry
    ld a, 8 : ld c, Display.ATTR_ALERT : call setDoubleAttr
    ld b, 100
.carRetryWait
    halt
    push bc
    call Keyboard.checkBreak
    pop bc
    jr z, .carCancelled
    djnz .carRetryWait
    jp .carRetry

.carSuccess
    ld a, 1 : ld (Wifi.is_connected), a
    ld hl, manual_ssid_buffer
    ld de, Wifi.connected_ssid
    call copyStringZ
    call updateWifiStatus_q
    ld b, 50
.carIpWait
    halt
    djnz .carIpWait
    call connSuccessScreen
    jp renderListAndLoop

.carCancelled
    call Wifi.flushInput
    ld hl, cmd_disconnect
    call Wifi.espSendZCheckOk   ; best effort: abort a join still in flight
    call Wifi.flushInput
    jp showCancelledScreen

.carDiscFailed
    call Wifi.flushInput
    ld hl, msg_disc_failed
    call topCleanAlertMsg
    jp pressKeyReturnList

.carDiscCancelled
    call Wifi.flushInput
    jp showCancelledScreen

.carFailed
    ld a, (Wifi.last_error)
    push af
    call Wifi.ensureCommandMode
    pop af
    ld (Wifi.last_error), a
    jp showConnFailScreen

.car_log_masked db ">> AT+CWJAP (hidden)", 13, 0

; ============================================
; connSuccessScreen - Shared success screen for all connection routes
; Shows "Connected!", waits for key, offers (S)ave on esxDOS platforms
; ============================================
connSuccessScreen:
    call ipShowConnected
    call topClean
    ld hl, msg_connected_title : ld c, Display.ATTR_SSID_INPUT : call showBigMessage
    ld a, 6 : ld hl, msg_done_body : call printAt0
    IFDEF HAS_ESXDOS
    ; Reconnect: standard "press any key". New connection: offer save.
    ld a, (is_reconnect)
    and a
    jr nz, .cssStdKey
    ld a, 17 : ld hl, msg_save_presskey : call printAt0
    ld a, 17 : ld c, ATTR_PRESS_KEY : call Display.setAttr
    jr .cssWait
.cssStdKey
    ENDIF
    call showPressKey
.cssWait
    halt
    ; Ignore BREAK here: connection succeeded, user just landed on the
    ; "Connected!" screen. Exiting to BASIC with CAPS+SPACE held would
    ; leave the BREAK latch set and BASIC would raise "L BREAK into
    ; program 50:1" on the next line.
    call Keyboard.inKeyNoWait : and a : jr z, .cssWait
    call Keyboard.keyClick
    cp 'l' : jr z, .cssLog : cp 'L' : jr z, .cssLog
    IFDEF HAS_ESXDOS
    ld c, a
    ld a, (is_reconnect) : and a : jr nz, .cssNoSave
    ld a, c
    cp 's' : jr z, .cssSave : cp 'S' : jr z, .cssSave
    ld a, c
.cssNoSave
    ld a, c                 ; restore key from C
    ENDIF
    ret
.cssLog
    call toggleLogQuiet : jr .cssWait
    IFDEF HAS_ESXDOS
.cssSave
    ; Clear bottom prompt
    ld a, 17 : call clearRowPixels
    ld a, 17 : ld c, Display.ATTR_NORMAL : call Display.setAttr
    call Config.save
    call restoreAfterFileIo     ; rearm printer-buffer state (both branches)
    jr nc, .cssSaveOk
    ; Error: double-height red on rows 8-9, then press any key
    ld a, 8 : call Display.gotoXY0
    ld hl, msg_save_fail : call Display.putStrBig
    ld a, 8 : ld c, Display.ATTR_ALERT : call setDoubleAttr
    call showPressKey
    jr .cssWait
.cssSaveOk
    ; Success: double-height green on rows 8-9, pause, auto-return
    ld a, 8 : call Display.gotoXY0
    ld hl, msg_save_ok : call Display.putStrBig
    ld a, 8 : ld c, Display.ATTR_SSID_INPUT : call setDoubleAttr
    ld b, 75                    ; ~1.5s pause
.cssPause
    halt
    djnz .cssPause
    ret                         ; return to caller → renderListAndLoop
    ENDIF

; Try to recover an unresponsive ESP
; ============================================
; showConnFailScreen - Shared fail screen for both connection routes
; Big red title + detail text + yellow "Press any key"
; ============================================
showCancelledScreen:
    call topClean
    ld hl, scc_title
    ld c, Display.ATTR_ALERT
    call showBigMessage
    call showPressKey
    ; Debounce: drain stale keys from BREAK release
    call debounce15
    call waitAnyKey
    jp renderListAndLoop

scc_title db "Cancelled.", 0

; ============================================
showConnFailScreen:
    xor a : ld (Wifi.is_connected), a
    ld (Wifi.connected_bssid_valid), a
    call updateWifiStatus_q
    call ipShowNotConnected
    call topClean
    ; Big red title (rows 3-4): "Connection failed!"
    ld hl, scf_title
    ld c, Display.ATTR_ALERT
    call showBigMessage

    ; Row 6: Preserve CWJAP detail, including a generic AT rejection.
    ld a, 6 : call Display.gotoXY0
    ld hl, scf_reason_pfx
    call Display.putStr
    ld a, (Wifi.last_error)
    cp 7 : jr c, .scfReasonOk
    xor a                       ; Unknown code -> generic
.scfReasonOk
    add a, a                    ; x2 (pointer table)
    ld e, a : ld d, 0
    ld hl, scf_reasons
    add hl, de
    ld a, (hl) : inc hl : ld h, (hl) : ld l, a
    call Display.putStr

    ; Row 8: Hint
    ld a, 8 : ld hl, scf_detail : call printAt0
    jp pressKeyReturnList

scf_title  db "Connection failed!", 0
scf_detail db "Check password, signal or router.", 0
scf_reason_pfx db "Reason: ", 0

scf_reasons
    dw .scf_r0, .scf_r1, .scf_r2, .scf_r3, .scf_r4, .scf_r5, .scf_r6
.scf_r0 db "Timeout (no response)", 0
.scf_r1 db "Connection timeout", 0
.scf_r2 db "Wrong password", 0
.scf_r3 db "AP not found", 0
.scf_r4 db "Connection refused", 0
.scf_r5 db "UART error", 0
.scf_r6 db "AT rejected", 0
msg_retry_big         db "Retry...", 0

; ============================================
; Diagnostics
; ============================================
DIAG_ITEMS = 7
DIAG_FIRST_LINE = 6
ATTR_DIAG_TITLE = 00000100b  ; Green on black (BRIGHT 0)

; "Press any key..." on line 17, col 0, yellow
ATTR_PRESS_KEY = 01000110b  ; Bright yellow on black
showPressKey:
    ld a, 17
; Show "Press any key..." at row A, col 0, yellow
showPressKeyAt:
    push af
    ld c, ATTR_PRESS_KEY
    call Display.setAttr
    pop af
    ld h, a : ld l, 0
    ld (Display.coords), hl
    ld hl, msg_press_key
    jp Display.putStr

; Standard header for diagnostic screens
; Input: HL = title pointer. Clears screen, green double-height title.
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
    ; Options via loop + pointer table
    ld hl, .diagPtrs
    ld b, DIAG_ITEMS
    ld c, DIAG_FIRST_LINE
.menuLp:
    push bc
    push hl
    ld a, c
    ld h, a : ld l, 0
    ld (Display.coords), hl
    pop hl
    push hl
    ld e, (hl) : inc hl : ld d, (hl) : inc hl
    ex de, hl
    call Display.putStr
    pop hl
    inc hl : inc hl
    pop bc
    inc c
    djnz .menuLp
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

; Buffer for diagnostic responses
    RTVAR diag_buffer, 64
DIAG_ROW_LIMIT = 16             ; Rows 0-15 may start diagnostic output
    IFDEF AY
DIAG_READ_INITIAL  = #00E0      ; ~1s
DIAG_READ_TAIL     = #001C      ; ~125ms
    ELSE
DIAG_READ_INITIAL  = #FFFF
DIAG_READ_TAIL     = #2000
    ENDIF
diag_line       = #5B1E         ; In printer buffer (set before use)

; Drain UART buffer and clear the transport latch at transaction boundaries.
flushUartBuffer = Wifi.flushInput

; Read a line preserving BC (for diagnostic loops)
readDiagLineBC:
    push bc
    call readDiagLine
    pop bc
    ret

; Read a line from ESP until CR/LF or timeout (no HALT)
; Output: CF=1 if data, CF=0 if timeout with no data
readDiagLine:
    ld hl, diag_buffer
    ld c, 60                    ; Max 60 characters
    ld de, DIAG_READ_INITIAL    ; Initial timeout
    xor a
    ld (Uart.break_hit), a

.readLoop
    push hl, bc, de
    call UartImpl.uartRead
    pop de, bc, hl
    push af
    ld a, (Uart.io_error)
    and a
    jr nz, .ioError
    pop af
    jr c, .gotByte

    call Keyboard.checkBreak
    jr nz, .notCancelled
    ld a, 1
    ld (Uart.break_hit), a
    jr .timeout
.notCancelled

    dec de
    ld a, d
    or e
    jr nz, .readLoop

.timeout
    xor a
    ld (hl), a
    ret                         ; CF=0

.gotByte
    ; On receiving data, reduce timeout to close line if missing terminator
    ld de, DIAG_READ_TAIL

    ; CR or LF = end of line
    cp 13
    jr z, .endLine
    cp 10
    jr z, .endLine

    ; Store character
    ld (hl), a
    inc hl
    dec c
    jr nz, .readLoop
    xor a
    ld (hl), a
    jp drainDiagLine

.endLine
    xor a
    ld (hl), a                  ; Terminate string
    scf                         ; CF=1, data available
    ret
.ioError
    pop af
    xor a
    ld (hl), a
    ret

; Finish an overlong line without touching the bounded destination buffer.
; CF=0 only on transport error or if the 255-byte drain cap is exhausted.
drainDiagLine:
    ld b, 255
.loop
    call Uart.readTimeoutMedium
    jr nc, .stopped
    cp 13
    jr z, .done
    cp 10
    jr z, .done
    djnz .loop
    ld a, 1
    ld (Uart.io_error), a       ; Keep an unframed suffix from becoming a line.
    or a
    ret
.stopped
    ; Silence before a terminator leaves framing unknown, even after 60 bytes.
    ld a, 1
    ld (Uart.io_error), a
    or a
    ret
.done
    scf
    ret

; Read a line with long initial wait (for queries that sometimes take time)
; Output: CF=1 if data, CF=0 if timeout with no data
readDiagLineLong:
    ld hl, diag_buffer
    ld c, 60

    ; Wait for first byte with long timeout
    call Uart.readTimeoutLong
    jr nc, .timeout

.readLoop
    ; CR or LF = end of line
    cp 13
    jr z, .endLine
    cp 10
    jr z, .endLine

    ; Store character
    ld (hl), a
    inc hl
    dec c
    jr nz, .readNext
    xor a
    ld (hl), a
    jp drainDiagLine

    ; Read next byte with medium timeout (more time for Next)
.readNext
    call Uart.readTimeoutMedium
    jr c, .readLoop
    ld a, (Uart.break_hit)
    and a
    jr nz, .timeout
    ld a, (Uart.io_error)
    and a
    jr nz, .timeout
    jr .endLine

.timeout
    xor a
    ld (hl), a
    or a                        ; CF=0
    ret

.endLine
    xor a
    ld (hl), a
    scf
    ret

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
    ; Disable UART log during diagnostics
    xor a
    ld (Uart.log_enabled), a
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
    call diagHeader

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
    ld a, '_'
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
    ld a, (Uart.break_hit)
    and a
    jp nz, showDiagnostics
    dec c
    jp nz, .pingLoop

.pingDone
    jp pressKeyReturnDiag



; ============================================
; Module info (firmware version)
; ============================================
doModuleInfo:
    ; Disable UART log
    xor a
    ld (Uart.log_enabled), a

    ld hl, .msg_module_title
    call diagHeader

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
    dec c
    jr nz, .gmrLoop

.gmrDone
    jp pressKeyReturnDiag

.msg_module_title db "MODULE INFO", 0
.cmd_gmr          db "AT+GMR", 0

; ============================================
; Network info
; ============================================
doNetworkInfo:
    xor a
    ld (Uart.log_enabled), a
    call topClean

    ; Show connected network details
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
    ld hl, Wifi.connected_ssid : call Display.putStr
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
    dec c
    jr nz, .cifsrLoop

.cifsrDone
    jp pressKeyReturnDiag

.findQuote
    ld a, (hl)
    cp '"' : jr z, .foundQ
    inc hl
    and a : ret z
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
    xor a
    ld (Uart.log_enabled), a
    ld hl, msg_baud_title
    call diagHeader

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
    ld a, (hl)
    and a : ret z
    cp ':' : jr z, .gotColon
    inc hl
    jr baudSkipToColon
.gotColon
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
    xor a
    ld (Uart.log_enabled), a
    ld hl, .sip_title
    call diagHeader
    ld a, 6 : ld hl, .sip_prompt : call printAt0
    call setPassRows8
    ld a, 11 : ld hl, .sip_help : call printAt0

    ; IP input (digits and dots only)
    ld hl, sip_buf
    ld b, 15                    ; Max IP length (xxx.xxx.xxx.xxx)
    ld a, 8 : ld (sti_line), a
    xor a : ld (sti_len), a
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
    ; Update IP on screen
    call Wifi.getIP
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
    RTVAR sip_buf, 16

; ============================================
; ipTextInput - Text input for IPs (digits and dots only)
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
    ld a, '_' : call Display.putCBig
    ld a, ' ' : call Display.putCBig
    ld a, ' ' : call Display.putCBig
    ei
.itiWait
    ld b, 4
.itiWL  halt
    call Keyboard.checkBreak : jr z, .itiCancel
    djnz .itiWL
    call Keyboard.inKeyNoWait : and a : jr z, .itiWait
    call Keyboard.keyClick
    cp 13 : jr z, .itiEnter
    cp Keyboard.KEY_BS : jr z, .itiBS
    ; Only accept '0'-'9' and '.'
    cp '.' : jr z, .itiAccept
    cp '0' : jr c, .itiWait
    cp '9'+1 : jr nc, .itiWait
.itiAccept
    ld c, a
    ld a, (sti_len) : ld b, a : ld a, (sti_max) : cp b : jr z, .itiWait
    ld a, (sti_len) : ld hl, (sti_buf) : ld d, 0 : ld e, a : add hl, de
    ld (hl), c : inc hl : ld (hl), 0
    ld a, (sti_len) : inc a : ld (sti_len), a
    jr .itiRedraw
.itiBS  ld a, (sti_len) : and a : jr z, .itiWait
    dec a : ld (sti_len), a
    ld hl, (sti_buf) : ld d, 0 : ld e, a : add hl, de : ld (hl), 0
    jr .itiRedraw
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
    xor a
    ld (Uart.log_enabled), a
    ld hl, .hn_title
    call diagHeader
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
    ld a, (pass_len) : ld b, a
.hn_copy
    ld a, (hl) : ld (de), a
    inc hl : inc de
    djnz .hn_copy
    xor a : ld (de), a                 ; Null-terminate

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

    RTVAR hn_buf, 21

; ============================================
; doConfigSummary - Show all config (option 7)
; ============================================
doConfigSummary:
    xor a
    ld (Uart.log_enabled), a
    ld hl, .cs_title
    call diagHeader

    ; Fetch gateway/mask (before display, only if connected)
    ld a, (Wifi.is_connected)
    and a
    jr z, .cs_skip_conninfo
    call Wifi.getConnectionInfo
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
    ld hl, .cs_none : call Display.putStr

.cs_ip
    ; IP - read directly from ip_buffer (already populated in status bar)
    ld a, 8 : ld hl, .cs_ip_lbl : call printAt0
    ld hl, Wifi.ip_buffer
    ld a, (hl) : and a : jr nz, .cs_ip_ok
    ld hl, .cs_none
.cs_ip_ok
    call Display.putStr

    ; Gateway
    ld a, 9 : ld hl, .cs_gw_lbl : call printAt0
    ld hl, Wifi.ci_gateway
    ld a, (hl) : and a : jr nz, .cs_gw_ok
    ld hl, .cs_none
.cs_gw_ok
    call Display.putStr

    ; Netmask
    ld a, 10 : ld hl, .cs_mask_lbl : call printAt0
    ld hl, Wifi.ci_netmask
    ld a, (hl) : and a : jr nz, .cs_mask_ok
    ld hl, .cs_none
.cs_mask_ok
    call Display.putStr

.cs_mac
    ; MAC - send AT+CIPSTAMAC?
    ld a, 11 : ld hl, .cs_mac_lbl : call printAt0
    call .cs_flush
    ld hl, .cs_mac_cmd : call Wifi.espSendZ_CRLF
    ld b, 8
.cs_mac_loop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call readDiagLineBC
    jr nc, .cs_mac_done
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_mac_done
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
    ld b, 6
.cs_hn_loop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call readDiagLineBC
    jr nc, .cs_hn_done
    ld a, (diag_buffer) : cp '+' : jr nz, .cs_hn_skip
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
    ld b, 10
.cs_fw_loop
    call Keyboard.checkBreak : jp z, showDiagnostics
    call readDiagLineBC
    jr nc, .cs_fw_done
    ld a, (diag_buffer) : and a : jr z, .cs_fw_next
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
.cs_ssid    db "SSID: ", 0
.cs_ip_lbl  db "IP:   ", 0
.cs_gw_lbl   db "GW:   ", 0
.cs_mask_lbl db "Mask: ", 0
.cs_mac_lbl  db "MAC:  ", 0
.cs_hn_lbl  db "Host: ", 0
.cs_fw_lbl  db "FW:   ", 0
.cs_band24  db " (2.4G)", 0
.cs_band5   db " (5G)", 0
.cs_none    db "(none)", 0
    IFDEF HAS_ESXDOS
.cs_saved_lbl db "Saved: ", 0
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
printClean:
    ld a, (hl) : and a : ret z
    cp '"' : ret z
    cp 13 : ret z
    cp 10 : ret z
    push bc : push hl : call Display.putC : pop hl : pop bc
    inc hl : jr printClean

; ============================================
; checkAsyncWifi - Detect async WiFi events
; Looks for "DISCONNECT" and "GOT IP" in the UART stream
; Output: A = event code
;   ASYNC_EVENT_NONE (0) = no event
;   ASYNC_EVENT_DISCONNECT (1) = disconnect detected
;   ASYNC_EVENT_GOTIP (2) = connection detected
; ============================================
ASYNC_EVENT_NONE       = 0
ASYNC_EVENT_DISCONNECT = 1
ASYNC_EVENT_GOTIP      = 2
ASYNC_DRAIN_BUDGET     = 64

checkAsyncWifi:
    ld a, (Wifi.uart_busy)
    and a
    jr nz, .none
    ld b, ASYNC_DRAIN_BUDGET
.drainLoop
    push bc
    call UartImpl.uartRead
    pop bc
    ld c, a
    ld a, (Uart.io_error)
    inc a : dec a              ; Test the fault without losing receive carry.
    jr nz, .fault
    jr nc, .none

    ; Match as bytes arrive; return before a following line can erase the event.
    push bc
    ld hl, .pat_discon
    ld de, async_buf_idx
    ld b, 15
    call .match
    pop bc
    ld a, ASYNC_EVENT_DISCONNECT
    ret c
    push bc
    ld hl, .pat_gotip
    ld de, async_buf_count
    ld b, 11
    call .match
    pop bc
    ld a, ASYNC_EVENT_GOTIP
    ret c
    djnz .drainLoop
.none
    xor a
    ret
.fault
    call Wifi.flushInput
    xor a
    ld (async_buf_idx), a
    ld (async_buf_count), a
    ret

; C = byte, HL = pattern, DE = matched-length byte, B = pattern length.
; Both patterns have no internal W, so only W can restart a mismatch.
.match
    push de
    ld a, (de)
    ld e, a
    ld d, 0
    add hl, de
    ld a, c
    cp (hl)
    pop de
    jr nz, .mismatch
    ld a, (de)
    inc a
    ld (de), a
    cp b
    jr nz, .notMatched
    xor a
    ld (de), a
    scf
    ret
.mismatch
    xor a
    ld (de), a
    ld a, c
    cp 'W'
    jr nz, .notMatched
    ld a, 1
    ld (de), a
.notMatched
    or a
    ret

.pat_discon db "WIFI DISCONNECT"
.pat_gotip  db "WIFI GOT IP"
    RTVAR async_buf_idx, 1
    RTVAR async_buf_count, 1

; ============================================--------------
; waitAnyKey
;   Blocks until any key is pressed.
;   For UI use (should not be used during high-speed parsers).
; ============================================--------------
waitAnyKey:
waitAnyKey_loop:
    halt
    call Keyboard.inKey
    and a
    jr z, waitAnyKey_loop
    ret

; ============================================
; Show network info right-aligned on line 17
; Text ends at column 41 (safe screen limit).
; ============================================
showPageInfo:
    ; Skip footer entirely if flag set (e.g. coming from diagnostics before scan)
    ld a, (skip_footer)
    and a
    ret nz

    ; --- 1. Calculate pagination data ---
    ld a, (Wifi.networks_count)
    and a
    jr nz, .haveNetworks

    ; 0 networks: clear line 17 completely (avoids stale counter)
    ld a, 17
    jp clearRowPixels

.haveNetworks
    
    ; Calculate Total pages = ceil(count / PER_PAGE)
    ; = (count - 1) / PER_PAGE + 1 (using repeated subtraction)
    dec a                   ; A = count - 1
    ld b, 0
.divTotal
    inc b
    sub PER_PAGE
    jr nc, .divTotal
    ld a, b
    ld (page_total), a

    ; Calculate Current page = offset / PER_PAGE + 1
    ld a, (offset)
    ld b, 0
.divCurrent
    inc b
    sub PER_PAGE
    jr nc, .divCurrent
    ld a, b
    ld (page_current), a

    ; --- 2. Calculate text length for alignment ---
    ; Base: "X networks detected"
    ; " networks detected" = 18 chars
    ld c, 18
    
    ; Add digits of networks_count
    ld a, (Wifi.networks_count)
    call getDigitCount      ; Returns 1 or 2 in A
    add a, c
    ld c, a                 ; C has partial length

    ; If paginated, add " (A/B pages)"
    ld a, (page_total)
    cp 2
    jr c, .calcFinish       ; Only 1 page, done calculating

    ; " (" + digit + "/" + digit + " pages)"
    ; 1 space + 1 "(" + page_curr + 1 "/" + page_total + 7 " pages)" = 10 + digits
    ld a, c
    add a, 10
    ld c, a
    
    ld a, (page_current)
    call getDigitCount
    add a, c
    ld c, a
    
    ld a, (page_total)
    call getDigitCount
    add a, c
    ld c, a                 ; C = TOTAL string length

.calcFinish
    ; --- 3. Calculate initial X position ---
    ; End at column 40 so column 41 stays free for the right scroll arrow.
    ; StartX = 41 - C.
    ld a, 41
    sub c
    ld b, a                 ; B = StartX
    
    ; --- 4. Clear full line 17 ---
    push bc
    ld a, 17
    call clearRowPixels
    pop bc

.printInfo
    ; --- 5. Print text at position ---
    ld l, b                 ; L = StartX
    ld h, 17
    ld (Display.coords), hl

    ; Print "Num networks detected"
    ld a, (Wifi.networks_count)
    call printNumber
    ld hl, .msg_net_det
    call Display.putStr

    ; Print pagination if applicable
    ld a, (page_total)
    cp 2
    ret c

    ld a, ' ' : call Display.putC
    ld a, '(' : call Display.putC
    ld a, (page_current) : call printNumber
    ld a, '/' : call Display.putC
    ld a, (page_total) : call printNumber
    ld hl, .msg_pages_suff
    jp Display.putStr

.msg_net_det    db " networks detected", 0
.msg_pages_suff db " pages)", 0

; Returns in A how many digits the number in A has (0-99)
; 1 if < 10, 2 if >= 10
getDigitCount:
    cp 10
    sbc a, a                ; CF=1 (< 10) → A=#FF; CF=0 (≥ 10) → A=0
    add a, 2                ; #FF+2=1; 0+2=2
    ret

; Print A (0-99) in decimal
printNumber:
    ld c, -1
.div10
    inc c
    sub 10
    jr nc, .div10
    add a, 10           ; A = units (remainder)
    push af
    ld a, c
    and a
    jr z, .skipTens     ; No leading zero
    add a, '0'
    call Display.putC
.skipTens
    pop af
    add a, '0'
    jp Display.putC

; In printer buffer (set in showPageInfo)
page_total      = #5B28
page_current    = #5B29

; ============================================
; About screen (I key)
; ============================================
; Print table: db row, dw string_ptr ... db 255
; Input: HL = table
; Destroys: all (via printAt0)
printRowTable:
.prtLoop
    ld a, (hl)
    cp 255
    ret z
    inc hl
    ld e, (hl) : inc hl : ld d, (hl) : inc hl
    push hl
    ex de, hl
    call printAt0
    pop hl
    jr .prtLoop

showAbout:
    ld hl, .msg_about_title
    call diagHeader
    ld hl, .aboutRows
    call printRowTable
    jp pressKeyReturnList

.aboutRows:
    db 6 : dw .msg_about_ver
    db 7 : dw .msg_about_build
    db 9 : dw .msg_about_desc
    db 10 : dw .msg_about_author
    db 11 : dw .msg_about_github
    db 12 : dw .msg_about_license
    db 255

.msg_about_title db "ABOUT NETMANZX", 0
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
.msg_about_build db "Build: ", BUILD_DATE, 0
.msg_about_desc  db "WiFi manager for ZX Spectrum", 0
.msg_about_author db "By Ignacio Monge Garcia", 0
.msg_about_github db "github.com/IgnacioMonge/NetManZX", 0
.msg_about_license db "License: MIT", 0

; ============================================
; Messages and data
; ============================================
    RTVAR pass_buffer, MAX_PASS_LEN + 2
    ; Cursor/page state survives esxDOS file I/O — kept out of the printer
    ; buffer. Zero-initialised by main.asm start: before any read.
    RTVAR cursor_position, 1
    RTVAR offset, 1
    RTVAR force_rescan, 1
    RTVAR diag_cursor, 1
    RTVAR status_color, 1
    RTVAR status_text_ptr, 2
; In printer buffer (set before use in respective handlers)
pass_len        = #5B3C
pass_cursor     = #5B3D
; cursor_position and offset migrated to RTVAR (see RTVAR block below):
; renderListAndLoop reads both right after Config.load/save in doReconnect
; and connSuccessScreen save paths. esxDOS rst $08 corrupted them otherwise.
is_open_network = #5B40
show_password   = #5B41
selected_ssid_ptr = #5B42  ; dw
selected_real_idx = #5B44
; In printer buffer (accumulation counters, reset in uiLoop init paths)
ui_async_div    = #5B49
autoscan_counter = #5B4A  ; dw
health_counter  = #5B4C   ; dw
hc_fail_count   = #5B10   ; Consecutive health-check failures (debounce)
skip_footer     = #5B0C   ; Suppress footer in renderList (set before call, cleared after)
is_reconnect = #5B5A             ; In printer buffer (set before connectAndReturn)

    endmodule
