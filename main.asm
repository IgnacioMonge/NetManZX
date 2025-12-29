    device ZXSPECTRUM48

    IFDEF DOT
        org #8000               ; DOT también en #8000 (más seguro)
    ELSE
        org #8000          
    ENDIF

    ; Definición global de versión
    DEFINE VERSION_STRING "v1.1"

; Constantes globales 
buffer = #C000
stack_top = #BFFE

text 
    jp start
    
    include "modules/display.asm"
    include "modules/wifi.asm"
    include "modules/ui.asm"
    include "modules/uart-common.asm"
    include "modules/keyboard.asm"
    include "modules/compat.asm"
    include "drivers/ay.asm"

start:
    ld (saved_sp), sp
    ld sp, stack_top
    
    call UI.init            ; Inicializa pantalla completa (IP: Scanning...)
    
    ; Mostrar mensaje en log
    ld hl, .msg_checking
    call Display.putStrLog
    
    ; Inicializar UART
    ld hl, .msg_preparing
    call Display.putStrLog
    call UartImpl.init
    
    ; Comprobar si ya hay conexión
    call Wifi.checkConnection
    jr nc, .already_connected  ; Si CF=0 (OK), estamos conectados

    ; --- NO CONECTADO: inicialización completa ---
    ld hl, .msg_init_wifi
    call Display.putStrLog
    
    call Wifi.init
    jr c, .init_failed
    
    ; Espera de calentamiento
    ld b, 125
.warmup
    halt
    djnz .warmup

    ; Comprobación final
    call Wifi.checkConnection
    jr c, .not_connected
    
.already_connected:
    ; --- CASO: CONECTADO ---
    call UI.updateWifiStatus    ; Cambia de Scanning a Connected (Verde)
    call UI.ipShowConnected     ; Mostrar IP
    
    call UI.showConnectedDialog 
    jr nc, .force_scan       ; Usuario eligió 'Y' (Reconfigurar) -> Escanear
    
    ; Usuario eligió 'N' (Keep) -> Pantalla de éxito infinita
    jp UI.showConnectedSuccessScreen

.not_connected
    ; --- MODIFICADO: Actualizar barra superior e inferior explícitamente ---
    call UI.ipShowNotConnected  ; Pone "IP: not connected" en la barra superior
    call UI.updateWifiStatus    ; Asegura que la barra inferior esté en ROJO (Disconnected)

.force_scan
    ; --- CASO: NO CONFIGURADO / REESCANEAR ---
    
    ; CRÍTICO: Resetear variables de UI antes de nueva búsqueda
    xor a
    ld (UI.cursor_position), a
    ld (UI.offset), a
    
    ld b, 5                 ; 5 intentos
    
.scan_loop
    push bc
    
    call UI.topClean
    gotoXY 1, 3
    ld hl, .msg_scanning
    call Display.putStr
    
    call Wifi.getList
    
    jr c, .retry_wait       ; Error -> Retry
    
    ld a, (Wifi.networks_count)
    and a
    jr nz, .scan_success    ; Encontradas -> Salir
    
.retry_wait
    pop bc
    push bc
    
    ld b, 25
.w  halt
    djnz .w
    
    pop bc
    djnz .scan_loop
    
    jr .end_scan

.scan_success
    pop bc

.end_scan
    call UI.renderList
    jp   UI.uiLoop

.init_failed
    call Display.clrscr
    ld hl, .msg_err_init
    call Display.putStr
    jr .wait_exit

.wait_exit
    ld hl, .msg_exit
    call Display.putStr
.k  halt
    call Keyboard.inKey
    and a
    jr z, .k
    ret

.exit_clean
    ld sp, (saved_sp)
    ei
    ret

; Textos auxiliares
.msg_checking   db "Checking connection...", 13, 0
.msg_preparing  db "Preparing UART...", 13, 0
.msg_init_wifi  db "Initializing WiFi module...", 13, 0
.msg_scanning   db "Scanning...", 0
.msg_err_init   db "WiFi Init Failed", 0
.msg_exit       db " Press key", 0

saved_sp dw 0

program_end:

    IFDEF TAP
        ; ==========================================
        ; Formato TAP completo (loader + código)
        ; ==========================================
        
        ; Definir loader BASIC en zona temporal
        ORG #6000
basic_start:
        ; Línea 10: CLEAR 32767
        db #00, #0A                 ; Número de línea (10) big-endian
        dw line10end - line10start ; Longitud del contenido
line10start:
        db #FD                      ; CLEAR
        db '3','2','7','6','7'      ; "32767" como texto
        db #0E, #00, #00            ; Marcador de número
        dw 32767                    ; Valor numérico
        db #00                      ; Exponente
        db #0D                      ; ENTER
line10end:

        ; Línea 20: LOAD ""CODE
        db #00, #14                 ; Número de línea (20)
        dw line20end - line20start
line20start:
        db #EF                      ; LOAD
        db '"', '"'                 ; ""
        db #AF                      ; CODE
        db #0D
line20end:

        ; Línea 30: RANDOMIZE USR 32768
        db #00, #1E                 ; Número de línea (30)
        dw line30end - line30start
line30start:
        db #F9                      ; RANDOMIZE
        db #C0                      ; USR
        db '3','2','7','6','8'      ; "32768"
        db #0E, #00, #00
        dw 32768
        db #00
        db #0D
line30end:
basic_end:

        ; Generar TAP
        emptytap "netmanzx.tap"
        savetap "netmanzx.tap", BASIC, "netmanzx", basic_start, basic_end - basic_start, 10
        savetap "netmanzx.tap", CODE, "netmanzx", text, program_end - text, text
        
    ELSE
        ; ==========================================
        ; Formato +3DOS estándar
        ; ==========================================
        save3dos "netmanzx.cod", text, program_end - text
    ENDIF