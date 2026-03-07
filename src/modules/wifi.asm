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

; ============================================
; UART lock (evita competencia con UI.checkAsyncWifi)
; ============================================
uartLock:
    ld a, 1
    ld (uart_busy), a
    ret

uartUnlock:
    xor a
    ld (uart_busy), a
    ret

; Constantes de configuración (MAX_NETWORKS, MAX_SSID_LEN, BUFFER_* defined in main.asm)
MAX_RETRIES     = 3           ; Reintentos en init

checkConnection:
    call flushInput

    ; Wake up ESP and consume full response.
    ; This avoids stray "OK" bytes remaining in RX and contaminating the next query.
    EspCmd "AT"
    call checkOkErr
    call flushInput

    ; Clear stored SSID
    ld hl, connected_ssid
    ld (hl), 0

    ; Try different query variants for maximum AT firmware compatibility
    EspCmd "AT+CWJAP?"
    call .waitCwJAP
    jr nc, .connected

    call flushInput
    EspCmd "AT+CWJAP_CUR?"
    call .waitCwJAP
    jr nc, .connected

    call flushInput
    EspCmd "AT+CWJAP_DEF?"
    call .waitCwJAP
    jr nc, .connected

    ; Not connected
    xor a
    ld (is_connected), a
    scf
    ret

.connected
    ld a, 1
    ld (is_connected), a
    or a
    ret

; ------------------------------------------------------------
; .waitCwJAP
;   Waits for a +CWJAP... line and extracts SSID.
;   Returns: CF=0 if connected (SSID extracted), CF=1 otherwise.
; ------------------------------------------------------------
.waitCwJAP
    ld b, 8                      ; allow several initial timeouts
.loop
    call Uart.readTimeout
    jr c, .got
    djnz .loop
    scf
    ret

.got
    cp '+' : jr z, .plusFound
    cp 'N' : jr z, .noAP
    cp 'E' : jr z, .errorLine
    cp 'O' : jr z, .okLine
    jr .loop

.okLine
    ; OK can appear (e.g., from a previous command). Do not treat it as definitive.
    call .flushToLF
    jr .loop

.errorLine
    ; ERROR can also be stale. Ignore and keep waiting for +CWJAP / No AP.
    call .flushToLF
    jr .loop

.noAP
    ; Consume rest of line ("No AP")
    call .flushToLF
    scf
    ret

.plusFound
    ; Expect CWJAP (possibly with _CUR/_DEF suffix)
    call Uart.readTimeout : jr nc, .fail
    cp 'C' : jr nz, .loop
    call Uart.readTimeout : jr nc, .fail
    cp 'W' : jr nz, .loop
    call Uart.readTimeout : jr nc, .fail
    cp 'J' : jr nz, .loop
    call Uart.readTimeout : jr nc, .fail
    cp 'A' : jr nz, .loop
    call Uart.readTimeout : jr nc, .fail
    cp 'P' : jr nz, .loop

    ; Accept ':' directly, or skip suffix until ':'
.readUntilColon
    call Uart.readTimeout : jr nc, .fail
    cp ':' : jr z, .afterColon
    jr .readUntilColon

.afterColon
    ; Find opening quote
.findQuote
    call Uart.readTimeout : jr nc, .fail
    cp '"' : jr nz, .findQuote

    ; Read SSID until closing quote (bounded)
    ld hl, connected_ssid
    ld b, MAX_SSID_LEN
.readSSID
    call Uart.readTimeout : jr nc, .fail
    cp '"' : jr z, .gotSSID
    ld (hl), a
    inc hl
    djnz .readSSID

    ; Buffer full: only accept if the very next char closes the quote
.waitClosingQuote
    call Uart.readTimeout : jr nc, .fail
    cp '"' : jr z, .gotSSID
    ; SSID too long or malformed line: avoid buffer overrun
    xor a
    ld (hl), a
    call .flushToLF
    scf
    ret

.gotSSID
    xor a
    ld (hl), a

    ; Flush remaining line
    call .flushToLF

    or a                        ; CF=0
    ret

.fail
    scf
    ret

.flushToLF
    call Uart.readTimeout
    ret nc
    cp 10 : jr nz, .flushToLF
    ret

flushInput:
    call UartImpl.uartRead
    jr c, flushInput
    ret

; Salir de modo transparente (+++, guard time, flush)
; Seguro llamar aunque el ESP no esté en modo transparente.
exitTransparent:
    EspSend "+++"
    ld b, 75               ; ~1.5s guard time
.etp_wait
    halt
    djnz .etp_wait
    call flushInput         ; Descartar respuesta (puede ser "NO CHANGE" etc.)
    ret

