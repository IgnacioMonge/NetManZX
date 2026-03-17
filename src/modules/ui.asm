    module UI
PER_PAGE = 10
MAX_PASS_LEN = 40           

init:
    call Display.clrscr
    ; Render status bar FIRST to avoid blank white bar flicker
    ld hl, status_scanning_data
    ld a, (hl) : ld (status_color), a
    inc hl : ld (status_text_ptr), hl
    call ipShowScanning         ; Sets IP text + renders full status bar
    ; Double-height banner: rows 0-1
    setLineColor 0, Display.ATTR_BANNER_TOP
    setLineColor 1, Display.ATTR_BANNER_BOT
    gotoXY 0, 0 : printMsg msg_head
    call Display.stretchRows01
    call drawBadge
    call drawSeparator
    call clearPassBuffer
    ret

; SpectalkZX-style badge: dithered triangle with color transitions
; Row 0 (top): 4 cells at bytes 28-31 (staggered, 1 cell less)
; Row 1 (bot): 5 cells at bytes 27-31 (full)
; Spectrum colors: red, yellow, green, blue

badge_pattern:
    db #00, #01, #03, #07, #0F, #1F, #3F, #7F

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
    ld (hl), 01000010b      ; P=black I=red BRIGHT
    inc hl
    ld (hl), 01010110b      ; P=red I=yellow BRIGHT
    inc hl
    ld (hl), 01110100b      ; P=yellow I=green BRIGHT
    inc hl
    ld (hl), 01100001b      ; P=green I=blue BRIGHT
    ; Attributes row 1 (bot): 5 cells BRIGHT
    ld hl, #583B            ; Row 1, cell 27
    ld (hl), 01000010b      ; P=black I=red BRIGHT
    inc hl
    ld (hl), 01010110b      ; P=red I=yellow BRIGHT
    inc hl
    ld (hl), 01110100b      ; P=yellow I=green BRIGHT
    inc hl
    ld (hl), 01100001b      ; P=green I=blue BRIGHT
    inc hl
    ld (hl), 01001000b      ; P=blue I=black BRIGHT (transition back)
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
    ld d, a : ld e, 0
    call Display.findAddr       ; DE = row A, scanline 0
    ld b, 8
.crpLoop
    push bc : push de
    ld h, d : ld l, e
    ld (hl), 0
    ld d, h : ld e, l : inc de
    ld bc, 31
    ldir
    pop de : pop bc
    inc d
    djnz .crpLoop
    ret

; ============================================
; statusBarFinalize - Render double-height status bar (rows 17-18)
; Reads: ip_line_buffer, status_text_ptr, ip_value_color, status_color
; ============================================
statusBarFinalize:
    ; Render text directly (no clear first = no flicker)
    gotoXY 0, 18
    ld hl, ip_line_buffer
    call Display.putStr
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
    call ipSetFromZ
    ld a, Display.ATTR_STATUSBAR
    ld (ip_value_color), a
    jp statusBarFinalize

; Show "IP:Disconnected" in red
ipShowNotConnected:
    ld hl, msg_ip_disconn
    call ipSetFromZ
    ld a, 172o              ; Red on bright white
    ld (ip_value_color), a
    jp statusBarFinalize

; Show "IP: x.x.x.x" in blue
ipShowConnected:
    call Wifi.getIP
    jr c, ipShowNotConnected
    ld hl, msg_ip_prefix
    call ipSetPrefix
    ld hl, Wifi.ip_buffer
    call ipAppendZ
    ld a, 171o              ; Blue on bright white
    ld (ip_value_color), a
    jp statusBarFinalize

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

; Copy prefix "IP: " to ip_line_buffer (with null terminator for ipAppendZ)
ipSetPrefix:
    ld de, ip_line_buffer
.copyP
    ld a, (hl)
    ld (de), a              ; Copy including the 0
    and a
    ret z                   ; Return after copying the 0
    inc hl
    inc de
    jr .copyP

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

; Buffers/messages
msg_ip_prefix      db "IP: ", 0
msg_ip_disconn     db "IP: Disconnected", 0
msg_ip_scanning    db "IP: Scanning...", 0
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

; Set status "Scanning"
setStatusScanning:
    ld hl, status_scanning_data
    jr setStatusCommon

; Set status "Connected"
setStatusConnected:
    ld hl, status_connected_data
    jr setStatusCommon

; Set status "Disconnected"
setStatusDisconnected:
    ld hl, status_disconn_data
    jr setStatusCommon

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

status_color db 0
status_text_ptr dw 0
ip_value_color db Display.ATTR_STATUSBAR

; Status data: color (1 byte) + message
status_scanning_data:
    db Display.ATTR_STATUSBAR   ; Black on bright white
    db "Scanning    ", 0
status_connected_data:
    db 174o                     ; Green on bright white
    db "Connected   ", 0
status_disconn_data:
    db 172o                     ; Red on bright white
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
    jr z, setStatusDisconnected
    jr setStatusConnected

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

passwordInput:
    ; Debounce: wait for previous key release
.piDebounce
    halt
    call Keyboard.inKeyNoWait
    and a
    jr nz, .piDebounce
; --- Full redraw (only for toggle and init) ---
.piRedraw
    halt
    ld a, (pass_line)
    ld h, a : ld l, 0
    ld (Display.coords), hl
    ld a, (pass_cursor) : and a : jr z, .piCursor
    ld b, a : ld hl, pass_buffer
    ld a, (show_password) : and a : jr nz, .piRealB
.piAstB
    push bc : push hl : ld a, '*' : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piAstB
    jr .piCursor
.piRealB
    push bc : push hl : ld a, (hl) : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piRealB
.piCursor
    ld a, 127 : call Display.putCBig
    ld a, (pass_len) : ld b, a : ld a, (pass_cursor) : cp b : jr nc, .piClrTail
    ld c, a : ld a, b : sub c : jr z, .piClrTail : ld b, a
    ld a, (pass_cursor) : ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de
    ld a, (show_password) : and a : jr nz, .piRealA
.piAstA
    push bc : push hl : ld a, '*' : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piAstA
    jr .piClrTail
.piRealA
    push bc : push hl : ld a, (hl) : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piRealA
.piClrTail
    ld a, ' ' : call Display.putCBig : ld a, ' ' : call Display.putCBig
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
    jp .piWait

; --- Key wait loop ---
.piWait
    ld b, 4
.piWL   halt : djnz .piWL
    call Keyboard.checkBreak : jp z, .piCancel
    call Keyboard.inKeyNoWait : and a : jr z, .piWait
    cp Keyboard.KEY_UP : jp z, .piToggle
    cp 8 : jp z, .piLeft
    cp 9 : jp z, .piRight
    cp Keyboard.KEY_BS : jp z, .piDel
    cp 13 : jp z, .piEnter
    cp 32 : jp c, .piWait
    cp 127 : jp nc, .piWait

    ; --- Insert character ---
    ld c, a
    ld a, (pass_len) : cp MAX_PASS_LEN : jp nc, .piWait
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
    jp .piWait

    ; Insert in middle -> shift + full redraw
.piInsMid
    ld a, (pass_len) : ld b, a : ld a, (pass_cursor) : ld e, a
.piShR  ld a, b : cp e : jr z, .piIns
    dec b : ld hl, pass_buffer : ld d, 0 : push de : ld e, b : add hl, de
    ld a, (hl) : inc hl : ld (hl), a : pop de : jr .piShR
.piIns  ld a, (pass_cursor) : ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de : ld (hl), c
    ld a, (pass_len) : inc a : ld (pass_len), a
    ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de : xor a : ld (hl), a
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    jp .piRedraw

; --- Cursor left (incremental: 2 cells) ---
.piLeft ld a, (pass_cursor) : and a : jp z, .piWait
    dec a : ld (pass_cursor), a
    ; Restore char at old position (cursor+1)
    ld a, (pass_cursor) : inc a : ld b, a
    call .piDrawBufAt
    ; Cursor at new position
    ld a, (pass_cursor) : ld b, a
    call .piDrawCurAt
    jp .piWait

; --- Cursor right (incremental: 2 cells) ---
.piRight
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : cp b : jp z, .piWait
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    ; Restore char at old position (cursor-1)
    ld a, (pass_cursor) : dec a : ld b, a
    call .piDrawBufAt
    ; Cursor at new position
    ld a, (pass_cursor) : ld b, a
    call .piDrawCurAt
    jp .piWait

; --- Toggle show/hide (full redraw, rare) ---
.piToggle ld a, (show_password) : xor 1 : ld (show_password), a : jp .piRedraw

; --- Delete character ---
.piDel  ld a, (pass_cursor) : and a : jp z, .piWait
    ld b, a : ld a, (pass_len) : cp b : jr z, .piDelEnd
    ; Delete in middle -> shift + full redraw
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : ld c, a
.piShL  ld a, b : cp c : jr z, .piDelEnd
    ld hl, pass_buffer : ld d, 0 : ld e, b : add hl, de
    ld a, (hl) : dec hl : ld (hl), a : inc b : jr .piShL
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

sti_buf  dw 0
sti_max  db 0
sti_len  db 0
sti_line db 0

topClean:
    call Display.clrListOnly    ; Only clears lines 2-14
    call clearListAttrs
    jp drawSeparator            ; Redraw separator (includes ret)

; Clear only the networks area (lines 6-14) - for sort/rescan
clearNetworksArea:
    jp Display.clrNetworksOnly

; renderNetworksOnly - Redraws ONLY the network list (lines 6-14).
; Does not touch indicators/upper menu (scroll/page info).
; Used for disconnect refreshes to avoid flicker/changes above.
renderNetworksOnly:
    call clearNetworksArea
    jr renderNetworksCommon

; renderListOnly - Redraws only networks + indicators, not the help text
; Used by sort and rescan to avoid flicker
renderListOnly:
    call clearNetworksArea
    call showScrollIndicators
    call showPageInfo
    call renderNetworksCommon
    ld a, (Wifi.networks_count)
    and a
    ret z                       ; No networks: don't draw cursor
    jp showCursor

; ============================================
; renderNetworksCommon - Common routine to draw network list
; Input: area already cleared
; ============================================
renderNetworksCommon:
    ; Position at line 6 to start listing
    gotoXY 0, 6

    ; Reset connected network found flag
    xor a
    ld (conn_row_found), a

    ; Calculate how many networks to show on this page
    ld a, (Wifi.networks_count)
    ld hl, offset
    sub (hl)
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

    ; Default attribute (list area only)
    push hl
    ld a, (current_line)
    ld c, Display.ATTR_NORMAL
    call Display.setAttrPartial
    pop hl

    ; Highlight connected SSID if applicable
    ld a, (Wifi.is_connected)
    and a
    jr z, .noConnAttr
    
    ; If we already found the connected network, don't search further
    ld a, (conn_row_found)
    and a
    jr nz, .noConnAttr
    
    ld a, (hl)
    and a
    jr z, .noConnAttr           ; Empty SSID -> don't highlight
    push hl
    ld de, Wifi.connected_ssid
    call Display.compareStringZ
    pop hl
    jr nz, .noConnAttr
    
    ; Mark that we found the connected network
    ld a, 1
    ld (conn_row_found), a
    
    push hl
    ld a, (current_line)
    ld c, Display.ATTR_CONNECTED  ; Yellow on black
    call Display.setAttrPartial
    pop hl
