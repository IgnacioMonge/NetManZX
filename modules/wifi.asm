    MACRO EspSend Text
    ld hl, .txtB
    ld e, (.txtE - .txtB)
    call Wifi.espSend
    jr .txtE
.txtB 
    db Text
.txtE 
    ENDM

    MACRO EspCmd Text
    ld hl, .txtB
    ld e, (.txtE - .txtB)
    call Wifi.espSend
    jr .txtE
.txtB 
    db Text
    db 13, 10 
.txtE
    ENDM

    MACRO EspCmdOkErr text
    EspCmd text
    call Wifi.checkOkErr
    ENDM

    module Wifi

; Constantes de configuración
MAX_NETWORKS    = 20          ; Máximo número de redes a almacenar
MAX_SSID_LEN    = 32          ; Longitud máxima de SSID
BUFFER_END      = buffer + (MAX_NETWORKS * (MAX_SSID_LEN + 1))
BUFFER_SIZE     = (MAX_NETWORKS * (MAX_SSID_LEN + 1))
MAX_RETRIES     = 3           ; Reintentos en init

checkConnection:
    call flushInput

    EspCmd "AT"
    call Uart.readTimeout 
    call flushInput       

    ld hl, connected_ssid
    ld (hl), 0
    
    EspCmd "AT+CWJAP?"
    
.waitResp
    call Uart.readTimeout
    jp nc, .notConnected
    
    cp '+' : jr z, .plusFound
    cp 'N' : jr z, .noAP
    cp 'O' : jr z, .okFound
    jr .waitResp

.plusFound
    call Uart.readTimeout : jr nc, .notConnected
    cp 'C' : jr nz, .waitResp
    call Uart.readTimeout : jr nc, .notConnected
    cp 'W' : jr nz, .waitResp
    call Uart.readTimeout : jr nc, .notConnected
    cp 'J' : jr nz, .waitResp
    call Uart.readTimeout : jr nc, .notConnected
    cp 'A' : jr nz, .waitResp
    call Uart.readTimeout : jr nc, .notConnected
    cp 'P' : jr nz, .waitResp
    call Uart.readTimeout : jr nc, .notConnected
    cp ':' : jr nz, .waitResp
    call Uart.readTimeout : jr nc, .notConnected
    cp '"' : jr nz, .waitResp
    
    ld hl, connected_ssid
.readSSID
    call Uart.readTimeout : jr nc, .notConnected
    cp '"' : jr z, .gotSSID
    ld (hl), a
    inc hl
    jr .readSSID
.gotSSID
    xor a
    ld (hl), a              
    
.flushOK
    call Uart.readTimeout
    jr nc, .connected
    cp 10 : jr nz, .flushOK
    
.connected
    ld a, 1
    ld (is_connected), a
    or a                    
    ret

.noAP
    call Uart.readTimeout : jr nc, .notConnected
    cp 'o' : jr nz, .waitResp
    
.okFound
.flushEnd
    call Uart.readTimeout
    jr nc, .notConnected
    cp 10 : jr nz, .flushEnd

.notConnected
    xor a
    ld (is_connected), a
    scf                     
    ret

flushInput:
    call UartImpl.uartRead  
    jr c, flushInput        
    ret                     

init:
    call flushInput         

    EspSend "+++"
    ld b, 50
.wait_init
    halt
    djnz .wait_init
    
    ld a, MAX_RETRIES
    ld (retry_count), a
    
.retry_reset
    call reset
    jr nc, .reset_ok
    
    ld a, (retry_count)
    dec a
    ld (retry_count), a
    jr z, .reset_failed
    
    ld b, 100
.retry_wait
    halt
    djnz .retry_wait
    jr .retry_reset

.reset_failed
    scf
    ret
    
.reset_ok
    EspCmdOkErr "ATE0"
    EspCmdOkErr "AT+SYSSTORE=1"
    jr c, .old_fw_detect
    EspCmdOkErr "AT+CWMODE=1"
    jr .check_mode

.old_fw_detect
    ld a, 1
    ld (old_fw), a
    EspCmdOkErr "AT+CWMODE_DEF=1"

.check_mode
    jr c, .err
    EspCmdOkErr "AT+CWAUTOCONN=1"
    jr c, .err
    EspCmdOkErr "AT+CWQAP"
    jr c, .err
    ret

.err
    ld hl, .err_msg
    call Display.putStrLog
    ld b, 100
.wait_err
    halt
    djnz .wait_err
    ei                  
    scf                 
    ret
.err_msg db 13, "ESP error!", 0

reset:
    call flushInput     

    EspCmdOkErr "AT"
    jr c, .timeout_err
    EspCmd "AT+RST"
    
    ld de, 0
