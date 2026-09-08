    module Display

; ============================================
; Color attribute constants
; Format: FBPPPIII (Flash, Bright, Paper, Ink)
; ============================================
ATTR_HIGHLIGHT   = 160o   ; Black on bright white (cursor)
ATTR_CONNECTED   = 106o   ; Bright yellow on black (connected network)
ATTR_SAVED       = 105o   ; Bright cyan on black (saved/known network)
ATTR_CONN_CURSOR = 061o   ; Blue on yellow (cursor on connected network)
ATTR_STATUSBAR   = 170o   ; Black on bright white (status bar)
ATTR_LOG         = 014o   ; Green on blue (log window)
ATTR_HEADER      = 117o   ; Bright white on blue (header)
ATTR_TITLE       = 116o   ; Bright yellow on blue (title)
ATTR_BANNER_TOP  = 01000111b  ; White on black, BRIGHT (row 0 banner)
ATTR_BANNER_BOT  = 00000111b  ; White on black, no BRIGHT (row 1 banner)
ATTR_RSSI        = 004o   ; Green on black (signal bars)
ATTR_SSID_INPUT  = 104o   ; Bright green on black (selected SSID)
ATTR_PASS_INPUT  = 171o   ; Bright blue on white (password input)
ATTR_PASS_EXPOSED = 172o   ; Bright red on white (password visible)
ATTR_STATUS_BOT  = 00111000b  ; Black ink, white paper, no BRIGHT (double-height bot)
ATTR_NORMAL      = 107o   ; Bright white on black (standard text)
ATTR_NORMAL_DIM  = 007o   ; White on black, no bright (double-height bottom)
ATTR_ALERT       = 102o   ; Bright red on black (warnings/disconnect)
ATTR_STATUS_DISC = 172o   ; Bright red on white (status: disconnected)
ATTR_STATUS_CONN = 174o   ; Bright green on white (status: connected)
ATTR_INPUT_LINE  = 071o   ; Blue on white (input field background)

    RTVAR row_target, 1
    RTVAR row_active, 1

; Input: A = row number (0-23)
; Output: HL = attribute address ($5800 + row*32)
; Destroys: AF
attrCalc:
	rrca
	rrca
	rrca
	ld	l,a
	and	31
	or	#58
	ld	h,a
	ld	a,l
	and	252
	ld	l,a
	ret

; Input: A = line number, C = color
; Sets color for entire line (32 columns)
setAttr:
    call attrCalc
    ld (hl), c              ; store color before bc is clobbered
    ld de, hl
    inc de
    ld bc, #1f
    ldir
    ret

; Input: A = line number, C = color
; Sets color for first 22 cells only
setAttrPartial:
    call attrCalc
    ld b, 22
    ld a, c
.loop
    ld (hl), a
    inc hl
    djnz .loop
    ret

putStr:
    ld bc, (coords)         ; C = col, B = row
.loop
    ld a, (hl)
    and a : jr z, .done
    cp 13 : jr nz, .notCR
    inc hl : jr .cr
.notCR
    push hl
    push bc
    ld (drawC.coords), bc   ; set drawC coords directly
    call drawC
    pop bc
    inc c                   ; next column
    ld a, c : cp 42 : jr nc, .cr2  ; wrap at column 42
    pop hl
    inc hl
    jr .loop
.cr2
    pop hl
    inc hl
.cr
    ld c, 0 : inc b
    jr .loop
.done
    ld (coords), bc         ; save final position
    ret

putStrBig:
    ld a, (hl) : and a : ret z
    push hl
    call putCBig
    pop hl
    inc hl
    jr putStrBig

putStrLog:
    ld a, (splash_mode)
    and a
    ret nz                      ; splash active: suppress log-area writes
    ld a, (hl) : and a : ret z
    push hl
    call putLogC
    pop hl
    inc hl
    jr putStrLog

splash_mode db 0                ; 1 while splash messages own rows 22-23

putC:
    cp 13 : jr z, .cr
    ld hl, (coords) : ld (drawC.coords), hl
    call drawC
    ld hl, coords
    inc (hl)
    ld a,(hl) : cp 42 : jr nc, .cr
    ret
.cr
    ld hl, coords
    xor a : ld (hl), a
    inc hl : inc (hl)
    ret

putCBig:
    cp 13 : jr z, putC.cr
    ld hl, (coords) : ld (drawCBig.coords), hl
    call drawCBig
    ld hl, coords
    inc (hl)
    ld a,(hl) : cp 42 : jr nc, putC.cr
    ret