.noConnAttr
    ; Check if SSID is empty (hidden network)
    ld a, (hl)
    and a
    jr nz, .printSSID
    ld hl, msg_hidden           ; Empty SSID - show "<hidden>"
.printSSID
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
    djnz .showLoop
    ret

.noNetworks
    gotoXY 0, 6
    ld hl, no_net_msg
    call Display.putStr
    ret

msg_hidden db "<hidden>", 0

; ============================================
; putStrLimited - Print Z-terminated string with limit
; Input: HL = string pointer, B = max characters
; ============================================
putStrLimited:
    ld a, (hl)
    and a
    ret z               ; End of string
    ld a, b
    and a
    ret z               ; Limit reached
    push hl
    push bc
    ld a, (hl)
    call Display.putC
    pop bc
    pop hl
    inc hl
    dec b
    jr putStrLimited

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
    gotoXY 0, 3
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

; Connection success screen
showConnectedSuccessScreen:
    jp exitProgram

; ============================================
; renderList - Draw full list with help text
; ============================================
renderList:
    call topClean

    ; Show help on line 3 (depends on connection state)
    gotoXY 0, 3
    ld a, (Wifi.is_connected)
    and a
    jr z, .showHelpDisconn
    ld hl, msg_help_conn       ; Connected: includes X:Disconnect
    jr .printHelp
.showHelpDisconn
    ld hl, msg_help            ; Not connected
.printHelp
    call Display.putStr

    ; Show manual SSID option on line 4
    gotoXY 0, 4
    ld hl, msg_help2
    call Display.putStr

    ; Separator line below menu
    ld a, 5 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline

    ; Show scroll indicators
    call showScrollIndicators

    call showPageInfo

    ; Use common routine to draw networks
    call renderNetworksCommon
    ld a, (Wifi.networks_count)
    and a
    ret z                       ; No networks: don't draw cursor
    jp showCursor

no_net_msg db "No networks found. Press 'R' to rescan.", 0
msg_help   db "Q/A:Nav O/P:Page R:Refresh D:Diag", 0
msg_help_conn db "Q/A:Nav R:Refresh X:Disconn D:Diag", 0
msg_help2  db "H:Hidden W:WPS L:Log I:About", 0

; ============================================
; Show scroll arrows on line 16
; DOWN at Col 0 (left), UP at Col 41 (right)
; ============================================
showScrollIndicators:
    ; 1. Clear arrow areas (left and right)
    gotoXY 0, 16
    ld a, ' ' : call Display.putC
    gotoXY 41, 16
    ld a, ' ' : call Display.putC

    ; 2. Check DOWN arrow (Offset + PER_PAGE < Count) - LEFT
    ld a, (offset)
    add a, PER_PAGE
    ld b, a
    ld a, (Wifi.networks_count)
    cp b
    jr c, .chkUp            ; No more below
    jr z, .chkUp            ; Equal

    gotoXY 0, 16
    ld a, 25                ; Down arrow char
    call Display.putC

.chkUp
    ; 3. Check UP arrow (Offset > 0) - RIGHT
    ld a, (offset)
    and a
    ret z                   ; No more above

    gotoXY 41, 16
    ld a, 24                ; Up arrow char
    call Display.putC
    ret

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

rssi_value db 0

current_line db 0
current_screen_idx db 0
conn_row_found db 0             ; Flag: 1 if connected network already found

; ============================================
; showConnectedDialog
; ============================================
showConnectedDialog:
    call topClean
    gotoXY 0, 3 : ld hl, .msg_network : call Display.putStr
    ; SSID in green double-height (rows 4-5)
    gotoXY 0, 4
    ld hl, Wifi.connected_ssid
    call Display.putStrBig
    setLineColor 4, Display.ATTR_SSID_INPUT
    setLineColor 5, Display.ATTR_SSID_INPUT
    ; Questions
    gotoXY 0, 7 : ld hl, .msg_question : call Display.putStr
    gotoXY 0, 9 : ld hl, .msg_options : call Display.putStr

    ; Debounce: drain stale keys for 15 frames (~300ms)
    ; Needed because ROM key repeat can leave residual values in BASIC_KEY
    ld b, 15
.drainKeys
    halt
    call Keyboard.inKeyNoWait
    djnz .drainKeys

.waitKey
    halt
    call Keyboard.inKey
    and a : jr z, .waitKey
    cp 'y' : jr z, .reconfigure
    cp 'Y' : jr z, .reconfigure
    cp 'n' : jr z, .keepConfig
    cp 'N' : jr z, .keepConfig
    cp 15  : jr z, .keepConfig
    jr .waitKey

.reconfigure
    or a : ret
.keepConfig
    scf : ret

.msg_network   db "Connected to network:", 0
.msg_question  db "Do you want to reconfigure?", 0
.msg_options   db "(Y)es reconfigure / (N)o exit", 0

; ============================================
; Cursor and navigation
; ============================================
hideCursor:
    call cursorIsConnectedRow
    ld c, Display.ATTR_NORMAL
    jr nc, cursor
    ld c, Display.ATTR_CONNECTED  ; Connected row: yellow on black
    jr cursor
showCursor:
    call cursorIsConnectedRow
    ld c, Display.ATTR_HIGHLIGHT
    jr nc, cursor
    ld c, Display.ATTR_CONN_CURSOR  ; Cursor on connected row: blue on yellow
cursor:
    ld a,(cursor_position) : add a, 6 : call Display.setAttrPartial
    ret

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

    ; HL = SSID pointer for (offset + cursor_position), respecting display_indices
    ld a, (cursor_position)
    ld hl, offset
    add a, (hl)
    ld d, a
    call findRow

    ; Hidden/empty SSID can't be the connected one
    ld a, (hl)
    and a
    ret z

    ; Compare selected SSID with connected_ssid
    ld de, Wifi.connected_ssid
    call Display.compareStringZ
    ret nz              ; No match -> CF=0
    scf                 ; Match -> CF=1
    ret

