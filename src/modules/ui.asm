    module UI
PER_PAGE = 10
    ASSERT MAX_NETWORKS <= PER_PAGE * 9
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
    ld hl, #5A43
    ld b, 15
    jr colorStatusRows

; Build the fixed prefix once and continue at its end. Destroys: AF, BC, DE, HL.
ipSetPrefixed:
    ld de, ip_line_buffer
    push hl
    ld hl, msg_ip_prefix
    ld bc, 4
    ldir
    pop hl
.copy
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    and a
    jr nz, .copy
    ret

; Buffers/messages
msg_ip_prefix      db "IP: "
msg_ip_unknown     db "---", 0
msg_ip_scanning    db "Scanning...", 0
    RTVAR ip_line_buffer, 40

; Color status area (cells 22-31) on both rows 18-19
colorStatusAreaBothRows:
    ld hl, #5A56
    ld b, 10
colorStatusRows:
    push bc
    push hl
.top
    ld (hl), a
    inc hl
    djnz .top
    pop hl
    pop bc
    set 5, l                ; row 19 is 32 bytes after row 18
    res 6, a
.bottom
    ld (hl), a
    inc hl
    djnz .bottom
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

    ; Highlight the connected AP if its identity is available.
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
    ld a, (current_screen_idx)
    call Wifi.getDisplayIndex
    pop hl
    call matchesConnectedAP
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
    call Display.setAttrList
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
    ; Print SSID limited to 28 chars (leave room before RSSI)
    ld b, 28
    call putStrLimited

    ; Move cursor to fixed column (29) for the lock and bar block
    ld a, (current_line)
    ld h, a
    ld l, 29
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
    push bc                 ; keep the name-diff accumulator
    ld a, (current_screen_idx)
    call Wifi.getDisplayIndex
    ld hl, Wifi.rssi_buffer
    ld e, a
    ld d, 0
    add hl, de
    ; Key on the bar that gets drawn, not on the raw reading. rssiCells
    ; quantises to 1..9, so the ±1 dBm wobble between two scans used to
    ; force a full recompose of every row while drawing the same pixels.
    ld a, (hl)
    ld e, a                 ; keep the open flag in bit 7
    and #7F
    call rssiCells          ; C = lit cells (1..9); destroys AF, B
    ld a, e
    and #80
    or c
    ld (rssi_value), a
    pop bc
    ld b, a
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
    jp Display.putStrN

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
    ld a, 3 : call Display.beginRow
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
    ld de, #4640                ; Row 2, scanline 6 (Y=22)
    call publishMenuRow

    ; Show help line 2 on line 4
    ld a, 4 : call Display.beginRow
    ld a, 4 : ld hl, msg_help2 : call printAt0
    ld de, #4660                ; Row 3, scanline 6 (Y=30)
    call publishMenuRow

    ; Separator line below menu
    ld a, 5 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline

    call showPageInfo

    ; Use common routine to draw networks
    jp renderNetworksCommon

; Publish one composed text row at an arbitrary bitmap scanline.
; Input: DE = destination. Destroys: AF, BC, DE, HL.
publishMenuRow:
    xor a
    ld (Display.row_active), a
    ld hl, Display.row_buffer
    ld b, 8
.copy
    push bc
    push hl
    push de
    ld bc, 32
    ldir
    pop de
    pop hl
    ld bc, 32
    add hl, bc
    ex de, hl
    call .nextScanline
    ex de, hl
    pop bc
    djnz .copy
    ret

; Advance a Spectrum bitmap address by one visible scanline.
.nextScanline
    inc h
    ld a, h
    and 7
    ret nz
    ld a, l
    add a, 32
    ld l, a
    ret c
    ld a, h
    sub 8
    ld h, a
    ret

no_net_msg db "No networks found. Press 'R' to rescan.", 0
; ============================================
; Show scroll arrows on line 17 (same row as page info)
; DOWN at Col 0 (left), UP at Col 41 (right)
; Composed with the counter by showPageInfo.
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
    ; rowPixelsChanged cached (open_bit | rssiCells) in rssi_value
    ld a, (rssi_value)
    rlca
    ld a, '`'               ; Closed (filled circle)
    jr nc, .printLock
    ld a, '~'               ; Open (hollow circle)
