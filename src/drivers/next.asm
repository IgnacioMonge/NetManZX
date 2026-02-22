    module UartImpl
; Definiciones de puertos del ZX Spectrum Next
UART_TX = #133B
UART_RX = #143B
UART_Sel  equ #153B       ; Selects between ESP and Pi
UART_SetBaud equ #143B    ; Sets baudrate (when writing)
UART_GetStatus equ #133B  ; Reads status

; Bits de estado
UART_TX_BUSY       equ %00000010
UART_RX_DATA_READY equ %00000001
UART_FIFO_FULL     equ %00000100

init:
    ; Seleccionar UART
    ld bc, UART_Sel
    ld a, %00100000      ; Select UART (bit 5=1)
    out (c), a
    
    ; Cálculo de timing para Next
    ld hl, .table
    ld bc, 9275
    ld a, 17
    out (c), a
    ld bc, 9531
    in a, (c)
    ld e, a
    rlc e
    ld d, 0
    add hl, de

    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl

    ; Set Baud Rate
    ld bc, UART_SetBaud
    ld a, l
    and %01111111
    out (c), a           ; Low 7 bits
    ld a, h
    rl l
    rla
    or %10000000
    out (c), a           ; High 7 bits

    ret

.table
    dw 243,248,256,260,269,278,286,234

write:
    ld d, a
    ld bc, UART_GetStatus
.wait
    in a, (c)
    and UART_TX_BUSY
    jr nz, .wait         ; Esperar si TX está ocupado
    out (c), d
    ret

; -----------------------------------------------------------------
; uartRead / read
; Lee un byte del UART de forma NO BLOQUEANTE.
; Salida:
;   CF = 1 : Byte leído en A
;   CF = 0 : No hay datos disponibles (retorno inmediato)
; -----------------------------------------------------------------
read:                        ; Alias para compatibilidad
uartRead:
    ld bc, UART_GetStatus
    in a, (c)
    rrca                 ; Bit 0 (Data Ready) al Carry
    ret nc               ; No hay datos -> Retorno inmediato con CF=0

    ; Si hay datos:
    ld bc, UART_RX
    in a, (c)            ; Leer el byte
    scf                  ; Marcar éxito (CF=1)
    ret

;; HL - buffptr
;; DE - size
;; Nota: Esta rutina es bloqueante por diseño (lee un bloque entero)
readBlock:
    call uartRead
    jr nc, readBlock     ; Esperar hasta que llegue un byte
    
    ld (hl), a
    inc hl
    dec de
    ld a, d
    or e
    ret z
    jr readBlock

    endmodule
