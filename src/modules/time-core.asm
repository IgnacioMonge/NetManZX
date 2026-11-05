; ============================================
; time-core.asm - Time state, zone handling and NETTIME.CFG persistence.
; Assembled inside module UI by the overlay include in main.asm. Uses the
; resident esxDOS helpers in Config for file access.
; ============================================

; ============================================
; Network time persistence (NETTIME.CFG)
; Layout: 'N','T',ver, tz, fields[6], zero padding, XOR checksum (15)
; ============================================
TC_SIZE       = 16
TC_TZ_OFF     = 3
TC_FIELDS_OFF = 4
TC_SIG_0      = 'N'
TC_SIG_1      = 'T'
TC_VERSION    = 1

    RTVAR time_buffer, TC_SIZE

; ============================================
; saveTime - Write Sntp.tz and Sntp.fields to NETTIME.CFG
; Output: CF=0 success
; ============================================
saveTime:
    ld hl, time_signature
    ld de, time_buffer
    ld b, 3
.copySig
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    djnz .copySig
    ld a, (Sntp.tz)
    ld (de), a
    inc de
    ld hl, Sntp.fields
    ld b, 6
.copyFields
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    djnz .copyFields
    ld b, TC_SIZE - 10
    xor a
.clearTail
    ld (de), a
    inc de
    djnz .clearTail
    ld hl, time_buffer
    ld b, TC_SIZE - 1
    xor a
.checksum
    xor (hl)
    inc hl
    djnz .checksum
    ld (hl), a

    push iy
    ld iy, #5C3A
    ld hl, time_filename
    push hl : pop ix
    ld b, Config.FA_WRITE_CREAT
    ld a, '*'
    rst $08
    db Config.F_OPEN
    jr nc, .openOk
    IFDEF NEXT
    ld hl, time_filename
    call Config.createPath
    jr c, .fail
    ld (Config.file_handle), a
    jr .write
    ELSE
    jr .fail
    ENDIF
.openOk
    ld (Config.file_handle), a
.write
    ld iy, #5C3A
    ld a, (Config.file_handle)
    ld hl, time_buffer
    push hl : pop ix
    ld bc, TC_SIZE
    rst $08
    db Config.F_WRITE
    call closeTransferT
    pop iy
    ret
.fail
    pop iy
    scf
    ret

; ============================================
; loadTime - Read NETTIME.CFG into Sntp.tz and Sntp.fields
; Output: CF=0 success
; ============================================
loadTime:
    push iy
    ld iy, #5C3A
    ld hl, time_filename
    push hl : pop ix
    ld b, Config.FA_READ
    ld a, '*'
    rst $08
    db Config.F_OPEN
    jr c, .failOpen
    ld (Config.file_handle), a
    ld iy, #5C3A
    ld a, (Config.file_handle)
    ld hl, time_buffer
    push hl : pop ix
    ld bc, TC_SIZE
    rst $08
    db Config.F_READ
    call closeTransferT
    pop iy
    jr c, .fail
    ld hl, time_buffer
    ld de, time_signature
    ld b, 3
.checkSig
    ld a, (de)
    cp (hl)
    jr nz, .fail
    inc hl
    inc de
    djnz .checkSig
    ld hl, time_buffer
    ld b, TC_SIZE - 1
    xor a
.checkSum
    xor (hl)
    inc hl
    djnz .checkSum
    cp (hl)
    jr nz, .fail
    ld a, (time_buffer + TC_TZ_OFF)
    ld (Sntp.tz), a
    ld hl, time_buffer + TC_FIELDS_OFF
    ld de, Sntp.fields
    ld bc, 6
    ldir
    or a
    ret
.failOpen
    pop iy
.fail
    scf
    ret

; Close the file; CF=0 only if close and exact transfer both succeeded
closeTransferT:
    jr c, .close
    ld a, c
    xor TC_SIZE
    or b
    jr z, .close
    scf
.close
    push af
    ld iy, #5C3A
    ld a, (Config.file_handle)
    rst $08
    db Config.F_CLOSE
    pop bc
    ret c
    rr c
    ret

time_signature db TC_SIG_0, TC_SIG_1, TC_VERSION
time_filename:
    IFDEF NEXT
    db "c:/sys/config/nettime.cfg", 0
    ELSE
    db "/SYS/CONFIG/NETTIME.CFG", 0
    ENDIF

; ============================================
; Field formatting
; ============================================

; Print A (0-99) as two digits
put2:
    ld b, 0
.loop
    cp 10
    jr c, .done
    sub 10
    inc b
    jr .loop
.done
    ld c, a
    push bc
    ld a, b
    add a, '0'
    call Display.putC
    pop bc
    ld a, c
    add a, '0'
    jp Display.putC

; Print "DD/MM/YYYY HH:MM:SS" from HL = y,mo,d,h,mi,s
printFields:
    ld de, pfbuf
    ld bc, 6
    ldir
    ld a, (pfbuf + 2)
    call put2
    ld a, '/'
    call Display.putC
    ld a, (pfbuf + 1)
    call put2
    ld a, '/'
    call Display.putC
    ld a, '2'
    call Display.putC
    ld a, '0'
    call Display.putC
    ld a, (pfbuf)
    call put2
    ld a, ' '
    call Display.putC
    ld a, (pfbuf + 3)
    call put2
    ld a, ':'
    call Display.putC
    ld a, (pfbuf + 4)
    call put2
    ld a, ':'
    call Display.putC
    ld a, (pfbuf + 5)
    jp put2

; Print "UTC+X" using Sntp.tz
printZone:
    ld hl, .z_utc
    call Display.putStr
    ld a, (Sntp.tz)
    or a
    jp p, .pos
    ld a, '-'
    jr .sign
.pos
    ld a, '+'
.sign
    call Display.putC
    ld a, (Sntp.tz)
    or a
    jp p, .abs
    neg
.abs
    jp put2

.z_utc db "UTC", 0

; ============================================
; Zone and date/time input parsing
; ============================================

; zone_buf -> Sntp.tz (signed hours), CF=0 valid
parseZone:
    ld hl, zone_buf
    ld b, 0
    ld a, (hl)
    cp '-'
    jr nz, .tryPlus
    ld b, 1
    inc hl
    jr .unsigned
.tryPlus
    cp '+'
    jr nz, .unsigned
    inc hl
.unsigned
    ld c, 0
    ld d, 0
.loop
    ld a, (hl)
    and a
    jr z, .done
    sub '0'
    cp 10
    jr nc, .bad
    ld e, a
    ld a, c
    add a, a
    add a, a
    add a, c
    add a, a
    add a, e
    ld c, a
    inc d
    ld a, d
    cp 3
    jr nc, .bad
    inc hl
    jr .loop
.done
    ld a, d
    or a
    jr z, .bad
    ld a, c
    bit 0, b
    jr z, .positive
    cp 13
    jr nc, .bad
    neg
    jr .store
.positive
    cp 15
    jr nc, .bad
.store
    ld (Sntp.tz), a
    or a
    ret
.bad
    scf
    ret

; time_buf parsing was removed with the manual set screen; SNTP fills
; Sntp.fields directly and the zone editor uses zone_buf.

zone_buf = sip_buf
    RTVAR pfbuf, 6