.loop
    call Uart.readTimeout
    jr nc, .check_timeout
    
    cp 'e' : jr nz, .loop
    call Uart.readTimeout : jr nc, .timeout_err
    cp 'a' : jr nz, .loop
    call Uart.readTimeout : jr nc, .timeout_err
    cp 'd' : jr nz, .loop
    call Uart.readTimeout : jr nc, .timeout_err
    cp 'y' : jr nz, .loop
    or a                
    ret

.check_timeout
    dec de
    ld a, d
    or e
    jr nz, .loop
.timeout_err
    ld hl, .timeout_msg
    call Display.putStrLog
    scf
    ret
.timeout_msg db 13, "ESP timeout!", 0

getList:
    call flushInput

    ; --- LIMPIEZA DE MEMORIA SEGURA (LDIR) ---
    ld hl, buffer
    ld de, buffer + 1
    ld bc, BUFFER_SIZE - 1
    xor a
    ld (hl), a      ; Poner a 0 el primer byte
    ldir            ; Extender el 0 a todo el buffer
    ; -----------------------------------------

    ld hl, buffer
    ld (buff_ptr), hl
    ld hl, rssi_buffer
    ld (rssi_ptr), hl
    xor a
    ld (networks_count), a
    
    EspCmd "AT+CWLAP"
    ; fall through to loadList

loadList:
    call Uart.readTimeout
    jp nc, .scan_timeout
    
    cp '+' : jr z, .plusStart
    cp 'O' : jr z, .okStart
    cp 'E' : jp z, .errStart
    jr loadList

.plusStart
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'C' : jr nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'W' : jr nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'L' : jr nz, loadList
    jr .loadAp

.okStart
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'K' : jr nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 13  : jr nz, loadList
    or a
    ret

.errStart
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'R' : jp nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'R' : jp nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'O' : jp nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'R' : jp nz, loadList
    jp init.err

.scan_timeout
    ld hl, .timeout_msg
    call Display.putStrLog
    scf
    ret
.timeout_msg db 13, "Scan timeout!", 0

.loadAp
    ld a, (networks_count)
    cp MAX_NETWORKS
    jp nc, loadList     

.skipToEcn
    call Uart.readTimeout : jp nc, .scan_timeout
    cp '(' : jr nz, .skipToEcn
    
    call Uart.readTimeout : jp nc, .scan_timeout
    sub '0'
    ld hl, (rssi_ptr)
    ld (hl), a          
    
.findQuote
    call Uart.readTimeout : jp nc, .scan_timeout
    cp '"' : jr nz, .findQuote
    
    ld c, 0
    
.loadName
    call Uart.readTimeout : jp nc, .scan_timeout
    cp '"' : jr z, .loadedName
    
    ld b, a             
    ld a, c
    cp MAX_SSID_LEN
    ld a, b             
    jr nc, .loadName    
    
    ld hl, (buff_ptr)
    push de
    ld de, BUFFER_END
    or a
    sbc hl, de
    add hl, de          
    pop de
    jr nc, .bufferFull  
    
    ld (hl), a
    inc hl
    ld (buff_ptr), hl
    inc c
    jr .loadName

.bufferFull
    ld hl, .full_msg
    call Display.putStrLog
    or a
    ret
.full_msg db 13, "Buffer full!", 0

.loadedName
    xor a
    ld hl, (buff_ptr) : ld (hl), a : inc hl : ld (buff_ptr), hl
    
.findRssi
    call Uart.readTimeout : jp nc, .scan_timeout
    cp ',' : jr nz, .findRssi
    
    call Uart.readTimeout : jp nc, .scan_timeout
    cp '-' : jr nz, .skipRssi   
    
    ld de, 0            
.readRssiDigit
    call Uart.readTimeout : jp nc, .scan_timeout
    cp '0' : jr c, .rssiDone
    cp '9'+1 : jr nc, .rssiDone
    
    sub '0'
    ld b, a
    ld a, e
    add a, a            
    ld e, a
    add a, a            
    add a, a            
    add a, e            
    add a, b            
    ld e, a
    jr .readRssiDigit

.skipRssi
    ld e, 99            
.rssiDone
    ld hl, (rssi_ptr)
    ld a, (hl)          
    and a
    ld a, e
    jr nz, .notOpen
    or #80              
.notOpen
    ld (hl), a
    inc hl
    ld (rssi_ptr), hl
    
    ld hl, networks_count : inc (hl)
    jp loadList

espSend:
    ld a, (hl) 
    push hl, de
    call Uart.write
    pop de, hl
    inc hl 
    dec e
    jr nz, espSend
    ret

espSendZ:
    ld a, (hl) : and a : ret z
    push hl
    call Uart.write
    pop hl
    inc hl
    jr espSendZ

; checkOkErr - Usa timeout normal
checkOkErr:
    xor a
    ld (use_long_timeout), a
    ld (last_error), a          ; Sin error específico
    jr checkOkErrCommon

