    module Compat
; API methods
ESX_GETSETDRV = #89
ESX_FOPEN = #9A
ESX_FCLOSE = #9B
ESX_FSYNC = #9C
ESX_FREAD = #9D
ESX_FWRITE = #9E

FMODE_CREATE = #0E

; Guarda configuración WiFi en /sys/config/iw.cfg
; Salida: CF=0 éxito, CF=1 error
iwConfig:
    ld a, (UI.cursor_position) : ld hl, UI.offset : add (hl) : ld d, a : call UI.findRow ;; HL = SSID NAME
    
    ; Limpiar buffers primero
    push hl
    ld hl, ssid
    ld de, ssid + 1
    xor a
    ld (hl), a
    ld bc, 79
    ldir
    ld hl, pass
    ld de, pass + 1
    ld (hl), a
    ld bc, 79
    ldir
    pop hl
    
    ld de, ssid
.copySSID
    ld a, (hl) : and a : jr z, .copyPass
    ld (de),a
    inc hl, de
    jr .copySSID
    
.copyPass
    ld hl, UI.pass_buffer
    ld de, pass
.loop
    ld a, (hl) : and a : jr z, .store
    ld (de),a
    inc hl, de
    jr .loop
    
.store
    ; Obtener drive actual
    ld a, 0 : rst #8
    db ESX_GETSETDRV
    jr c, .error

    ; Abrir archivo para escritura
    ld ix, .filename
    ld hl, .filename
    ld b, FMODE_CREATE
    rst #8 
    db ESX_FOPEN
    jr c, .error
    
    ld (.handle), a     ; Guardar handle

    ; Escribir datos
    ld ix, ssid
    ld bc, 160
    rst #8
    db ESX_FWRITE
    jr c, .close_error

    ; Sincronizar
    ld a, (.handle)
    rst #8
    db ESX_FSYNC
    jr c, .close_error

    ; Cerrar archivo
    ld a, (.handle)
    rst #8
    db ESX_FCLOSE
    jr c, .error
    
    ; Éxito
    or a                ; CF = 0
    ret

.close_error
    ; Intentar cerrar el archivo antes de reportar error
    ld a, (.handle)
    rst #8
    db ESX_FCLOSE

.error
    ; Mostrar mensaje de error
    push af
    ld hl, .err_msg
    call Display.putStrLog
    pop af
    scf                 ; CF = 1
    ret

.filename db "/sys/config/iw.cfg", 0
.handle db 0
.err_msg db 13, "Config save failed!", 0

ssid    ds 80
pass    ds 80
    endmodule
