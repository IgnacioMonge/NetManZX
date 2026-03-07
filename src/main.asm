    device ZXSPECTRUM48

    IFDEF DOT
        org #8000               ; DOT también en #8000 (más seguro)
    ELSE
        org #8000          
    ENDIF

    ; Definición global de versión (fuente única)
    ; V = Mmp...  (M=major, m=minor, p=patch opcional)
    ; Ejemplos: V=12  -> 1.2
    ;           V=121 -> 1.2.1
    DEFINE V 130

; Constantes globales
buffer = #C000
stack_top = #FFF0

; Runtime data area: uninitialized buffers placed after the SSID buffer
; to keep them out of the binary. Use RTVAR to allocate.
MAX_NETWORKS    = 20
MAX_SSID_LEN    = 32
BUFFER_SIZE     = (MAX_NETWORKS * (MAX_SSID_LEN + 1))
BUFFER_END      = buffer + BUFFER_SIZE
rt_ptr = BUFFER_END

    MACRO RTVAR name?, size?
name? = @rt_ptr
@rt_ptr = @rt_ptr + size?
    ENDM

text 
    jp start
    
    include "modules/display.asm"
    include "modules/wifi.asm"
    include "modules/version.asm"    ; genera VERSION_STRING desde V
version_string:
    db VERSION_STRING, 0
    include "modules/ui.asm"
    include "modules/uart-common.asm"
    include "modules/keyboard.asm"

    ; ------------------------------------------------------------
    ; UART backend selection (SjASMPlus compatible)
    ;
    ; Build defines:
    ;   -DUNO  : ZX-Uno compatible UART (e.g., divMMC+ESP-12 boards such as DivTIESUS)
    ;   -DNEXT : ZX Spectrum Next UART
    ;   -DAY   : AY-3-8912 UART (ZX-Badaloc and similar)
    ;
    ; If none is provided, AY is used as a safe default.
    ; ------------------------------------------------------------
    IFDEF UNO
        include "drivers/zxuno.asm"
    ELSE
        IFDEF NEXT
            include "drivers/next.asm"
        ELSE
            include "drivers/ay.asm"
        ENDIF
    ENDIF

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
    call Uart.init

    ; Salir de modo transparente (si SpecTalkZX u otro lo dejó activo)
    ; Requiere 1s de silencio previo (cumplido: acabamos de iniciar)
    call Wifi.exitTransparent

    ; Comprobar si ya hay conexión
    ld hl, .msg_query_status
    call Display.putStrLog
    call Wifi.checkConnection
    jr nc, .already_connected  ; Si CF=0 (OK), estamos conectados

    ; Fallback: algunos firmwares no responden a CWJAP? pero sí tienen IP asignada.
    ; Si hay IP válida, consideramos que ya está conectado.
    call Wifi.getIP
    jr c, .no_preconn
    ld a, 1
    ld (Wifi.is_connected), a
    ld hl, Wifi.connected_ssid
    ld a, (hl)
    and a
    jr nz, .already_connected
    ; SSID desconocido -> mostrar marcador
    ld hl, .ssid_unknown
    ld de, Wifi.connected_ssid
.copy_ssid_u
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    and a
    jr nz, .copy_ssid_u
    jr .already_connected

.no_preconn
    ; --- NO CONECTADO: inicialización completa ---
    ld hl, .msg_init_wifi
    call Display.putStrLog
    
    call Wifi.init
    jp c, .init_failed
    
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
    ld (.scan_fail_reason), a    ; 0 = sin fallo, 1 = timeout, 2 = 0 redes
    
    ld b, 5                 ; 5 intentos
    
.scan_loop
    push bc
    
    call UI.topClean
    gotoXY 1, 3
    ld hl, .msg_scanning
    call Display.putStr
    
    call Wifi.getList
    
    jr c, .scan_timeout     ; CF=1 -> Error de comunicación
    
    ld a, (Wifi.networks_count)
    and a
    jr nz, .scan_success    ; Encontradas -> Salir
    
    ; 0 redes encontradas
    ld a, 2
    ld (.scan_fail_reason), a
    jr .retry_wait

.scan_timeout
    ld a, 1
    ld (.scan_fail_reason), a
    
.retry_wait
    pop bc
    push bc
    
    ; Mostrar mensaje de reintento según tipo de fallo
    gotoXY 1, 5
    ld a, (.scan_fail_reason)
    cp 1
    jr nz, .show_no_networks
    ld hl, .msg_esp_timeout
    jr .show_retry_msg
.show_no_networks
    ld hl, .msg_no_networks
.show_retry_msg
    call Display.putStr
    
    ld b, 50                ; Espera más larga para ver mensaje
.w  halt
    djnz .w
    
    pop bc
    djnz .scan_loop
    
    jr .end_scan

.scan_success
    pop bc
    xor a
    ld (.scan_fail_reason), a    ; Éxito

.end_scan
    ; Si no hay redes, mostrar razón en el log
    ld a, (Wifi.networks_count)
    and a
    jr nz, .show_list
    
    ld a, (.scan_fail_reason)
    cp 1
    jr nz, .log_no_networks
    ld hl, .msg_log_timeout
    jr .log_reason
.log_no_networks
    ld hl, .msg_log_empty
.log_reason
    call Display.putStrLog

.show_list
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
    ; Fall through to exit_clean

.exit_clean
    ld sp, (saved_sp)
    ei
    ret

; Textos auxiliares
.msg_checking   db "Checking connection...", 13, 0
.msg_preparing  db "Preparing UART...", 13, 0
.msg_query_status db "Checking WiFi status...", 13, 0
.ssid_unknown     db "(unknown)", 0
.msg_init_wifi  db "Initializing WiFi module...", 13, 0
.msg_scanning   db "Scanning...", 0
.msg_err_init   db "WiFi Init Failed", 0
.msg_exit       db " Press key", 0
.msg_esp_timeout db "ESP not responding, retrying...", 0
.msg_no_networks db "No networks found, retrying...", 0
.msg_log_timeout db "Scan failed: ESP timeout", 13, 0
.msg_log_empty   db "Scan complete: no networks", 13, 0

; Variables
.scan_fail_reason db 0          ; 0=ok, 1=timeout, 2=empty
saved_sp dw 0

program_end:

    ; Build-time safety checks
    ASSERT program_end <= buffer              ; code must not overlap SSID buffer
    ASSERT rt_ptr <= stack_top - 64           ; runtime vars must not reach stack

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