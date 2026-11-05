    module Display64

; 64-column renderer: one 3x6 glyph in each 4x8 pixel cell.
; The padding scanlines and spaces are opaque, so overwriting always erases
; the complete cell. The other nibble in the byte is preserved.

; Input: A = row (0-23). Destroys: HL.
gotoXY0:
    ld h, a
    ld l, 0
    ld (coords), hl
    ret

; Input: HL = zero-terminated string. Destroys: AF, BC, DE, HL.
putStr:
    ld a, (hl)
    and a
    ret z
    push hl
    call putC
    pop hl
    inc hl
    jr putStr

; Input: A = ASCII character. Advances and wraps at column 64.
; Destroys: AF, BC, DE, HL.
putC:
    cp 13
    jr z, .cr
    ld hl, (coords)
    ld (drawC.coords), hl
    call drawC
    ld hl, coords
    inc (hl)
    ld a, (hl)
    cp 64
    ret c
.cr
    ld hl, coords
    xor a
    ld (hl), a
    inc hl
    inc (hl)
    ret

; Input: A = ASCII character (32-127; other values map to space).
; Coordinates are stored in drawC.coords as column,row.
; Destroys: AF, BC, DE, HL.
drawC:
    sub 32
    cp 96
    jr c, .valid
    xor a
.valid
    ld e, a
    ld d, 0
    ld l, e
    ld h, d
    add hl, hl
    add hl, de
    ld de, font64_packed
    add hl, de
    push hl

    ld hl, 0
.coords = $ - 2
    ld a, l
    srl a
    ld e, a
    ld d, h
    ld a, (Display.row_active)
    and a
    jr z, .screenTarget
    ld l, e
    ld h, 0
    ld de, Display.row_buffer
    add hl, de
    jr .targetReady
.screenTarget
    call Display.findAddr
    ex de, hl
.targetReady
    ld (font64_addr), hl
    pop hl

    push hl
    ld c, 0
    call writePattern
    pop hl

    ld b, 3
.byteLoop
    ld a, (hl)
    inc hl
    push hl
    push bc
    push af
    rrca
    rrca
    rrca
    rrca
    and #0F
    call font64Lookup
    call writePattern
    pop af
    and #0F
    call font64Lookup
    call writePattern
    pop bc
    pop hl
    djnz .byteLoop

    ld c, 0
    jp writePattern

; Input: C = duplicated nibble pattern. Destroys: AF, DE, HL.
writePattern:
    ld hl, (font64_addr)
    ld a, (drawC.coords)
    bit 0, a
    jr nz, .right
    ld a, c
    and #F0
    ld c, a
    ld a, (hl)
    and #0F
    or c
    ld (hl), a
    jr .next
.right
    ld a, c
    and #0F
    ld c, a
    ld a, (hl)
    and #F0
    or c
    ld (hl), a
.next
    call nextScan
    ld (font64_addr), hl
    ret

; Input: A = packed row index. Output: C = duplicated nibble pattern.
; Destroys: DE, HL.
font64Lookup:
    ld e, a
    ld d, 0
    ld hl, font64_lut
    add hl, de
    ld c, (hl)
    ret

; Input/output: HL = target address. Destroys: AF, DE.
nextScan:
    ld a, (Display.row_active)
    and a
    jr nz, .buffered
    inc h
    ret
.buffered
    ld de, 32
    add hl, de
    ret

coords:         dw 0
font64_addr:    dw 0

font64_lut:
    db #00,#22,#44,#55,#66,#88,#AA,#CC,#EE,#FF

; ASCII 32-127, three bytes per glyph (two 3-bit rows per byte).
font64_packed:
    db #00,#00,#00,#55,#55,#05,#06,#60,#00,#06,#86,#86,#28,#58,#18,#61
    db #47,#56,#26,#26,#74,#25,#00,#00,#25,#55,#52,#52,#22,#25,#06,#28
    db #26,#02,#28,#22,#00,#02,#25,#00,#08,#00,#00,#00,#77,#11,#22,#55
    db #26,#68,#62,#27,#22,#28,#26,#12,#58,#81,#21,#62,#56,#68,#11,#85
    db #71,#17,#45,#76,#62,#81,#12,#22,#26,#26,#62,#26,#64,#17,#00,#50
    db #05,#02,#02,#25,#01,#25,#21,#00,#80,#80,#05,#21,#25,#26,#12,#02
    db #26,#88,#52,#26,#68,#66,#76,#76,#67,#45,#55,#54,#76,#66,#67,#85
    db #75,#58,#85,#75,#55,#26,#58,#62,#66,#86,#66,#82,#22,#28,#41,#11
    db #62,#66,#87,#66,#55,#55,#58,#68,#88,#66,#86,#66,#66,#26,#66,#62
    db #76,#67,#55,#26,#66,#74,#76,#67,#66,#45,#21,#62,#82,#22,#22,#66
    db #66,#68,#66,#66,#62,#66,#88,#82,#66,#26,#66,#66,#62,#22,#81,#22
    db #58,#75,#55,#57,#55,#22,#11,#72,#22,#27,#86,#22,#68,#00,#00,#09
    db #28,#88,#82,#07,#14,#64,#55,#76,#67,#04,#55,#54,#11,#46,#64,#02
    db #68,#54,#26,#57,#55,#46,#64,#17,#55,#76,#66,#20,#72,#28,#10,#41
    db #62,#55,#67,#66,#55,#55,#62,#06,#88,#66,#07,#66,#66,#02,#66,#62
    db #07,#67,#55,#04,#64,#11,#04,#55,#55,#04,#52,#17,#28,#22,#21,#06
    db #66,#68,#06,#66,#62,#06,#88,#82,#06,#26,#66,#06,#64,#17,#08,#12
    db #58,#08,#82,#00,#78,#99,#90,#00,#28,#80,#26,#66,#62,#99,#99,#99
font64_packed_end:
    ASSERT font64_packed_end - font64_packed == 96 * 3

    endmodule
