    module UartImpl
UART_DATA_REG = #c6
UART_STAT_REG = #c7
UART_BYTE_RECIVED = #80
UART_BYTE_SENDING = #40
ZXUNO_ADDR = #FC3B
ZXUNO_REG = #FD3B
init:
    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a
    ld bc, ZXUNO_REG : in A, (c)
    ld bc, ZXUNO_ADDR : ld a, UART_DATA_REG : out (c), a
    ld bc, ZXUNO_REG : in A, (c)

    ; Brief startup wait and RX garbage drain.
    ; Important: no logging here (too expensive) to avoid byte loss
    ; on fast backends (115200).
    ei
    ld b,50
.drain
    push bc
    call uartRead           ; discard (if any)
    pop bc
    halt
    djnz .drain

    ; Additional bounded drain
    ld bc, #0800
.flush
    push bc
    call uartRead           ; discard (if any)
    pop bc
    dec bc
    ld a,b : or c
    jr nz, .flush
    ret

write:
    push bc
    push hl
    push af
    ld hl, Uart.DEFAULT_TIMEOUT
    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a
    ld bc, ZXUNO_REG : in A, (c) : and UART_BYTE_RECIVED
    jr nz, .is_recvF
.checkSent
    ld bc, ZXUNO_REG : in A, (c) : and UART_BYTE_SENDING
    jr z, .send
    dec hl
    ld a, h : or l
    jr nz, .checkSent
    ld a, 1
    ld (Uart.io_error), a
    pop af, hl, bc
    ret

.send
    ld bc, ZXUNO_ADDR : ld a, UART_DATA_REG : out (c), a

    ld bc, ZXUNO_REG : pop af : out (c), a
    pop hl, bc
    ret
.is_recvF
    ld a, (is_recv)
    and a
    jr nz, .checkSent
    ; Read incoming byte NOW before it's lost
    ld bc, ZXUNO_ADDR : ld a, UART_DATA_REG : out (c), a
    ld bc, ZXUNO_REG : in a, (c)
    ld (byte_buff), a
    ld a, 1 : ld (is_recv), a
    ; Restore status register selection before checking TX busy
    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a
    jr .checkSent


; Read byte from UART
; A: byte
; CF=1 if a byte was read, CF=0 if no data
uartRead:
    ld a, (is_recv)
    and a
    jr nz, recvRet

    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a
    inc b : in a, (c) : and UART_BYTE_RECIVED
    jr nz, retReadByte

    or a
    ret

retReadByte:
    dec b : ld a, UART_DATA_REG : out (c), a
    inc b : in a, (c)

    scf
    ret

recvRet:
    xor a : ld (is_recv), a
    ld a, (byte_buff)
    scf
    ret


byte_buff defb 0
is_recv defb 0

    endmodule
