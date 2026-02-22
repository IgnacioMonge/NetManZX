    module EsxDOS

ESX_GETSETDRV = #89
ESX_EXEC = #8F
ESX_FOPEN = #9A
ESX_FCLOSE = #9B
ESX_FSYNC = #9C
ESX_FWRITE = #9E
ESX_UNLINK = #AD
ESX_FRENAME = #B0


FMODE_CREATE = #0E

CMD_BUFF = 23512


; Build filename from Wifi.fname_buf (ASCIIZ), max 12 chars.
; Replaces path separators with '_' as a safety measure.
setFilenameFromWifi:
    ld de, filename
    ld hl, Wifi.fname_buf
    ld b, 12
    ld c, 1                  ; first output character flag (avoid leading space)
.sf_loop
    ld a, (hl)
    or a
    jr z, .sf_done

    ; Ensure filename does not start with a space (FAT compatibility)
    cp 32                    ; ' '
    jr nz, .sf_filter
    ld a, c
    or a
    ld a, 32                 ; default: keep space (not first)
    jr z, .sf_filter
    ld a, '_'                ; first char was space -> '_'

.sf_filter
    ; Replace path separators and FAT-forbidden characters with '_'
    cp 47                    ; '/'
    jr z, .sf_us
    cp 92                    ; '\'
    jr z, .sf_us
    cp 42                    ; '*'
    jr z, .sf_us
    cp 63                    ; '?'
    jr z, .sf_us
    cp 60                    ; '<'
    jr z, .sf_us
    cp 62                    ; '>'
    jr z, .sf_us
    cp 124                   ; '|'
    jr z, .sf_us
    cp 34                    ; '"'
    jr z, .sf_us
    jr .sf_store

.sf_us
    ld a, '_'

.sf_store
    ld (de), a
    inc de
    inc hl
    xor a
    ld c, a                  ; after first stored char
    djnz .sf_loop
.sf_done
    xor a
    ld (de), a
    ret

; Delete the current file (filename buffer).
; Used to clean up incomplete transfers.
; Returns: CF=0 on success, CF=1 on error
deleteFile:
    xor a
    rst #8
    db ESX_GETSETDRV

    ld hl, filename
    ld ix, filename
    rst #8
    db ESX_UNLINK
    ret

prepareFile:
    xor a
    rst #8
    db ESX_GETSETDRV
    jr nc, .drv_ok
    push af
    printMsg msg_drv_err
    pop af
    call PrintHexA
    ld a, 13 : rst #10
    scf
    ret
.drv_ok

    ld hl, filename
    ld ix, filename
    ld b, FMODE_CREATE
    rst #8 
    db ESX_FOPEN
    jp c, .err

    ld (fhandle), a
    xor a
    ld (total_written), a
    ld (total_written+1), a
    ld (total_written+2), a
    ld (total_written+3), a
    ret
.err
    push af
    printMsg msg_fopen_err
    pop af
    call PrintHexA
    ; Also print the filename that failed
    printMsg msg_fopen_file
    ld hl, filename
    ld ix, filename
    call Display.putStr
    ld a, 13 : rst #10
    scf
    ret