; checkOkErrLong - Usa timeout largo para AT+CWJAP
checkOkErrLong:
    ld a, 1
    ld (use_long_timeout), a
    xor a
    ld (last_error), a          ; Sin error específico
    ; Fall through

checkOkErrCommon:
    ; Límite de bytes para evitar bucle infinito con tráfico de red
    ld hl, 2000                 ; Máximo 2000 bytes antes de rendirse
    ld (byte_limit), hl

.mainLoop
    ; Verificar límite
    ld hl, (byte_limit)
    ld a, h
    or l
    jr z, .timeout              ; Límite alcanzado
    dec hl
    ld (byte_limit), hl
    
    call .doRead
    jr nc, .timeout
    cp 'O' : jp z, .okStart 
    cp 'E' : jp z, .errStart 
    cp 'F' : jp z, .failStart
    cp '+' : jp z, .plusStart   ; Detectar +CWJAP:X
    ; Ignorar mensajes asíncronos
    jr .mainLoop

.timeout
    scf
    ret

.okStart
    call .doRead : jr nc, .timeout
    cp 'K' : jp nz, .mainLoop
    call .doRead : jr nc, .timeout
    cp 13  : jp nz, .mainLoop
    call .flushToLF
    or a
    ret
.errStart
    call .doRead : jr nc, .timeout
    cp 'R' : jp nz, .mainLoop
    call .doRead : jr nc, .timeout
    cp 'R' : jp nz, .mainLoop
    call .doRead : jr nc, .timeout
    cp 'O' : jp nz, .mainLoop
    call .doRead : jr nc, .timeout
    cp 'R' : jp nz, .mainLoop
    call .flushToLF
    scf 
    ret 
.failStart
    call .doRead : jr nc, .timeout
    cp 'A' : jp nz, .mainLoop
    call .doRead : jr nc, .timeout
    cp 'I' : jp nz, .mainLoop
    call .doRead : jr nc, .timeout
    cp 'L' : jp nz, .mainLoop
    call .flushToLF
    scf
    ret

; Detectar +CWJAP:X para códigos de error
.plusStart
    call .doRead : jp nc, .timeout
    cp 'C' : jp nz, .mainLoop   ; No es +CWJAP
    call .doRead : jp nc, .timeout
    cp 'W' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 'J' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 'A' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 'P' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp ':' : jp nz, .mainLoop
    ; Leer código de error (1-4)
    call .doRead : jp nc, .timeout
    sub '0'                     ; Convertir ASCII a número
    ld (last_error), a          ; Guardar código de error
    call .flushToLF
    jp .mainLoop                ; Seguir esperando ERROR/FAIL

.flushToLF
    call .doRead
    ret nc              
    cp 10 : jr nz, .flushToLF
    ret

; Subrutina que llama al read apropiado según use_long_timeout
.doRead
    ld a, (use_long_timeout)
    and a
    jp z, Uart.readTimeout
    jp Uart.readTimeoutLong

use_long_timeout db 0
byte_limit       dw 0
last_error       db 0           ; Código de error CWJAP (0=ninguno, 1-4=error)

; ============================================
; getIP - Obtiene la IP actual del ESP
; Resultado en ip_buffer
; CF=0 si éxito, CF=1 si error
; ============================================
getIP:
    ; Limpiar buffer primero
    ld hl, ip_buffer
    ld b, 16
    xor a
.clear
    ld (hl), a
    inc hl
    djnz .clear

    EspCmd "AT+CIFSR"
.loop
    call Uart.read
    cp 'P' : jr z, .infoStart
    jr .loop
.infoStart
    call Uart.read : cp ',' : jr nz, .loop
    call Uart.read : cp '"' : jr nz, .loop
    ld hl, ip_buffer
.copyIpLoop
    push hl
    call Uart.read
    pop hl
    cp '"' : jr z, .finish
    ld (hl), a
    inc hl
    jr .copyIpLoop
.finish
    xor a
    ld (hl), a
    ; Verificar que hay algo válido
    ld a, (ip_buffer)
    cp '0'
    jr nz, .ok
    ld a, (ip_buffer + 1)
    cp '.'
    jr z, .noIP
.ok
    or a                    ; CF = 0
    ret
.noIP
    scf                     ; CF = 1
    ret

; Variables del módulo
buff_ptr        dw buffer
rssi_ptr        dw rssi_buffer
networks_count  db 0
old_fw          db 0
retry_count     db 0
is_connected    db 0

rssi_buffer     ds MAX_NETWORKS
connected_ssid  ds MAX_SSID_LEN + 1
ip_buffer       ds 16               ; Buffer para IP (xxx.xxx.xxx.xxx + null)

    endmodule