; ============================================
; config.asm - Save/load WiFi credentials
; NEXT: native +3DOS via M_P3DOS
; UNO:  esxDOS (divMMC firmware)
; ============================================

    module Config

; esxDOS API (works on both UNO/divMMC and NEXT/NextZXOS)
; Carry convention: C=error, NC=success
F_OPEN         = $9A
F_CLOSE        = $9B
F_READ         = $9D
F_WRITE        = $9E
FA_READ        = $01
FA_WRITE_CREAT = $0A            ; $02 (write) | $08 (open or create, no truncate)
; +3DOS (for IDE_PATH directory creation on Next)
M_P3DOS        = $94
IDE_PATH       = $01B1

; Config file layout (80 bytes)
CFG_SIZE      = 80

; Allocate runtime buffer (must be before first use)
    RTVAR cfg_buffer, CFG_SIZE
CFG_SIG_0     = 'N'
CFG_SIG_1     = 'M'
CFG_SIG_2     = $1A
CFG_SIG_3     = $00
CFG_VERSION   = $01
CFG_SSID_OFF  = 5
CFG_PASS_OFF  = 38
CFG_CKSUM_OFF = 79

; ============================================
; save - Write current credentials to config file
; Input: Wifi.connected_ssid and UI.pass_buffer must be valid
; Output: CF=0 success, CF=1 fail (silent)
; ============================================
save:
    ; The replacement is not saved until both transfer and close succeed.
    xor a
    ld (cfg_valid), a
    ld hl, cfg_signature
    ld de, cfg_buffer
    ld bc, 5
    ldir
    ex de, hl

    ; Zero-fill SSID area (33 bytes)
    push hl
    ld d, h : ld e, l : inc de
    ld (hl), 0 : ld bc, 32 : ldir
    pop de
    ld hl, Wifi.connected_ssid
    call UI.copyStringZ

    ; Zero-fill password area (41 bytes)
    ld hl, cfg_buffer + CFG_PASS_OFF
    push hl
    ld d, h : ld e, l : inc de
    ld (hl), 0 : ld bc, 40 : ldir
    pop de
    ld hl, UI.pass_buffer
    ld b, 41
.copyPass
    ld a, (hl) : ld (de), a
    and a : jr z, .passDone
    inc hl : inc de
    djnz .copyPass
.passDone

    ; Compute XOR checksum of bytes 0-78
    call calcChecksum
    ld (hl), a

    ; esxDOS save — identical to NextSync createfilewithpath + fwrite + fclose
    push iy

    ; fopen
    ld iy, #5C3A
    ld hl, cfg_filename
    push hl : pop ix
    ld b, FA_WRITE_CREAT
    ld a, '*'
    rst $08
    db F_OPEN
    jr nc, .openOk

    ; fopen failed — create path and retry (Next only, M_P3DOS)
    IFDEF NEXT
    ld hl, cfg_filename
    call createPath
    jr c, .openFail
    ELSE
    jr .openFail                ; divMMC: no mkdir API, just fail
    ENDIF

.openOk
    ld (file_handle), a

    ; fwrite
    ld iy, #5C3A
    ld a, (file_handle)
    ld hl, cfg_buffer
    push hl : pop ix
    ld bc, CFG_SIZE
    rst $08
    db F_WRITE
    call closeTransfer

    pop iy
    ret c

.saveOk
    ld a, 1
    ld (cfg_valid), a
    or a
    ret

.openFail
    pop iy
    scf
    ret

calcChecksum:
    ld hl, cfg_buffer
    ld b, CFG_CKSUM_OFF
    xor a
.loop
    xor (hl) : inc hl
    djnz .loop
    ret

; Close the file; CF=0 only if close and exact transfer both succeeded.
closeTransfer:
    jr c, .close
    ld a, c
    xor CFG_SIZE
    or b
    jr z, .close
    scf
.close
    push af
    ld iy, #5C3A
    ld a, (file_handle)
    rst $08
    db F_CLOSE
    pop bc                       ; C = saved transfer flags
    ret c                        ; Close failure wins
    rr c                         ; Restore transfer CF from saved F
    ret

