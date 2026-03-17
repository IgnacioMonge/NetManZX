    module UartImpl
; ZX Spectrum Next port definitions
UART_TX = #133B
UART_RX = #143B
UART_Sel  equ #153B       ; Selects between ESP and Pi
UART_SetBaud equ #143B    ; Sets baudrate (when writing)
UART_GetStatus equ #133B  ; Reads status

; Status bits
UART_TX_BUSY       equ %00000010
UART_RX_DATA_READY equ %00000001
UART_FIFO_FULL     equ %00000100

init:
    ; Select UART
    ld bc, UART_Sel
    ld a, %00100000      ; Select UART (bit 5=1)
    out (c), a
    
    ; Timing calculation for Next
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
    jr nz, .wait         ; Wait if TX is busy
    out (c), d
    ret

; -----------------------------------------------------------------
; uartRead / read
; Reads a byte from UART in NON-BLOCKING mode.
; Output:
;   CF = 1 : Byte read in A
;   CF = 0 : No data available (immediate return)
; -----------------------------------------------------------------
read:                        ; Alias for compatibility
uartRead:
    ld bc, UART_GetStatus
    in a, (c)
    rrca                 ; Bit 0 (Data Ready) to Carry
    ret nc               ; No data -> Immediate return with CF=0

    ; Data available:
    ld bc, UART_RX
    in a, (c)            ; Read the byte
    scf                  ; Mark success (CF=1)
    ret

; -----------------------------------------------------------------
; tryFastBaud - Temporarily switches UART to ~1152000 baud
; For recovery if NextSync left the ESP at high speed.
; After use, call init to restore 115200.
; -----------------------------------------------------------------
tryFastBaud:
    ; Detect core type (same as init)
    ld hl, .tableFast
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
    ; Set baud rate (same sequence as init)
    ld bc, UART_SetBaud
    ld a, l
    and %01111111
    out (c), a
    ld a, h
    rl l
    rla
    or %10000000
    out (c), a
    ret

; Prescaler for ~1152000 baud (115200 table / 10)
.tableFast
    dw 24,25,26,26,27,28,29,23

    endmodule
