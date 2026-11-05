; ============================================
; sntp.asm - SNTP time over the ESP-AT modem
;   AT+CIPSNTPCFG=1,<tz>   then poll AT+CIPSNTPTIME?
;   +CIPSNTPTIME:Sat Sep 19 18:42:05 2026
; fields layout: year-2000, month, date, hour, min, sec (binary)
; ============================================

    module Sntp

    RTVAR tz, 1                  ; signed UTC offset, -11..+13
    RTVAR fields, 6              ; last synchronized time
    RTVAR cmd, 56                ; AT+CIPSNTPCFG=1,<tz>[,<servers>] buffer
    RTVAR mtext, 3               ; month token scratch

; ============================================
; sync - Configure SNTP and fetch the current time
; Output: CF=0 success (fields valid), CF=1 fail or BREAK
; ============================================
sync:
    call buildCfg
    ld hl, cmd
    call Wifi.espSendZCheckOk
    jr nc, .cfgOk
    ld a, (Uart.break_hit)
    and a
    jr nz, .abort
    ; Some ESP firmwares reject the explicit server list; retry without it.
    call buildCfgPlain
    ld hl, cmd
    call Wifi.espSendZCheckOk
    ret c
.cfgOk
    ; Give the modem time to reach the server, honouring BREAK.
    ld b, 100
.settle
    halt
    call Keyboard.checkBreak
    jr z, .abort
    djnz .settle
    ld b, 3
.try
    push bc
    call query
    pop bc
    ret nc
    ld a, (Uart.break_hit)
    and a
    jr nz, .abort
    push bc
    ld b, 50
.pause
    halt
    call Keyboard.checkBreak
    jr z, .cancelPause
    djnz .pause
    pop bc
    djnz .try
    scf
    ret
.cancelPause
    pop bc
.abort
    scf
    ret

; ============================================
; query - One AT+CIPSNTPTIME? round trip
; Output: CF=0 valid, CF=1 not ready or error
; ============================================
query:
    call Wifi.uartLock
    ld hl, 4096
    ld (Wifi.byte_limit), hl
    xor a
    ld (Wifi.use_long_timeout), a
    ld hl, s_query
    call Wifi.espSendZ_CRLF
.loop
    call Wifi.readReplyStart
    jr nc, .fail
    jr nz, .terminal
    cp 'C'
    jr nz, .flush
    ld hl, s_prefix
    call Wifi.checkOkErrCommon.matchSuffix
    jr nc, .fail
    jr nz, .flush
    call parseTime
    jr c, .flush
    call Wifi.checkOkErr
    jr c, .fail
    ld hl, cmd
    ld de, fields
    ld bc, 6
    ldir                    ; Commit only after the complete round trip succeeds
    jp Wifi.uartUnlock
.terminal
    cp 'O'
    ld hl, Wifi.dbg_rx_ok + 4
    jr z, .suffix
    cp 'E'
    jr nz, .flush
    ld hl, Wifi.dbg_rx_error + 4
.suffix
    call Wifi.checkOkErrCommon.matchSuffix
    jr nc, .fail
    jr z, .fail
.flush
    call Wifi.flushReplyLine
    jr .loop
.fail
    jp Wifi.uartUnlockFail

; Parses "Ddd Mmm dd hh:mm:ss yyyy"
; Output: CF=0 valid (cmd scratch), CF=1 invalid; fields remain unchanged
parseTime:
    ld b, 4
.skipDay
    push bc
    call Wifi.readResponseByte
    pop bc
    jp nc, .fail
    djnz .skipDay         ; weekday is always three letters plus a space

    ld hl, mtext
    ld b, 3
.token
    push hl
    push bc
    call Wifi.readResponseByte
    pop bc
    pop hl
    jp nc, .fail
    ld (hl), a
    inc hl
    djnz .token
    call monthIndex
    ret c
    ld (cmd + 1), a

    ld e, 2
    call number
    jr nc, .fail
    or a
    jr z, .fail
    cp 32
    jr nc, .fail
    ld (cmd + 2), a

    ld e, 2
    call number
    jr nc, .fail
    cp 24
    jr nc, .fail
    ld (cmd + 3), a

    ld e, 2
    call number
    jr nc, .fail
    cp 60
    jr nc, .fail
    ld (cmd + 4), a

    ld e, 2
    call number
    jr nc, .fail
    cp 60
    jr nc, .fail
    ld (cmd + 5), a

    call parseYear
    jr nc, .fail
    ld (cmd), a
    or a
    ret