init:
    call flushInput

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
    
    ; Bounded number of readTimeout misses while waiting for "ready"
    ld de, 200
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
    call uartLock
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
    ld (seen_cwlap), a
    ld (ok_ignored), a
    
    EspCmd "AT+CWLAP"
    ; fall through to loadList

loadList:
    ; Primera espera con timeout largo (el scan puede tardar 5-15 segundos)
    IFDEF NEXT
    ld b, 60                     ; Next: CPU más rápida, más intentos
    ELSE
    ld b, 20                     ; UNO/divMMC: valor original
    ENDIF
.waitFirstResponse
    push bc
    call Uart.readTimeoutLong
    pop bc
    jr c, .gotFirstChar
    djnz .waitFirstResponse
    jp .scan_timeout             ; Sin respuesta después de timeout
    
.gotFirstChar
    cp '+' : jr z, .plusStart
    cp 'O' : jr z, .okStart
    cp 'E' : jp z, .errStart
    jr .continueLoad

.continueLoad
    call Uart.readTimeoutMedium
    jp nc, .scan_timeout
    
    cp '+' : jr z, .plusStart
    cp 'O' : jr z, .okStart
    cp 'E' : jp z, .errStart
    jr .continueLoad

.plusStart
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'C' : jr nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'W' : jr nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'L' : jr nz, loadList
    ld a, 1
    ld (seen_cwlap), a
    jp .loadAp

.okStart
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 'K' : jr nz, loadList
    call Uart.readTimeout : jp nc, .scan_timeout
    cp 13  : jr nz, loadList

    ; Some firmwares (or prior commands) may leave a stray OK in the RX stream.
    ; Ignore the first OK if we have not seen any +CWLAP lines yet.
    ld a, (seen_cwlap)
    and a
    jr nz, .ok_return

    ld a, (ok_ignored)
    and a
    jr nz, .ok_return
    ld a, 1
    ld (ok_ignored), a
    jr loadList

.ok_return
    call initDisplayIndices     ; Inicializar índices para mostrar
    call sortNetworks           ; Ordenar por RSSI automáticamente
    or a
    call uartUnlock
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
    ; Scan devolvió ERROR - limpiar y salir
    ld hl, .scan_err_msg
    call Display.putStrLog
    call uartUnlock
    scf
    ret
.scan_err_msg db 13, "Scan fail!", 0

.scan_timeout
    ld hl, .timeout_msg
    call Display.putStrLog
    call uartUnlock
    scf
    ret
.timeout_msg db 13, "Scan timeout!", 0

.loadAp
    ld a, (networks_count)
    cp MAX_NETWORKS
    jr c, .skipToEcn
    ; Drenar resto de línea antes de volver (evita desincronización)
.flushMax
    call Uart.readTimeout
    jp nc, .scan_timeout
    cp 10
    jr nz, .flushMax
    jp loadList

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
    call uartUnlock
    scf
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
    ; Safe TX log (line-based) for debugging.
    ; Masks AT+CWJAP to avoid printing passwords.
    ld a, (debug_log)
    and a
    jr z, .sendLoop
    push hl
    call logTxMasked
    pop hl
.sendLoop
    ld a, (hl) : and a : ret z
    push hl
    call Uart.write
    pop hl
    inc hl
    jr .sendLoop

; ------------------------------------------------------------
; logTxMasked
;   HL -> Z-terminated command string (usually includes CR/LF)
;   Logs to on-screen UART log as:
;       >> <command>
;   but masks AT+CWJAP payload.
; ------------------------------------------------------------
logTxMasked:
    push hl
    ld hl, dbg_prefix
    call Display.putStrLog
    pop hl

    ; Check prefix "AT+CWJAP" (8 chars)
    push hl
    ld de, dbg_cwjap_prefix
    ld b, 8
.chk
    ld a, (hl)
    ld c, a
    ld a, (de)
    cp c
    jr nz, .notCw
    inc hl
    inc de
    djnz .chk
    pop hl
    ; If this is a query (AT+CWJAP? / _CUR? / _DEF?), suppress TX log to avoid spam.
    push hl
    ld b, 16
.qscan
    ld a, (hl)
    cp '?' : jr z, .skipLog
    cp '=' : jr z, .doMask
    cp 13  : jr z, .doMask
    inc hl
    djnz .qscan
.doMask
    pop hl
    ld hl, dbg_tx_cwjap
    jp Display.putStrLog
.skipLog
    pop hl
    ret
.notCw
    pop hl
    jp Display.putStrLog