.printLock
    call Display.putC

    ; Recover lit cells (1..9) and draw the bar block (pixels + attributes)
    ld a, (rssi_value)
    and #0F                 ; C = lit cells (1..9)
    ld c, a
    ld a, RSSI_COL_LIST
    ld (drb_col), a
    ld a, (current_line)
    jp drawRssiBlock

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
    ld a,(cursor_position) : add a, 6 : jp Display.setAttrList

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
; Output: CF=1 if the connected AP is in the list, CF=0 if not
; If CF=1, A = real network index (0-based)
; ============================================
connectedSSIDPresentInList:
    ld a, (Wifi.networks_count)
    and a
    jr z, .notFound

    ld b, a
    ld c, 0             ; C = current index
.loopNet
    ld a, c
    call Wifi.getSSIDPointer    ; HL = SSID; preserves BC
    ld a, (hl)
    and a
    jr z, .skipEmpty     ; Hidden SSID (empty): skip without aborting

    ld a, c
    call matchesConnectedAP
    jr z, .found        ; Z=1 means equal

.skipEmpty
    inc c               ; Next index
    djnz .loopNet

.notFound
    or a
    ret

.found
    ld a, c             ; A = real index
    scf
    ret

; A = real index, HL = SSID. Z = connected AP; preserves HL and BC.
; Missing BSSID information retains the SSID-only firmware fallback.
matchesConnectedAP:
    push bc
    ld c, a
    ld de, Wifi.connected_ssid
    call Display.compareStringZ
    jr nz, .done
    push hl
    ld a, (Wifi.connected_bssid_valid)
    and a
    jr z, .restore
    ld a, c
    call getScanBSSID
    jr nc, .match
    ld de, Wifi.connected_bssid
    ld b, 6
.compare
    ld a, (de)
    cp (hl)
    jr nz, .restore
    inc de
    inc hl
    djnz .compare
.match
    xor a
.restore
    pop hl
.done
    pop bc
    ret


; Restore the caller even when runtime clearing or our stack overwrote its return.
exitRestore:
    di
    IFNDEF NEXT
    exx
    ld hl, 0
.callerAltHL = $ - 2
    exx
    ENDIF
    ld hl, 0
.callerStack = $ - 2
    ld de, 0
.callerReturn = $ - 2
    ld (hl), e
    inc hl
    ld (hl), d
    dec hl
.stackSwitch
    ld sp, hl
    ei
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
    jp z, quitConfirm        ; ask before quitting to BASIC

    ; Handle queued input before optional ESP work, but keep forced scans first.
    ld a, (force_rescan)
    and a
    jr nz, .maintenance
    ld a, (Keyboard.BASIC_KEY)
    and a
    jp nz, .noForceRescan
.maintenance
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
    IFDEF HAS_TIME
    cp 't' : jp z, showTime
    cp 'T' : jp z, showTime
    ENDIF
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
    ; File I/O does not consume RX: retain any fragmented +IPD frame.
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
; drawSignalLine - Draw "Signal:" plus the right-edge bar block
; Input: A = line number
; Uses: selected_real_idx to get RSSI
; ============================================
drawSignalLine:
    ld h, a : ld l, 0
    ld (Display.coords), hl
    push af
    ld a, RSSI_COL_DETAIL
    ld (drb_col), a
    ld hl, showNetDetail.nd_sig
    call Display.putStr
    ; Same bar block as the network list
    ld a, (selected_real_idx)
    ld hl, Wifi.rssi_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl) : and #7F
    call rssiCells
    pop af
    jp drawRssiBlock

; Bar block start, in byte columns. The list keeps it flush right; the detail
; screens put it at byte 9, which is pixel 72, exactly where column 12 starts,
; so it lines up with the values printed next to the 12-character labels.
RSSI_COL_LIST   = 23
RSSI_COL_DETAIL = 9