; ============================================
; invalidateConnectedIfMissing
; If we are marked as connected but the connected SSID is not in the last scan,
; invalidate state and update UI (only invalidate, don't rebuild)
; ============================================
invalidateConnectedIfMissing:
    ; Only if is_connected=1 and connected_ssid not empty
    ld a, (Wifi.is_connected)
    and a
    ret z
    ld a, (Wifi.connected_ssid)
    and a
    ret z

    call connectedSSIDPresentInList
    ret c                       ; present -> keep
    ; Not in list -> invalidate
    call doMarkDisconnected
    ret

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
    jr z, .notFound

    push hl
    push bc
    ld de, Wifi.connected_ssid
    call Display.compareStringZ
    pop bc
    pop hl
    jr z, .found        ; Z=1 means equal

    ; Advance to next SSID (find null terminator)
    inc c               ; Next index
    push bc             ; Preserve B and C
    xor a
    ld bc, #ffff
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
    ; Clear keyboard buffer at start (prevents auto-selection from garbage)
    xor a
    ld (Keyboard.BASIC_KEY), a
    
uiLoopMain:
    halt
    
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

    ; Mute UART log during health-check (avoids CWJAP? spam)
    call Uart.logReset
    ld a, (Uart.log_enabled)
    push af
    xor a
    ld (Uart.log_enabled), a
    call Wifi.checkConnection
    pop af
    ld (Uart.log_enabled), a
    call Uart.logReset
    ld a, (Wifi.is_connected)
    and a
    jr nz, .noHealthCheck
    jp handleDisconnect

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
    call clampOffsetToCount

    ; Adjust cursor_position to current page (offset) and actual size
    ld a, (Wifi.networks_count)
    and a
    jr z, .forceCursorZero

    ; remaining = count - offset
    ld a, (Wifi.networks_count)
    ld b, a
    ld a, (offset)
    ld c, a
    ld a, b
    sub c
    ; limit remaining to PER_PAGE
    cp PER_PAGE
    jr c, .forceRemOk
    ld a, PER_PAGE
.forceRemOk
    ld b, a                  ; B = visible items on page (1..PER_PAGE)

    ld a, (cursor_position)
    cp b
    jr c, .forceCursorOk
    ld a, b
    dec a
    ld (cursor_position), a
    jr .forceCursorOk
.forceCursorZero
    xor a
    ld (cursor_position), a
.forceCursorOk

    call showScrollIndicators
    call showPageInfo
    call renderNetworksOnly
    call showCursor
.noForceRescan

    call Keyboard.inKeyNoWait
    and a
    jp z, .noKey
    
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

    cp 15  : jp z, exitProgram     ; ESC
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
    ld hl, Wifi.connected_ssid
    ld (hl), a
    ld a, 1
    ld (force_rescan), a
    call updateWifiStatus_q
    call ipShowNotConnected
    ld hl, msg_conn_lost
    call Display.putStrLog
    ret

handleDisconnect
    call doMarkDisconnected
    jp uiLoopMain

handleGotIP
    ld a, 1
    ld (Wifi.is_connected), a
    ; Get the SSID of current connection
    call Wifi.checkConnection
    call updateWifiStatus_q
    call ipShowConnected         ; Update IP in status bar
    ; Redraw list to apply connected network attribute
    call renderNetworksOnly
    call showCursor
    jp uiLoopMain

rescan:
    call hideCursor
    xor a : ld (cursor_position), a : ld (offset), a
    
    ; Show "Scanning..." on line 17, col 0
    gotoXY 0, 17
    ld hl, .scanning_msg
    call Display.putStr
    
    ; Clear networks area while scanning
    call clearNetworksArea
    
    call Wifi.getList
    call invalidateConnectedIfMissing
    call renderListOnly         ; Only redraws the list, not the help
    jp uiLoop
.scanning_msg db "Scanning...", 0

; ============================================
; doAutoRescan - Silent automatic rescan
; Does not move cursor or show messages
; ============================================
doAutoRescan:
    push bc
    push de
    push hl

    ; Show hourglass on row 17, col 0
    gotoXY 0, 17
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
    
    ; Restore position (adjusting if needed)
    pop bc
    ld a, (Wifi.networks_count)
    and a
    jr z, .autoResetPos         ; No networks, reset
    
    ; Check offset is still valid (offset must be < count)
    ld a, c                     ; saved offset
    ld d, a
    ld a, (Wifi.networks_count)
    cp d
    jr z, .autoResetPos         ; offset == count -> invalid
    jr nc, .autoOffsetOK        ; offset < count -> OK
    jr .autoResetPos            ; offset > count -> reset
    
.autoOffsetOK
    ld a, c
    ld (offset), a
    
    ; Check cursor is still valid
    ld a, (Wifi.networks_count)
    ld e, a
    ld a, c                     ; offset
    ld d, a
    ld a, e
    sub d                       ; count - offset = available
    cp PER_PAGE
    jr c, .autoLimitCursor
    ld a, PER_PAGE
.autoLimitCursor
    ; A = max allowed cursor
    dec a                       ; 0-indexed
    cp b                        ; compare with saved cursor
    jr nc, .autoCursorOK
    ; cursor > max, adjust
    ld b, a
.autoCursorOK
    ld a, b
    ld (cursor_position), a
    jr .autoRender
    
.autoResetPos
    xor a
    ld (cursor_position), a
    ld (offset), a
    
.autoRender
    call invalidateConnectedIfMissing
    call renderListOnly
    
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
    call hideCursor : call topClean
    gotoXY 1, 3
    ld hl, .msg_disc_confirm
    call Display.putStr
    gotoXY 1, 5
    ld hl, .msg_disc_yn
    call Display.putStr
.waitDiscConfirm
    halt
    call Keyboard.inKey
    and a : jr z, .waitDiscConfirm
    cp 'y' : jr z, .doDiscNow
    cp 'Y' : jr z, .doDiscNow
    ; Any other key cancels
    call renderList : jp uiLoop

.doDiscNow
    ; Send disconnect command
    ld hl, cmd_disconnect
    call Wifi.espSendZ

    ; Wait for response
    ld b, 100
.waitDisconnect
    halt
    djnz .waitDisconnect
    call Wifi.flushInput

    ; Update state
    xor a
    ld (Wifi.is_connected), a
    call updateWifiStatus_q
    call ipShowNotConnected

    ; Show confirmation in double-height
    call topClean
    ld hl, .msg_disconnected : ld c, 102o : call showBigMessage
    call showPressKey

.waitDiscKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitDiscKey
    
    call renderList
    jp uiLoop

.msg_disc_confirm  db "Disconnect from WiFi?", 0
.msg_disc_yn       db "(Y)es / any key = cancel", 0
.msg_disconnected  db "Disconnected.", 0

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
    
    ; Show title
    gotoXY 0, 4
    ld hl, .msg_manual_title
    call Display.putStr

    gotoXY 0, 6
    ld hl, .msg_enter_ssid
    call Display.putStr

    ; Show cancel message
    gotoXY 0, 11
    ld hl, .msg_ssid_help
    call Display.putStr

    setLineColor 8, Display.ATTR_PASS_INPUT
    setLineColor 9, Display.ATTR_PASS_INPUT

; Full SSID redraw (for cursor left)
.drawSSIDFull
    halt
    gotoXY 0, 8
    ; Clear full line (double-height)
    ld b, 34
.clearSSIDFull
    ld a, ' '
    push bc
    call Display.putCBig
    pop bc
    djnz .clearSSIDFull

    gotoXY 0, 8

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

    ld a, (manual_ssid_cursor)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de

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
    gotoXY 0, 8

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
    
    ; HL = &buffer[cursor]
    ld a, (manual_ssid_cursor)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    
.ssidDrawAfter
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidDrawAfter

.ssidClearRest
    ld a, ' ' : call Display.putCBig
    ld a, ' ' : call Display.putCBig

.ssidFinishDraw
.waitSSIDKey
    ld b, 4
.waitSSIDLoop
    halt
    djnz .waitSSIDLoop

    call Keyboard.checkBreak : jp z, .cancelManual
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitSSIDKey
    
    ; Cursor left
    cp 8 : jp z, .ssidCursorLeft

    ; Cursor right
    cp 9 : jp z, .ssidCursorRight

    ; Delete
    cp Keyboard.KEY_BS : jp z, .removeSSIDChar

    ; Enter = proceed to password
    cp 13 : jp z, .ssidEntered
    
    ; Filter valid characters (32-126)
    cp 32 : jp c, .waitSSIDKey
    cp 127 : jp nc, .waitSSIDKey
    
    ; === Insert character ===
    ld c, a                         ; Save char
    ld a, (manual_ssid_len)
    cp 32                           ; Max 32 chars
    jp nc, .waitSSIDKey
    
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
.ssidShiftRight
    ld a, b
    cp e
    jr z, .ssidDoInsert
    dec b
    ld hl, manual_ssid_buffer
    ld d, 0
    push de
    ld e, b
    add hl, de
    ld a, (hl)
    inc hl
    ld (hl), a
    pop de
    jr .ssidShiftRight

.ssidInsertAtEnd
.ssidDoInsert
    ; Insert character
    ld a, (manual_ssid_cursor)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
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
.ssidShiftLeft
    ld a, b
    cp c
    jr z, .ssidFinishDelete
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, b
    add hl, de
    ld a, (hl)
    dec hl
    ld (hl), a
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
    setLineColor 8, 107o
    call renderList
    jp uiLoop

.msg_ssid_help db "BREAK=cancel, L/R=move cursor", 0

.ssidEntered
    ; Check there is an SSID
    ld a, (manual_ssid_len)
    and a
    jp z, .waitSSIDKey              ; Empty SSID, keep waiting
    
    ; Now request password
    setLineColor 6, 107o
    call topClean
    
    ; Show selected SSID
    gotoXY 0, 3
    ld hl, msg_ssid
    call Display.putStr
    gotoXY 1, 4
    ld hl, manual_ssid_buffer
    call Display.putStr

    ; Prepare password input
    xor a
    ld (is_open_network), a         ; Assume closed network
    call clearPassBuffer

    gotoXY 0, 6
    ld hl, msg_pass
    call Display.putStr

    setLineColor 4, 071o
    setLineColor 7, Display.ATTR_PASS_INPUT
    setLineColor 8, Display.ATTR_PASS_INPUT
    xor a
    ld (show_password), a
    ld (pass_cursor), a

    ; Password input using shared routine (pass_line=7 = default)
    call passwordInput
    jp c, .cancelManual

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
    
    ; Initialize retries
    ld a, 3
    ld (conn_retries), a
; Check previous state
    ld a, (Wifi.is_connected)
    and a
    jr z, .skipUiUpdate

    ; Update UI only if was connected
    xor a
    ld (Wifi.is_connected), a
    call updateWifiStatus_q
    call ipShowNotConnected

.skipUiUpdate

    call Wifi.flushInput
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    call Wifi.checkOkErr
    call Wifi.flushInput

.connectRetryManual
    ld a, 10
    call clearRowPixels
    gotoXY 0, 10
    ld a, (conn_retries)
    ld b, a
    ld a, 4
    sub b
    add a, '0'
    ld (msg_conn_attempt + 12), a
    ld hl, msg_conn_attempt
    call Display.putStr
    
    gotoXY 1, 12
    ld hl, msg_break_cancel
    call Display.putStr
    
    ; AT+CWJAP is sent in multiple parts. To avoid mixing log and hide password,
    ; the log is muted during the entire send.
    ld hl, selectItem.log_cwjap_masked
    call Display.putStrLog
    call Uart.logReset
    xor a : ld (Uart.log_enabled), a

    ; Send connect command with manual SSID
    ld a, (Wifi.old_fw) : ld hl, at_start : or a : jr z, .sendCmdManual : ld hl, at_start_old
.sendCmdManual
    call Wifi.espSendZ
    ld hl, manual_ssid_buffer       ; Use manual SSID
    call Wifi.espSendZ
    ld hl, at_middle
    call Wifi.espSendZ

    ld hl, pass_buffer : call Wifi.espSendZ
    ld a, '"' : call Uart.write
    ld a, 13  : call Uart.write
    ld a, 10  : call Uart.write
    
    call Wifi.checkOkErrLong
    
    push af
    ld a, 1 : ld (Uart.log_enabled), a
    ; Add newline to log to separate from previous command
    ld hl, selectItem.log_newline
    call Display.putStrLog
    pop af
    
    jr nc, .connSuccessManual
    
    ; Fail - show "Retry" next to current message
    gotoXY 20, 10
    ld hl, msg_retry_suffix
    call Display.putStr
    
    ; Check if retries remain
    ld a, (conn_retries)
    dec a
    ld (conn_retries), a
    jp z, .connFailedManual
    
    ld b, 100
.retryWaitManual
    halt
    push bc
    call Keyboard.checkBreak
    pop bc
    jr z, .breakPressedManual
    djnz .retryWaitManual
    
    jp .connectRetryManual

.breakPressedManual
    call Wifi.flushInput
    call renderList
    jp uiLoop

.connSuccessManual
    ld a, 1 : ld (Wifi.is_connected), a

    ; Copy manual SSID to connected_ssid
    ld hl, manual_ssid_buffer
    ld de, Wifi.connected_ssid
    ld bc, 33                       ; MAX_SSID_LEN + 1 (includes null terminator)
    ldir
    
    call updateWifiStatus_q
    call topClean
    ld b, 50
.ipDelayManual
    halt
    djnz .ipDelayManual
    call ipShowConnected
    ld hl, msg_connected_title : ld c, 104o : call showBigMessage
    gotoXY 0, 6 : ld hl, msg_done_body : call Display.putStr
    gotoXY 0, 8 : ld hl, msg_press_key : call Display.putStr
.waitSuccessManual
    halt : call Keyboard.inKey : and a : jr z, .waitSuccessManual
    cp 15 : jp z, exitProgram
    call renderList : jp uiLoop

.connFailedManual
    call tryRecoverESP
    xor a : ld (Wifi.is_connected), a
    call updateWifiStatus_q
    call ipShowNotConnected
    call topClean
    setLineColor 4, 107o : setLineColor 7, 107o
    gotoXY 0, 3
    ld a, (Wifi.last_error)
    cp 1 : jr z, .errTimeoutManual
    cp 2 : jr z, .errPasswordManual
    cp 3 : jr z, .errNotFoundManual
    cp 4 : jr z, .errConnFailManual
    ld hl, msg_fail_generic
    jr .showFailMsgManual
.errTimeoutManual
    ld hl, msg_fail_timeout
    jr .showFailMsgManual
.errPasswordManual
    ld hl, msg_fail_password
    jr .showFailMsgManual
.errNotFoundManual
    ld hl, msg_fail_notfound
    jr .showFailMsgManual
.errConnFailManual
    ld hl, msg_fail_connfail
.showFailMsgManual
    call Display.putStr
    gotoXY 0, 7 : ld hl, msg_press_key : call Display.putStr
.waitFailManual
    halt : call Keyboard.inKey : and a : jr z, .waitFailManual
    call renderList : jp uiLoop

.msg_manual_title db "Hidden Network (Manual SSID)", 0
.msg_enter_ssid   db "Enter network SSID:", 0

    RTVAR manual_ssid_buffer, 33
manual_ssid_len    db 0
manual_ssid_cursor db 0

exitProgram:
    call Display.clrscr
    ld sp, (saved_sp)
    ei
    ret

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
    jr z, .wps_start

    call hideCursor : call topClean
    gotoXY 0, 3
    ld hl, .msg_wps_warn
    call Display.putStr
    gotoXY 0, 5
    ld hl, .msg_wps_yn
    call Display.putStr
.wps_confirm
    halt
    call Keyboard.inKey
    and a : jr z, .wps_confirm
    cp 'y' : jr z, .wps_do_disc
    cp 'Y' : jr z, .wps_do_disc
    ; Cancel
    call renderList : jp uiLoop

.wps_do_disc
    ; Disconnect first
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    call Wifi.checkOkErr
    xor a : ld (Wifi.is_connected), a
    call updateWifiStatus
    ld b, 75
.wps_disc_wait
    halt
    djnz .wps_disc_wait
    call flushUartBuffer

.wps_start
    call topClean
    gotoXY 1, 4
    ld hl, .msg_wps_prompt
    call Display.putStr
    gotoXY 1, 6
    ld hl, .msg_wps_wait
    call Display.putStr

.wps_send
    ; Send AT+WPS=1
    call flushUartBuffer
    ld hl, .cmd_wps
    call Wifi.espSendZ
    ; Wait for long response (WPS can take ~120s)
    call Wifi.checkOkErrLong
    jr c, .wps_fail
    ; Flush post-WPS (residual async messages)
    call flushUartBuffer
    ; Check connection
    call Wifi.checkConnection
    jr c, .wps_fail
    ; Success
    call updateWifiStatus_q
    call ipShowConnected
    gotoXY 1, 8
    ld hl, .msg_wps_ok
    call Display.putStr
    jr .wps_exit
.wps_fail
    ; WPS failure leaves the ESP in bad state: reset to recover
    call flushUartBuffer
    call Wifi.reset
    ; Wait for ESP to stabilize after reset
    ld b, 125
.wps_reset_wait
    halt
    djnz .wps_reset_wait
    call flushUartBuffer
    gotoXY 1, 8
    ld hl, .msg_wps_fail
    call Display.putStr
.wps_exit
    call showPressKey
.wps_waitkey
    halt
    call Keyboard.inKeyNoWait
    and a
    jr z, .wps_waitkey
    cp 'l' : jr z, .wpsLog : cp 'L' : jr z, .wpsLog
    jr .wps_keyOk
.wpsLog
    call toggleLogQuiet : jr .wps_waitkey
.wps_keyOk
    ; Wait before scanning (ESP may need time after WPS)
    ld b, 100
.wps_scanwait
    halt
    djnz .wps_scanwait
    call flushUartBuffer
    ; Rescan to recover network list
    call Wifi.getList
    call renderList
    jp uiLoop
.msg_wps_warn   db "WPS requires disconnecting first.", 0
.msg_wps_yn     db "(Y)es / any key = cancel", 0
.msg_wps_prompt db "Press WPS button on router", 0
.msg_wps_wait   db "Waiting for WPS...", 0
.msg_wps_ok     db "WPS connected!", 0
.msg_wps_fail   db "WPS failed", 0
.cmd_wps        db "AT+WPS=1", 13, 10, 0

cursorDown:
    call hideCursor
    ; Check if there are more networks below
    ld a, (cursor_position)
    ld hl, offset
    add a, (hl)
    inc a                       ; Next absolute position
    ld hl, Wifi.networks_count
    cp (hl)                     ; More networks?
    jp nc, .atEnd               ; No more, don't move
    
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
    
    ld (offset), a
    xor a : ld (cursor_position), a
    call renderList
    jp uiLoop
    
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
    call renderList
    jr .back

; Page Down - jump one full page
pageDown:
    call hideCursor
    ld a, (offset)
    add a, PER_PAGE
    ld hl, Wifi.networks_count
    cp (hl)
    jr nc, .lastPage            ; No full page, go to last
    ld (offset), a
    xor a : ld (cursor_position), a
    call renderList
    jp uiLoop
.lastPage
    ; Go to last network.
    ; If already visible on current page, just move cursor (no repaint).
    ld a, (Wifi.networks_count)
    and a
    jp z, uiLoop                ; No networks
    dec a                       ; Last network (index)
    ld b, a                     ; B = last_index

    ld a, (offset)
    ld c, a                     ; C = current offset
    ld a, b
    sub c                       ; A = last_index - offset
    jr c, .needRepaint          ; (safety) last_index < offset
    cp PER_PAGE
    jr nc, .needRepaint         ; last_index outside current page -> repaint

    ld (cursor_position), a     ; cursor_position = last_index - offset
    call showCursor
    jp uiLoop

.needRepaint
    ; Calculate offset so last network is visible
    ld a, b
    sub PER_PAGE - 1
    jr nc, .setOffset
    xor a                       ; If fewer than PER_PAGE networks, offset=0
.setOffset
    ld (offset), a
    ; cursor_position = index - offset
    ld a, b
    ld hl, offset
    sub (hl)
    ld (cursor_position), a
    call renderList
    jp uiLoop

; Page Up - jump one full page
pageUp:
    call hideCursor
    ld a, (offset)
    and a
    jp z, .firstItem            ; Already on first page
    sub PER_PAGE
    jr nc, .setOffset
    xor a                       ; Clamp to 0
.setOffset
    ld (offset), a
    xor a : ld (cursor_position), a
    call renderList
    jp uiLoop
.firstItem
    xor a : ld (cursor_position), a
    call showCursor
    jp uiLoop

findRow:
    ; d = screen position
    ; First get real index from display_indices
    ld hl, Wifi.display_indices
    ld e, d
    ld d, 0
    add hl, de
    ld a, (hl)
    ld d, a                     ; D = real network index
    
    ; Now find SSID[d] in the buffer
    ld hl, buffer : ld a, d : and a : ret z
    xor a
.loop    
    ld bc, #ffff : cpir : dec d : jr nz, .loop
    ret

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
    jp drawRssiBars

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
    ld a, b : and a : jr nz, .cmax
    inc a
.cmax
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
    gotoXY 0, 4
    ld hl, msg_ssid
    call Display.putStr
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
    ; Row 5: same colors without BRIGHT
    ld hl, #58A0
    ld a, 007o
    ld b, 12
.nd_attr_w5
    ld (hl), a : inc hl : djnz .nd_attr_w5
    ld a, 004o
    ld b, 20
.nd_attr_g5
    ld (hl), a : inc hl : djnz .nd_attr_g5

    ; Line 7: Security
    gotoXY 0, 7
    ld hl, .nd_sec
    call Display.putStr
    ld a, (selected_real_idx)
    ld hl, Wifi.ecn_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl)
    ; ECN: 0=OPEN, 1=WEP, 2=WPA-PSK, 3=WPA2-PSK, 4=WPA/WPA2, 5=Enterprise
    cp 6 : jr c, .nd_ecn_ok
    xor a                   ; Unknown value -> treat as Open
