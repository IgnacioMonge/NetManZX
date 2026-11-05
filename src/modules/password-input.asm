; Shared masked line editor. Included inside the platform UI module.
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
    push bc : ld a, '*' : call Display.decompressChar : pop bc
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
    push bc : ld a, '*' : call Display.decompressChar : pop bc
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
; Position screen cursor at column B, row pass_line
.piSetPos
    ld a, (pass_line) : ld h, a
    ld l, b
    ld (Display.coords), hl
    ret

; Draw char from buffer at position B (* or real depending on show_password)
.piDrawBufAt
    call .piSetPos
.piDrawBuf
    ld a, (show_password) : and a
    jr nz, .piDrawReal
    ld a, '*'
    jp Display.putCBig
.piDrawReal
    ld hl, pass_buffer : ld d, 0 : ld e, b : add hl, de
    ld a, (hl)
    jp Display.putCBig

; Draw buffer position B one cell to the right of the cursor
.piDrawBufRightAt
    inc b
    call .piSetPos
    dec b
    jr .piDrawBuf

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

; --- Cursor left (drain ghost '5' from ROM, then repaint two cells) ---
.piLeft ld a, (pass_cursor) : and a : jp z, .piWait
    dec a : ld (pass_cursor), a
    halt : call Keyboard.inKeyNoWait
    ld a, (pass_cursor) : ld b, a
    call .piDrawCurAt
    ld a, (pass_cursor) : ld b, a
    call .piDrawBufRightAt
    jp .piWait

; --- Cursor right (drain ghost '8' from ROM, then repaint two cells) ---
.piRight
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : cp b : jp z, .piWait
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    halt : call Keyboard.inKeyNoWait
    ld a, (pass_cursor) : dec a : ld b, a
    call .piDrawBufAt
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

