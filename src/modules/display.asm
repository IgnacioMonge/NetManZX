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

; Input: A = line number, C = color
; Sets color for entire line (32 columns)
setAttr:
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

    ld de, hl
    inc de
    ld a, c : ld (hl), a
    ld bc, #1f
    ldir
    ret

; Input: A = line number, C = color
; Sets color for first 22 cells only
setAttrPartial:
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


drawC:
    call decompressChar     ; A = char, returns DE = glyph_buf
    push de                 ; save font data ptr
    ld hl, 0
.coords = $ - 2
    ld b, l
    call calc               ; L = byte col, A = pixel offset (0,2,4,6)
    ld (dcb_rot), a         ; save pixel offset (reuses drawCBig's temp)
    ld d, h : ld e, l
    call findAddr
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
    pop ix, de              ; IX = screen addr, DE = glyph_buf
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
    inc ixh
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
    call decompressChar
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
    ; First scanline
    ld a, (ix + 1)
    push hl : ld l, a : ld a, (dcb_m1) : and l : pop hl
    or l : ld (ix + 1), a
    ld a, (ix)
    push hl : ld l, a : ld a, (dcb_m2) : and l : pop hl
    or h : ld (ix), a
    inc ixh
    ; Second scanline (duplicate, H:L intact)
    ld a, (ix + 1)
    push hl : ld l, a : ld a, (dcb_m1) : and l : pop hl
    or l : ld (ix + 1), a
    ld a, (ix)
    push hl : ld l, a : ld a, (dcb_m2) : and l : pop hl
    or h : ld (ix), a
    inc ixh
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
    ld bc, #100             ; Next scanline (+256)
    add hl, bc
    pop bc
    djnz .loopT0

    ; Third 1: lines 8-15 (full middle third, contiguous $4800-$4FFF)
    ld hl, #4800
    ld de, #4801
    ld bc, 2047             ; 2048 bytes - 1
    xor a : ld (hl), a
    ldir

    ; Third 2: lines 16-17 (2 lines)
    ld hl, #5000            ; Scanline 0, line 16
    ld b, 8
.loopT2
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 63               ; 64 bytes (2 lines * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    ld bc, #100
    add hl, bc
    pop bc
    djnz .loopT2
    ret

; Clear network area only (lines 6-15)
clrNetworksOnly:
    ; Third 0: lines 6-7 (2 lines)
    ld hl, #40C0
    ld b, 8                 ; 8 scanlines
.loopN0
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 63               ; 64 bytes (2 lines * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    ld bc, #100
    add hl, bc
    pop bc
    djnz .loopN0

    ; Third 1: lines 8-15 (full middle third, contiguous $4800-$4FFF)
    ld hl, #4800
    ld de, #4801
    ld bc, 2047             ; 2048 bytes - 1
    xor a : ld (hl), a
    ldir

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

; ============================================
; decompressChar - Decompress a character from the packed font
; Input: A = ASCII code (32-127, others mapped to space)
; Output: DE = glyph_buf (8 bytes of decompressed font data)
; Destroys: AF, BC, DE, HL
; ============================================
decompressChar:
    sub 32
    cp 96
    jr c, .valid
    xor a                   ; out of range -> space (index 0)
.valid:
    ld c, a                 ; C = character index (0-95)
    ; HL = font_packed + index * 4
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld de, font_packed
    add hl, de
    ; Unpack 4 bytes -> 8 scanlines via LUT (font_lut is 16-byte aligned)
    ld de, glyph_buf
    push bc                 ; preserve C (char index)
    ld b, 4
.unpack:
    ld a, (hl)
    push hl
    ld c, a                 ; save packed byte
    ld hl, font_lut         ; H = page, L = base (aligned, no page cross)
    ; High nibble -> even scanline
    ld a, c
    rrca : rrca : rrca : rrca
    and #0F
    add a, l : ld l, a     ; HL = &font_lut[high_nibble], H preserved
    ld a, (hl)
    ld (de), a
    inc de
    ; Low nibble -> odd scanline (H still valid)
    ld a, c
    and #0F
    add a, low font_lut : ld l, a  ; reset L to base + low_nibble
    ld a, (hl)
    ld (de), a
    inc de
    pop hl
    inc hl
    djnz .unpack
    pop bc                  ; restore C = char index
    ; Apply exceptions (table sorted by index)
    ld hl, font_exceptions
.excScan:
    ld a, (hl)
    cp #FF
    jr z, .excDone
    cp c
    jr z, .excMatch
    jr nc, .excDone         ; sorted table: if entry > c, done
    inc hl
    inc hl
    inc hl
    jr .excScan
.excMatch:
    inc hl
    ld a, (hl)              ; scanline number (0-7)
    inc hl
    ld b, (hl)              ; actual value
    inc hl
    push hl
    ld hl, glyph_buf
    ld d, 0
    ld e, a
    add hl, de
    ld (hl), b
    pop hl
    jr .excScan
.excDone:
    ld de, glyph_buf
    ret

glyph_buf: ds 8

; ============================================
; Compressed 6px font - 96 characters (ASCII 32-127)
; Format: nibble-packed with 16-value LUT + exception table
; ============================================
    ALIGN 16
font_lut:
    db #00, #0C, #10, #18, #1C, #28, #30, #36, #38, #3C, #4C, #54, #60, #6C, #78, #7C

font_packed:
    db #00, #00, #00, #00  ; ' '
    db #33, #33, #30, #30  ; '!'
    db #DD, #00, #00, #00  ; '"'
    db #55, #F5, #F5, #50  ; '#'
    db #39, #C8, #1E, #60  ; '$'
    db #0D, #13, #36, #70  ; '%'
    db #8D, #87, #DD, #70  ; '&'
    db #33, #00, #00, #00  ; '''
    db #13, #66, #63, #10  ; '('
    db #C6, #33, #36, #C0  ; ')'
    db #02, #B8, #B2, #00  ; '*'
    db #02, #2F, #22, #00  ; '+'
    db #00, #00, #00, #36  ; ','
    db #00, #0F, #00, #00  ; '-'
    db #00, #00, #00, #30  ; '.'
    db #11, #33, #36, #60  ; '/'
    db #8D, #DF, #DD, #80  ; '0'
    db #38, #33, #33, #30  ; '1'
    db #8D, #13, #6C, #F0  ; '2'
    db #8D, #13, #1D, #80  ; '3'
    db #14, #9D, #F1, #10  ; '4'
    db #FC, #E1, #1D, #80  ; '5'
    db #8C, #CE, #DD, #80  ; '6'
    db #F1, #33, #36, #60  ; '7'
    db #8D, #D8, #DD, #80  ; '8'
    db #8D, #D9, #13, #60  ; '9'
    db #00, #30, #00, #30  ; ':'
    db #00, #30, #00, #36  ; ';'
    db #01, #36, #63, #10  ; '<'
    db #00, #F0, #F0, #00  ; '='
    db #0C, #63, #36, #C0  ; '>'
    db #8D, #13, #60, #60  ; '?'
    db #30, #AB, #BA, #03  ; '@'
    db #28, #DF, #DD, #D0  ; 'A'
    db #ED, #DE, #DD, #E0  ; 'B'
    db #8D, #CC, #CD, #80  ; 'C'
    db #ED, #DD, #DD, #E0  ; 'D'
    db #FC, #CE, #CC, #F0  ; 'E'
    db #FC, #CE, #CC, #C0  ; 'F'
    db #8D, #CD, #DD, #90  ; 'G'
    db #DD, #DF, #DD, #D0  ; 'H'
    db #93, #33, #33, #90  ; 'I'
    db #11, #11, #1D, #80  ; 'J'
    db #DD, #DE, #DD, #D0  ; 'K'
    db #CC, #CC, #CC, #F0  ; 'L'
    db #0D, #FF, #DD, #D0  ; 'M'
    db #AD, #FF, #FD, #00  ; 'N'
    db #8D, #DD, #DD, #80  ; 'O'
    db #ED, #DE, #CC, #C0  ; 'P'
    db #8D, #DD, #DD, #81  ; 'Q'
    db #ED, #DE, #DD, #D0  ; 'R'
    db #8D, #C8, #1D, #80  ; 'S'
    db #93, #33, #33, #30  ; 'T'
    db #DD, #DD, #DD, #80  ; 'U'
    db #DD, #DD, #D8, #20  ; 'V'
    db #DD, #DF, #FD, #00  ; 'W'
    db #DD, #D8, #DD, #D0  ; 'X'
    db #DD, #D8, #66, #60  ; 'Y'
    db #F1, #36, #CC, #F0  ; 'Z'
    db #86, #66, #66, #80  ; '['
    db #66, #33, #31, #10  ; '\'
    db #83, #33, #33, #80  ; ']'
    db #F0, #52, #28, #FF  ; '^' → hourglass (scanning indicator)
    db #00, #00, #00, #00  ; '_'
    db #08, #FF, #FF, #80  ; '`' → filled circle (lock indicator)
    db #00, #81, #9D, #90  ; 'a'
    db #CC, #ED, #DD, #E0  ; 'b'
    db #00, #8D, #CD, #80  ; 'c'
    db #11, #9D, #DD, #90  ; 'd'
    db #00, #8D, #FC, #80  ; 'e'
    db #46, #F6, #66, #60  ; 'f'
    db #00, #9D, #D9, #1E  ; 'g'
    db #CC, #ED, #DD, #D0  ; 'h'
    db #30, #83, #33, #30  ; 'i'
    db #30, #33, #33, #30  ; 'j'
    db #CC, #DD, #ED, #D0  ; 'k'
    db #66, #66, #66, #30  ; 'l'
    db #00, #0F, #FD, #D0  ; 'm'
    db #00, #ED, #DD, #D0  ; 'n'
    db #00, #8D, #DD, #80  ; 'o'
    db #00, #ED, #DD, #EC  ; 'p'
    db #00, #9D, #DD, #91  ; 'q'
    db #00, #D0, #CC, #C0  ; 'r'
    db #00, #9C, #81, #E0  ; 's'
    db #26, #F6, #66, #40  ; 't'
    db #00, #DD, #DD, #90  ; 'u'
    db #00, #DD, #D8, #20  ; 'v'
    db #00, #DD, #FD, #00  ; 'w'
    db #00, #DD, #8D, #D0  ; 'x'
    db #00, #DD, #D8, #6C  ; 'y'
    db #00, #F3, #6C, #F0  ; 'z'
    db #00, #F8, #20, #00  ; '{' → down arrow (scroll indicator)
    db #33, #33, #33, #30  ; '|'
    db #00, #28, #F0, #00  ; '}' → up arrow (scroll indicator)
    db #08, #00, #00, #80  ; '~' → hollow circle (open network, 6 rows)
    db #FF, #FF, #FF, #FF  ; DEL → cursor block (0x7C solid)

font_exceptions:
    db 32, 1, #24  ; '@' line 1
    db 32, 6, #20  ; '@' line 6
    db 45, 0, #44  ; 'M' line 0
    db 46, 6, #64  ; 'N' line 6
    db 55, 6, #44  ; 'W' line 6
    db 62, 1, #44  ; '^' line 1 (hourglass: X...X)
    db 63, 7, #7E  ; '_' line 7
    db 74, 7, #70  ; 'j' line 7
    db 77, 2, #68  ; 'm' line 2
    db 82, 3, #70  ; 'r' line 3
    db 87, 6, #44  ; 'w' line 6
    db 94, 2, #44  ; '~' line 2 (hollow circle)
    db 94, 3, #44  ; '~' line 3 (hollow circle)
    db 94, 4, #44  ; '~' line 4 (hollow circle)
    db 94, 5, #44  ; '~' line 5 (hollow circle)
    db #FF          ; end of table

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
    jr nz, .diff
    and a
    jr z, .done             ; both zero -> Z=1, CF=0
    inc hl
    inc de
    jr .loop
.diff
    or 1                    ; Z=0, CF=0 (fixes false equality on prefix match)
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
    ; Attributes
    ld a, c
    ld l, 0
    srl a : rr l
    srl a : rr l
    srl a : rr l
    or #58
    ld h, a
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
    pop hl
    ld d, h : ld e, l              ; DE = original HL (destination)
    ld a, h : sub 4 : ld h, a      ; HL -= #400 (scanline 3)
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
