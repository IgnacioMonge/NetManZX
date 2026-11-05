; Shared acknowledgement prompt. Included inside the platform UI module.
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