; Same as putCBig but skips decompressChar (glyph_buf already valid)
putCBigGlyph:
    ld hl, (coords) : ld (drawCBig.coords), hl
    ld de, glyph_buf
    call drawCBig.glyph
    ld hl, coords
    inc (hl)
    ld a,(hl) : cp 42 : jr nc, putC.cr
    ret

; ============================================
; putLogC - Write to the log window (lines 20-23)
; ============================================
putLogC:
    cp 13 : jr z, .cr
    cp ' ' : ret c
    ld c,a
    
    ; Always write to line 23
    ld h, 23
    ld a, (putLogC_coord)
    ld l, a
    ld (drawC.coords), hl
    
    ld a,c
    call drawC
    
    ; Advance X cursor
    ld hl, putLogC_coord : inc (hl) : ld a,(hl)
    cp 42 : ret c

.cr
    xor a : ld (putLogC_coord), a
    ; Fall through to .scrollLog

.scrollLog
    ; Scroll log: lines 20-23
    ; Per scanline: copy 21-23 → 20-22, clear ghost indicator from row 22,
    ; clear row 23, paint indicator on row 23 byte 31. Indicator data is
    ; never absent from the screen, so no flicker.

    di

    ld hl, log_ind_data
    ld (.indPtr), hl     ; Self-mod: init indicator pointer
    ld b, 8              ; 8 scanlines per text row
    ld hl, #50A0         ; Source: line 21, scanline 0
    ld de, #5080         ; Dest: line 20, scanline 0

.scrollLoop
    push bc
    push hl
    push de

    ; Copy 3 text lines (96 bytes): lines 21-23 to 20-22
    ld bc, 96
    ldir

    ; Clear ghost indicator from row 22 byte 31 (just copied from row 23)
    dec de
    ld a, (de)
    and #F0              ; Clear bottom 4 bits only
    ld (de), a
    inc de

    ; Clear row 23 bytes 0-30 (31 bytes)
    ex de, hl            ; HL = start of row 23 this scanline
    ld b, 31
    xor a
.clrLine
    ld (hl), a
    inc hl
    djnz .clrLine

    ; HL = byte 31 of row 23 — write indicator data
    push hl
    ld hl, 0
.indPtr = $ - 2
    ld a, (hl)
    inc hl
    ld (.indPtr), hl     ; Advance pointer
    pop hl
    ld (hl), a

    pop de
    pop hl
    pop bc

    ; Next scanline (+256 bytes)
    inc h
    inc d
    djnz .scrollLoop

    ei
    ret

; Log indicator pixel data — 8 bytes, one per scanline.
; In printer buffer. Populated by UI.updateLogIndicator.
log_ind_data = #5B4E  ; 8 bytes (#5B4E-#5B55)
putLogC_coord = #5B36  ; In printer buffer (set before use)

; Compose one text row away from the display. Keeps a live list pointer/count.
; Input: A = row (0-23). Preserves: BC, DE, HL.
beginRow:
    ld (row_target), a
    ld a, 1
    ld (row_active), a
    push bc
    push de
    push hl
    ld hl, row_buffer
    ld de, row_buffer + 1
    ld bc, 255
    xor a
    ld (hl), a
    ldir
    pop hl
    pop de
    pop bc
    ret

; Publish a composed row only when its pixels changed.
; Output: Z = unchanged/skipped, NZ = published. Destroys: AF, BC, DE, HL.
endRow:
    xor a
    ld (row_active), a
    ld a, (row_target)
    ld d, a
    ld e, 0
    call findAddr
    ld hl, row_buffer
    ld b, 8
.compareScanline
    push bc
    push de
    ld b, 32
.compareByte
    ld a, (de)
    cp (hl)
    jr nz, .changed
    inc de
    inc hl
    djnz .compareByte
    pop de
    inc d
    pop bc
    djnz .compareScanline
    xor a                   ; Z = unchanged
    ret
.changed
    pop de
    pop bc
    ld a, (row_target)
    ld d, a
    ld e, 0
    call findAddr
    ld hl, row_buffer
    ld b, 8
.copyScanline
    push bc
    push de
    ld bc, 32
    ldir
    pop de
    inc d
    pop bc
    djnz .copyScanline
    ld a, 1                 ; NZ = published
    or a
    ret


drawC:
    call fontCharPtr        ; A = char, returns DE = cached glyph
    push de                 ; save font data ptr
    ld hl, 0