;; HL - source pointer
;; BC - chunk size
;; Returns: CF=0 on success, CF=1 on error (including size overflow)
writeChunkPtr:
    ; First check if this write would exceed MAX_SNA_SIZE (131103 = #1FFFF + header)
    ; Calculate: total_written + BC and compare against MAX_SNA_SIZE
    push hl
    push bc
    
    ; Load total_written into DE:HL (32-bit)
    ld hl, (total_written)
    ld de, (total_written+2)
    
    ; Add BC to HL (low 16 bits)
    add hl, bc
    jr nc, .no_carry
    inc de                    ; Propagate carry to high word
.no_carry:
    
    ; Compare DE:HL against MAX_SNA_SIZE (0x0002001F = 131103)
    ; If DE > 2, overflow
    ld a, d
    or a
    jr nz, .overflow
    ld a, e
    cp 3
    jr nc, .overflow          ; DE >= 3, definitely too big
    cp 2
    jr c, .size_ok            ; DE < 2, definitely OK
    ; DE == 2, check HL <= #001F
    ld a, h
    or a
    jr nz, .overflow          ; H != 0, too big
    ld a, l
    cp #20
    jr nc, .overflow          ; L >= #20, too big
    
.size_ok:
    pop bc
    pop hl
    
    ; Proceed with actual write
    ld a, (fhandle)
    ld ix, hl
    push bc
    rst #8 : db ESX_FWRITE
    pop bc
    jr c, .fwrite_err_ptr

    ; accumulate total bytes written (32-bit)
    ld hl, total_written
    ld a, (hl) : add a, c : ld (hl), a
    inc hl
    ld a, (hl) : adc a, b : ld (hl), a
    inc hl
    ld a, (hl) : adc a, 0 : ld (hl), a
    inc hl
    ld a, (hl) : adc a, 0 : ld (hl), a
    or a
    ret

.overflow:
    pop bc
    pop hl
    printMsg msg_size_overflow
    scf
    ret

.fwrite_err_ptr
    push af
    printMsg msg_fwrite
    pop af
    call PrintHexA
    ld a, 13 : rst #10
    or a
    scf
    ret


closeOnly:
    ld a, (fhandle)
    rst #8 : db ESX_FSYNC
    ; Ignore FSYNC errors on abort

    ld a, (fhandle)
    rst #8 : db ESX_FCLOSE
    ret

closeAndRun:
    ld a, (fhandle)
    rst #8 : db ESX_FSYNC
    jr nc, .fsync_ok
    push af
    printMsg msg_fsync
    pop af
    call PrintHexA
    ld a, 13 : rst #10
    or a
.fsync_ok

    ld a, (fhandle)
    rst #8 : db ESX_FCLOSE
    jr nc, .fclose_ok
    push af
    printMsg msg_fclose
    pop af
    call PrintHexA
    ld a, 13 : rst #10
    or a
.fclose_ok


    ; Validate snapshot size before executing snapload
    call .CheckSnapSize
    ret c

    ; Stop TCP server and reset ESP8266 so port 6144 is not left open after the dot-command finishes
    ; (matches original Lain behavior). Best-effort; does not wait for responses.
    call Wifi.cleanupAfterDone

    ld hl, command
    ld de, CMD_BUFF
    ld bc, size
    ldir

    ld hl, CMD_BUFF
    ld ix, CMD_BUFF
    ei
    rst #8
    db ESX_EXEC
    ret nc
    push af
    printMsg msg_exec
    pop af
    call PrintHexA
    ld a, 13 : rst #10
    or a
    ret

.CheckSnapSize:
    ; 48K SNA size = 49179 (0x0000C01B)
    ld hl, total_written
    ld a, (hl) : cp #1B : jr nz, .chk128
    inc hl
    ld a, (hl) : cp #C0 : jr nz, .chk128
    inc hl
    ld a, (hl) : or a : jr nz, .chk128
    inc hl
    ld a, (hl) : or a : jr nz, .chk128
    or a
    ret
.chk128:
    ; 128K SNA size = 131103 (0x0002001F)
    ld hl, total_written
    ld a, (hl) : cp #1F : jr nz, .bad
    inc hl
    ld a, (hl) : or a : jr nz, .bad
    inc hl
    ld a, (hl) : cp #02 : jr nz, .bad
    inc hl
    ld a, (hl) : or a : jr nz, .bad
    or a
    ret
.bad:
    printMsg msg_badsize
    ld a, 13 : rst #10
    scf
    ret

PrintHexA:
    push af
    rrca : rrca : rrca : rrca
    call .Nib
    pop af
    call .Nib
    ret
.Nib:
    and #0F
    add a, '0'
    cp '9'+1
    jr c, .out
    add a, 7
.out:
    rst #10
    ret

msg_fwrite db "FWRITE error A=", 0
msg_size_overflow db "ERROR: File too large (max 128K SNA)", 13, 0
msg_fsync  db "FSYNC error A=", 0
msg_fclose db "FCLOSE error A=", 0
msg_exec   db "EXEC error A=", 0
msg_badsize db "Invalid SNA size", 0
msg_drv_err db "Drive error A=", 0
msg_fopen_err db "FOPEN error A=", 0
msg_fopen_file db 13, "File: ", 0
total_written db 0,0,0,0
fhandle db 0
command db "snapload "
filename ds 13
    ds 12
    db 0
size = $ - command
    endmodule
