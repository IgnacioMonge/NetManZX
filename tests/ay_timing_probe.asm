; Standalone hardware probe: the production AY receiver and timeout wrapper.
; Configure #6000 and #600C before USR #8000; see docs/ay-timing.md.
    DEVICE ZXSPECTRUM48
    DEFINE AY
    ORG #8000
    jp probe

rt_ptr = #C800
    MACRO RTVAR name?, size?
name? = @rt_ptr
@rt_ptr = @rt_ptr + size?
    ENDM

    include "modules/uart-common.asm"
    include "drivers/ay.asm"
    include "modules/keyboard.asm"
    module Display
putStrLog:
    ret ; Logging stays disabled; no screen work inside the measurement.
    endmodule

probe:
    di
    ld (saved_sp), sp
    exx
    ld (saved_hl_alt), hl
    exx
    ld iy, #5C3A
    ld sp, #FFF0
    call Uart.init
    xor a
    ld (Uart.log_enabled), a
    ld (Uart.io_error), a
    ld (Uart.break_hit), a
    ld (#6001), a
    ld hl, 0
    ld (#6002), hl
    ld (#6004), hl
    ld hl, (#600C)
    ld (remaining), hl
    ; Snapshot FRAMES outside the marked interval.
    di
    ld hl, (#5C78)
    ld (#6006), hl
    ld a, (#5C7A)
    ld (#6008), a
    ei
    ld a, 2
    out (#FE), a
.loop
    ld hl, (remaining)
    ld a, h
    or l
    jr z, .done
    dec hl
    ld (remaining), hl
    ld a, (#6000)
    and a
    jr nz, .timeout
    call UartImpl.uartRead
    jr .sample
.timeout
    call Uart.readTimeout
.sample
    ld hl, (#6002)
    inc hl
    ld (#6002), hl
    jr nc, .checkBreak
    ld hl, (#6004)
    inc hl
    ld (#6004), hl
.checkBreak
    ld a, (Uart.break_hit)
    and a
    jr nz, .cancelled
    call Keyboard.checkBreak
    jr nz, .loop
.cancelled
    ld a, 1
    ld (#6001), a
.done
    ld a, 4
    out (#FE), a
    di
    ld hl, (#5C78)
    ld (#6009), hl
    ld a, (#5C7A)
    ld (#600B), a
    ei
    call Keyboard.waitBreakRelease
    exx
    ld hl, (saved_hl_alt)
    exx
    ld sp, (saved_sp)
    ret

saved_sp dw 0
saved_hl_alt dw 0
remaining dw 0
probe_end:
    ASSERT probe_end < #C000
    ASSERT rt_ptr < #FFF0 - 64
    SAVEBIN "ay-timing-probe.bin", #8000, probe_end - #8000
    EMPTYTAP "ay-timing-probe.tap"
    SAVETAP "ay-timing-probe.tap", CODE, "AY timing", #8000, probe_end - #8000, #8000