.coords = $ - 2
    ld b, l
    call calc               ; L = byte col, A = pixel offset (0,2,4,6)
    ld (dcb_rot), a         ; save pixel offset (reuses drawCBig's temp)
    ld c, l : ld b, 0
    ld a, (row_active)
    and a
    jr z, .screenTarget
    ld hl, row_buffer
    add hl, bc
    ld d, h : ld e, l
    jr .targetReady
.screenTarget
    ld d, h : ld e, l
    call findAddr
.targetReady
    push de                 ; save screen address
; Mask table lookup (replaces mask rotation loop)
    ld a, (dcb_rot)
    ld c, a : ld b, 0
    ld hl, .maskTable
    add hl, bc              ; HL = &maskTable[pixel_offset]
    ld a, (hl) : ld (.mask2), a
    inc hl
    ld a, (hl) : ld (.mask1), a
; Shift dispatch: compute jr offset into unrolled shift chain
    ld a, c                 ; pixel offset (0,2,4,6)
    add a, a : add a, a     ; ×4 = bytes to skip back from .shift0
    ld c, a
    ld a, .shift0 - .shiftJr - 2
    sub c
    ld (.shiftJr + 1), a
    pop ix, de              ; IX = target address, DE = cached glyph
    ld b, 8
.printIt
    ld a, (de)
    ld h, a
    ld l, 0
.shiftJr
    jr .shift0              ; self-mod: dispatches to correct shift entry
.shift6
    srl h : rr l
    srl h : rr l
.shift4
    srl h : rr l
    srl h : rr l
.shift2
    srl h : rr l
    srl h : rr l
.shift0
    ld a, (ix + 1)
    and #0f
.mask1 = $ - 1
    or l
    ld (ix + 1), a
    ld a, (ix)
    and #fc
.mask2 = $ - 1
    or h
    ld (ix), a
    ld a, (row_active)
    and a
    jr nz, .nextBuffered
    inc ixh
    jr .advanced
.nextBuffered
    ld a, ixl
    add a, 32
    ld ixl, a
    jr nc, .advanced
    inc ixh
.advanced
    inc de
    djnz .printIt
    ret

.maskTable
    db #03, #FF             ; shift 0: mask2 (left), mask1 (right)
    db #C0, #FF             ; shift 2
    db #F0, #3F             ; shift 4
    db #FC, #0F             ; shift 6

; SMC variables for drawCBig (in printer buffer, set before use)
dcb_rot     = #5B32
dcb_m1      = #5B34
dcb_m2      = #5B35

drawCBig:
    call fontCharPtr
.glyph:                          ; entry: DE = glyph_buf (pre-decompressed)
    push de
    ld hl, 0
.coords = $ - 2
    ld b, l
    call calc
    ld (dcb_rot), a
    ld d, h : ld e, l
    call findAddr
    push de
; Mask table lookup (shared with drawC)
    ld a, (dcb_rot)
    ld c, a : ld b, 0
    ld hl, drawC.maskTable
    add hl, bc
    ld a, (hl) : ld (dcb_m2), a
    inc hl
    ld a, (hl) : ld (dcb_m1), a
; Shift dispatch setup
    ld a, c                 ; pixel offset (0,2,4,6)
    add a, a : add a, a     ; ×4
    ld c, a
    ld a, .wShift0 - .wShiftJr - 2
    sub c
    ld (.wShiftJr + 1), a
    pop ix, de
    push ix
    ld b, 4
.topLoop
    call .writeOnePair
    inc de
    djnz .topLoop
    ; Calculate base address of row Y+1
    pop hl
    ld a, l : add a, 32 : ld l, a
    jr nc, .botBaseReady
    ld a, h : and #F8 : add a, 8 : ld h, a
.botBaseReady
    push hl : pop ix
    ld b, 4
.botLoop
    call .writeOnePair
    inc de
    djnz .botLoop
    ret

; Sub: read 1 glyph byte, shift, write to 2 scanlines (duplicated)
.writeOnePair
    ld a, (de) : ld h, a : ld l, 0
.wShiftJr
    jr .wShift0             ; self-mod: dispatches to correct shift entry
.wShift6
    srl h : rr l
    srl h : rr l
.wShift4
    srl h : rr l
    srl h : rr l
.wShift2
    srl h : rr l
    srl h : rr l
.wShift0
    ; First scanline — and (ix+d) masks screen byte directly, H:L preserved
    ld a, (dcb_m1) : and (ix + 1)
    or l : ld (ix + 1), a
    ld a, (dcb_m2) : and (ix + 0)
    or h : ld (ix), a
    inc ixh
    ; Second scanline (duplicate, H:L intact)
    ld a, (dcb_m1) : and (ix + 1)
    or l : ld (ix + 1), a
    ld a, (dcb_m2) : and (ix + 0)
    or h : ld (ix), a
    inc ixh
    ret

; Clear third 1 ($4800-$4FFF, lines 8-15) — shared by clrListOnly / clrNetworksOnly
clrThird1:
    ld hl, #4800
    ld de, #4801
    ld bc, 2047             ; 2048 bytes - 1
    xor a : ld (hl), a
    ldir
    ret

clrTwoRows8Scanlines:
    ld b, 8
.loop
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 63               ; 64 bytes (2 lines * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    inc h                   ; Next scanline (+256)
    pop bc
    djnz .loop
    ret

; Clear list area (lines 2-17)
; For each scanline, clear all lines at once
clrListOnly:
    ; Third 0: lines 2-7 (6 lines)
    ld hl, #4040            ; Scanline 0, line 2
    ld b, 8
.loopT0
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 191              ; 192 bytes (6 lines * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    inc h                   ; Next scanline (+256)
    pop bc
    djnz .loopT0

    ; Third 1: lines 8-15 (full middle third, contiguous $4800-$4FFF)
    call clrThird1

    ; Third 2: lines 16-17 (2 lines)
    ld hl, #5000            ; Scanline 0, line 16
    jp clrTwoRows8Scanlines

; Clear network area only (lines 6-15)
clrNetworksOnly:
    ; Third 0: lines 6-7 (2 lines)
    ld hl, #40C0
    call clrTwoRows8Scanlines

    ; Third 1: lines 8-15 (full middle third, contiguous $4800-$4FFF)
    call clrThird1

    ; Clear network area attrs (lines 6-15) to avoid residual colors after rescan
    ld a, ATTR_NORMAL
    ld hl, #58C0             ; 0x5800 + (6 * 32)
    ld de, #58C1
    ld bc, 319               ; 10 lines * 32 - 1
    ld (hl), a
    ldir
    ret

clrscr:
    xor a
    out (#fe), a

    ; 1. Clear pixels
    ld hl, #4000
    ld de, #4001
    ld bc, #17ff
    ld (hl),a
    ldir

    ; 2. Lines 0-17: white on black (list + info)
    ld a, ATTR_NORMAL
    ld hl, #5800
    ld de, #5801
    ld bc, 575              ; 18 lines * 32 - 1 = 575
    ld (hl), a
    ldir

    ; 3. Line 18: status bar top (BRIGHT)
    ld a, ATTR_STATUSBAR
    ld hl, #5A40            ; Line 18
    ld de, #5A41
    ld bc, 31
    ld (hl), a
    ldir

    ; 4. Line 19: status bar bottom (no BRIGHT)
    ld a, ATTR_STATUS_BOT
    ld hl, #5A60            ; Line 19
    ld de, #5A61
    ld bc, 31
    ld (hl), a
    ldir

    ; 5. Lines 20-23: log (green on blue)
    ld a, ATTR_LOG
    ld hl, #5A80            ; Line 20
    ld de, #5A81
    ld bc, 127              ; 4 lines * 32 - 1 = 127
    ld (hl), a
    ldir

    ; Zero printer-buffer display vars (128K/Next leaves garbage here)
    xor a
    ld (putLogC_coord), a
    ld hl, log_ind_data
    ld b, 8
.clrInd
    ld (hl), a
    inc hl
    djnz .clrInd
    ret

findAddr:
    LD A,D
    AND 7
    RRCA
    RRCA
    RRCA
    OR E
    LD E,A
    LD A,D
    AND 24
    OR #40
    LD D,A
    ret

; ============================================
; calc - Calculate X offset in pixels
; Input:  B = x column (0-41)
; Output: L = byte column (0-31), A = pixel offset (0-7)
; ============================================
calc:
    ld a, b
    add a, a        ; A = B * 2
    add a, b        ; A = B * 3
    ld l, a
    srl l
    srl l           ; L = (B*3)/4 = (B*6)/8 = byte column
    and 3           ; A = (B*3)%4
    add a, a        ; A = ((B*3)%4)*2 = (B*6)%8 = pixel offset
    ret

; gotoXY0 - Set cursor to column 0, row A
; Input: A = row (Y coordinate)
; Destroys: HL
gotoXY0:
    ld h, a
    ld l, 0
    ld (coords), hl
    ret

coords = #5B37  ; In printer buffer (set by gotoXY macro)

; Glyphs are loaded expanded; retain the display initialization entry.
initFontCache:
    xor a
    ld (row_active), a
    ret

; Input: A = ASCII code (32-127, others mapped to space)
; Output: DE = cached 8-byte glyph. Destroys: AF, DE, HL.
fontCharPtr:
    sub 32
    cp 96
    jr c, .valid
    xor a
.valid
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, font_cache
    add hl, de
    ex de, hl
    ret

; Compatibility entry: copy the cached glyph to glyph_buf.
; Input: A = ASCII code. Output: DE = glyph_buf. Destroys: AF, BC, DE, HL.
decompressChar:
    call fontCharPtr
    ld hl, de
    ld de, glyph_buf
    ld bc, 8
    ldir
    ld de, glyph_buf
    ret

glyph_buf: ds 8


; ============================================
; compareStringZ - Compare two zero-terminated strings
; Input: HL, DE = string pointers
; Output: Z=1 if equal, Z=0 if different
; Preserves: HL, DE, BC (BC not touched, HL/DE restored via push/pop)
; ============================================
compareStringZ:
    push hl
    push de
.loop
    ld a, (de)
    cp (hl)
    jr nz, .done            ; mismatch -> cp already set Z=0
    and a
    jr z, .done             ; both zero -> Z=1
    inc hl
    inc de
    jr .loop
.done
    pop de
    pop hl
    ret

; ============================================
; draw_hline - 1-pixel horizontal line across full screen width
; Input: A = row (0-23), E = scanline (0-7), D = attribute
; Destroys: AF, BC, DE, HL
; ============================================
draw_hline:
    push de
    call draw_hline_only
    pop de
    ; Attributes — C = row (preserved by draw_hline_only), D = color
    ld a, c
    call attrCalc           ; HL = attr addr for row C
    ld a, d
    ld b, 32
.attr
    ld (hl), a
    inc l
    djnz .attr
    ret

; draw_hline_only - Pixels only, no attribute change
; Input: A = row (0-23), E = scanline (0-7)
; Destroys: AF, BC, HL. Preserves: C = row
draw_hline_only:
    ld c, a
    and #18
    ld h, a
    ld a, c
    and #07
    rrca
    rrca
    rrca
    ld l, a
    ld a, h
    or #40
    add a, e
    ld h, a
    ld a, #FF
    ld b, 32
.fill
    ld (hl), a
    inc l
    djnz .fill
    ret

; ============================================
; stretchRows01 - Stretch row 0 to double-height across rows 0-1
; Must be called AFTER rendering text/graphics in row 0
; Each scanline is duplicated: top 4 -> row 0, bottom 4 -> row 1
; Destroys: AF, BC, DE, HL
; ============================================
stretchRows01:
    ld hl, #4700
    jr stretchRowPair

stretchRows1819:
    ld hl, #5740
    jr stretchRowPair

stretchRows45:
    ld hl, #4780
    jr stretchRowPair

stretchRows34:
    ld hl, #4760
    ; fall through

; Generic double-height stretch (HL = row scanline 7 address)
; Duplicates top 4 scanlines → bottom half, bottom 4 → next row
stretchRowPair:
    ld d, h : ld e, l
    ld a, e : add a, #20 : ld e, a ; DE = HL + #20 (next row)
    push hl
    call stretchFour
    pop de                         ; DE = original HL (destination, scanline 7)
    ld a, d : sub 4 : ld h, a      ; HL = DE - #400 (scanline 3)
    ld l, e
    ; fall through

stretchFour:
    ld b, 4
.sloop:
    push bc
    push hl
    push de
    ld bc, 32
    ldir                ; copy src -> dst_high
    pop de
    pop hl
    push hl
    dec d               ; dst_low = dst_high - 256
    push de
    ld bc, 32
    ldir                ; copy src -> dst_low (duplicate)
    pop de
    pop hl
    dec h               ; src -= 256
    dec d               ; next dst_high = dst_low - 256
    pop bc
    djnz .sloop
    ret

    endmodule

    macro setLineColor line, color
    ld a, line, c, color
    call Display.setAttr
    endm

    macro gotoXY x, y
    ld hl, x or (y<<8)
    ld (Display.coords), hl
    endm

    macro printMsg ptr
    ld hl, ptr : call Display.putStr
    endm