; ============================================
; RSSI bar block - 9 ULA cells, byte-aligned like the
; BridgeZX minibar: two 3px bars per active cell (#EE pattern), 6px tall.
; Inactive cells use four dim-white 1px stripes (#AA). One attribute per
; cell prevents color clash.
; ============================================

; Input: A = RSSI (0-127). Output: C = lit cells (1..9). Destroys: AF, B.
rssiCells:
    ld b, a
    ld a, 93
    sub b
    jr c, .weak             ; Stronger than -93 dBm: single cell
    ld c, 0
.div
    inc c
    sub 9
    jr nc, .div
    ld a, c
    cp 10
    ret c
    ld c, 9
    ret
.weak
    ld c, 1
    ret

; Input: HL = scanline address of the first bar cell.
; Writes all nine bar cells and keeps HL. Destroys: AF, B, D.
fillBarScan:
    push hl
    ld b, 9
    ld a, (drb_lit)
    ld d, a
.fill
    ld a, d
    and a
    jr z, .inactive
    ld a, #EE               ; 3px bar, 1px gap, 3px bar, 1px gap
    dec d
    jr .write
.inactive
    ld a, #AA               ; Four 1px vertical stripes
.write
    ld (hl), a
    inc hl                    ; Row buffer blocks may cross a 256-byte page
    djnz .fill
    pop hl
    ret

; Input: A = row, C = lit cells (1..9), (drb_col) = first byte column.
; The list puts the block at byte 23, flush right; the detail screens put it
; at byte 9 so it starts in their value column. Draws into the staging buffer
; while a row is open, straight to the screen otherwise.
; Destroys: AF, BC, DE, HL.
drawRssiBlock:
    ld (drb_row), a
    ld a, c
    ld (drb_lit), a
    ld a, (Display.row_active)
    and a
    jr z, .screen
    ; Staging row: scanline 1 starts at row_buffer + 32 + column
    ld hl, Display.row_buffer + 32
    ld a, (drb_col)
    ld e, a : ld d, 0
    add hl, de
    ld c, 6
.buffered
    call fillBarScan
    ld de, 32
    add hl, de
    dec c
    jr nz, .buffered
    jr .attrs
.screen
    ld a, (drb_row)
    ld d, a
    ld a, (drb_col)
    ld e, a
    call Display.findAddr
    ex de, hl
    inc h                     ; Match the staging row's one-pixel top margin
    ld c, 6
.visible
    call fillBarScan
    inc h
    dec c
    jr nz, .visible
.attrs
    ld a, (drb_row)
    call Display.attrCalc
    ld a, (drb_col)
    ld e, a : ld d, 0
    add hl, de
    ld de, rssi_zone
    ld c, 9
    ld a, (drb_lit)
    ld b, a
.lit
    ld a, (de)
    inc de
    or #40                  ; BRIGHT: lit cell shows its zone colour
    ld (hl), a
    inc hl
    dec b
    jr z, .pending
    dec c
    jr nz, .lit
    ret
.pending
    dec c
    ret z
    ld a, Display.ATTR_NORMAL_DIM
.pendingLoop
    ld (hl), a              ; White, no BRIGHT
    inc hl
    dec c
    jr nz, .pendingLoop
    ret

rssi_zone:
    db 002o, 002o, 002o     ; Low third: red
    db 006o, 006o, 006o     ; Middle third: yellow
    db 004o, 004o, 004o     ; High third: green

    RTVAR drb_row, 1
    RTVAR drb_lit, 1
    RTVAR drb_col, 1         ; first byte column of the bar block

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

.nd_sec         db "Security:   ", 0
.nd_chan        db "Channel:    ", 0
.nd_band24     db " (2.4 GHz)", 0
.nd_band5      db " (5 GHz)", 0
.nd_sig         db "Signal:     ", 0

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
; A=row, HL=label, DE=value, BC=fallback; drawing clobbers both pointers.
printConnectionField:
    push bc
    push de
    call printAt0
    pop hl
    pop de
    ld a, (hl)
    and a
    jr nz, .value
    ex de, hl
.value
    jp Display.putStr

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
    
    ; Use the same AP identity as list highlighting and diagnostics.
    ld hl, (selected_ssid_ptr)
    ld a, (selected_real_idx)
    call matchesConnectedAP
    jp nz, .notConnectedYet

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
    ld a, 10 : ld hl, .ci_ip_lbl
    ld de, Wifi.ip_buffer : ld bc, .ci_na
    call printConnectionField

    ; Row 11: Gateway
    ld a, 11 : ld hl, .ci_gw_lbl
    ld de, Wifi.ci_gateway : ld bc, .ci_na
    call printConnectionField

    ; Row 12: Netmask
    ld a, 12 : ld hl, .ci_mask_lbl
    ld de, Wifi.ci_netmask : ld bc, .ci_na
    call printConnectionField

    ; Row 13: MAC
    ld a, 13 : ld hl, .ci_mac_lbl
    ld de, Wifi.ci_mac : ld bc, .ci_na
    call printConnectionField

    ; Set attrs for rows 10-13
    ld a, 10 : ld b, 4 : ld c, Display.ATTR_NORMAL : call setRowsColor

    ; Row 15: message (bright red for visibility)
    ld a, 15 : ld hl, .msg_already_conn : call printAt0
    ld a, 15 : ld b, 1 : ld c, Display.ATTR_ALERT : call setRowsColor
    jp pressKeyReturnList

.ci_retrieving db "Retrieving information...", 0
.ci_ip_lbl   db "IP:         ", 0
.ci_gw_lbl   db "Gateway:    ", 0
.ci_mask_lbl db "Mask:       ", 0
.ci_mac_lbl  db "MAC:        ", 0
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
; A = real scan index; same result contract as getSelectedBSSID.
getScanBSSID:
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

.carRetry
    call Wifi.prepareRetry
    jr nc, .carPrepared
    ld a, (Uart.break_hit)
    and a
    jp nz, .carDiscCancelled
    jp .carFailed
.carPrepared
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
    ld a, 1
    ld (is_reconnect), a
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
    ld hl, scc_title
    call topCleanAlertMsg
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
    include "modules/press-key.asm"

; Standard header for diagnostic screens
; Input: HL = title pointer. Clears screen, green double-height title.
; Cold UI (manual SSID, password entry).
; Classic: resident here. Next: paged at #6000 (see main.asm).
    IFNDEF NEXT
    include "modules/cold-ui.asm"
    ; Classic TAP diagnostics live at #6000, but AY polls from uncontended RAM.
    IFNDEF UNO
    DEFINE DIAG_RX_RESIDENT
    include "modules/diag-rx.asm"
    ASSERT readDiagLineBC >= #8000
    ASSERT $ <= #C000
    ENDIF
    ENDIF
printClean:
    ld a, (hl) : and a : ret z
    cp '"' : ret z
    cp 13 : ret z
    cp 10 : ret z
    push bc : push hl : call Display.putC : pop hl : pop bc
    inc hl : jr printClean

; ============================================
; checkAsyncWifi - Detect async WiFi events
; Accept complete event lines outside length-framed +IPD payloads.
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

    push bc
    call .consume
    pop bc
    and a
    ret nz
    djnz .drainLoop
.none
    xor a
    ret
.fault
    call Wifi.flushInput
    jp resetAsyncWifi

; C = byte. State survives empty polls and the per-call drain budget.
.consume
    ld a, (async_state)
    and a
    jr z, .start
    cp 1 : jr z, .match
    cp 2 : jr z, .lineEnd
    cp 5 : jp z, .peer
    cp 6 : jp z, .payload
    cp 7 : jr z, .none         ; Malformed header: wait for explicit RX recovery.
    jp .number
.start
    ld a, c
    cp 13 : jr z, .none
    cp 10 : jr z, .none
    ld hl, .pat_discon
    cp '+'
    jr nz, .begin
    ld hl, .pat_ipd
.begin
    ld (async_match), hl
    ld a, 1
    ld (async_state), a
.match
    ld hl, (async_match)
    ld a, c
    cp (hl)
    jr z, .advance
    cp 'G'
    jr nz, .discardLine
    ld de, .pat_discon + 5
    or a
    sbc hl, de
    jr nz, .discardLine
    ld hl, .pat_gotip
.advance
    inc hl
    ld (async_match), hl
    ld a, (hl)
    cp 4
    jp nc, .none
    cp 3
    jr z, .newNumber
    push af
    call resetAsyncWifi
    pop af
    ret
.discardLine
    ld a, 2                   ; Reject the entire line after any mismatch.
    ld (async_state), a
.lineEnd
    ld a, c
    cp 10
    jp z, resetAsyncWifi
    xor a
    ret
.newNumber
    ld (async_state), a
    xor a
    ld (async_digits), a       ; At least one decimal digit is required.
    ld hl, 0
    ld (async_remaining), hl
    ret
.number
    ld a, c
    sub '0'
    cp 10
    jr nc, .delimiter
    ld e, a
    ld d, 0
    ld hl, (async_remaining)
    ld b, h
    ld c, l
    add hl, hl
    jr c, .badHeader
    add hl, hl
    jr c, .badHeader
    add hl, bc
    jr c, .badHeader
    add hl, hl
    jr c, .badHeader
    add hl, de
    jr c, .badHeader
    ld (async_remaining), hl
    ld a, 1
    ld (async_digits), a
    xor a
    ret
.delimiter
    ld a, (async_digits)
    and a
    jr z, .quotedPeer
    ld a, c
    cp ':' : jr z, .payloadStart
    cp 13 : jr z, .discardLine ; Passive receive notification, no inline data.
    cp 10 : jp z, resetAsyncWifi
    cp ',' : jr z, .comma
    cp '.' : jr z, .singlePeer
.badHeader
    ld a, 7                   ; Never expose bytes after an invalid length.
    ld (async_state), a
    xor a
    ret
.comma
    ld hl, (async_remaining)
    ld (async_first), hl
    ld a, 4
    jr .newNumber
.quotedPeer
    ld a, c
    cp '"'
    jr nz, .badHeader
.singlePeer
    ld a, (async_state)
    cp 4
    jr nz, .badHeader
    ld hl, (async_first)
    ld (async_remaining), hl
.peerStart
    ld a, 5
    ld (async_state), a
    xor a
    ret
.peer
    ld a, c
    cp 13 : jr z, .badHeader
    cp 10 : jr z, .badHeader
    cp ':' : jp nz, .none
.payloadStart
    ld hl, (async_remaining)
    ld a, h
    or l
    jp z, resetAsyncWifi
    ld a, 6
    ld (async_state), a
    xor a
    ret
.payload
    ld hl, (async_remaining)
    dec hl
    ld (async_remaining), hl
    ld a, h
    or l
    jp z, resetAsyncWifi
    xor a
    ret

    RTVAR async_match, 2
; Header parsing reuses the inactive matcher pointer's low byte.
async_digits = async_match
    RTVAR async_state, 1
    RTVAR async_remaining, 2
    RTVAR async_first, 2

; Preserve BC/DE/HL: uartUnlock callers rely on their parsed result registers.
resetAsyncWifi:
    xor a
    ld (async_state), a
    ret

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

    ld a, 17
    call Display.beginRow
    call composePageInfo
    call showScrollIndicators
    jp Display.endRow

composePageInfo:
    ; --- 1. Calculate pagination data ---
    ld a, (Wifi.networks_count)
    and a
    ret z                       ; Publish the blank staging row when empty.
    
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

    ; MAX_NETWORKS bounds both page numbers to one digit.
    ld a, c
    add a, 12
    ld c, a

.calcFinish
    ; --- 3. Calculate initial X position ---
    ; End at column 40 so column 41 stays free for the right scroll arrow.
    ; StartX = 41 - C.
    ld a, 41
    sub c
    ld b, a                 ; B = StartX
    
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