.nd_ecn_ok
    ld hl, .ecn_table
    add a, a               ; x2 (each pointer = 2 bytes)
    ld e, a : ld d, 0 : add hl, de
    ld a, (hl) : inc hl : ld h, (hl) : ld l, a
    call Display.putStr

    ; Line 8: Channel
    gotoXY 0, 8
    ld hl, .nd_chan
    call Display.putStr
    ld a, (selected_real_idx)
    ld hl, Wifi.channel_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl)
    and a
    jr z, .nd_chan_unk
    call printNumber
    jr .nd_signal
.nd_chan_unk
    ld a, '-' : call Display.putC

    ; Line 9: Signal - label in white, bars in yellow
.nd_signal
    ld a, 9
    jp drawSignalLine              ; Tail call (draws "Signal: ||||..." on line A)

.nd_sec         db "Security: ", 0
.nd_chan        db "Channel:  ", 0
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

; ============================================
; selectItem and connection
; ============================================
selectItem:
    ld a, (Wifi.networks_count) : and a : jp z, uiLoop
    
    ; Get screen position
    ld a, (cursor_position) : ld hl, offset : add a, (hl)
    ; Convert to real index using display_indices
    call Wifi.getDisplayIndex   ; A = real network index
    ld (selected_real_idx), a
    ld hl, Wifi.rssi_buffer : ld d, 0 : ld e, a : add hl, de
    ld a, (hl) : and #80 : ld (is_open_network), a
    
    ; Get pointer to selected SSID (findRow already uses display_indices)
    ld a, (cursor_position) : ld hl, offset : add (hl) : ld d, a : call findRow
    ld (selected_ssid_ptr), hl
    
    ; Check if already connected to this network
    ld a, (Wifi.is_connected)
    and a
    jr z, .notConnectedYet
    
    ; Compare selected SSID with connected_ssid
    ld hl, (selected_ssid_ptr)
    ld de, Wifi.connected_ssid
.compareLoop
    ld a, (de)
    ld b, a
    ld a, (hl)
    cp b
    jr nz, .notConnectedYet      ; Different, continue
    and a
    jr z, .alreadyConnected      ; Both ended at 0, they are equal
    inc hl
    inc de
    jr .compareLoop

.alreadyConnected
    call hideCursor : call topClean
    call showNetDetail
    gotoXY 0, 11
    ld hl, .msg_already_conn
    call Display.putStr
    call showPressKey
.waitAlready
    halt
    call Keyboard.inKey
    and a
    jr z, .waitAlready
    call renderList
    jp uiLoop

.msg_already_conn db "Already connected to this network", 0
.msg_connect_yn   db "(Y)es connect / (N)o cancel", 0

.notConnectedYet
    call hideCursor : call topClean
    call showNetDetail

    ld a, (is_open_network) : and a : jp nz, .openConfirm
    call clearPassBuffer
    gotoXY 0, 11 : ld hl, msg_pass : call Display.putStr
    setLineColor 12, Display.ATTR_PASS_INPUT
    setLineColor 13, Display.ATTR_PASS_INPUT
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
    setLineColor 12, Display.ATTR_NORMAL
    setLineColor 13, Display.ATTR_NORMAL
    call renderList : jp uiLoop

.openConfirm
    ; Open network: show confirmation before connecting
    gotoXY 0, 11 : ld hl, msg_open_net : call Display.putStr
    gotoXY 0, 13 : ld hl, .msg_connect_yn : call Display.putStr
.openWait
    halt
    call Keyboard.inKey
    and a : jr z, .openWait
    cp 'y' : jr z, .connectDirect
    cp 'Y' : jr z, .connectDirect
    cp 'n' : jp z, .cancel
    cp 'N' : jp z, .cancel
    cp 15  : jp z, .cancel             ; ESC
    jr .openWait

