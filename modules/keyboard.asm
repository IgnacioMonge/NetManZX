    module Keyboard
BASIC_KEY = #5C08
KEY_BS = 12
KEY_UP = 11
KEY_DN = 10

; Verifica si BREAK está pulsado (CAPS SHIFT + SPACE)
; Devuelve: Z=1 si BREAK pulsado, Z=0 si no
checkBreak:
    ld a, #7F               ; Fila SPACE (B-SPACE)
    in a, (#FE)
    bit 0, a                ; SPACE es bit 0
    ret nz                  ; No pulsado, Z=0
    ld a, #FE               ; Fila CAPS SHIFT (SHIFT-V)
    in a, (#FE)
    bit 0, a                ; CAPS SHIFT es bit 0
    ret                     ; Z=1 si ambos pulsados

; Lectura bloqueante - espera hasta que haya tecla
inKey:
    ld a,(BASIC_KEY)
    and a : jr z, inKey
    ld c, a
    xor a : ld (BASIC_KEY),a
    ld a, c
    ret

; Lectura no bloqueante - devuelve 0 si no hay tecla
inKeyNoWait:
    ld a,(BASIC_KEY)
    and a
    ret z               ; Sin tecla, devolver 0
    ld c, a
    xor a : ld (BASIC_KEY),a
    ld a, c
    ret

    endmodule