; ============================================
; load - Read credentials from config file
; Output: CF=0 success (cfg_buffer valid), CF=1 fail
; ============================================
load:
    push iy

    ; fopen
    ld iy, #5C3A
    ld hl, cfg_filename
    push hl : pop ix
    ld b, FA_READ
    ld a, '*'
    rst $08
    db F_OPEN
    jr c, .loadOpenFail
    ld (file_handle), a

    ; fread
    ld iy, #5C3A
    ld a, (file_handle)
    ld hl, cfg_buffer
    push hl : pop ix
    ld bc, CFG_SIZE
    rst $08
    db F_READ
    call closeTransfer

    pop iy
    jr c, .loadFail

.loadValidate
    ; Validate signature
    ld hl, cfg_buffer
    ld de, cfg_signature
    ld b, 5
.checkSignature
    ld a, (de)
    cp (hl)
    jr nz, .loadFail
    inc de
    inc hl
    djnz .checkSignature

    ; Validate XOR checksum
    call calcChecksum
    cp (hl)
    jr nz, .loadFail

    ; Both fixed-width fields must contain a terminator.
    ld hl, cfg_buffer + CFG_SSID_OFF
    ld bc, 33
    xor a
    cpir
    jr nz, .loadFail
    ld hl, cfg_buffer + CFG_PASS_OFF
    ld bc, 41
    cpir
    jr nz, .loadFail

    jp save.saveOk

.loadOpenFail
    pop iy

.loadFail
    xor a
    ld (cfg_valid), a
    scf
    ret

cfg_signature db CFG_SIG_0, CFG_SIG_1, CFG_SIG_2, CFG_SIG_3, CFG_VERSION

; ============================================
; copyToBuffers - Prepare buffers for AT+CWJAP
; ============================================
copyToBuffers:
    ld hl, cfg_buffer + CFG_SSID_OFF
    ld de, UI.manual_ssid_buffer
    call UI.copyStringZ

    ld hl, cfg_buffer + CFG_PASS_OFF
    ld de, UI.pass_buffer
    ld b, UI.MAX_PASS_LEN + 1
.cpLoop
    ld a, (hl) : ld (de), a
    and a : jr z, .cpDone
    inc hl : inc de
    djnz .cpLoop
    xor a : ld (de), a
.cpDone
    xor a
    ld (UI.pass_len), a
    ld (UI.pass_cursor), a
    ret

; Create directory path and open file (NextSync _createfilewithpath, literal copy)
; Input: HL = filename (null-terminated)
; Output: A = file handle, CF=1 on error
; Follows NextSync register pattern exactly: exx for IDE_PATH, retry fopen at end
createPath:
    ld iy, #5C3A
    push hl : pop ix
    ld b, FA_WRITE_CREAT
    ld a, '*'
    push hl
    rst $08
    db F_OPEN
    pop hl
    jr c, .cpOpenFail
    ; Success on first try
    or a                      ; CF=0
    ret
.cpOpenFail
    ld d, h
    ld e, l
    ld a, (hl)
    cp '/'
    jr nz, .cpLoop
    inc hl                     ; Skip root slash; it is not a directory name
.cpLoop
    ld a, (hl)
    or a
    jr z, .cpPathDone
    cp '/'
    jr nz, .cpNotSlash
    ld (hl), $FF              ; Replace '/' with path terminator
    ex de, hl
    push de
    push hl
    ld iy, #5C3A              ; reload IY for M_P3DOS
    ld a, $02                 ; make path
    exx
    ld de, IDE_PATH
    ld c, 7
    rst $08
    db M_P3DOS
    exx                         ; Restore main register set after M_P3DOS args
    pop hl
    pop de
    ex de, hl
    ld (hl), '/'              ; Restore '/'
.cpNotSlash
    inc hl
    jr .cpLoop
.cpPathDone
    ex de, hl
    push hl : pop ix
    ld iy, #5C3A
    ld b, FA_WRITE_CREAT
    ld a, '*'
    rst $08
    db F_OPEN
    jr nc, .cpRetryOk
    ; Failed even after creating path
    scf
    ret
.cpRetryOk
    or a                      ; CF=0
    ret

    IFDEF NEXT
cfg_filename db "c:/sys/config/netman.cfg", 0
    ELSE
cfg_filename db "/SYS/CONFIG/NETMAN.CFG", 0
    ENDIF
file_handle  db 0

    endmodule
