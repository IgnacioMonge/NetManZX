    module Keyboard
BASIC_KEY = #5C08
KEY_BS = 12
KEY_UP = 11
KEY_DN = 10

; Checks if BREAK is pressed (CAPS SHIFT + SPACE)
; Returns: Z=1 if BREAK pressed, Z=0 if not
checkBreak:
    ld a, #7F               ; SPACE row (B-SPACE)
    in a, (#FE)
    bit 0, a                ; SPACE is bit 0
    ret nz                  ; Not pressed, Z=0
    ld a, #FE               ; CAPS SHIFT row (SHIFT-V)
    in a, (#FE)
    bit 0, a                ; CAPS SHIFT is bit 0
    ret                     ; Z=1 if both pressed

; Blocking read - waits until a key is available (sync 50Hz)
inKey:
    halt
    call inKeyNoWait
    and a
    jr z, inKey
    ret

; Non-blocking read - returns 0 if no key available
inKeyNoWait:
    ld hl, BASIC_KEY
    ld a, (hl)
    and a
    ret z               ; No key, return 0
    ld (hl), 0          ; Clear immediately
    ret

    endmodule