    module Uart

; Default timeout, counted in poll_block iterations - Next needs more due
; to faster CPU
    IFDEF NEXT
DEFAULT_TIMEOUT = #FFFF          ; Next: max 16-bit timeout
    ELSE
        IFDEF AY
DEFAULT_TIMEOUT = #0160          ; AY: uartRead already waits ~4.5ms
        ELSE
DEFAULT_TIMEOUT = 54400          ; UNO/divMMC: 153 T idle poll, ~2.4s at 3.5MHz
        ENDIF
    ENDIF

; TX wait, counted in status polls before latching io_error. A 9600-baud
; byte (Next baud scan) lasts ~1ms; 4096 polls last >=20ms at 28MHz.
TX_TIMEOUT = #1000

; Long timeout: multiple blocks to tolerate long pauses
; (JOIN/DHCP/SCAN) without premature timeout.
    IFDEF AY
LONG_TIMEOUT_BLOCK = #0052       ; AY: ~0.37s per block
    ELSE
LONG_TIMEOUT_BLOCK = #FFFF
    ENDIF
    IFDEF NEXT
LONG_TIMEOUT_REPS  = 80          ; Next: faster CPU needs more reps
    ELSE
        IFDEF AY
LONG_TIMEOUT_REPS  = 8
        ELSE
LONG_TIMEOUT_REPS  = 13          ; UNO: ~2.9s blocks, ~37s total
        ENDIF
    ENDIF

init:
    call UartImpl.init
    ; Warm entry resets resident state; flush terminates only captured bytes.
    xor a
    ld (log_enabled), a
    ld (io_error), a
    ld (tx_pending), a
    IFNDEF STANDALONE_PROBE
    ld (Wifi.flushInput.recovering), a
    ENDIF
    jp logReset

write:
    push af
    ld a, (io_error)
    and a
    jr nz, .skipWrite
    pop af
    push af
    call UartImpl.write
    ld a, (io_error)
    and a
    jr nz, .skipLog
    pop af
    push af
    call trackTx
    ld a, (log_enabled)
    and a
    jr z, .skipLog
    pop af
    push af
    call log_char
.skipLog
.skipWrite
    pop af
    ret

; Track complete AT lines without treating raw +++ as a command.
trackTx:
    sub 10
    jr z, .store
    cp 'A' - 10
    ret nz
    ld a, 1
.store
    ld (tx_pending), a
    ret
  

; Read with default timeout
; Out: A = byte read, CF=1 success, CF=0 timeout
readTimeout:
    push bc, de, hl
    ld de, DEFAULT_TIMEOUT
    call poll_block
    jr c, got_byte
readTimeoutFail:
    pop hl, de, bc
    or a
    ret

; Medium currently equals the default timeout on all targets.
readTimeoutMedium = readTimeout

; Read with long timeout (for WiFi connection)
; Out: A = byte read, CF=1 success, CF=0 timeout or BREAK pressed
; Side effect: sets break_hit=1 if BREAK detected (caller latch)
readTimeoutLong:
    push bc, de, hl
    xor a
    ld (break_hit), a
    ld b, LONG_TIMEOUT_REPS
.outer
    ld de, LONG_TIMEOUT_BLOCK
    push bc
    call poll_block
    pop bc
    jr c, got_byte
    ; Did poll_block exit via BREAK?
    ld a, (break_hit)
    ld hl, io_error
    or (hl)
    jr nz, readTimeoutFail
    ; Check BREAK between blocks (~370ms each)
    call Keyboard.checkBreak
    jr nz, .nextBlock
    ld a, 1
    ld (break_hit), a
    jr readTimeoutFail
.nextBlock
    djnz .outer
    jr readTimeoutFail

; ============================================
; poll_block
;   In:  DE = counter
;   Out: CF=1 byte available (A=byte), CF=0 timeout
; ============================================
poll_block:
    IFNDEF NEXT
    ; Only the Next backend latches io_error while polling.
    ld a, (io_error)
    and a
    ret nz
    ENDIF
.loop
    push de                     ; AY backend destroys DE
    call UartImpl.uartRead
    pop de
    ret c
    IFDEF NEXT
    ld a, (io_error)
    and a
    ret nz

    ; Keeps Next's 16-bit counters calibrated; its FIFO absorbs the delay.
    ; UNO has a one-byte RX register, so it polls without one.
    ld a, 4
.delay
    dec a
    jr nz, .delay
    ENDIF

    dec de
    ld a, e
    or a
    jr nz, .loop
    ; E=0: every 256 iterations, check BREAK
    ld a, d
    or a
    jr z, .done
    call Keyboard.checkBreak
    jr nz, .loop
    ; BREAK detected: latch it so caller can tell apart from timeout
    ld a, 1
    ld (break_hit), a
.done
    or a
    ret

got_byte
    push af
    ld a, (io_error)
    and a
    jr nz, .fault
    ld a, (log_enabled)
    and a
    jr z, .skipLog
    pop af
    push af
    call log_char
.skipLog
    pop af
    pop hl, de, bc
    scf
    ret
.fault
    pop af
    jr readTimeoutFail

; ============================================
; Deferred log capture. Rendering during RX loses bytes on fast targets.
; ============================================
LOG_BUF_SIZE = 160

log_char:
    push bc, hl, de
    ld c, a

    ld hl, (log_ptr)
    ld de, log_buf + (LOG_BUF_SIZE - 1)
    or a
    sbc hl, de
    jr c, .have_space

    ld a, 1
    ld (log_lost), a
    jr .done

.have_space
    add hl, de
    ld a, c
    ld (hl), a
    inc hl
    ld (log_ptr), hl

.done
    pop de, hl, bc
    ret

; Call only after the UART transaction has returned to the UI.
logFlushPending:
    push af, bc, de, hl
    ld hl, (log_ptr)
    ld de, log_buf
    or a
    sbc hl, de
    jr z, .reportLoss
    add hl, de
    xor a
    ld (hl), a
    ld hl, log_buf
    call Display.putStrLog
.reportLoss
    ld a, (log_lost)
    and a
    jr z, .reset
    ld hl, .truncated
    call Display.putStrLog
.reset
    call logReset
    pop hl, de, bc, af
    ret
.truncated db 13, 10, "<< UART log truncated", 13, 10, 0

; Reset log buffer (discards partial line). Used to mute log mid-command
; (e.g. AT+CWJAP) without mixing output.
logReset:
    ld hl, log_buf
    ld (log_ptr), hl
    xor a
    ld (log_lost), a
    ret

; Disabled by default; toggled at runtime with L key.
log_enabled  db 0
; Sticky transaction fault; cleared only after an explicit input drain.
io_error     db 0
; Set after the first transmitted AT byte and cleared by its LF.
tx_pending   db 0
log_ptr      dw 0
; ponytail: bounded capture reports loss; enlarge only if real traces need it.
log_lost     db 0
; BREAK latch: set by poll_block/readTimeoutLong, checked by caller.
; Distinguishes genuine BREAK-cancel from plain timeout across the
; checkOkErr layer, which collapses both into CF=1.
break_hit    = #5B13
    RTVAR log_buf, LOG_BUF_SIZE

    endmodule
