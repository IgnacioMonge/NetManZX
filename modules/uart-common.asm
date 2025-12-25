    module Uart

; Timeout por defecto (~1.6 segundos a 3.5MHz)
DEFAULT_TIMEOUT = #8000
; Timeout largo para conexión WiFi (~10 segundos)
LONG_TIMEOUT = #FFFF

init:
    ; Mensaje movido a main.asm para control de flujo
    call UartImpl.init
    ret

write:
    push af
    call UartImpl.write
    pop af
    push af                 ; Guardar byte para log
    ld a, (log_enabled)
    and a
    jr z, .skipLog
    pop af
    jp Display.putLogC
.skipLog
    pop af
    ret
  

writeStringZ:
    push hl
    call Display.putStrLog
    pop hl
.loop
    ld a,(hl) : and a : ret z
    push hl
    call UartImpl.write
    pop hl
    inc hl
    jr .loop

; Lectura bloqueante (compatibilidad)
read:
    call UartImpl.read
    push af
    call Display.putLogC
    pop af
    ret

; Lectura con timeout normal
; Salida: A = byte leído, CF=1 si éxito
;         CF=0 si timeout
readTimeout:
    push bc, de, hl
    ld de, DEFAULT_TIMEOUT
    jr readTimeoutCommon

; Lectura con timeout largo (para conexión WiFi)
; Salida: A = byte leído, CF=1 si éxito
;         CF=0 si timeout
readTimeoutLong:
    push bc, de, hl
    ld de, LONG_TIMEOUT
    ; Fall through to readTimeoutCommon

readTimeoutCommon:
.loop
    call UartImpl.uartRead  ; Lectura no bloqueante
    jr c, .got_byte
    
    ; Pequeño delay para no saturar
    ld b, 4
.delay
    djnz .delay
    
    dec de
    ld a, d
    or e
    jr nz, .loop
    
    ; Timeout
    pop hl, de, bc
    or a                ; CF = 0
    ret

.got_byte
    push af                 ; Guardar byte leído PRIMERO
    ld a, (log_enabled)
    and a
    jr z, .skipLog
    pop af                  ; Recuperar para mostrar
    push af                 ; Volver a guardar
    call Display.putLogC
.skipLog
    pop af                  ; Recuperar byte leído
    pop hl, de, bc
    scf                 ; CF = 1, éxito
    ret

; Variables al final (después del código)
log_enabled db 1

    endmodule