dbg_prefix       db ">> ", 0
dbg_cwjap_prefix db "AT+CWJAP"
dbg_tx_cwjap     db "AT+CWJAP=<hidden>", 13, 10, 0
dbg_rx_ok       db "<< OK", 13, 10, 0
dbg_rx_error    db "<< ERROR", 13, 10, 0
dbg_rx_fail     db "<< FAIL", 13, 10, 0


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
    call uartLock
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
    jp nc, .timeout
    cp 'O' : jp z, .okStart 
    cp 'E' : jp z, .errStart 
    cp 'F' : jp z, .failStart
    cp '+' : jp z, .plusStart   ; Detectar +CWJAP:X
    ; Ignorar mensajes asíncronos
    jr .mainLoop

.timeout
    call uartUnlock
    scf
    ret

.okStart
    call .doRead : jp nc, .timeout
    cp 'K' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 13  : jp nz, .mainLoop
    call .flushToLF
    ld a, (debug_log)
    and a
    jr z, .ok_no_log
    push hl
    ld hl, dbg_rx_ok
    call Display.putStrLog
    pop hl
.ok_no_log
    or a
    call uartUnlock
    ret
.errStart
    call .doRead : jp nc, .timeout
    cp 'R' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 'R' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 'O' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 'R' : jp nz, .mainLoop
    call .flushToLF
    ld a, (debug_log)
    and a
    jr z, .err_no_log
    push hl
    ld hl, dbg_rx_error
    call Display.putStrLog
    pop hl
.err_no_log
    call uartUnlock
    scf
    ret 
.failStart
    call .doRead : jp nc, .timeout
    cp 'A' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 'I' : jp nz, .mainLoop
    call .doRead : jp nc, .timeout
    cp 'L' : jp nz, .mainLoop
    call .flushToLF
    ld a, (debug_log)
    and a
    jr z, .fail_no_log
    push hl
    ld hl, dbg_rx_fail
    call Display.putStrLog
    pop hl
.fail_no_log
    call uartUnlock
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
    call uartLock
    ; Limpiar buffer primero
    ld hl, ip_buffer
    ld b, 16
    xor a
.clear
    ld (hl), a
    inc hl
    djnz .clear

    ld bc, 500                  ; Límite de bytes
    EspCmd "AT+CIFSR"
.loop
    dec bc
    ld a, b
    or c
    jr z, .timeout              ; Límite alcanzado
    call Uart.readTimeout
    jp nc, .timeout
    cp 'P' : jr z, .infoStart
    jr .loop
.infoStart
    call Uart.readTimeout : jp nc, .timeout
    cp ',' : jr nz, .loop
    call Uart.readTimeout : jp nc, .timeout
    cp '"' : jr nz, .loop
    ld hl, ip_buffer
    ld b, 16                    ; Límite de caracteres IP
.copyIpLoop
    push hl
    push bc
    call Uart.readTimeout
    pop bc
    pop hl
    jp nc, .timeout
    cp '"' : jr z, .finish
    ld (hl), a
    inc hl
    djnz .copyIpLoop
    ; IP demasiado larga, truncar
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
    call uartUnlock
    ret
.timeout
.noIP
    call uartUnlock
    scf                     ; CF = 1
    ret

; ============================================
; ensureCommandMode
;   Best-effort attempt to ensure the ESP is in AT command mode.
;   1) Send AT and expect OK.
;   2) If not OK, send escape sequence +++ with guard times and retry AT.
;
;   Returns: CF=0 if OK received, CF=1 otherwise.
;
;   Notes:
;   - Mutes UART byte-log while sending raw +++/CRLF to avoid polluting the UART log buffer.
; ============================================
ensureCommandMode:
    ; Fast path
    call flushInput
    EspCmd "AT"
    call checkOkErr
    ret nc

    ; Slow path: try to exit a possible transparent/pass-through mode
    call uartLock

    ; Optional hint in the log (only if UART log is enabled)
    ld a, (Uart.log_enabled)
    and a
    jr z, .noLog
    ld hl, .msg_escape
    call Display.putStrLog
.noLog

    ; Guard time before +++ (about 1 second)
    ld b, 50
.preGuard
    halt
    djnz .preGuard

    ; Mute UART byte log during raw escape transmission
    ld a, (Uart.log_enabled)
    push af
    xor a
    ld (Uart.log_enabled), a

    ; IMPORTANT: per ESP-AT docs, the escape sequence to quit passthrough mode
    ; is exactly three '+' characters with *no* CR/LF appended.
    ; Any extra characters around it may be forwarded as passthrough data and
    ; can also prevent the escape sequence from being recognized.
    ld a, '+'
    call UartImpl.write
    ld a, '+'
    call UartImpl.write
    ld a, '+'
    call UartImpl.write

    pop af
    ld (Uart.log_enabled), a
    call Uart.logReset

    ; Guard time after +++ (about 1 second)
    ld b, 50
