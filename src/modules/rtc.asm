; ============================================
; rtc.asm - Real-time clock backends
;   NEXT : DS1307 on the Next I2C bus (#103B SCL / #113B SDA)
;   UNO  : esxDOS / NextZXOS RTC driver, or PCF8563 bit-banged through the
;          ZX-Uno / DivTIESUS I2C register #F8
;   AY   : no RTC
; buf layout (binary): sec, min, hour, date, month, year-2000
; ============================================

    module Rtc

KIND_NONE   = 0
KIND_PCF    = 1
KIND_DS1307 = 2
KIND_ESX    = 3

M_DRVAPI   = #92
M_GETDATE  = #8E

ZXUNO_SEL  = #FC3B
I2C_REG    = #F8
PCF_W      = #A2
PCF_R      = #A3

NEXT_SCL   = #103B
NEXT_SDA   = #113B
DS1307_W   = #D0
DS1307_R   = #D1

; ZX-Uno I2C register bit patterns: bit0 = SDA, bit1 = SCL
I2C_00     = 0
I2C_01     = 1
I2C_10     = 2
I2C_11     = 3

    RTVAR buf, 6                 ; sec, min, hour, date, month, year-2000
    RTVAR kind, 1
    RTVAR valid, 1               ; buf contains a validated RTC value
    RTVAR i2c_mask, 1            ; SDA bit mask found on the ZX-Uno bus
    RTVAR sbcd, 7                ; raw BCD registers of the last access

; ============================================
; probe - Detect an RTC and read it when possible
; Output: CF=0 detected, CF=1 none
; ============================================
probe:
    IFDEF NEXT
    call dsProbe
    ret nc
    ENDIF
    IFDEF UNO
    call esxProbeDrvApi
    jr nc, .esxOk
    call esxProbeGetDate
    jr nc, .esxOk
    call pcfProbe
    ret nc
    jr .none
.esxOk
    ; A directly reachable chip is also writable; prefer it for SNTP sets.
    ; If it cannot be read, keep the esxDOS time by asking the driver again.
    call pcfProbe
    ret nc
    call esxProbeDrvApi
    ret nc
    call esxProbeGetDate
    ret nc
    ENDIF
.none
    xor a
    ld (kind), a
    ld (valid), a
    scf
    ret

; Source name for the screen, HL = pointer
kindName:
    ld a, (kind)
    cp KIND_PCF
    ld hl, s_pcf
    ret z
    cp KIND_DS1307
    ld hl, s_ds1307
    ret z
    cp KIND_ESX
    ld hl, s_esx
    ret z
    ld hl, s_none
    ret

; CF=0 when the chip itself can be written
writable:
    ld a, (kind)
    cp KIND_PCF
    jr z, .yes
    cp KIND_DS1307
    jr z, .yes
    scf
    ret
.yes
    or a
    ret

; ============================================
; writeTime - Write buf to the detected chip
; Output: CF=0 success
; ============================================
writeTime:
    call writable
    ret c
    IFDEF NEXT
    jp dsWrite
    ENDIF
    IFDEF UNO
    jp pcfWrite
    ENDIF

; ============================================
; read - Refresh buf from the detected chip
; Output: CF=0 valid time in buf
; ============================================
read:
    ld a, (kind)
    and a
    jr z, .none
    cp KIND_DS1307
    jr z, .ds
    cp KIND_PCF
    jr z, .pcf
; KIND_ESX has no refresh path: reaching the driver means rst $08, which
; scribbles the printer buffer, and the rearm that repairs it also resets the
; auto-rescan and health-check counters. Callers use the value probe captured.
.none
    scf
    ret
.ds
    IFDEF NEXT
    jp dsReadTime
    ENDIF
    scf
    ret
.pcf
    IFDEF UNO
    jp pcfReadTime
    ENDIF
    scf
    ret

; ============================================
; Shared BCD helpers
; ============================================
; A = BCD -> A binary, CF set when a nibble is not BCD
bcdToBin:
    ld b, a
    and #0F
    cp 10
    jr nc, .bad
    ld c, a
    ld a, b
    and #F0
    rrca
    rrca
    rrca
    rrca
    cp 10
    jr nc, .bad
    ld b, a
    add a, a
    add a, a
    add a, b
    add a, a
    add a, c
    or a
    ret
.bad
    scf
    ret

; A = binary (0..99) -> A BCD
binToBcd:
    ld b, 0
.loop
    cp 10
    jr c, .done
    sub 10
    inc b
    jr .loop
.done
    ld c, a
    ld a, b
    add a, a
    add a, a
    add a, a
    add a, a
    add a, c
    ret

; buf (HL) -> sec,min,hour,date,month,year as BCD (DE)
bufToSix:
    ld b, 6
.loop
    ld a, (hl)
    push bc
    call binToBcd
    pop bc
    ld (de), a
    inc hl
    inc de
    djnz .loop
    ret

; Return weekday in A: Sunday=0, for dates in 2000..2099.
weekday:
    ld a, (buf + 5)
    ld b, a
    add a, 3
    srl a
    srl a
    add a, b
    ld c, a
    ld a, (buf + 4)
    ld b, a
    dec a
    ld e, a
    ld d, 0
    ld hl, weekday_months
    add hl, de
    ld a, (hl)
    add a, c
    ld c, a
    ld a, b
    cp 3
    jr c, .day
    ld a, (buf + 5)
    and 3
    jr nz, .day
    inc c
.day
    ld a, (buf + 3)
    dec a
    add a, c
    add a, 6                ; 2000-01-01 was Saturday
.mod7
    cp 7
    jr c, .done
    sub 7
    jr .mod7
.done
    ret

weekday_months db 0, 3, 3, 6, 1, 4, 6, 2, 5, 0, 3, 5

; ============================================
; Next: DS1307 over the Next I2C bus
; ============================================
    IFDEF NEXT
; A = bit for the SDA line
dsWriteSda:
    ld bc, NEXT_SDA
    out (c), a
    ret

; A = bit for the SCL line
dsWriteScl:
    ld bc, NEXT_SCL
    out (c), a
    ret

dsStart:
    ld a, 1
    call dsWriteSda
    ld a, 1
    call dsWriteScl
    xor a
    call dsWriteSda
    xor a
    call dsWriteScl
    ret

dsStop:
    xor a
    call dsWriteSda
    ld a, 1
    call dsWriteScl
    ld a, 1
    call dsWriteSda
    ret

dsPulse:
    ld a, 1
    call dsWriteScl
    xor a
    call dsWriteScl
    ret

; A = byte to send. Output: CF=0 ACK, CF=1 NACK.
dsSendByte:
    ld l, a
    ld h, 8
.loop
    rlc l
    ld a, l
    and 1
    call dsWriteSda
    call dsPulse
    dec h
    jr nz, .loop
    ld a, 1
    call dsWriteSda
    ld a, 1
    call dsWriteScl
    ld bc, NEXT_SDA
    in a, (c)
    rra
    push af
    xor a
    call dsWriteScl
    pop af
    ret

; A = byte read (SCL high, sample, SCL low)
dsReadByte:
    ld l, 0
    ld h, 8
.loop
    ld a, 1
    call dsWriteScl
    ld bc, NEXT_SDA
    in a, (c)
    and 1
    sla l
    or l
    ld l, a
    xor a
    call dsWriteScl
    dec h
    jr nz, .loop
    ld a, l
    ret

dsAck:
    xor a
    call dsWriteSda
    call dsPulse
    jp dsRelease
dsNack:
    ld a, 1
    call dsWriteSda
    call dsPulse
dsRelease:
    ld a, 1
    call dsWriteSda
    ret

dsReadRegs:
    call dsStart
    ld a, DS1307_W
    call dsSendByte
    jr c, .fail
    xor a
    call dsSendByte
    jr c, .fail
    call dsStart
    ld a, DS1307_R
    call dsSendByte
    jr c, .fail
    call dsRelease
    ld hl, sbcd
    ld b, 7
.loop
    push hl
    push bc
    call dsReadByte
    pop bc
    pop hl
    ld (hl), a
    inc hl
    dec b
    jr z, .stop
    push hl
    push bc
    call dsAck
    pop bc
    pop hl
    jr .loop
.stop
    call dsNack
    call dsStop
    or a
    ret
.fail
    call dsStop
    scf
    ret

; sbcd: sec, min, hour, weekday, date, month, year
dsProbe:
    call dsReadRegs
    jr c, .none
    ld a, KIND_DS1307
    ld (kind), a
    ld hl, sbcd
    ld de, buf
    call dsConv
    jr c, .invalid
    ld a, 1
    ld (valid), a
    or a
    ret
.invalid
    xor a
    ld (valid), a
    or a                    ; chip detected, but its time is invalid
    ret
.none
    xor a
    ld (valid), a
    scf
    ret

dsReadTime:
    call dsReadRegs
    jr c, .invalid
    ld hl, sbcd
    ld de, buf
    call dsConv
    jr c, .invalid
    ld a, 1
    ld (valid), a
    or a
    ret
.invalid
    xor a
    ld (valid), a
    scf
    ret

; Same ranges as pcfToBuf but with the DS1307 register order
dsConv:
    bit 7, (hl)             ; CH=1: oscillator stopped
    jp nz, .fail
    ld a, (hl)
    and #7F
    call bcdToBin
    ret c
    cp 60
    jp nc, .fail
    ld (de), a
    inc de
    inc hl

    ld a, (hl)
    call bcdToBin
    ret c
    cp 60
    jp nc, .fail
    ld (de), a
    inc de
    inc hl

    ld a, (hl)
    bit 6, a
    jr z, .hour24
    and #1F
    call bcdToBin
    ret c
    or a
    jr z, .fail
    cp 13
    jr nc, .fail
    cp 12
    jr nz, .ampm
    xor a                   ; 12 AM is midnight, 12 PM is noon
.ampm
    bit 5, (hl)
    jr z, .hourReady
    add a, 12
    jr .hourReady
.hour24
    and #3F
    call bcdToBin
    ret c
    cp 24
    jr nc, .fail
.hourReady
    ld (de), a
    inc de
    inc hl
    inc hl                  ; weekday

    ld a, (hl)
    and #3F
    call bcdToBin
    ret c
    or a
    jr z, .fail
    cp 32
    jr nc, .fail
    ld (de), a
    inc de
    inc hl

    ld a, (hl)
    and #1F
    call bcdToBin
    ret c
    or a
    jr z, .fail
    cp 13
    jr nc, .fail
    ld (de), a
    inc de
    inc hl

    ld a, (hl)
    call bcdToBin
    ret c
    cp 100
    jr nc, .fail
    ld (de), a
    or a
    ret
.fail
    scf
    ret

; buf -> DS registers 0x00..0x06: sec(CH=0), min, hour, weekday, date, month, year
dsWrite:
    ld hl, buf
    ld de, sbcd
    call bufToSix
    ld a, (sbcd + 5)
    ld (sbcd + 6), a
    ld a, (sbcd + 4)
    ld (sbcd + 5), a
    ld a, (sbcd + 3)
    ld (sbcd + 4), a
    call weekday
    inc a                   ; DS1307 uses Sunday=1..Saturday=7
    ld (sbcd + 3), a

    call dsStart
    ld a, DS1307_W
    call dsSendByte
    jr c, .fail
    xor a
    call dsSendByte
    jr c, .fail
    ld hl, sbcd
    ld b, 7
.loop
    ld a, (hl)
    push hl
    push bc
    call dsSendByte
    pop bc
    pop hl
    jr c, .fail
    inc hl
    djnz .loop
    call dsStop
    ld a, 1
    ld (valid), a
    or a
    ret
.fail
    call dsStop
    xor a
    ld (valid), a
    scf
    ret
    ENDIF

; ============================================
; UNO: esxDOS RTC calls (RTC.SYS driver or NextZXOS)
; B,C = MS-DOS date, D,E = MS-DOS time. Also used by M_GETDATE.
; ============================================
    IFDEF UNO
esxProbeDrvApi:
    push iy
    push ix
    ld iy, #5C3A
    xor a
    ld b, a                 ; B=0: query RTC
    ld c, a                 ; C=0: driver API
    ld d, a
    ld e, a
    ld h, a
    ld l, a
    rst $08
    db M_DRVAPI
    jr esxDecode

esxProbeGetDate:
    push iy
    push ix
    ld iy, #5C3A
    rst $08
    db M_GETDATE
esxDecode:
    pop ix
    pop iy
    ret c
    jp decodeMsdos

; MS-DOS-encoded date/time -> buf, kind=ESX. CF=0 valid.
; Year is accepted for 2000..2099 so a serviceable RTC is not rejected.
decodeMsdos:
    ld a, b
    cp 40                   ; (year-1980)<<1
    jr c, .bad
    cp 240
    jr nc, .bad
    ld a, c
    and 31                  ; day
    jr z, .bad
    ld (buf + 3), a
    ld a, b
    and 1
    add a, a
    add a, a
    add a, a
    ld l, a
    ld a, c
    and #E0
    rlca
    rlca
    rlca
    or l                    ; month
    jr z, .bad
    cp 13
    jr nc, .bad
    ld (buf + 4), a
    ld a, b
    srl a                   ; year-1980
    sub 20
    ld (buf + 5), a         ; year-2000
    ld a, d
    and #F8
    rrca
    rrca
    rrca
    cp 24                   ; hour
    jr nc, .bad
    ld (buf + 2), a
    ld a, d
    and 7
    add a, a
    add a, a
    add a, a
    ld l, a
    ld a, e
    and #E0
    rlca
    rlca
    rlca
    or l                    ; minute
    cp 60
    jr nc, .bad
    ld (buf + 1), a
    ld a, e
    and 31
    cp 30                   ; seconds/2
    jr nc, .bad
    add a, a
    ld (buf), a
    ld a, KIND_ESX
    ld (kind), a
    ld a, 1
    ld (valid), a
    or a
    ret
.bad
    xor a
    ld (valid), a
    scf
    ret
    ENDIF

; ============================================
; UNO: PCF8563 through the ZX-Uno / DivTIESUS I2C register #F8.
; The register is selected once and BC keeps pointing at the data port,
; matching the DivTIESUS NTPDATE utility and the SpecTalkZX seed.
; ============================================
    IFDEF UNO
pcfProbe:
    ld a, 1
.maskLoop
    ld (i2c_mask), a
    push af
    call pcfReadTime
    jr nc, .found
    pop af
    add a, a
    jr nc, .maskLoop
    scf
    ret
.found
    pop af
    ld a, KIND_PCF
    ld (kind), a
    or a
    ret

; One read transaction with the current i2c_mask; CF=0 when a valid PCF replied.
pcfReadTime:
    ld bc, ZXUNO_SEL
    ld a, I2C_REG
    out (c), a
    inc b                   ; BC = #FD3B, I2C data register
    di
    call pcfStart
    ld a, PCF_W
    call pcfSendByte
    jr c, .fail
    ld a, 2                 ; VL_seconds register
    call pcfSendByte
    jr c, .fail
    call pcfStart           ; repeated START for read
    ld a, PCF_R
    call pcfSendByte
    jr c, .fail
    ld hl, sbcd
    ld d, 6
.read
    call pcfReadByte
    ld (hl), a
    inc hl
    call pcfAck
    dec d
    jr nz, .read
    call pcfReadByte
    ld (hl), a
    call pcfNack
    call pcfStop
    ei
    ld hl, sbcd
    ld de, buf
    call pcfToBuf
    jr c, .invalid
    ld a, 1
    ld (valid), a
    or a
    ret
.fail
    call pcfStop
    ei
.invalid
    xor a
    ld (valid), a
    scf
    ret

; Bit-banged primitives. BC points at the I2C data register on entry.
pcfStart:
    ld a, I2C_11
    out (c), a
    ld a, I2C_10
    out (c), a
    ld a, I2C_00
    out (c), a
    ret

pcfStop:
    ld a, I2C_00
    out (c), a
    ld a, I2C_10
    out (c), a
    ld a, I2C_11
    out (c), a
    ret

; A = byte to send. Output: CF=0 ACK, CF=1 NACK.
pcfSendByte:
    push bc
    push hl
    ld l, a
    ld h, 8
.loop
    rlc l
    ld a, l
    and 1
    out (c), a              ; SDA = bit, SCL low
    or I2C_10
    out (c), a              ; SCL high
    and 1
    out (c), a              ; SCL low
    dec h
    jr nz, .loop
    ld a, I2C_01
    out (c), a              ; release SDA, ACK slot
    ld a, I2C_11
    out (c), a
    in a, (c)
    push af
    ld a, I2C_01
    out (c), a
    pop af
    ld hl, i2c_mask
    and (hl)
    jr z, .ack
    scf
    jr .done
.ack
    or a
.done
    pop hl
    pop bc
    ret

; A = byte read
pcfReadByte:
    push bc
    push de
    push hl
    ld l, 0
    ld h, 8
.loop
    ld a, I2C_01
    out (c), a              ; SCL low, SDA released
    ld a, I2C_11
    out (c), a              ; SCL high
    in a, (c)
    ld e, a
    ld a, I2C_01
    out (c), a              ; SCL low
    ld a, (i2c_mask)
    and e
    jr z, .zero
    scf
    jr .shift
.zero
    or a
.shift
    ld a, l
    rla
    ld l, a
    dec h
    jr nz, .loop
    ld a, l
    pop hl
    pop de
    pop bc
    ret

pcfAck:
    ld a, I2C_00
    out (c), a              ; SDA low
    ld a, I2C_10
    out (c), a              ; SCL high
    ld a, I2C_00
    out (c), a
    ret

pcfNack:
    ld a, I2C_01
    out (c), a
    ld a, I2C_11
    out (c), a
    ld a, I2C_01
    out (c), a
    ret

; Six fields sec,min,hour,date,[skip],month,year as BCD (HL) into buf (DE).
; Output: CF=0 valid
pcfToBuf:
    ld a, (hl)
    bit 7, a                ; VL flag: clock integrity not guaranteed
    jr nz, .fail
    and #7F
    call bcdToBin
    ret c
    cp 60
    jr nc, .fail
    ld (de), a
    inc de
    inc hl

    ld a, (hl)
    call bcdToBin
    ret c
    cp 60
    jr nc, .fail
    ld (de), a
    inc de
    inc hl

    ld a, (hl)
    and #3F
    call bcdToBin
    ret c
    cp 24
    jr nc, .fail
    ld (de), a
    inc de
    inc hl

    ld a, (hl)
    and #3F
    call bcdToBin
    ret c
    or a
    jr z, .fail
    cp 32
    jr nc, .fail
    ld (de), a
    inc de
    inc hl
    inc hl                  ; weekday

    ld a, (hl)
    and #1F
    call bcdToBin
    ret c
    or a
    jr z, .fail
    cp 13
    jr nc, .fail
    ld (de), a
    inc de
    inc hl

    ld a, (hl)
    call bcdToBin
    ret c
    cp 100
    jr nc, .fail
    ld (de), a
    or a
    ret
.fail
    scf
    ret

; buf -> control registers then time registers 0x02..0x08
pcfWrite:
    ld hl, buf
    ld de, sbcd
    call bufToSix
    ld a, (sbcd + 5)
    ld (sbcd + 6), a
    ld a, (sbcd + 4)
    ld (sbcd + 5), a
    call weekday
    ld (sbcd + 4), a         ; PCF weekday follows the date

    ld bc, ZXUNO_SEL
    ld a, I2C_REG
    out (c), a
    inc b                   ; BC = #FD3B, I2C data register
    di
    call pcfStart
    ld a, PCF_W
    call pcfSendByte
    jr c, .fail
    xor a
    call pcfSendByte       ; register pointer 0x00
    jr c, .fail
    xor a
    call pcfSendByte       ; control 0x00 = normal mode
    jr c, .fail
    xor a
    call pcfSendByte       ; control 0x01 = clock running
    jr c, .fail
    call pcfStop

    call pcfStart
    ld a, PCF_W
    call pcfSendByte
    jr c, .fail
    ld a, 2
    call pcfSendByte
    jr c, .fail
    ld hl, sbcd
    ld d, 7
.loop
    ld a, (hl)
    call pcfSendByte
    jr c, .fail
    inc hl
    dec d
    jr nz, .loop
    call pcfStop
    ei
    ld a, 1
    ld (valid), a
    or a
    ret
.fail
    call pcfStop
    ei
    xor a
    ld (valid), a
    scf
    ret
    ENDIF

; Source names
s_none   db "not available", 0
s_pcf    db "PCF8563", 0
s_ds1307 db "DS1307", 0
s_esx    db "esxDOS", 0

    endmodule
