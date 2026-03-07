    module Uart

; Timeout por defecto - Next necesita más porque su CPU es más rápida
    IFDEF NEXT
DEFAULT_TIMEOUT = #FFFF          ; Next: timeout máximo 16-bit
    ELSE
DEFAULT_TIMEOUT = #8000          ; UNO/divMMC: (~1.6s a 3.5MHz)
    ENDIF

; Timeout largo: se implementa como varios bloques para tolerar pausas
; largas (JOIN/DHCP/SCAN) sin declarar timeout prematuro.
; Next tiene CPU más rápida, necesita más repeticiones
LONG_TIMEOUT_BLOCK = #FFFF
    IFDEF NEXT
LONG_TIMEOUT_REPS  = 80          ; Next: CPU más rápida, necesita más tiempo
    ELSE
LONG_TIMEOUT_REPS  = 8           ; UNO/divMMC: valor original
    ENDIF

; Timeout medio: para lectura de datos en curso (ej: scan)
    IFDEF NEXT
MEDIUM_TIMEOUT = #FFFF           ; Next: timeout máximo 16-bit
    ELSE
MEDIUM_TIMEOUT = #8000           ; UNO/divMMC: igual que default
    ENDIF

init:
    ; Mensaje movido a main.asm para control de flujo
    call UartImpl.init
    ; Inicializar buffer de log (modo linea)
    ld hl, log_buf
    ld (log_ptr), hl
    xor a
    ld (log_overflow), a
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
    push af
    call log_char
.skipLog
    pop af
    ret
  

; Lectura con timeout normal
; Salida: A = byte leído, CF=1 si éxito
;         CF=0 si timeout
readTimeout:
    push bc, de, hl
    ld de, DEFAULT_TIMEOUT
    call poll_block
    jr c, got_byte
    ; Timeout
    pop hl, de, bc
    or a
    ret

; Lectura con timeout medio (para datos en curso, ej: scan)
; Salida: A = byte leído, CF=1 si éxito
;         CF=0 si timeout
readTimeoutMedium:
    push bc, de, hl
    ld de, MEDIUM_TIMEOUT
    call poll_block
    jr c, got_byte
    ; Timeout
    pop hl, de, bc
    or a
    ret

; Lectura con timeout largo (para conexión WiFi)
; Salida: A = byte leído, CF=1 si éxito
;         CF=0 si timeout
readTimeoutLong:
    push bc, de, hl
    ld b, LONG_TIMEOUT_REPS
.outer
    ld de, LONG_TIMEOUT_BLOCK
    call poll_block
    jr c, got_byte
    djnz .outer
    ; Timeout total
    pop hl, de, bc
    or a
    ret

; ------------------------------------------------------------
; poll_block
;   Entrada: DE = contador
;   Salida:  CF=1 si hay byte (A=byte), CF=0 si timeout
; ------------------------------------------------------------
poll_block:
.loop
    call UartImpl.uartRead
    ret c

    ; Pequeño delay para no saturar
    ld a, 4
.delay
    dec a
    jr nz, .delay

    dec de
    ld a, d
    or e
    jr nz, .loop
    or a
    ret

got_byte
    push af                 ; Guardar byte leído PRIMERO
    ld a, (log_enabled)
    and a
    jr z, .skipLog
    pop af                  ; Recuperar para mostrar
    push af                 ; Volver a guardar
    call log_char
.skipLog
    pop af                  ; Recuperar byte leído
    pop hl, de, bc
    scf                 ; CF = 1, éxito
    ret

; ------------------------------------------------------------
; Log modo linea
;   Acumula bytes en log_buf y vuelca en Display.putStrLog al ver LF.
;   Mantiene CR/LF (si CR llega antes de LF se almacena igual).
; ------------------------------------------------------------
LOG_BUF_SIZE = 160

log_char:
    push bc, hl, de
    ld c, a

    ld hl, (log_ptr)
    ld de, log_buf + (LOG_BUF_SIZE - 2)
    or a
    sbc hl, de
    jr c, .have_space

    ; Sin espacio: marcar overflow y forzar flush cuando llegue LF
    ld a, 1
    ld (log_overflow), a
    jr .maybe_flush

.have_space
    ld a, c
    ld hl, (log_ptr)
    ld (hl), a
    inc hl
    ld (log_ptr), hl

.maybe_flush
    ld a, c
    cp 10                    ; LF
    jr nz, .done
    call log_flush
.done
    pop de, hl, bc
    ret

log_flush:
    push af, hl
    ld hl, (log_ptr)
    xor a
    ld (hl), a               ; Zero-terminate
    ld hl, log_buf
    call Display.putStrLog
    ld hl, log_buf
    ld (log_ptr), hl
    xor a
    ld (log_overflow), a
    pop hl, af
    ret

; Reinicia el buffer de log (descarta linea parcial). Util para mutear log en medio
; de un comando multipart (p. ej. AT+CWJAP) sin mezclar contenidos.
logReset:
    ld hl, log_buf
    ld (log_ptr), hl
    xor a
    ld (log_overflow), a
    ret

; Variables al final (después del código)
; Por defecto activado: ahora es log por lineas (mucho mas ligero).
log_enabled  db 1
log_overflow db 0
log_ptr      dw 0
    RTVAR log_buf, LOG_BUF_SIZE

    endmodule