.connectDirect
    call clearPassBuffer

.connect
    ; Clear password area (rows 10-13) -- fast via LDIR
    setLineColor 10, Display.ATTR_NORMAL
    setLineColor 11, Display.ATTR_NORMAL
    setLineColor 12, Display.ATTR_NORMAL
    setLineColor 13, Display.ATTR_NORMAL
    ld d, 10 : ld e, 0 : call Display.findAddr  ; DE = row 10 sl0
    ld b, 8
.clrPwSl
    push bc : push de
    ld h, d : ld l, e
    ld (hl), 0
    ld d, h : ld e, l : inc de
    ld bc, 127          ; 4 rows × 32 bytes - 1
    ldir
    pop de : pop bc
    inc d
    djnz .clrPwSl

    ; Initialize retry counter
    ld a, 3
    ld (conn_retries), a

;    Check previous state
    ld a, (Wifi.is_connected)
    and a
    jr z, .skipUiUpdate

    ; Update UI only if was connected
    xor a
    ld (Wifi.is_connected), a
    call updateWifiStatus_q
    call ipShowNotConnected

.skipUiUpdate:

    call Wifi.flushInput
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    call Wifi.checkOkErr
    call Wifi.flushInput

.connectRetry
    ; Clear password/input area (rows 11-13) -- fast via LDIR
    setLineColor 11, Display.ATTR_NORMAL
    setLineColor 12, Display.ATTR_NORMAL
    setLineColor 13, Display.ATTR_NORMAL
    ; Clear pixels of rows 11-13 (third 1: rows 8-15)
    ld d, 11 : ld e, 0 : call Display.findAddr  ; DE = row 11 sl0
    ld b, 8             ; 8 scanlines
.clrRows
    push bc : push de
    ld h, d : ld l, e
    ld (hl), 0
    ld d, h : ld e, l : inc de
    ld bc, 95           ; 3 rows × 32 bytes - 1
    ldir
    pop de : pop bc
    inc d               ; next scanline
    djnz .clrRows

    gotoXY 0, 11
    ; Show current attempt
    ld a, (conn_retries)
    ld b, a
    ld a, 4
    sub b                       ; 4 - retries = attempt (1, 2, 3)
    add a, '0'
    ld (msg_conn_attempt + 12), a
    ld hl, msg_conn_attempt
    call Display.putStr

    ; Show cancel option
    gotoXY 0, 13
    ld hl, msg_break_cancel
    call Display.putStr

    ; AT+CWJAP is sent in multiple parts. To avoid mixing log and hide password,
    ; the log is muted during the entire send.
    ld hl, .log_cwjap_masked
    call Display.putStrLog
    call Uart.logReset
    xor a : ld (Uart.log_enabled), a

    ld a, (Wifi.old_fw) : ld hl, at_start : or a : jr z, .send_cmd : ld hl, at_start_old
.send_cmd
    call Wifi.espSendZ
    ld hl, (selected_ssid_ptr)
    call Wifi.espSendZ
    ld hl, at_middle   : call Wifi.espSendZ
    
    ; Send password (muted)
    ld hl, pass_buffer : call Wifi.espSendZ
    
    ; Send closing quote + CR LF manually (muted)
    ; This prevents logging the password or echo prematurely
    ld a, '"' : call Uart.write
    ld a, 13  : call Uart.write
    ld a, 10  : call Uart.write
    
    ; Use long timeout for WiFi connection (can take 5-15 seconds)
    ; LOG STILL MUTED to avoid password echo
    call Wifi.checkOkErrLong
    
    ; --- UNMUTE UART LOG ---
    push af                     ; Preserve result
    ld a, 1 : ld (Uart.log_enabled), a
    ; Add newline to log to separate from previous command
    ld hl, .log_newline
    call Display.putStrLog
    pop af
    
    jr nc, .connSuccess         ; CF=0 -> OK

    ; Fail - show "Retry" next to "Connecting..."
    gotoXY 20, 11
    ld hl, msg_retry_suffix
    call Display.putStr
    
    ; Check if retries remain
    ld a, (conn_retries)
    dec a
    ld (conn_retries), a
    jp z, .connFailedFinal      ; No more retries
    
    ; Wait before retrying, checking BREAK
    ld b, 100
.retryWait
    halt
    push bc
    call Keyboard.checkBreak
    pop bc
    jr z, .breakPressed         ; Z=1 if BREAK pressed
    djnz .retryWait
    
    jp .connectRetry

.breakPressed
    ; User cancelled with BREAK
    call Wifi.flushInput
    call renderList
    jp uiLoop

.connSuccess
    ld a, 1 : ld (Wifi.is_connected), a
    
    ; Copy selected SSID to connected_ssid
    ld hl, (selected_ssid_ptr)
    ld de, Wifi.connected_ssid
    ld bc, MAX_SSID_LEN + 1
    ldir
    
    call updateWifiStatus_q

    call topClean
    ld hl, msg_connected_title : ld c, 104o : call showBigMessage
    gotoXY 0, 6 : ld hl, msg_done_body : call Display.putStr
    gotoXY 0, 8 : ld hl, msg_press_key : call Display.putStr

    ; Delay for ESP to have IP ready, retry if fails
    ld c, 3                 ; 3 attempts to get IP
.ipRetry
    ld b, 50                ; ~1s delay
.ipDelay
    halt
    djnz .ipDelay
    call Wifi.getIP
    jr nc, .ipGot           ; CF=0 → IP obtained
    dec c
    jr nz, .ipRetry         ; Retry
.ipGot
    call ipShowConnected
.waitSuccess
    halt : call Keyboard.inKey : and a : jr z, .waitSuccess
    cp 'l' : jr z, .wsLog : cp 'L' : jr z, .wsLog
    cp 15 : jp z, exitProgram
    jr .wsEnd
.wsLog
    call toggleLogQuiet : jr .waitSuccess
.wsEnd
    call renderList : jp uiLoop

.connFailedFinal
    ; Try to recover ESP if hung
    call tryRecoverESP
    
.connFailed
    xor a : ld (Wifi.is_connected), a
    call updateWifiStatus_q
    call ipShowNotConnected
    call topClean
    setLineColor 4, 107o : setLineColor 7, 107o
    
    ; Show message based on error code
    gotoXY 0, 3
    ld a, (Wifi.last_error)
    cp 1 : jr z, .errTimeout
    cp 2 : jr z, .errPassword
    cp 3 : jr z, .errNotFound
    cp 4 : jr z, .errConnFail
    ; Generic error (0 or unknown)
    ld hl, msg_fail_generic
    jr .showFailMsg
    
.errTimeout
    ld hl, msg_fail_timeout
    jr .showFailMsg
.errPassword
    ld hl, msg_fail_password
    jr .showFailMsg
.errNotFound
    ld hl, msg_fail_notfound
    jr .showFailMsg
.errConnFail
    ld hl, msg_fail_connfail
    
.showFailMsg
    call Display.putStr
    gotoXY 0, 7 : ld hl, msg_press_key : call Display.putStr
.waitFail
    halt : call Keyboard.inKey : and a : jr z, .waitFail
    cp 'l' : jr z, .wfLog : cp 'L' : jr z, .wfLog
    call renderList : jp uiLoop
.wfLog
    call toggleLogQuiet : jr .waitFail

.log_cwjap_masked db ">> AT+CWJAP (password hidden)", 13, 0

.log_newline db 13, 0

; Try to recover an unresponsive ESP
tryRecoverESP:
    jp Wifi.ensureCommandMode

; ============================================
; Diagnostics
; ============================================
DIAG_ITEMS = 7
DIAG_FIRST_LINE = 6
ATTR_DIAG_TITLE = 00000100b  ; Green on black (BRIGHT 0)

; "Press any key..." on line 17, col 0, yellow
ATTR_PRESS_KEY = 01000110b  ; Bright yellow on black
showPressKey:
    setLineColor 17, ATTR_PRESS_KEY
    gotoXY 0, 17
    ld hl, msg_press_key
    jp Display.putStr

; Standard header for diagnostic screens
; Input: HL = title pointer. Clears screen, green double-height title.
diagHeader:
    push hl
    call topClean
    pop hl
    ld c, 104o              ; Green BRIGHT on black
    jp showBigMessage

showDiagnostics:
    call topClean

    ; Check if connected
    ld a, (Wifi.is_connected)
    and a
    jr nz, .showMenu

    ; Not connected - show error
    gotoXY 0, 3
    ld hl, .msg_not_conn
    call Display.putStr
    call showPressKey
.waitNotConn
    halt
    call Keyboard.inKey
    and a
    jr z, .waitNotConn
    cp 'l' : jr z, .wncLog : cp 'L' : jr z, .wncLog
    call renderList
    jp uiLoop
.wncLog
    call toggleLogQuiet : jr .waitNotConn

.showMenu
    ld hl, .msg_diag_title
    call diagHeader
    ; Options (without numbers)
    gotoXY 0, 6
    ld hl, .msg_diag_opt1
    call Display.putStr
    gotoXY 0, 7
    ld hl, .msg_diag_opt2
    call Display.putStr
    gotoXY 0, 8
    ld hl, .msg_diag_opt3
    call Display.putStr
    gotoXY 0, 9
    ld hl, .msg_diag_opt4
    call Display.putStr
    gotoXY 0, 10
    ld hl, .msg_diag_opt5
    call Display.putStr
    gotoXY 0, 11
    ld hl, .msg_diag_opt6
    call Display.putStr
    gotoXY 0, 12
    ld hl, .msg_diag_opt7
    call Display.putStr
    ; Separator line below items
    ld a, 13 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline
    gotoXY 0, 14
    ld hl, .msg_diag_exit
    call Display.putStr
    ; Initial cursor
    xor a : ld (.diag_cursor), a
    call .showDiagCursor

.diagLoop
    ld b, 3
.diagWait
    halt : djnz .diagWait
    call Keyboard.checkBreak : jp z, .exitDiag
    call Keyboard.inKeyNoWait
    and a : jr z, .diagLoop
    cp Keyboard.KEY_UP : jr z, .diagUp
    cp 'q' : jr z, .diagUp
    cp 'Q' : jr z, .diagUp
    cp Keyboard.KEY_DN : jr z, .diagDown
    cp 'a' : jr z, .diagDown
    cp 'A' : jr z, .diagDown
    cp 'l' : jr z, .diagLog : cp 'L' : jr z, .diagLog
    cp 13 : jr z, .diagSelect
    jr .diagLoop
.diagLog
    call toggleLogQuiet : jr .diagLoop

.diagUp
    ld a, (.diag_cursor)
    and a : jr z, .diagLoop
    call .hideDiagCursor
    ld hl, .diag_cursor
    dec (hl)
    call .showDiagCursor
    jr .diagLoop

