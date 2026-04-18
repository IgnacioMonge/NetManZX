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
    ld hl, baudTable
    ; Fall through to setBaudFromTable

; Shared baud rate setup (HL = prescaler table)
setBaudFromTable:
    di
    ld bc, 9275
    ld a, 17
    out (c), a
    ld bc, 9531
    in a, (c)            ; atomic NextReg select+read pair
    ei
    ld e, a
    rlc e
    ld d, 0
    add hl, de
    ld e, (hl)
    inc hl
    ld d, (hl)
    ex de, hl
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

baudTable:
    dw 243,248,256,260,269,278,286,234

write:
    push bc, de
    ld d, a
    ld bc, UART_GetStatus
.wait
    in a, (c)
    and UART_TX_BUSY
    jr nz, .wait         ; Wait if TX is busy
    out (c), d
    pop de, bc
    ret

; ============================================
; uartRead
; Reads a byte from UART in NON-BLOCKING mode.
; Output:
;   CF = 1 : Byte read in A
;   CF = 0 : No data available (immediate return)
; ============================================
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

; ============================================
; baudScan - Try common baud rates to find ESP
; Returns: CF=0 found (UART at detected rate), CF=1 not found
; ============================================
baudScan:
    ld hl, .scanPtrs
    ld b, .scanEnd - .scanPtrs
    srl b                       ; B = number of entries (ptr count / 2)
.loop:
    push bc, hl
    ld e, (hl) : inc hl : ld d, (hl)
    ex de, hl
    call setBaudFromTable       ; set UART to this baud rate
    call Wifi.flushInput
    ld hl, Wifi.S_AT : call Wifi.espSendZ
    call Wifi.checkOkErr
    pop hl, bc
    ret nc                      ; CF=0 — ESP responded
    inc hl : inc hl
    djnz .loop
    ; Not found — restore 115200 before giving up
    ld hl, baudTable
    call setBaudFromTable
    scf                         ; CF=1 — not found at any rate
    ret

.scanPtrs:
    dw baudTableFast            ; 1152000 (NextSync)
    dw baudTable2M              ; 2000000 (NextSync fast)
    dw baudTable9600            ; 9600 (factory default)
    dw baudTable57600           ; 57600 (some firmwares)
.scanEnd:

; Prescaler tables (8 entries = ZX48,ZX128,Pentagon,+2A/+3,HDMI,VGA0,VGA1,VGA2)
baudTableFast:                  ; 1152000
    dw 24,25,26,26,27,28,29,23
baudTable9600:
    dw 2917,2976,3069,3125,3229,3333,3438,2813
baudTable57600:
    dw 486,496,512,521,538,556,573,469
baudTable2M:                    ; 2000000 (NextSync fast)
    dw 14,14,15,15,15,16,16,13

; ============================================
; espHardReset - Hardware ESP reset via NextReg $02
; Forces ESP to reboot at its default baud (115200).
; Last resort when baudScan can't find the ESP.
; ============================================
espHardReset:
    ld bc, $243B        ; NextReg Select
    ld a, $02           ; Reset register
    out (c), a
    ld bc, $253B        ; NextReg Data
    ld a, 128           ; Bit 7 = ESP reset
    out (c), a
    ld b, 25            ; ~500ms hold
.rstWait:
    halt
    djnz .rstWait
    ld bc, $243B
    ld a, $02
    out (c), a
    ld bc, $253B
    xor a               ; Release reset
    out (c), a
    ld b, 150           ; ~3s for ESP boot
.bootWait:
    halt
    djnz .bootWait
    ret

    endmodule
