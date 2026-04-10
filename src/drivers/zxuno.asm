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
1
    push bc
    call uartRead           ; discard (if any)
    pop bc
    halt
    djnz 1b

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
    push af
    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a
    ld bc, ZXUNO_REG : in A, (c) : and UART_BYTE_RECIVED
    jr nz, .is_recvF
.checkSent
    ld bc, ZXUNO_REG : in A, (c) : and UART_BYTE_SENDING
    jr nz, .checkSent

    ld bc, ZXUNO_ADDR : ld a, UART_DATA_REG : out (c), a

    ld bc, ZXUNO_REG : pop af : out (c), a
    pop bc
    ret
.is_recvF
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
; B:
;     1 - Was read
;     0 - Nothing to read
uartRead:
    ld a, (poked_byte) : and 1 : jr nz, .retBuff

    ld a, (is_recv) : and 1 : jr nz, recvRet

    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a
    ld bc, ZXUNO_REG : in a, (c) : and UART_BYTE_RECIVED
    jr nz, retReadByte

    or a
    ret
.retBuff
    ld a, 0 : ld (poked_byte), a : ld a, (byte_buff)
    scf 
    ret

retReadByte:
    xor a : ld (poked_byte), a : ld (is_recv), a

    ld bc, ZXUNO_ADDR : ld a, UART_DATA_REG : out (c), a
    ld bc, ZXUNO_REG : in a, (c)

    scf
    ret

recvRet:
    xor a : ld (is_recv), a : ld (poked_byte), a
    ld a, (byte_buff)
    scf
    ret


poked_byte defb 0
byte_buff defb 0
is_recv defb 0

    endmodule