.diagDown
    ld a, (.diag_cursor)
    cp DIAG_ITEMS - 1 : jr z, .diagLoop
    call .hideDiagCursor
    ld hl, .diag_cursor
    inc (hl)
    call .showDiagCursor
    jr .diagLoop

.diagSelect
    ld a, (.diag_cursor)
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
    ld a, (.diag_cursor)
    add a, DIAG_FIRST_LINE
    jp Display.setAttrPartial

.exitDiag
    ; Reactivate UART log on exit
    ld a, 1
    ld (Uart.log_enabled), a
    call renderList
    jp uiLoop

.diag_cursor    db 0
.msg_not_conn   db "Connect to a network first!", 0
.msg_diag_title db "DIAGNOSTICS", 0
.msg_diag_opt1  db "Ping test", 0
.msg_diag_opt2  db "Module info (firmware)", 0
.msg_diag_opt3  db "Network info", 0
.msg_diag_opt4  db "UART baud rate", 0
.msg_diag_opt5  db "Static IP config", 0
.msg_diag_opt6  db "Set hostname", 0
.msg_diag_opt7  db "Config summary", 0
.msg_diag_exit  db "Q/A:Move ENTER:Select BREAK:Exit", 0

; Buffer for diagnostic responses
    RTVAR diag_buffer, 64
diag_line       db 0            ; Current line on screen

; Drain UART buffer (fast, no HALT: avoids losing bytes at 115200)
flushUartBuffer:
    ; Read until no traffic for a short period
    ld de, #4000                ; ~0.2-0.3 s of "silence" depending on CPU
.flushWait
    call UartImpl.uartRead      ; Read all available
    jr c, .gotByte
    dec de
    ld a, d
    or e
    jr nz, .flushWait
    ret
.gotByte
    ld de, #4000
    jr .flushWait

; Read a line from ESP until CR/LF or timeout (no HALT)
; Output: CF=1 if data, CF=0 if timeout with no data
readDiagLine:
    ld hl, diag_buffer
    ld c, 60                    ; Max 60 characters
    ld de, #FFFF                ; Initial timeout (~1 s approx)

.readLoop
    call UartImpl.uartRead
    jr c, .gotByte

    dec de
    ld a, d
    or e
    jr nz, .readLoop

    ; Timeout with no data
    xor a
    ld (hl), a
    ret                         ; CF=0

.gotByte
    ; On receiving data, reduce timeout to close line if missing terminator
    ld de, #2000

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

.endLine
    xor a
    ld (hl), a                  ; Terminate string
    scf                         ; CF=1, data available
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
    jr z, .endLine

    ; Read next byte with medium timeout (more time for Next)
    call Uart.readTimeoutMedium
    jr nc, .endLine
    jr .readLoop

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

; Show diag_buffer on current line and advance
showDiagLine:
    ld a, (diag_line)
    ld h, a
    ld l, 0
    ld (Display.coords), hl
    ld hl, diag_buffer
    call Display.putStr
    ld a, (diag_line)
    inc a
    ld (diag_line), a
    ret

; ------------------------------
; Ping test
; ------------------------------
MAX_IP_LEN = 15                 ; xxx.xxx.xxx.xxx

; IP buffer (persistent between calls)
    RTVAR ping_ip_buffer, MAX_IP_LEN + 1
ping_ip_len     db 0                ; Current length

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
    and a
    jr nz, .skipInit
    call initPingIP
.skipInit
    
    ; Disable UART log during diagnostics
    xor a
    ld (Uart.log_enabled), a
    
    ld hl, .msg_ping_title
    call diagHeader

    gotoXY 0, 6
    ld hl, .msg_ip_prompt
    call Display.putStr
    setLineColor 8, Display.ATTR_PASS_INPUT
    setLineColor 9, Display.ATTR_PASS_INPUT

    gotoXY 0, 11
    ld hl, .msg_ping_help
    call Display.putStr

.drawIP
    ; Draw current IP directly in double-height
    halt
    di
    gotoXY 0, 8
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
    djnz .waitIPLoop

    call Keyboard.checkBreak : jp z, .pingCancel
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitIPKey

    ; ENTER = execute ping
    cp 13 : jp z, .doPingNow
    
    ; Backspace = delete
    cp Keyboard.KEY_BS : jp z, .ipBackspace
    
    ; Manual dot
    cp '.'
    jp z, .ipTryAddDot
    
    ; Only allow digits (0-9)
    cp '0'
    jr c, .waitIPKey            ; < '0'
    cp '9' + 1
    jr nc, .waitIPKey           ; > '9'
    
    ; It's a digit - check if it fits
    ld b, a                     ; Save digit
    ld a, (ping_ip_len)
    cp MAX_IP_LEN
    jp nc, .waitIPKey           ; Buffer full
    
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
    jp nc, .waitIPKey           ; Already 3 dots, no more digits
    
    ; Check room for 2 characters (dot + digit)
    ld a, (ping_ip_len)
    cp MAX_IP_LEN - 1
    jp nc, .waitIPKey           ; No room for 2 chars
    
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
    jp z, .waitIPKey
    
    ; Don't allow consecutive dots
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    dec hl                      ; Last character
    ld a, (hl)
    cp '.'
    jp z, .waitIPKey            ; Last is dot, don't add another
    
    ; Check max 3 dots
    push bc
    call .countDots
    pop bc
    cp 3
    jp nc, .waitIPKey           ; Already 3 dots
    
    ; Check room
    ld a, (ping_ip_len)
    cp MAX_IP_LEN
    jp nc, .waitIPKey
    
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
    gotoXY 0, 4
    ld hl, .msg_pinging
    call Display.putStr
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
    ld a, 007o              ; White on black, no bright
    ld b, 6
.pa5w
    ld (hl), a : inc hl : djnz .pa5w
    ld a, 004o              ; Green on black, no bright
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
    ld hl, .cmd_ping_end
    call Wifi.espSendZ
    
    ; Read responses
    ld c, 20                    ; Max 20 timeouts
    ld b, 100                   ; Absolute limit: 100 lines
.pingLoop
    push bc
    call readDiagLine
    pop bc
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
    ld a, (diag_line) : ld h, a : ld l, 0 : ld (Display.coords), hl
    ld hl, .msg_time_lbl
    call Display.putStr
    ld hl, diag_buffer + 1      ; Skip the '+'
    call Display.putStr
    ld hl, .msg_time_ms
    call Display.putStr
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .pingLoop

.pingShowTimeout
    ; Show "Request timed out"
    ld a, (diag_line) : ld h, a : ld l, 0 : ld (Display.coords), hl
    ld hl, .msg_timeout
    call Display.putStr
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .pingLoop

.pingShow
    call showDiagLine
    jr .pingLoop
    
.pingTimeout
    dec c
    jp nz, .pingLoop

.pingDone
    call showPressKey
.waitPingKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitPingKey
    jp showDiagnostics

.msg_ping_title  db "PING TEST", 0
.msg_ip_prompt   db "Enter IP address:", 0
.msg_ping_help   db "ENTER=ping, BREAK=cancel", 0
.msg_pinging     db "Pinging ", 0
.msg_dots        db "...", 0
.cmd_ping_start  db "AT+PING=", '"', 0
.cmd_ping_end    db '"', 13, 10, 0
.msg_time_lbl    db "Response time: ", 0
.msg_time_ms     db " ms", 0
.msg_timeout     db "Request timed out", 0

; ------------------------------
; Module info (firmware version)
; ------------------------------
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
    call Wifi.espSendZ
    
    ; Read and show responses
    ld c, 20                    ; Max 20 timeouts
    ld b, 100                   ; Absolute limit: 100 lines
.gmrLoop
    push bc
    call readDiagLine
    pop bc
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
    cp 'S' : jr z, .gmrLoop     ; SEND OK

.showInfo
    ; Valid line - show
    call showDiagLine
    jr .gmrLoop                 ; Continue without decrementing
    
.gmrTimeout
    dec c
    jr nz, .gmrLoop

.gmrDone
    call showPressKey
.waitGmrKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitGmrKey
    jp showDiagnostics

.msg_module_title db "MODULE INFO", 0
.cmd_gmr          db "AT+GMR", 13, 10, 0

; ------------------------------
; Network info
; ------------------------------
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
    gotoXY 0, 4
    ld hl, .ni_ssid_lbl : call Display.putStr
    ld hl, Wifi.connected_ssid : call Display.putStr
.ni_detail_done
    ld a, 10 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline
    ld a, 11
    ld (diag_line), a

    call flushUartBuffer
    ld hl, .cmd_cifsr
    call Wifi.espSendZ
    ld c, 20
    ld b, 100
.cifsrLoop
    push bc
    call readDiagLine
    pop bc
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
    ld a, (diag_line) : ld d, a : ld e, 0
    ld (Display.coords), de
    call Display.putStr
    ld hl, diag_buffer
    call .findQuote
    call .printUntilQuote
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .cifsrLoop

.cifsrTimeout
    dec c
    jr nz, .cifsrLoop

.cifsrDone
    call showPressKey
.waitCifsrKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitCifsrKey
    jp showDiagnostics

.findQuote
    ld a, (hl)
    cp '"' : jr z, .foundQ
    inc hl
    and a : ret z
    jr .findQuote
.foundQ
    inc hl : ret

.printUntilQuote
    ld a, (hl)
    and a : ret z
    cp '"' : ret z
    push hl : call Display.putC : pop hl
    inc hl
    jr .printUntilQuote

.cmd_cifsr     db "AT+CIFSR", 13, 10, 0
.lbl_ip        db "IP:  ", 0
.lbl_mac       db "MAC: ", 0
.ni_ssid_lbl   db "Connected: ", 0

; ------------------------------
; UART Baud rate
; ------------------------------
doBaudRate:
    ld hl, msg_baud_title
    call diagHeader

    ; Initialize output line
    ld a, 6
    ld (diag_line), a
    xor a
    ld (baud_tried_def), a
    ld (baud_tried_plain), a
    ld (baud_have_value), a
    ld (baud_saw_error), a
    ld (baud_recover_tried), a

    
    ; Drain buffer before sending command
    call flushUartBuffer
	
	; Ensure the ESP is in AT command mode (not in pass-through/data mode)
	call Wifi.ensureCommandMode
	jp nc, doBaudRate_cmode_ok
	gotoXY 0, 6
	ld hl, msg_no_at
	call Display.putStr
	call waitAnyKey
	jp showDiagnostics

doBaudRate_cmode_ok:
    
    ; Send AT+UART_CUR?
    ld hl, cmd_uart_cur
    call Wifi.espSendZ
    
    ; Read responses
    ld c, 4                     ; Max 4 timeouts (each one is long)
    ld b, 100                   ; Absolute limit: 100 lines
