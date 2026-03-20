    module Uart

; Default timeout - Next needs more due to faster CPU
    IFDEF NEXT
DEFAULT_TIMEOUT = #FFFF          ; Next: max 16-bit timeout
    ELSE
DEFAULT_TIMEOUT = #8000          ; UNO/divMMC: ~1.6s at 3.5MHz
    ENDIF

; Long timeout: multiple blocks to tolerate long pauses
; (JOIN/DHCP/SCAN) without premature timeout.
LONG_TIMEOUT_BLOCK = #FFFF
    IFDEF NEXT
LONG_TIMEOUT_REPS  = 80          ; Next: faster CPU needs more reps
    ELSE
LONG_TIMEOUT_REPS  = 8
    ENDIF

; Medium timeout: for in-progress data reads (e.g. scan)
    IFDEF NEXT
MEDIUM_TIMEOUT = #FFFF
    ELSE
MEDIUM_TIMEOUT = #8000
    ENDIF

init:
    call UartImpl.init
    ; Init line-mode log buffer
    ld hl, log_buf
    ld (log_ptr), hl
    xor a
    ld (log_overflow), a
    ret

write:
    push af
    call UartImpl.write
    pop af
    push af
    ld a, (log_enabled)
    and a
    jr z, .skipLog
    pop af
    push af
    call log_char
.skipLog
    pop af
    ret
  

; Read with default timeout
; Out: A = byte read, CF=1 success, CF=0 timeout
readTimeout:
    push bc, de, hl
    ld de, DEFAULT_TIMEOUT
    call poll_block
    jr c, got_byte
    pop hl, de, bc
    or a
    ret

; Read with medium timeout (for in-progress data, e.g. scan)
; Out: A = byte read, CF=1 success, CF=0 timeout
readTimeoutMedium:
    push bc, de, hl
    ld de, MEDIUM_TIMEOUT
    call poll_block
    jr c, got_byte
    pop hl, de, bc
    or a
    ret

; Read with long timeout (for WiFi connection)
; Out: A = byte read, CF=1 success, CF=0 timeout or BREAK pressed
readTimeoutLong:
    push bc, de, hl
    ld b, LONG_TIMEOUT_REPS
.outer
    ld de, LONG_TIMEOUT_BLOCK
    call poll_block
    jr c, got_byte
    ; Check BREAK between blocks (~370ms each)
    call Keyboard.checkBreak
    jr z, .breakAbort
    djnz .outer
.breakAbort
    ; Total timeout or BREAK
    pop hl, de, bc
    or a
    ret

; ============================================
; poll_block
;   In:  DE = counter
;   Out: CF=1 byte available (A=byte), CF=0 timeout
; ============================================
poll_block:
.loop
    call UartImpl.uartRead
    ret c

    ; Small delay to avoid bus saturation
    ld a, 4
.delay
    dec a
    jr nz, .delay

    dec de
    ld a, e
    or a
    jr nz, .loop
    ; E=0: every 256 iterations, check BREAK
    ld a, d
    or a
    jr z, .done
    call Keyboard.checkBreak
    jr z, .done
    jr .loop
.done
    or a
    ret

got_byte
    push af
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

; ============================================
; Line-mode log
;   Accumulates bytes in log_buf, flushes via Display.putStrLog on LF.
;   CR/LF preserved (CR before LF is stored as-is).
; ============================================
LOG_BUF_SIZE = 160

log_char:
    push bc, hl, de
    ld c, a

    ld hl, (log_ptr)
    ld de, log_buf + (LOG_BUF_SIZE - 2)
    or a
    sbc hl, de
    jr c, .have_space

    ; No space: mark overflow, flush will happen on next LF
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
    ld (hl), a
    ld hl, log_buf
    call Display.putStrLog
    ld hl, log_buf
    ld (log_ptr), hl
    xor a
    ld (log_overflow), a
    pop hl, af
    ret

; Reset log buffer (discards partial line). Used to mute log mid-command
; (e.g. AT+CWJAP) without mixing output.
logReset:
    ld hl, log_buf
    ld (log_ptr), hl
    xor a
    ld (log_overflow), a
    ret

; Disabled by default; toggled at runtime with L key.
log_enabled  db 0
log_overflow db 0
log_ptr      dw 0
    RTVAR log_buf, LOG_BUF_SIZE

    endmodule
