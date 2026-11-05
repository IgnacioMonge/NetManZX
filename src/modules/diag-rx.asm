; Shared diagnostic UART reader, included inside module UI.
; AY TAP keeps this byte loop resident to avoid ULA fetch contention.

; Buffer for diagnostic responses
    RTVAR diag_buffer, 64
DIAG_ROW_LIMIT = 16             ; Rows 0-15 may start diagnostic output
    IFDEF AY
DIAG_READ_INITIAL  = #00E0      ; ~1s
DIAG_READ_TAIL     = #001C      ; ~125ms
    ELSE
DIAG_READ_INITIAL  = #FFFF
DIAG_READ_TAIL     = #2000
    ENDIF
diag_line       = #5B1E         ; In printer buffer (set before use)

; Drain UART buffer and clear the transport latch at transaction boundaries.
flushUartBuffer = Wifi.flushInput

; Read a line preserving BC (for diagnostic loops)
readDiagLineBC:
    push bc
    call readDiagLine
    pop bc
    ret

; Read a line from ESP until CR/LF or timeout (no HALT)
; Output: CF=1 if data, CF=0 if timeout with no data
readDiagLine:
    ld hl, diag_buffer
    ld c, 60                    ; Max 60 characters
    ld de, DIAG_READ_INITIAL    ; Initial timeout
    xor a
    ld (Uart.break_hit), a

.readLoop
    push hl, bc, de
    call UartImpl.uartRead
    pop de, bc, hl
    push af
    ld a, (Uart.io_error)
    and a
    jr nz, .ioError
    pop af
    jr c, .gotByte

    call Keyboard.checkBreak
    jr nz, .notCancelled
    ld a, 1
    ld (Uart.break_hit), a
    jr .timeout
.notCancelled

    dec de
    ld a, d
    or e
    jr nz, .readLoop

.timeout
    xor a
    ld (hl), a
    ret                         ; CF=0

.gotByte
    ; On receiving data, reduce timeout to close line if missing terminator
    ld de, DIAG_READ_TAIL

    ; CR or LF = end of line
    cp 13
    jr z, .endLine
    cp 10
    jr z, .endLine

    ; Store character
    ld (hl), a
    inc hl
    dec c
    jr nz, .readLoop
    xor a
    ld (hl), a
    jp drainDiagLine

.endLine
    xor a
    ld (hl), a                  ; Terminate string
    scf                         ; CF=1, data available
    ret
.ioError
    pop af
    xor a
    ld (hl), a
    ret

; Finish an overlong line without touching the bounded destination buffer.
; CF=0 only on transport error or if the 255-byte drain cap is exhausted.
drainDiagLine:
    ld b, 255
.loop
    call Uart.readTimeoutMedium
    jr nc, .stopped
    cp 13
    jr z, .done
    cp 10
    jr z, .done
    djnz .loop
.stopped
    ; Silence or the drain cap leaves framing unknown, even after 60 bytes.
    ld a, 1
    ld (Uart.io_error), a
    or a
    ret
.done
    scf
    ret

; Read a line with long initial wait (for queries that sometimes take time)
; Output: CF=1 if data, CF=0 if timeout with no data
readDiagLineLong:
    ld hl, diag_buffer
    ld c, 60

    ; Wait for first byte with long timeout
    call Uart.readTimeoutLong
    jr nc, .timeout

.readLoop
    ; CR or LF = end of line
    cp 13
    jr z, .endLine
    cp 10
    jr z, .endLine

    ; Store character
    ld (hl), a
    inc hl
    dec c
    jr nz, .readNext
    xor a
    ld (hl), a
    jp drainDiagLine

    ; Read next byte with medium timeout (more time for Next)
.readNext
    call Uart.readTimeoutMedium
    jr c, .readLoop
    ld a, (Uart.break_hit)
    and a
    jr nz, .timeout
    ld a, (Uart.io_error)
    and a
    jr nz, .timeout
    jr .endLine

.timeout = readDiagLine.timeout
.endLine = readDiagLine.endLine