.baudLoop
    push bc
    call readDiagLineLong
    pop bc
    jp nc, .baudTimeout         ; CF=0 = timeout real
    
    ; Decrement absolute limit
    dec b
    jp z, .baudDone             ; Limit reached
    
    ; CF=1 = got line
    ld a, (diag_buffer)
    and a
    jp z, .baudLoop             ; Empty line, doesn't count
    
    ; Check if it is "OK" -> end
    cp 'O'
    jp z, .baudDone
    cp 'E'                      ; ERROR -> try alternative commands
    jp nz, .noErrLine
    ; Record that we saw ERROR (if nothing obtained, we'll show it)
    ld a, 1
    ld (baud_saw_error), a

    ; First ERROR: try to recover by ensuring AT command mode, then retry CUR once
    ld a, (baud_recover_tried)
    and a
    jp nz, .skipRecover
    ld a, 1
    ld (baud_recover_tried), a
    call Wifi.ensureCommandMode
    call flushUartBuffer
    xor a
    ld (baud_tried_def), a
    ld (baud_tried_plain), a
    ld hl, cmd_uart_cur
    call Wifi.espSendZ
    ld c, 4
    ld b, 100
    jp .baudLoop
.skipRecover

    ; 1) Try AT+UART_DEF? (some firmwares don't support CUR)
    ld a, (baud_tried_def)
    and a
    jp nz, .tryPlain
    ld a, 1
    ld (baud_tried_def), a
    call flushUartBuffer
    ld hl, cmd_uart_def
    call Wifi.espSendZ
    ld c, 4
    ld b, 100
    jp .baudLoop

.tryPlain
    ; 2) Try AT+UART? (old firmwares)
    ld a, (baud_tried_plain)
    and a
    jp nz, .baudDone
    ld a, 1
    ld (baud_tried_plain), a
    call flushUartBuffer
    ld hl, cmd_uart_plain
    call Wifi.espSendZ
    ld c, 4
    ld b, 100
    jp .baudLoop
.noErrLine
    
    ; Filter noise and echo
    cp 'A' : jp z, .baudLoop    ; Ignore echo AT...
    cp '0' : jp z, .baudLoop
    cp 'C' : jp z, .baudLoop
    
    ; If starts with +, check it is not +IPD
    cp '+'
    jp nz, .baudLoop            ; Does not start with +, ignore
    ld a, (diag_buffer + 1)
    cp 'I'                      ; +IPD -> ignore
    jp z, .baudLoop
    cp 'U'                      ; Check +UART
    jp nz, .baudLoop

    ; --- BAUD RATE FORMATTING ---
    ; String: +UART_CUR:9600,8,1,0,0
    ; Header length (+UART_CUR:) is 10 chars, not 11
    
    ld a, (diag_line) : ld h, a : ld l, 0 : ld (Display.coords), hl
    
    ld hl, lbl_baud
    call Display.putStr
    
    ld hl, diag_buffer
    call .skipToColon           ; Skip to ':' (supports +UART and +UART_CUR)
    call .printUntilComma       ; Print only the number

    ld a, 1
    ld (baud_have_value), a

    ld a, (diag_line) : inc a : ld (diag_line), a
    jp .baudLoop                ; Continue without decrementing

.baudTimeout
    dec c
    jp nz, .baudLoop

.baudDone
    ; If no +UART line could be obtained, warn
    ld a, (baud_have_value)
    and a
    jp nz, .baudDoneHasValue
    gotoXY 0, 6
    ld a, (baud_saw_error)
    and a
    jp z, .noErrMsg
    ld hl, msg_uart_error
    call Display.putStr
    jp .afterErrMsg
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
    jp z, .waitBaudKey
    jp showDiagnostics

.skipToColon
    ld a, (hl)
    and a : ret z
    cp ':' : jr z, .gotColon
    inc hl
    jr .skipToColon
.gotColon
    inc hl
    ret


.printUntilComma
    ld a, (hl)
    and a : ret z
    cp ',' : ret z
    cp 13  : ret z
    push hl
    call Display.putC
    pop hl
    inc hl
    jr .printUntilComma

msg_baud_title db "UART BAUD RATE", 0
msg_no_at      db "No AT response (still in data mode?)", 0
cmd_uart_cur   db "AT+UART_CUR?", 13, 10, 0
cmd_uart_def   db "AT+UART_DEF?", 13, 10, 0
cmd_uart_plain db "AT+UART?", 13, 10, 0
lbl_baud       db "Baud Rate: ", 0
msg_uart_none db "No UART info (no response).", 0
msg_uart_error db "UART query returned ERROR.", 0

baud_tried_def  db 0
baud_tried_plain db 0
baud_have_value db 0
baud_saw_error  db 0
baud_recover_tried db 0

; ============================================
; doStaticIP - Static IP configuration (option 5)
; ============================================
doStaticIP:
    ld hl, .sip_title
    call diagHeader
    gotoXY 0, 6
    ld hl, .sip_prompt : call Display.putStr
    setLineColor 8, Display.ATTR_PASS_INPUT
    setLineColor 9, Display.ATTR_PASS_INPUT
    gotoXY 0, 11
    ld hl, .sip_help : call Display.putStr

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
    gotoXY 0, 9
    ld hl, .sip_badformat : call Display.putStr
    call waitAnyKey
    jp showDiagnostics

.sip_valid
    ; Send AT+CIPSTA_CUR="ip"
    call flushUartBuffer
    ld hl, .sip_cmd : call Wifi.espSendZ
    ld hl, sip_buf : call Wifi.espSendZ
    ld hl, .sip_end : call Wifi.espSendZ
    call Wifi.checkOkErr
    jr c, .sip_fail
    ; Update IP on screen
    call Wifi.getIP
    call ipShowConnected
    gotoXY 0, 9
    ld hl, .sip_ok : call Display.putStr
    jr .sip_wait
.sip_fail
    gotoXY 0, 9
    ld hl, .sip_err : call Display.putStr
.sip_wait
    call waitAnyKey
    jp showDiagnostics

.sip_title     db "STATIC IP CONFIG", 0
.sip_prompt    db "Enter IP (empty=cancel):", 0
.sip_help      db "ENTER=accept, BREAK=cancel", 0
.sip_ok        db "IP set OK!", 0
.sip_err       db "Failed to set IP", 0
.sip_badformat db "Invalid IP format!", 0
.sip_cmd       db "AT+CIPSTA_CUR=\"", 0
.sip_end       db "\"", 13, 10, 0
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
.itiWL  halt : djnz .itiWL
    call Keyboard.checkBreak : jr z, .itiCancel
    call Keyboard.inKeyNoWait : and a : jr z, .itiWait
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
    jp .itiRedraw
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
    call diagHeader
    gotoXY 0, 6
    ld hl, .hn_prompt : call Display.putStr
    setLineColor 8, Display.ATTR_PASS_INPUT
    setLineColor 9, Display.ATTR_PASS_INPUT
    gotoXY 0, 11
    ld hl, .hn_help : call Display.putStr

    call clearPassBuffer
    ld a, 1 : ld (show_password), a     ; Show text (not asterisks)
    ld a, 8 : ld (pass_line), a
    call passwordInput
    ld a, PASS_LINE_DEFAULT : ld (pass_line), a
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
    ld hl, hn_buf : call Wifi.espSendZ
    ld hl, .hn_end : call Wifi.espSendZ
    call Wifi.checkOkErr
    jr c, .hn_fail
    gotoXY 0, 10
    ld hl, .hn_ok : call Display.putStr
    jr .hn_wait
.hn_fail
    gotoXY 0, 10
    ld hl, .hn_err : call Display.putStr
.hn_wait
    call waitAnyKey
    jp showDiagnostics

.hn_title   db "SET HOSTNAME", 0
.hn_prompt  db "Enter hostname:", 0
.hn_help    db "ENTER=accept, BREAK=cancel", 0
.hn_ok      db "Hostname set OK!", 0
.hn_err     db "Failed to set hostname", 0
.hn_cmd     db "AT+CWHOSTNAME=\"", 0
.hn_end     db "\"", 13, 10, 0
    RTVAR hn_buf, 21

; ============================================
; doConfigSummary - Show all config (option 7)
; ============================================
doConfigSummary:
    ld hl, .cs_title
    call diagHeader

    ; Connected SSID
    gotoXY 0, 6
    ld hl, .cs_ssid : call Display.putStr
    ld a, (Wifi.is_connected) : and a : jr z, .cs_no_ssid
    ld hl, Wifi.connected_ssid : call Display.putStr
    jr .cs_ip
.cs_no_ssid
    ld hl, .cs_none : call Display.putStr

.cs_ip
    ; IP - use readDiagLine to consume full AT+CIFSR response
    gotoXY 0, 7
    ld hl, .cs_ip_lbl : call Display.putStr
    call .cs_flush
    ld hl, .cs_ip_cmd : call Wifi.espSendZ
    ld b, 8
.cs_ip_loop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cs_ip_done
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_ip_done
    cp '+' : jr nz, .cs_ip_next
    ; Find STAIP (not STAMAC): look for "," followed by '"' and a digit
    ld hl, diag_buffer
    call .cs_find_colon
    jr nc, .cs_ip_next
    inc hl                          ; skip ':'
    ; Find first '"'
.cs_ip_fq
    ld a, (hl) : and a : jr z, .cs_ip_next
    cp '"' : jr z, .cs_ip_gq
    inc hl : jr .cs_ip_fq
.cs_ip_gq
    inc hl
    ; Check if content has '.' (IP) or ':' (MAC)
    push hl
.cs_ip_chk
    ld a, (hl) : and a : jr z, .cs_ip_notip
    cp '"' : jr z, .cs_ip_notip
    cp '.' : jr z, .cs_ip_isip
    inc hl : jr .cs_ip_chk
.cs_ip_isip
    pop hl
    call .cs_printClean
    jr .cs_ip_next
.cs_ip_notip
    pop hl
.cs_ip_next
    djnz .cs_ip_loop
.cs_ip_done

.cs_mac
    ; MAC - send AT+CIPSTAMAC?
    gotoXY 0, 8
    ld hl, .cs_mac_lbl : call Display.putStr
    call .cs_flush
    ld hl, .cs_mac_cmd : call Wifi.espSendZ
    ld b, 8
.cs_mac_loop
    push bc
    call readDiagLine
    pop bc
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
    call .cs_printClean
.cs_mac_next
    djnz .cs_mac_loop
.cs_mac_done

    ; Hostname - AT+CWHOSTNAME?
    gotoXY 0, 9
    ld hl, .cs_hn_lbl : call Display.putStr
    call .cs_flush
    ld hl, .cs_hn_cmd : call Wifi.espSendZ
    ld b, 6
