    module Keyboard
BASIC_KEY = #5C08
KEY_BS = 12
KEY_UP = 11
KEY_DN = 10
KEY_LEFT = 8
KEY_RIGHT = 9

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
    ret nz                  ; Not pressed (just SPACE alone), Z=0
    ; BREAK detected - clear stale SPACE from ROM buffer
    xor a
    ld (BASIC_KEY), a
    ret                     ; A=0, Z=1

; Prevent a held cancellation chord from acting on the next screen.
waitBreakRelease:
    call checkBreak
    ret nz
    halt
    jr waitBreakRelease

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

; Audible click for key feedback (~3.4 kHz, ~2.3 ms)
; Preserves all registers
keyClick:
    push af, bc
    ld b, 8
.kc:
    ld a, #10 : out (#FE), a
    ld c, 32
.on: dec c : jr nz, .on
    xor a : out (#FE), a
    ld c, 32
.off: dec c : jr nz, .off
    djnz .kc
    pop bc, af
    ret

    endmodule