.fail
    scf
    ret

; Read up to E digits (spaces and colons skipped)
; Output: CF=1 ok A=value, CF=0 read error or no digits
number:
    ld c, 0
    ld d, 0
.skip
    call Wifi.readResponseByte
    ret nc
    cp ' '
    jr z, .skip
    cp ':'
    jr z, .skip
.loop
    sub '0'
    cp 10
    jr nc, .done
    ld b, a
    ld a, c
    add a, a
    add a, a
    add a, c
    add a, a
    add a, b
    ld c, a
    inc d
    ld a, d
    cp e
    jr z, .max
    call Wifi.readResponseByte
    ret nc
    jr .loop
.done
    ld a, d
    or a
    jr z, .bad
    ld a, c
    scf
    ret
.max
    ld a, c
    scf
    ret
.bad
    or a
    ret

; Read a four-digit year and return year-2000.
; Only the RTC-compatible 2000..2099 range is representable.
parseYear:
.skip
    call Wifi.readResponseByte
    ret nc
    cp ' '
    jr z, .skip
    cp '2'
    jr nz, .bad
    call Wifi.readResponseByte
    ret nc
    cp '0'
    jr nz, .bad
    call Wifi.readResponseByte
    ret nc
    cp '0'
    jr c, .bad
    cp '9' + 1
    jr nc, .bad
    sub '0'
    ld c, a
    add a, a
    add a, a
    add a, c
    add a, a
    ld c, a
    call Wifi.readResponseByte
    ret nc
    cp '0'
    jr c, .bad
    cp '9' + 1
    jr nc, .bad
    sub '0'
    add a, c
    scf
    ret
.bad
    or a
    ret

; mtext -> A = month 1..12, CF=0 valid
monthIndex:
    ld hl, months
    ld b, 1
.outer
    push hl
    ld de, mtext
    push bc
    ld b, 3
.inner
    ld a, (de)
    cp (hl)
    jr nz, .miss
    inc hl
    inc de
    djnz .inner
    pop bc
    pop hl
    ld a, b
    or a
    ret
.miss
    pop bc
    pop hl
    inc hl
    inc hl
    inc hl
    inc b
    ld a, b
    cp 13
    jr nz, .outer
    scf
    ret
months db "JanFebMarAprMayJunJulAugSepOctNovDec", 0

; ============================================
; buildCfg - "AT+CIPSNTPCFG=1,<tz>,"pool.ntp.org","time.google.com""
; ============================================
buildCfg:
    call buildCfgPlain
    ld hl, cmd
.findEnd
    ld a, (hl)
    or a
    jr z, .append
    inc hl
    jr .findEnd
.append
    ex de, hl
    ld hl, s_servers
    ld b, 34                ; server list plus terminator
.copyServers
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    djnz .copyServers
    ret

; ============================================
; buildCfgPlain - "AT+CIPSNTPCFG=1,<tz>" into cmd
; ============================================
buildCfgPlain:
    ld hl, cmd
    ld de, s_cfg
    ld b, 16
.copy
    ld a, (de)
    ld (hl), a
    inc hl
    inc de
    djnz .copy
    ld a, (tz)
    or a
    jp p, .pos
    ld (hl), '-'
    inc hl
    neg
.pos
    cp 10
    jr c, .one
    ld c, a
    ld (hl), '1'
    inc hl
    ld a, c
    sub 10
.one
    add a, '0'
    ld (hl), a
    inc hl
    xor a
    ld (hl), a
    ret

s_cfg    db "AT+CIPSNTPCFG=1,", 0
s_servers db ',"pool.ntp.org","time.google.com"', 0
s_query  db "AT+CIPSNTPTIME?", 0
s_prefix db "IPSNTPTIME:", 0

    endmodule