.postGuard
    halt
    djnz .postGuard

    call uartUnlock

    ; Clear any response noise and retry AT
    call flushInput
    EspCmd "AT"
    call checkOkErr
    ret

.msg_escape db 13, "-- Escape +++ (trying to exit pass-through)", 13, 10, 0

; ============================================
; initDisplayIndices - Inicializa índices a 0,1,2,...,n-1
; Llamar después de cada escaneo
; ============================================
initDisplayIndices:
    ld hl, display_indices
    xor a
.initLoop
    ld (hl), a
    inc hl
    inc a
    cp MAX_NETWORKS
    jr nz, .initLoop
    xor a
    ld (is_sorted), a
    ret

; ============================================
; sortNetworks - Toggle ordenación por señal
; Si no está ordenado: ordena los índices por RSSI
; Si está ordenado: restaura orden original
; ============================================
sortNetworks:
    ld a, (is_sorted)
    and a
    jr nz, .unsort
    
    ; --- Ordenar por señal (bubble sort sobre índices) ---
    ld a, (networks_count)
    cp 2
    ret c                       ; Si hay 0 o 1 red, no ordenar
    
    dec a
    ld (sort_passes), a

.outerLoop
    ld a, (networks_count)
    dec a
    ld (sort_compares), a
    
    xor a
    ld (sort_index), a
    
.innerLoop
    ; Obtener display_indices[i] y display_indices[i+1]
    ld a, (sort_index)
    ld hl, display_indices
    ld e, a
    ld d, 0
    add hl, de                  ; HL = &display_indices[i]
    
    ld b, (hl)                  ; B = display_indices[i] (índice real red i)
    inc hl
    ld c, (hl)                  ; C = display_indices[i+1] (índice real red i+1)
    
    ; Obtener RSSI de las redes reales
    push hl                     ; Guardar &display_indices[i+1]
    push bc                     ; Guardar B y C
    
    ; RSSI de red B
    ld hl, rssi_buffer
    ld e, b
    ld d, 0
    add hl, de
    ld a, (hl)
    and #7F
    ld d, a                     ; D = RSSI[indices[i]] & 0x7F
    
    ; RSSI de red C
    pop bc                      ; Recuperar B y C
    push de                     ; Guardar D (RSSI de i)
    ld hl, rssi_buffer
    ld e, c
    ld d, 0
    add hl, de
    ld a, (hl)
    and #7F                     ; A = RSSI[indices[i+1]] & 0x7F
    
    pop de                      ; D = RSSI de i
    
    ; Comparar: si RSSI[i+1] < RSSI[i], intercambiar índices
    cp d
    pop hl                      ; HL = &display_indices[i+1]
    jr nc, .noSwap
    
    ; Intercambiar display_indices[i] y display_indices[i+1]
    ld (hl), b                  ; display_indices[i+1] = antiguo indices[i]
    dec hl
    ld (hl), c                  ; display_indices[i] = antiguo indices[i+1]
    
.noSwap
    ld a, (sort_index)
    inc a
    ld (sort_index), a
    
    ld a, (sort_compares)
    dec a
    ld (sort_compares), a
    jr nz, .innerLoop
    
    ld a, (sort_passes)
    dec a
    ld (sort_passes), a
    jr nz, .outerLoop
    
    ld a, 1
    ld (is_sorted), a
    ret

.unsort
    ; Restaurar orden original
    call initDisplayIndices
    ret

; ============================================
; getDisplayIndex - Obtiene el índice real de una red
; Entrada: A = posición en pantalla (0-19)
; Salida: A = índice real de la red
; ============================================
getDisplayIndex:
    ld hl, display_indices
    ld e, a
    ld d, 0
    add hl, de
    ld a, (hl)
    ret

sort_passes     db 0
sort_compares   db 0
sort_index      db 0
    RTVAR display_indices, MAX_NETWORKS
is_sorted       db 0

; Variables del módulo
buff_ptr        dw buffer
rssi_ptr        dw rssi_buffer
networks_count  db 0
seen_cwlap      db 0
ok_ignored      db 0
old_fw          db 0
retry_count     db 0
is_connected    db 0
uart_busy       db 0           ; 1=UART ocupado por parser/operación crítica
debug_log      db 0           ; 1=log TX/RX key info (safe)

    RTVAR rssi_buffer, MAX_NETWORKS
    RTVAR connected_ssid, MAX_SSID_LEN + 1
    RTVAR ip_buffer, 17

    endmodule