.cs_hn_loop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cs_hn_done
    ld a, (diag_buffer) : cp '+' : jr nz, .cs_hn_skip
    ld hl, diag_buffer
    call .cs_find_colon
    jr nc, .cs_hn_skip
    inc hl
    ld a, (hl) : cp '"' : jr nz, .cs_hn_pr
    inc hl
.cs_hn_pr
    call .cs_printClean
    jr .cs_hn_done
.cs_hn_skip
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_hn_done
    djnz .cs_hn_loop
.cs_hn_done

    ; Firmware
    gotoXY 0, 10
    ld hl, .cs_fw_lbl : call Display.putStr
    call .cs_flush
    ld hl, .cs_fw_cmd : call Wifi.espSendZ
    ld b, 10
.cs_fw_loop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cs_fw_done
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_fw_done
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

    ; Application version
    gotoXY 0, 11
    ld hl, .cs_ver_lbl : call Display.putStr
    ld hl, version_string : call Display.putStr

    call showPressKey
    call waitAnyKey
    jp showDiagnostics

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

; Helper: print string until 0, '"', CR or LF
.cs_printClean
    ld a, (hl) : and a : ret z
    cp '"' : ret z
    cp 13 : ret z
    cp 10 : ret z
    push hl : call Display.putC : pop hl
    inc hl : jr .cs_printClean

.cs_title   db "CONFIG SUMMARY", 0
.cs_ssid    db "SSID: ", 0
.cs_ip_lbl  db "IP:   ", 0
.cs_mac_lbl db "MAC:  ", 0
.cs_hn_lbl  db "Host: ", 0
.cs_fw_lbl  db "FW:   ", 0
.cs_ver_lbl db "App:  NetManZX v", 0
.cs_none    db "(none)", 0
.cs_ip_cmd  db "AT+CIFSR", 13, 10, 0
.cs_mac_cmd db "AT+CIPSTAMAC?", 13, 10, 0
.cs_hn_cmd  db "AT+CWHOSTNAME?", 13, 10, 0
.cs_fw_cmd  db "AT+GMR", 13, 10, 0

conn_retries db 0
cmd_disconnect db "AT+CWQAP", 13, 10, 0

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

checkAsyncWifi:
    ; Do NOT read UART if critical operation in progress
    ld a, (Wifi.uart_busy)
    and a
    jr z, .canRead
    xor a                       ; A = ASYNC_EVENT_NONE
    ret
    
.canRead
    ; Try to read a byte from UART (non-blocking)
    call UartImpl.uartRead
    jr c, .gotByte
    xor a                       ; A = ASYNC_EVENT_NONE
    ret
    
.gotByte
    ; A = byte read
    ; Ignore control characters (CR, LF, etc)
    cp 32
    jr nc, .validChar
    xor a                       ; A = ASYNC_EVENT_NONE
    ret
    
.validChar
    ; Add to circular buffer
    ld c, a                     ; Save byte in C
    ld hl, async_buf_idx
    ld e, (hl)
    ld d, 0
    ld hl, async_buffer
    add hl, de
    ld (hl), c                  ; Store byte
    
    ; Increment circular index
    ld a, e
    inc a
    cp ASYNC_BUF_SIZE
    jr c, .storeIdx
    xor a                       ; Wrap to 0
.storeIdx
    ld (async_buf_idx), a
    
    ; Increment received bytes counter (up to ASYNC_BUF_SIZE)
    ld a, (async_buf_count)
    cp ASYNC_BUF_SIZE
    jr nc, .checkPatterns       ; Already full, don't increment more
    inc a
    ld (async_buf_count), a
    
.checkPatterns
    ; Check if we have enough characters
    ld a, (async_buf_count)
    cp 6                        ; Minimum for "GOT IP" or "DISCON"
    jr nc, .enoughChars
    xor a                       ; A = ASYNC_EVENT_NONE
    ret
    
.enoughChars
    ; Search for patterns
    call .checkDisconnect
    ret nz                      ; If NZ, A already has ASYNC_EVENT_DISCONNECT
    call .checkGotIP
    ret                         ; A has the result (0 or 2)

.checkDisconnect:
    ; Search for "DISCON" (6 chars)
    ; Calculate start position considering wrap-around
    ld a, (async_buf_idx)
    sub 6
    jr nc, .discNoWrap
    add a, ASYNC_BUF_SIZE       ; Wrap: idx + (SIZE - 6)
.discNoWrap
    ; A = pattern start position
    ld de, .pat_discon
    call .comparePattern
    jr nz, .notFoundDisc
    
    ; Found DISCONNECT!
    xor a
    ld (async_buf_idx), a       ; Reset buffer
    ld (async_buf_count), a
    ld a, ASYNC_EVENT_DISCONNECT
    ret                         ; NZ because A != 0
    
.notFoundDisc
    xor a                       ; Z, A = 0
    ret

.checkGotIP:
    ; Search "GOT IP" (6 chars)
    ld a, (async_buf_idx)
    sub 6
    jr nc, .gotNoWrap
    add a, ASYNC_BUF_SIZE
.gotNoWrap
    ld de, .pat_gotip
    call .comparePattern
    jr nz, .notFoundGot
    
    ; Found GOT IP!
    xor a
    ld (async_buf_idx), a
    ld (async_buf_count), a
    ld a, ASYNC_EVENT_GOTIP
    ret
    
.notFoundGot
    xor a                       ; A = ASYNC_EVENT_NONE
    ret

; Compare 6 bytes from circular buffer with pattern
; Input: A = start position in buffer, DE = pattern
; Output: Z if match, NZ if not
.comparePattern
    ld b, 6
.cmpLoop
    push bc
    push de
    
    ; Calculate address in buffer (with wrap)
    ld c, a                     ; Save index
    ld hl, async_buffer
    ld d, 0
    ld e, a
    add hl, de
    
    ; Compare byte
    pop de
    ld a, (de)
    cp (hl)
    pop bc
    ret nz                      ; No match
    
    ; Next byte
    inc de
    ld a, c
    inc a
    cp ASYNC_BUF_SIZE
    jr c, .noWrap
    xor a                       ; Wrap
.noWrap
    djnz .cmpLoop
    
    xor a                       ; Z = match
    ret

.pat_discon db "DISCON"
.pat_gotip  db "GOT IP"

ASYNC_BUF_SIZE = 16
    RTVAR async_buffer, ASYNC_BUF_SIZE
async_buf_idx   db 0
async_buf_count db 0                ; Byte count in buffer (for correct wrap)

; --------------------------------------------
; waitAnyKey
;   Blocks until any key is pressed.
;   For UI use (should not be used during high-speed parsers).
; --------------------------------------------
waitAnyKey:
waitAnyKey_loop:
    halt
    call Keyboard.inKey
    and a
    jp z, waitAnyKey_loop
    ret

; ============================================
; Show network info right-aligned on line 17
; Text ends at column 41 (safe screen limit).
; ============================================
showPageInfo:
    ; --- 1. Calculate pagination data ---
    ld a, (Wifi.networks_count)
    and a
    jr nz, .haveNetworks

    ; 0 networks: clear line 17 completely (avoids stale counter)
    ld a, 17
    call clearRowPixels
    ret

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
    ; 1 space + 1 "(" + page_curr + 1 "/" + page_total + 7 " pages)" = 11 + digits
    ld a, c
    add a, 11
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
    ; We want to end at column 41 (right limit)
    ; StartX = 42 - C.
    ld a, 42
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
    call Display.putStr
    ret

.msg_net_det    db " networks detected", 0
.msg_pages_suff db " pages)", 0

; Returns in A how many digits the number in A has (0-99)
; 1 if < 10, 2 if >= 10
getDigitCount:
    cp 10
    ld a, 1
    ret c
    inc a
    ret

; Print A (0-99) in decimal
printNumber:
    ld c, a
    ld b, 0
    cp 10
    jr c, .oneDigit
    ld d, 0
.div10
    sub 10
    inc d
    cp 10
    jr nc, .div10
    push af
    ld a, d
    add a, '0'
    call Display.putC
    pop af
.oneDigit
    add a, '0'
    jp Display.putC

page_total      db 0
page_current    db 0

; ============================================
; About screen (I key)
; ============================================
showAbout:
    ld hl, .msg_about_title
    call diagHeader

    gotoXY 0, 6
    ld hl, .msg_about_ver
    call Display.putStr
    gotoXY 0, 7
    ld hl, .msg_about_build
    call Display.putStr
    gotoXY 0, 9
    ld hl, .msg_about_desc
    call Display.putStr
    gotoXY 0, 10
    ld hl, .msg_about_author
    call Display.putStr
    gotoXY 0, 11
    ld hl, .msg_about_github
    call Display.putStr
    gotoXY 0, 12
    ld hl, .msg_about_license
    call Display.putStr
    call showPressKey

.aboutWait
    halt
    call Keyboard.inKey
    and a
    jr z, .aboutWait
    call renderList
    jp uiLoop

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
msg_connected_title db "Connected!", 0
msg_done_body       db "Now you can use network apps!", 0
msg_fail_generic  db "Connection failed!", 13, 13, "Unknown error.", 0
msg_fail_timeout  db "Connection timeout!", 13, 13, "Router not responding.", 0
msg_fail_password db "Wrong password!", 13, 13, "Check password and try again.", 0
msg_fail_notfound db "Network not found!", 13, 13, "AP may be out of range.", 0
msg_fail_connfail db "Connection failed!", 13, 13, "Try again or check router.", 0
msg_press_key   db "Press any key to continue...", 0
msg_conn_attempt db "Connecting (x/3)...", 0
msg_retry_suffix db " Retry", 0
msg_break_cancel db "Press BREAK to cancel", 0
msg_open_net    db "Open network (no password needed)", 0
at_start        db 'AT+CWJAP="',0
at_start_old    db 'AT+CWJAP_DEF="',0
at_middle       db '","', 0
msg_ssid        db "Selected SSID:", 0
msg_pass        db "Password (BREAK=cancel, UP=show):", 0

    RTVAR pass_buffer, MAX_PASS_LEN + 2
pass_len        db 0
pass_cursor     db 0                ; Cursor position in the password
cursor_position db 0
offset          db 0
is_open_network db 0
show_password   db 0                ; Flag to show password
selected_ssid_ptr dw 0              ; Pointer to the selected SSID
selected_real_idx db 0              ; Real index of the selected network
ui_async_div    db 0                ; Divider for checkAsyncWifi
autoscan_counter dw 0              ; Counter for auto-rescan (15000 = 5 min)
health_counter  dw 0              ; Counter for periodic health-check (invalidate only)
force_rescan   db 0              ; 1 => rescan pending after disconnect

msg_head
    db "NetManZX "
    db VERSION_STRING
    db " - Network manager", 0

msg_wifi_label
    db "WiFi:", 0

    endmodule