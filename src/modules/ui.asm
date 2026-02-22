    module UI
PER_PAGE = 10
MAX_PASS_LEN = 40           

init:
    call Display.clrscr
    setLineColor 0, 117o : gotoXY 0, 0 : printMsg msg_head
    ; Poner "NetManZX v1.0" en amarillo (celdas 14-25)
    call highlightTitle
    call drawStatusBar
    call drawIpBar
    call ipShowScanning         ; IP: Scanning al inicio
    call setStatusScanning      ; Estado inicial: Scanning
    call clearPassBuffer
    ret

; Cambia atributos de " NetManZX v1.0 " a amarillo sobre azul
highlightTitle:
    ld hl, #5800 + 11           ; Atributos línea 0, columna 11
    ld a, Display.ATTR_TITLE    ; Amarillo brillante sobre azul
    ld b, 11                    ; 11 celdas: " NetManZX v1.0 "
.loop
    ld (hl), a
    inc hl
    djnz .loop
    ret

; Dibuja la barra de estado inferior
drawStatusBar:
    setLineColor 18, Display.ATTR_STATUSBAR  ; Negro sobre blanco brillante
    gotoXY 0, 18
    ld hl, msg_log_left
    call Display.putStr
    gotoXY 24, 18
    ld hl, msg_wifi_label
    call Display.putStr
    ret

; Dibuja la barra de IP (línea 1) con el mismo estilo que el banner superior
drawIpBar:
    setLineColor 1, Display.ATTR_HEADER  ; Blanco sobre azul
    gotoXY 0, 1
    ld hl, spaces_44
    jp Display.putStr

spaces_44:
    ds 44, ' '
    db 0

; Muestra "IP: Scanning..."
ipShowScanning:
    ld hl, msg_ip_scanning
    call ipSetFromZ
    jp ipRenderCentered

; Muestra "IP: not connected"
ipShowNotConnected:
    ld hl, msg_ip_notconn
    call ipSetFromZ
    jp ipRenderCentered

; Muestra "IP: x.x.x.x" si se puede obtener; si no, not connected
ipShowConnected:
    call Wifi.getIP
    jr c, ipShowNotConnected
    ld hl, msg_ip_prefix
    call ipSetPrefix
    ld hl, Wifi.ip_buffer
    call ipAppendZ
    jp ipRenderCentered

; --- helpers para construir línea de IP en ip_line_buffer ---
; HL -> string Z (0-terminated) a copiar completo a ip_line_buffer
ipSetFromZ:
    ld de, ip_line_buffer
.copy
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    and a
    jr nz, .copy
    ret

; Copia prefijo "IP: " a ip_line_buffer (con terminador para ipAppendZ)
ipSetPrefix:
    ld de, ip_line_buffer
.copyP
    ld a, (hl)
    ld (de), a              ; Copiar incluyendo el 0
    and a
    ret z                   ; Retornar después de copiar el 0
    inc hl
    inc de
    jr .copyP

; Añade string Z (HL) al final de ip_line_buffer
ipAppendZ:
    ; buscar 0 en buffer
    ld de, ip_line_buffer
.find0
    ld a, (de)
    and a
    jr z, .atEnd
    inc de
    jr .find0
.atEnd
.copyA
    ld a, (hl)
    ld (de), a
    inc hl
    inc de
    and a
    jr nz, .copyA
    ret

; Render centrado en línea 1 con fondo azul (desplazado 4 chars a la derecha)
ipRenderCentered:
    call drawIpBar

    ; calcular longitud de ip_line_buffer en B
    ld hl, ip_line_buffer
    ld b, 0
.lenLoop
    ld a, (hl)
    and a
    jr z, .lenDone
    inc hl
    inc b
    jr .lenLoop
.lenDone
    ; x = (32 - B) / 2 + 6
    ld a, 32
    sub b
    srl a
    add a, 6                ; Desplazar 6 a la derecha
    ld l, a
    ld h, 1
    ld (Display.coords), hl
    ld hl, ip_line_buffer
    jp Display.putStr

; Buffers/mensajes
msg_ip_prefix      db "IP: ", 0
msg_ip_notconn     db "IP: not connected", 0
msg_ip_scanning    db "IP: Scanning...", 0
ip_line_buffer     ds 40

; Colorea las últimas celdas de la línea 18 con color en C
colorStatusArea:
    ld hl, #5A40 + 22           ; Línea 18, celda 22 (de 32)
    ld b, 10                    ; 10 celdas para cubrir el texto
    ld a, c
.loop
    ld (hl), a
    inc hl
    djnz .loop
    ret

; Pone estado "Scanning"
setStatusScanning:
    ld hl, status_scanning_data
    jr setStatusCommon

; Pone estado "Connected"
setStatusConnected:
    ld hl, status_connected_data
    jr setStatusCommon

; Pone estado "Disconnected"
setStatusDisconnected:
    ld hl, status_disconn_data
    ; Fall through

; Rutina común para mostrar estado
; HL = puntero a datos (color, mensaje)
setStatusCommon:
    ld a, (hl)              ; A = color
    ld (status_color), a    ; Guardar color temporalmente
    inc hl
    push hl                 ; Guardar puntero a mensaje
    gotoXY 30, 18
    pop hl
    call Display.putStr     ; HL apunta al mensaje
    ld a, (status_color)
    ld c, a
    jp colorStatusArea

status_color db 0

; Datos de estado: color (1 byte) + mensaje
status_scanning_data:
    db Display.ATTR_STATUSBAR   ; Negro sobre blanco brillante
    db "Scanning    ", 0
status_connected_data:
    db 174o                     ; Verde sobre blanco brillante (sin constante, especial)
    db "Connected   ", 0
status_disconn_data:
    db 172o                     ; Rojo sobre blanco brillante (sin constante, especial)
    db "Disconnected", 0
msg_conn_lost      db "Connection lost!", 13, 10, 0

; Actualiza estado según Wifi.is_connected
updateWifiStatus:
    ld a, (Wifi.is_connected)
    and a
    jr z, setStatusDisconnected
    jr setStatusConnected

clearPassBuffer:
    ld hl, pass_buffer
    ld de, pass_buffer + 1
    xor a
    ld (hl), a
    ld bc, MAX_PASS_LEN - 1   ; -1 porque el primer byte ya está escrito
    ldir
    xor a
    ld (pass_len), a
    ld (pass_cursor), a
    ret

topClean:
    call Display.clrListOnly    ; Solo limpia líneas 2-14
    call clearListAttrs
    ret

; Limpia solo el área de redes (líneas 6-14) - para sort/rescan
clearNetworksArea:
    jp Display.clrNetworksOnly

; renderNetworksOnly - Redibuja SOLO el listado (líneas 6-14).
; No toca indicadores/menú superior (scroll/page info).
; Usado para refrescos por desconexión para evitar parpadeo/cambios arriba.
renderNetworksOnly:
    call clearNetworksArea
    jr renderNetworksCommon

; renderListOnly - Redibuja solo las redes + indicadores, no la ayuda
; Usado por sort y rescan para evitar parpadeo
renderListOnly:
    call clearNetworksArea
    call showScrollIndicators
    call showPageInfo
    call renderNetworksCommon
    jp showCursor

; ============================================
; renderNetworksCommon - Rutina común para dibujar lista de redes
; Entrada: área ya limpiada
; ============================================
renderNetworksCommon:
    ; Posicionar en línea 6 para empezar a listar
    gotoXY 0, 6

    ; Reiniciar flag de red conectada encontrada
    xor a
    ld (conn_row_found), a

    ; Calcular cuántas redes mostrar en esta página
    ld a, (Wifi.networks_count)
    ld hl, offset
    sub (hl)
    cp PER_PAGE
    jr c, .gotCount
    ld a, PER_PAGE
.gotCount
    ld b, a

    ; Verificar que hay redes
    and a
    jr z, .noNetworks

    ; Inicializar índice de pantalla actual
    ld a, (offset)
    ld (current_screen_idx), a

    ; Inicializar línea actual (empezar en 6)
    ld a, 6
    ld (current_line), a

.showLoop
    push bc

    ; Obtener puntero al SSID usando findRow (respeta display_indices)
    ld a, (current_screen_idx)
    ld d, a
    call findRow                ; HL = puntero al SSID

    ; Atributo por defecto (solo zona de lista)
    push hl
    ld a, (current_line)
    ld c, Display.ATTR_NORMAL
    call Display.setAttrPartial
    pop hl

    ; Resaltar SSID conectado si corresponde
    ld a, (Wifi.is_connected)
    and a
    jr z, .noConnAttr
    
    ; Si ya encontramos la red conectada, no buscar más
    ld a, (conn_row_found)
    and a
    jr nz, .noConnAttr
    
    ld a, (hl)
    and a
    jr z, .noConnAttr           ; SSID vacío -> no resaltar
    push hl
    ld de, Wifi.connected_ssid
.cmpConn
    ld a, (de)
    ld b, a
    ld a, (hl)
    cp b
    jr nz, .noMatchConn
    and a
    jr z, .matchConn
    inc hl
    inc de
    jr .cmpConn
.noMatchConn
    pop hl
    jr .noConnAttr
.matchConn
    pop hl
    
    ; Marcar que ya encontramos la red conectada
    ld a, 1
    ld (conn_row_found), a
    
    push hl
    ld a, (current_line)
    ld c, Display.ATTR_CONNECTED  ; Amarillo sobre negro
    call Display.setAttrPartial
    pop hl
.noConnAttr
    ; Verificar si SSID está vacío (red oculta)
    ld a, (hl)
    and a
    jr nz, .printSSID
    ld hl, msg_hidden           ; SSID vacío - mostrar "<hidden>"
.printSSID
    ; Imprimir SSID limitado a 29 caracteres (dejar espacio antes de RSSI)
    ld b, 29
    call putStrLimited

    ; Mover cursor a columna fija (30) para RSSI
    ld a, (current_line)
    ld h, a
    ld l, 30
    ld (Display.coords), hl

    ; Mostrar indicador RSSI (usa current_screen_idx)
    call printRssi

    ; Incrementar índice de pantalla
    ld a, (current_screen_idx)
    inc a
    ld (current_screen_idx), a

    ; Incrementar línea
    ld a, (current_line)
    inc a
    ld (current_line), a

    ; Ir a la siguiente línea
    call Display.putC.cr

    pop bc
    djnz .showLoop
    ret

.noNetworks
    gotoXY 0, 6
    ld hl, no_net_msg
    call Display.putStr
    ret

msg_hidden db "<hidden>", 0

; ============================================
; putStrLimited - Imprime string Z-terminated con límite
; Entrada: HL = puntero al string, B = máximo caracteres
; ============================================
putStrLimited:
    ld a, (hl)
    and a
    ret z               ; Fin del string
    ld a, b
    and a
    ret z               ; Límite alcanzado
    push hl
    push bc
    ld a, (hl)
    call Display.putC
    pop bc
    pop hl
    inc hl
    dec b
    jr putStrLimited

; Limpia los atributos de las líneas 2-17 (blanco sobre negro)
; Optimizado con LDIR
clearListAttrs:
    ld hl, #5800 + 64           ; Línea 2, columna 0
    ld a, Display.ATTR_NORMAL   ; Blanco sobre negro
    ld (hl), a                  ; Primer byte
    ld de, #5800 + 65           ; Destino = origen + 1
    ld bc, 16 * 32 - 1          ; 16 líneas (2-17) * 32 - 1 = 511 bytes
    ldir
    ret

; Pantalla de éxito de conexión (bucle infinito)
showConnectedSuccessScreen:
    call topClean
    gotoXY 0, 3 : ld hl, msg_done : call Display.putStr
.deadLoop
    halt
    jr .deadLoop

; ============================================
; renderList - Dibuja lista completa con ayuda
; ============================================
renderList:
    call topClean
    
    ; Mostrar ayuda en línea 3 (según estado de conexión)
    gotoXY 0, 3
    ld a, (Wifi.is_connected)
    and a
    jr z, .showHelpDisconn
    ld hl, msg_help_conn       ; Conectado: incluye X:Disconnect
    jr .printHelp
.showHelpDisconn
    ld hl, msg_help            ; No conectado
.printHelp
    call Display.putStr
    
    ; Mostrar opción de SSID manual en línea 4
    gotoXY 0, 4
    ld hl, msg_help2
    call Display.putStr
    
    ; Mostrar indicadores de scroll
    call showScrollIndicators
    
    call showPageInfo
    
    ; Usar rutina común para dibujar redes
    call renderNetworksCommon
    jp showCursor

no_net_msg db "No networks found. Press 'R' to rescan.", 0
msg_help   db "Q/A:Nav O/P:Page R:Refresh S:Sort", 0
msg_help_conn db "Q/A:Nav R:Refresh S:Sort X:Disconn", 0
msg_help2  db "H:Hidden network D:Diagnostics", 0

; ============================================
; Muestra flechas de scroll en línea 16
; DOWN en Col 0 (izquierda), UP en Col 41 (derecha)
; ============================================
showScrollIndicators:
    ; 1. Limpiar zona de flechas (izquierda y derecha)
    gotoXY 0, 16
    ld a, ' ' : call Display.putC
    gotoXY 41, 16
    ld a, ' ' : call Display.putC

    ; 2. Verificar Flecha ABAJO (Offset + PER_PAGE < Count) - IZQUIERDA
    ld a, (offset)
    add a, PER_PAGE
    ld b, a
    ld a, (Wifi.networks_count)
    cp b
    jr c, .chkUp            ; No hay más abajo
    jr z, .chkUp            ; Son iguales

    gotoXY 0, 16
    ld a, 25                ; Char flecha abajo (↓)
    call Display.putC

.chkUp
    ; 3. Verificar Flecha ARRIBA (Offset > 0) - DERECHA
    ld a, (offset)
    and a
    ret z                   ; No hay más arriba

    gotoXY 41, 16
    ld a, 24                ; Char flecha arriba (↑)
    call Display.putC
    ret

; ============================================
; clampOffsetToCount
;   Asegura que 'offset' no apunte fuera del rango tras un rescan.
;   Si offset >= networks_count, lo ajusta al inicio de la última página.
;   Si networks_count == 0, offset = 0.
; ============================================
clampOffsetToCount:
    ld a, (Wifi.networks_count)
    and a
    jr nz, .have
    xor a
    ld (offset), a
    ret
.have
    ld b, a                      ; B = count
    ld a, (offset)
    cp b
    ret c                        ; offset < count -> OK

    ; Calcular last_start = ((count-1)/PER_PAGE)*PER_PAGE
    ld a, b
    dec a                        ; A = count-1
    ld b, 0                      ; B = last_start
.div
    sub PER_PAGE
    jr c, .done
    ld c, a
    ld a, b
    add a, PER_PAGE
    ld b, a
    ld a, c
    jr .div
.done
    ld a, b
    ld (offset), a
    ret

; ============================================
; printRssi - Imprime indicador de señal
; Usa current_screen_idx para obtener el índice real vía display_indices
; ============================================
printRssi:
    ; Obtener índice real usando display_indices
    ld a, (current_screen_idx)
    call Wifi.getDisplayIndex   ; A = índice real de la red
    
    ; Obtener RSSI de esa red
    ld hl, Wifi.rssi_buffer
    ld e, a
    ld d, 0
    add hl, de
    ld a, (hl)
    
    ; Guardar valor en memoria
    ld (rssi_value), a
    
    ; Indicador red abierta/cerrada
    and #80
    jr z, .locked
    ld a, 9                 ; Abierta (círculo hueco)
    jr .printLock
.locked
    ld a, 7                 ; Cerrada (círculo relleno)
.printLock
    call Display.putC
    
    ; Recuperar RSSI y calcular barras
    ld a, (rssi_value)
    and #7F                 ; A = RSSI (0-127)
    
    ; Fórmula: Barras = (93 - RSSI) / 6, clampeado 1-10
    ; RSSI bajo = mejor señal = más barras
    ld b, a                 ; B = RSSI
    ld a, 93
    sub b                   ; A = 93 - RSSI
    jr nc, .calc_bars
    xor a                   ; Si RSSI > 93, resultado 0
    jr .clamp_min

.calc_bars
    ld b, 0                 ; Contador de barras
    ld c, 6                 ; Divisor
.div_loop
    inc b
    sub c
    jr nc, .div_loop
    ld a, b                 ; A = resultado división

.clamp_min
    and a
    jr nz, .clamp_max
    inc a                   ; Mínimo 1 barra
.clamp_max
    cp 11
    jr c, .gotBars
    ld a, 10                ; Máximo 10 barras
    
.gotBars
    ld b, a
    ld (rssi_bars), a       ; Guardar número de barras
    ld c, b
    
.drawFull
    ld a, b
    and a
    jr z, .drawEmpty
    push bc
    ld a, '|'
    call Display.putC
    pop bc
    dec b
    jr .drawFull
    
.drawEmpty
    ld a, 10
    sub c
    jr z, .colorBars
    ld b, a
    
.emptyLoop
    push bc
    ld a, '.'
    call Display.putC
    pop bc
    dec b
    jr nz, .emptyLoop

.colorBars
    ; Colorear la zona de barras en verde
    ; current_line tiene la línea actual (6-15)
    ld a, (current_line)
    ld l, a
    ld h, 0
    add hl, hl              ; x2
    add hl, hl              ; x4
    add hl, hl              ; x8
    add hl, hl              ; x16
    add hl, hl              ; x32
    ld de, #5800 + 22       ; Base + columna 22 (cubre cols texto 30-40)
    add hl, de              ; HL = dirección del atributo
    
    ; Colorear 10 celdas en verde (columnas 22-31)
    ld a, Display.ATTR_RSSI ; Verde sobre negro
    ld b, 10
.colorLoop
    ld (hl), a
    inc hl
    djnz .colorLoop
    
    ret

rssi_value db 0
rssi_bars db 0
current_line db 0
current_screen_idx db 0
conn_row_found db 0             ; Flag: 1 si ya se encontró la red conectada

; ============================================
; showConnectedDialog
; ============================================
showConnectedDialog:
    call topClean
    gotoXY 1, 3 : ld hl, .msg_already : call Display.putStr
    gotoXY 1, 5 : ld hl, .msg_network : call Display.putStr
    gotoXY 3, 6
    setLineColor 6, Display.ATTR_SSID_INPUT
    ld hl, Wifi.connected_ssid
    call Display.putStr
    setLineColor 6, Display.ATTR_NORMAL    
    gotoXY 1, 8 : ld hl, .msg_question : call Display.putStr
    gotoXY 1, 10 : ld hl, .msg_options : call Display.putStr

.waitKey
    halt
    call Keyboard.inKey
    and a : jr z, .waitKey
    cp 'y' : jr z, .reconfigure
    cp 'Y' : jr z, .reconfigure
    cp 'n' : jr z, .keepConfig
    cp 'N' : jr z, .keepConfig
    cp 15  : jr z, .keepConfig
    jr .waitKey

.reconfigure
    or a : ret
.keepConfig
    scf : ret

.msg_already   db "WiFi is already configured!", 0
.msg_network   db "Connected to network:", 0
.msg_question  db "Do you want to reconfigure?", 0
.msg_options   db "(Y)es to reconfigure / (N)o to exit", 0

; ============================================
; Cursor y navegación
; ============================================
hideCursor:
    call cursorIsConnectedRow
    ld c, Display.ATTR_NORMAL
    jr nc, cursor
    ld c, Display.ATTR_CONNECTED  ; Connected row: yellow on black
    jr cursor
showCursor:
    call cursorIsConnectedRow
    ld c, Display.ATTR_HIGHLIGHT
    jr nc, cursor
    ld c, Display.ATTR_CONN_CURSOR  ; Cursor on connected row: blue on yellow
cursor:
    ld a,(cursor_position) : add a, 6 : call Display.setAttrPartial
    ret

; ============================================
; cursorIsConnectedRow
;   CF=1 if cursor is on the currently connected SSID (and WiFi is connected)
;   CF=0 otherwise
; Destroys: AF,BC,DE,HL
; ============================================
cursorIsConnectedRow:
    ; Must be connected
    ld a, (Wifi.is_connected)
    and a
    or a
    ret z

    ; HL = SSID pointer for (offset + cursor_position), respecting display_indices
    ld a, (cursor_position)
    ld hl, offset
    add a, (hl)
    ld d, a
    call findRow

    ; Hidden/empty SSID can't be the connected one
    ld a, (hl)
    and a
    or a
    ret z

    ; Compare selected SSID with connected_ssid
    ld de, Wifi.connected_ssid
    call Display.compareStringZ
    ret nz              ; No coincide -> CF=0
    scf                 ; Coincide -> CF=1
    ret

; ============================================
; invalidateConnectedIfMissing
; Si estamos marcados como conectados pero el SSID conectado no aparece en el último scan,
; invalida estado y actualiza UI (solo invalidar, no reconstruir)
; ============================================
invalidateConnectedIfMissing:
    ; Solo si is_connected=1 y connected_ssid no vacío
    ld a, (Wifi.is_connected)
    and a
    ret z
    ld a, (Wifi.connected_ssid)
    and a
    ret z

    call connectedSSIDPresentInList
    ret c                       ; presente -> mantener
    ; No aparece en lista -> invalidar
    call doMarkDisconnected
    ret

; ============================================
; connectedSSIDPresentInList
; CF=1 si Wifi.connected_ssid aparece en la lista (buffer), CF=0 si no
; ============================================
connectedSSIDPresentInList:
    ld a, (Wifi.networks_count)
    and a
    jr z, .notFound

    ld b, a
    ld hl, buffer
.loopNet
    ld a, (hl)
    and a
    jr z, .notFound

    push hl
    push bc
    ld de, Wifi.connected_ssid
    call Display.compareStringZ
    pop bc
    pop hl
    jr z, .found        ; Z=1 significa iguales

    ; Avanzar al siguiente SSID (buscar el 0 terminador)
    xor a
    ld bc, #ffff
    cpir                ; HL apunta después del 0
    djnz .loopNet

.notFound
    or a
    ret

.found
    scf
    ret


uiLoop:
    ; Limpiar buffer de teclado al inicio (evita auto-selección por basura)
    xor a
    ld (Keyboard.BASIC_KEY), a
    
uiLoopMain:
    halt
    
    ; Incrementar contador de auto-rescan
    ld hl, (autoscan_counter)
    inc hl
    ld (autoscan_counter), hl
    
    ; Verificar si llegó a 15000 (5 min × 50 fps)
    ld de, 15000
    or a
    sbc hl, de
    jr nz, .noAutoRescan
    
    ; Auto-rescan: resetear contador y hacer rescan silencioso
    ld hl, 0
    ld (autoscan_counter), hl
    call doAutoRescan
    
.noAutoRescan
    ; Health-check periódico (solo para invalidar estado si se pierde conexión)
    ld hl, (health_counter)
    inc hl
    ld (health_counter), hl
    ld de, 500                   ; ~10s @50fps (menos agresivo)
    or a
    sbc hl, de
    jr nz, .noHealthCheck
    ld hl, 0
    ld (health_counter), hl

    ; Solo si estamos marcados como conectados y UART libre
    ld a, (Wifi.is_connected)
    and a
    jr z, .noHealthCheck
    ld a, (Wifi.uart_busy)
    and a
    jr nz, .noHealthCheck

    ; Silenciar log UART durante el health-check (evita spam de CWJAP?)
    call Uart.logReset
    ld a, (Uart.log_enabled)
    push af
    xor a
    ld (Uart.log_enabled), a
    call Wifi.checkConnection
    pop af
    ld (Uart.log_enabled), a
    call Uart.logReset
    ld a, (Wifi.is_connected)
    and a
    jr nz, .noHealthCheck
    jp handleDisconnect

.noHealthCheck


    ; Rescan pendiente tras pérdida de conexión (solo si UART libre)
    ld a, (force_rescan)
    and a
    jr z, .noForceRescan
    ld a, (Wifi.uart_busy)
    and a
    jr nz, .noForceRescan
    xor a
    ld (force_rescan), a

    call hideCursor
    call Wifi.getList
    call clampOffsetToCount

    ; Ajustar cursor_position a la página actual (offset) y tamaño real
    ld a, (Wifi.networks_count)
    and a
    jr z, .forceCursorZero

    ; remaining = count - offset
    ld a, (Wifi.networks_count)
    ld b, a
    ld a, (offset)
    ld c, a
    ld a, b
    sub c
    ; limitar remaining a PER_PAGE
    cp PER_PAGE
    jr c, .forceRemOk
    ld a, PER_PAGE
.forceRemOk
    ld b, a                  ; B = elementos visibles en página (1..PER_PAGE)

    ld a, (cursor_position)
    cp b
    jr c, .forceCursorOk
    ld a, b
    dec a
    ld (cursor_position), a
    jr .forceCursorOk
.forceCursorZero
    xor a
    ld (cursor_position), a
.forceCursorOk

    call showScrollIndicators
    call showPageInfo
    call renderNetworksOnly
    call showCursor
.noForceRescan

    call Keyboard.inKeyNoWait
    and a
    jr z, .noKey
    
    ; Resetear contador cuando hay actividad del usuario
    ld hl, 0
    ld (autoscan_counter), hl
    ld (health_counter), hl

    cp Keyboard.KEY_UP : jp z, cursorUp
    cp 'q'             : jp z, cursorUp
    cp Keyboard.KEY_DN : jp z, cursorDown
    cp 'a'             : jp z, cursorDown

    cp 'o' : jp z, pageUp
    cp 'O' : jp z, pageUp
    cp 'p' : jp z, pageDown
    cp 'P' : jp z, pageDown

    cp 'r' : jp z, rescan
    cp 'R' : jp z, rescan
    cp 's' : jp z, sortBySignal
    cp 'S' : jp z, sortBySignal
    cp 'd' : jp z, showDiagnostics
    cp 'D' : jp z, showDiagnostics
    cp 'h' : jp z, manualSSID
    cp 'H' : jp z, manualSSID
    cp 'x' : jp z, doDisconnect
    cp 'X' : jp z, doDisconnect

    cp 15  : jp z, exitProgram     ; ESC
    cp 13  : jp z, selectItem      ; ENTER

    jp uiLoopMain

.noKey:
    ld a, (ui_async_div)
    inc a
    ld (ui_async_div), a
    cp 4                           ; 4 frames ≈ 80 ms
    jp nz, uiLoopMain
    xor a
    ld (ui_async_div), a
    call checkAsyncWifi
    ; A = código de evento
    and a
    jp z, uiLoopMain               ; Sin evento
    cp ASYNC_EVENT_DISCONNECT
    jr z, handleDisconnect
    cp ASYNC_EVENT_GOTIP
    jr z, handleGotIP
    jp uiLoopMain

; ============================================
; doMarkDisconnected
;   Invalida estado WiFi, limpia SSID, actualiza estado/IP y avisa en log.
;   NO toca cursor ni repinta lista (lo decide el caller).
; ============================================
doMarkDisconnected:
    xor a
    ld (Wifi.is_connected), a
    ld hl, Wifi.connected_ssid
    ld (hl), a
    ld a, 1
    ld (force_rescan), a
    call setStatusDisconnected
    call ipShowNotConnected
    ld hl, msg_conn_lost
    call Display.putStrLog
    ret

handleDisconnect
    call doMarkDisconnected
    jp uiLoopMain

handleGotIP
    ld a, 1
    ld (Wifi.is_connected), a
    ; Obtener el SSID de la conexión actual
    call Wifi.checkConnection
    call setStatusConnected
    call ipShowConnected         ; Actualizar IP en barra superior
    ; Redibujar lista para aplicar atributo de red conectada
    call renderNetworksOnly
    call showCursor
    jp uiLoopMain

rescan:
    call hideCursor
    xor a : ld (cursor_position), a : ld (offset), a
    
    ; Limpiar zona izquierda de línea 17 (hasta columna 31) y mostrar "Scanning..."
    gotoXY 0, 17
    ld b, 31
.clrLine17
    ld a, ' '
    push bc
    call Display.putC
    pop bc
    djnz .clrLine17
    
    ld hl, .scanning_msg
    call Display.putStr
    
    ; Limpiar área de redes mientras escanea
    call clearNetworksArea
    
    call Wifi.getList
    call invalidateConnectedIfMissing
    call renderListOnly         ; Solo redibuja la lista, no la ayuda
    jp uiLoop
.scanning_msg db "Scanning...", 0

; ============================================
; doAutoRescan - Rescan automático silencioso
; No mueve cursor ni muestra mensajes
; ============================================
doAutoRescan:
    push af
    push bc
    push de
    push hl
    
    ; Guardar posición actual
    ld a, (cursor_position)
    ld b, a
    ld a, (offset)
    ld c, a
    push bc
    
    call hideCursor
    call Wifi.getList
    
    ; Restaurar posición (ajustando si es necesario)
    pop bc
    ld a, (Wifi.networks_count)
    and a
    jr z, .autoResetPos         ; Sin redes, resetear
    
    ; Verificar que offset sigue siendo válido
    ld a, c                     ; offset guardado
    ld d, a
    ld a, (Wifi.networks_count)
    cp d
    jr nc, .autoOffsetOK
    ; offset >= count, resetear
    jr .autoResetPos
    
.autoOffsetOK
    ld a, c
    ld (offset), a
    
    ; Verificar que cursor sigue siendo válido
    ld a, (Wifi.networks_count)
    ld e, a
    ld a, c                     ; offset
    ld d, a
    ld a, e
    sub d                       ; count - offset = disponibles
    cp PER_PAGE
    jr c, .autoLimitCursor
    ld a, PER_PAGE
.autoLimitCursor
    ; A = máximo cursor permitido
    dec a                       ; 0-indexed
    cp b                        ; comparar con cursor guardado
    jr nc, .autoCursorOK
    ; cursor > max, ajustar
    ld b, a
.autoCursorOK
    ld a, b
    ld (cursor_position), a
    jr .autoRender
    
.autoResetPos
    xor a
    ld (cursor_position), a
    ld (offset), a
    
.autoRender
    call renderListOnly
    
    pop hl
    pop de
    pop bc
    pop af
    ret

; ============================================
; sortBySignal - Ordena redes por intensidad de señal
; ============================================
sortBySignal:
    call hideCursor
    xor a : ld (cursor_position), a : ld (offset), a
    call Wifi.sortNetworks
    call renderListOnly         ; Solo redibuja la lista, no la ayuda
    jp uiLoop

; ============================================
; doDisconnect - Desconectar de la red actual
; ============================================
doDisconnect:
    ; Verificar si está conectado
    ld a, (Wifi.is_connected)
    and a
    jp z, uiLoop                ; No conectado, ignorar
    
    call topClean
    gotoXY 1, 3
    ld hl, .msg_disconnecting
    call Display.putStr
    
    ; Enviar comando de desconexión
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    
    ; Esperar respuesta
    ld b, 100
.waitDisconnect
    halt
    djnz .waitDisconnect
    call Wifi.flushInput
    
    ; Actualizar estado
    xor a
    ld (Wifi.is_connected), a
    call updateWifiStatus
    call ipShowNotConnected
    
    ; Mostrar confirmación
    gotoXY 1, 5
    ld hl, .msg_disconnected
    call Display.putStr
    gotoXY 1, 7
    ld hl, msg_press_key
    call Display.putStr
    
.waitDiscKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitDiscKey
    
    call renderList
    jp uiLoop

.msg_disconnecting db "Disconnecting...", 0
.msg_disconnected  db "Disconnected from WiFi network.", 0

; ============================================
; manualSSID - Introducir SSID manualmente
; ============================================
manualSSID:
    call hideCursor
    call topClean
    
    ; Limpiar buffer de SSID manual
    ld hl, manual_ssid_buffer
    ld b, 33
    xor a
.clearSSID
    ld (hl), a
    inc hl
    djnz .clearSSID
    xor a
    ld (manual_ssid_len), a
    ld (manual_ssid_cursor), a
    
    ; Mostrar título
    gotoXY 0, 3
    ld hl, .msg_manual_title
    call Display.putStr
    
    gotoXY 0, 5
    ld hl, .msg_enter_ssid
    call Display.putStr
    
    ; Mostrar mensaje de cancelación
    gotoXY 0, 8
    ld hl, .msg_ssid_help
    call Display.putStr
    
    setLineColor 6, 171o

; Repintado completo de SSID (para cursor left)
.drawSSIDFull
    gotoXY 1, 6
    ; Limpiar línea completa
    ld b, 34
.clearSSIDFull
    ld a, ' '
    push bc
    call Display.putC
    pop bc
    djnz .clearSSIDFull
    
    gotoXY 1, 6
    
    ; Chars antes del cursor
    ld a, (manual_ssid_cursor)
    and a
    jr z, .ssidFullCursor
    
    ld b, a
    ld hl, manual_ssid_buffer
.ssidFullBefore
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .ssidFullBefore

.ssidFullCursor
    ld a, 219
    call Display.putC
    
    ; Chars después del cursor
    ld a, (manual_ssid_len)
    ld b, a
    ld a, (manual_ssid_cursor)
    cp b
    jr nc, .waitSSIDKey
    
    ld c, a
    ld a, b
    sub c
    jr z, .waitSSIDKey
    ld b, a
    
    ld a, (manual_ssid_cursor)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    
.ssidFullAfter
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .ssidFullAfter
    jr .waitSSIDKey

; Repintado parcial de SSID (desde cursor, para insertar/borrar)
.drawSSID
    ; Posicionar al inicio de la línea
    gotoXY 1, 6
    
    ; Dibujar caracteres antes del cursor
    ld a, (manual_ssid_cursor)
    and a
    jr z, .ssidDrawCursor
    
    ld b, a
    ld hl, manual_ssid_buffer
.ssidDrawBefore
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .ssidDrawBefore

.ssidDrawCursor
    ; Dibujar cursor
    ld a, 219
    call Display.putC
    
    ; Chars después del cursor
    ld a, (manual_ssid_len)
    ld b, a
    ld a, (manual_ssid_cursor)
    cp b
    jr nc, .ssidClearRest
    
    ; Cantidad = len - cursor
    ld c, a
    ld a, b
    sub c
    jr z, .ssidClearRest
    ld b, a
    
    ; HL = &buffer[cursor]
    ld a, (manual_ssid_cursor)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    
.ssidDrawAfter
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .ssidDrawAfter

.ssidClearRest
    ; Limpiar resto de línea (2-3 espacios para borrar residuos)
    ld a, ' '
    call Display.putC
    ld a, ' '
    call Display.putC
    
.waitSSIDKey
    ld b, 5
.waitSSIDLoop
    halt
    djnz .waitSSIDLoop
    
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitSSIDKey
    
    ; Cancelar con EDIT
    cp 7 : jp z, .cancelManual
    
    ; Cursor izquierda
    cp 8 : jp z, .ssidCursorLeft
    
    ; Cursor derecha
    cp 9 : jp z, .ssidCursorRight
    
    ; Borrar
    cp Keyboard.KEY_BS : jp z, .removeSSIDChar
    
    ; Enter = continuar a contraseña
    cp 13 : jp z, .ssidEntered
    
    ; Filtrar caracteres válidos (32-126)
    cp 32 : jp c, .waitSSIDKey
    cp 127 : jp nc, .waitSSIDKey
    
    ; === Insertar carácter ===
    ld c, a                         ; Guardar char
    ld a, (manual_ssid_len)
    cp 32                           ; Max 32 chars
    jp nc, .waitSSIDKey
    
    ; Verificar si insertamos al final o en medio
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    cp b
    jr z, .ssidInsertAtEnd
    
    ; Insertar en medio: desplazar caracteres a la derecha
    ld a, (manual_ssid_len)
    ld b, a
    ld a, (manual_ssid_cursor)
    ld e, a
.ssidShiftRight
    ld a, b
    cp e
    jr z, .ssidDoInsert
    dec b
    ld hl, manual_ssid_buffer
    ld d, 0
    push de
    ld e, b
    add hl, de
    ld a, (hl)
    inc hl
    ld (hl), a
    pop de
    jr .ssidShiftRight

.ssidInsertAtEnd
.ssidDoInsert
    ; Insertar carácter
    ld a, (manual_ssid_cursor)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    ld (hl), c
    
    ; Incrementar longitud
    ld a, (manual_ssid_len)
    inc a
    ld (manual_ssid_len), a
    
    ; Poner null terminator
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    
    ; Incrementar cursor
    ld a, (manual_ssid_cursor)
    inc a
    ld (manual_ssid_cursor), a
    jp .drawSSID

.ssidCursorLeft
    ld a, (manual_ssid_cursor)
    and a
    jp z, .waitSSIDKey
    dec a
    ld (manual_ssid_cursor), a
    jp .drawSSID                ; Usar repintado parcial (no Full)

.ssidCursorRight
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    cp b
    jp z, .waitSSIDKey
    ld a, (manual_ssid_cursor)
    inc a
    ld (manual_ssid_cursor), a
    jp .drawSSID

.removeSSIDChar
    ld a, (manual_ssid_cursor)
    and a
    jp z, .waitSSIDKey
    
    ; Verificar si borramos al final o en medio
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    cp b
    jr z, .ssidDeleteAtEnd
    
    ; Borrar en medio: desplazar caracteres a la izquierda
    ld a, (manual_ssid_cursor)
    ld b, a
    ld a, (manual_ssid_len)
    ld c, a
.ssidShiftLeft
    ld a, b
    cp c
    jr z, .ssidFinishDelete
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, b
    add hl, de
    ld a, (hl)
    dec hl
    ld (hl), a
    inc b
    jr .ssidShiftLeft

.ssidDeleteAtEnd
.ssidFinishDelete
    ; Decrementar longitud
    ld a, (manual_ssid_len)
    dec a
    ld (manual_ssid_len), a
    
    ; Poner null terminator
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    
    ; Decrementar cursor
    ld a, (manual_ssid_cursor)
    dec a
    ld (manual_ssid_cursor), a
    jp .drawSSID

.cancelManual
    setLineColor 6, 107o
    call renderList
    jp uiLoop

.msg_ssid_help db "EDIT=cancel, L/R=move cursor", 0

.ssidEntered
    ; Verificar que hay SSID
    ld a, (manual_ssid_len)
    and a
    jp z, .waitSSIDKey              ; SSID vacío, seguir esperando
    
    ; Ahora pedir contraseña
    setLineColor 6, 107o
    call topClean
    
    ; Mostrar SSID seleccionado
    gotoXY 0, 3
    ld hl, msg_ssid
    call Display.putStr
    gotoXY 1, 4
    ld hl, manual_ssid_buffer
    call Display.putStr
    
    ; Preparar entrada de contraseña
    xor a
    ld (is_open_network), a         ; Asumir red cerrada
    call clearPassBuffer
    
    gotoXY 0, 6
    ld hl, msg_pass
    call Display.putStr
    
    setLineColor 4, 071o : setLineColor 7, 171o
    xor a
    ld (show_password), a
    ld (pass_cursor), a
    
    ; Usar el mismo código de entrada de contraseña
    jp .drawPassManual

; Repintado completo de contraseña (para toggle vis, cursor left)
.drawPassFull
    gotoXY 1, 7
    ld b, 34
.clearPassFull
    ld a, ' '
    push bc
    call Display.putC
    pop bc
    djnz .clearPassFull
    
    gotoXY 1, 7
    
    ; Chars antes del cursor
    ld a, (pass_cursor)
    and a
    jr z, .passFullCursor
    
    ld b, a
    ld hl, pass_buffer
    
    ld a, (show_password)
    and a
    jr nz, .passFullRealBefore
    
.passFullAsterBefore
    push bc
    push hl
    ld a, '*'
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .passFullAsterBefore
    jr .passFullCursor
    
.passFullRealBefore
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .passFullRealBefore

.passFullCursor
    ld a, 219
    call Display.putC
    
    ; Chars después del cursor
    ld a, (pass_len)
    ld b, a
    ld a, (pass_cursor)
    cp b
    jp nc, .waitKeyManual
    
    ld c, a
    ld a, b
    sub c
    jp z, .waitKeyManual
    ld b, a
    
    ld a, (pass_cursor)
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de
    
    ld a, (show_password)
    and a
    jr nz, .passFullRealAfter
    
.passFullAsterAfter
    push bc
    push hl
    ld a, '*'
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .passFullAsterAfter
    jp .waitKeyManual
    
.passFullRealAfter
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .passFullRealAfter
    jp .waitKeyManual

; Repintado parcial de contraseña (desde cursor)
.drawPassManual
    ; Posicionar al inicio de la línea
    gotoXY 1, 7
    
    ; Dibujar caracteres antes del cursor
    ld a, (pass_cursor)
    and a
    jr z, .passDrawCursor
    
    ld b, a
    ld hl, pass_buffer
    
    ld a, (show_password)
    and a
    jr nz, .passDrawRealBefore
    
.passDrawAsterBefore
    push bc
    push hl
    ld a, '*'
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .passDrawAsterBefore
    jr .passDrawCursor
    
.passDrawRealBefore
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .passDrawRealBefore

.passDrawCursor
    ; Dibujar cursor
    ld a, 219
    call Display.putC
    
    ; Chars después del cursor
    ld a, (pass_len)
    ld b, a
    ld a, (pass_cursor)
    cp b
    jr nc, .passClearRest
    
    ld c, a
    ld a, b
    sub c
    jr z, .passClearRest
    ld b, a
    
    ld a, (pass_cursor)
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de
    
    ld a, (show_password)
    and a
    jr nz, .passDrawRealAfter
    
.passDrawAsterAfter
    push bc
    push hl
    ld a, '*'
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .passDrawAsterAfter
    jr .passClearRest
    
.passDrawRealAfter
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .passDrawRealAfter

.passClearRest
    ; Limpiar resto de línea
    ld a, ' '
    call Display.putC
    ld a, ' '
    call Display.putC

.waitKeyManual
    ld b, 5
.waitLoopManual
    halt
    djnz .waitLoopManual
    
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitKeyManual
    
    cp Keyboard.KEY_UP : jp z, .toggleVisManual
    cp 7 : jp z, .cancelManual
    cp 8 : jp z, .passCursorLeftManual      ; LEFT
    cp 9 : jp z, .passCursorRightManual     ; RIGHT
    cp Keyboard.KEY_BS : jp z, .removeCharManual
    cp 13 : jp z, .connectManual
    cp 32 : jr c, .waitKeyManual
    cp 127 : jr nc, .waitKeyManual
    
    ; === Insertar carácter ===
    ld c, a                         ; Guardar char
    ld a, (pass_len)
    cp MAX_PASS_LEN
    jp nc, .waitKeyManual
    
    ; Verificar si insertamos al final o en medio
    ld a, (pass_cursor)
    ld b, a
    ld a, (pass_len)
    cp b
    jr z, .passInsertAtEndManual
    
    ; Insertar en medio: desplazar a la derecha
    ld a, (pass_len)
    ld b, a
    ld a, (pass_cursor)
    ld e, a
.passShiftRightManual
    ld a, b
    cp e
    jr z, .passDoInsertManual
    dec b
    ld hl, pass_buffer
    ld d, 0
    push de
    ld e, b
    add hl, de
    ld a, (hl)
    inc hl
    ld (hl), a
    pop de
    jr .passShiftRightManual

.passInsertAtEndManual
.passDoInsertManual
    ld a, (pass_cursor)
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de
    ld (hl), c
    
    ld a, (pass_len)
    inc a
    ld (pass_len), a
    
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    
    ld a, (pass_cursor)
    inc a
    ld (pass_cursor), a
    jp .drawPassManual

.passCursorLeftManual
    ld a, (pass_cursor)
    and a
    jp z, .waitKeyManual
    dec a
    ld (pass_cursor), a
    jp .drawPassManual          ; Usar repintado parcial

.passCursorRightManual
    ld a, (pass_cursor)
    ld b, a
    ld a, (pass_len)
    cp b
    jp z, .waitKeyManual
    ld a, (pass_cursor)
    inc a
    ld (pass_cursor), a
    jp .drawPassManual

.toggleVisManual
    ld a, (show_password)
    xor 1
    ld (show_password), a
    jp .drawPassFull            ; Repintado completo al cambiar visibilidad

.removeCharManual
    ld a, (pass_cursor)
    and a
    jp z, .waitKeyManual
    
    ; Verificar si borramos al final o en medio
    ld a, (pass_cursor)
    ld b, a
    ld a, (pass_len)
    cp b
    jr z, .passDeleteAtEndManual
    
    ; Borrar en medio: desplazar a la izquierda
    ld a, (pass_cursor)
    ld b, a
    ld a, (pass_len)
    ld c, a
.passShiftLeftManual
    ld a, b
    cp c
    jr z, .passFinishDeleteManual
    ld hl, pass_buffer
    ld d, 0
    ld e, b
    add hl, de
    ld a, (hl)
    dec hl
    ld (hl), a
    inc b
    jr .passShiftLeftManual

.passDeleteAtEndManual
.passFinishDeleteManual
    ld a, (pass_len)
    dec a
    ld (pass_len), a
    
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    
    ld a, (pass_cursor)
    dec a
    ld (pass_cursor), a
    jp .drawPassManual

.connectManual
    ; Mostrar asteriscos finales
    gotoXY 1, 7
    ld a, (pass_len)
    and a
    jr z, .noAsterManual
    ld b, a
.showConnAsterManual
    push bc
    ld a, '*'
    call Display.putC
    pop bc
    djnz .showConnAsterManual
.noAsterManual
    ld a, ' ' : call Display.putC
    
    ; Inicializar reintentos
    ld a, 3
    ld (conn_retries), a
; Verificar estado previo
    ld a, (Wifi.is_connected)
    and a
    jr z, .skipUiUpdate

    ; Actualizar UI solo si estaba conectado
    xor a
    ld (Wifi.is_connected), a
    call updateWifiStatus
    call ipShowNotConnected

.skipUiUpdate

    call Wifi.flushInput
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    call Wifi.checkOkErr
    call Wifi.flushInput

.connectRetryManual
    gotoXY 1, 10
    ld b, 30
.clrConnLineManual
    ld a, ' '
    push bc
    call Display.putC
    pop bc
    djnz .clrConnLineManual
    
    gotoXY 1, 10
    ld a, (conn_retries)
    ld b, a
    ld a, 4
    sub b
    add a, '0'
    ld (msg_conn_attempt + 12), a
    ld hl, msg_conn_attempt
    call Display.putStr
    
    gotoXY 1, 12
    ld hl, msg_break_cancel
    call Display.putStr
    
    ; AT+CWJAP se envia en varias partes. Para evitar mezclar log y ocultar password,
    ; se mutea el log durante todo el envio.
    ld hl, selectItem.log_cwjap_masked
    call Display.putStrLog
    call Uart.logReset
    xor a : ld (Uart.log_enabled), a

    ; Enviar comando de conexión con SSID manual
    ld a, (Wifi.old_fw) : ld hl, at_start : or a : jr z, .sendCmdManual : ld hl, at_start_old
.sendCmdManual
    call Wifi.espSendZ
    ld hl, manual_ssid_buffer       ; Usar SSID manual
    call Wifi.espSendZ
    ld hl, at_middle
    call Wifi.espSendZ

    ld hl, pass_buffer : call Wifi.espSendZ
    ld a, '"' : call Uart.write
    ld a, 13  : call Uart.write
    ld a, 10  : call Uart.write
    
    call Wifi.checkOkErrLong
    
    push af
    ld a, 1 : ld (Uart.log_enabled), a
    ; Añadir salto de línea al log para separar del comando anterior
    ld hl, selectItem.log_newline
    call Display.putStrLog
    pop af
    
    jr nc, .connSuccessManual
    
    ; Fallo - mostrar "Retry" junto al mensaje actual (línea 10, después de "Connecting (x/3)...")
    gotoXY 20, 10
    ld hl, msg_retry_suffix
    call Display.putStr
    
    ; Verificar si quedan reintentos
    ld a, (conn_retries)
    dec a
    ld (conn_retries), a
    jp z, .connFailedManual
    
    ld b, 100
.retryWaitManual
    halt
    push bc
    call Keyboard.checkBreak
    pop bc
    jr z, .breakPressedManual
    djnz .retryWaitManual
    
    jp .connectRetryManual

.breakPressedManual
    call Wifi.flushInput
    call renderList
    jp uiLoop

.connSuccessManual
    ld a, 1 : ld (Wifi.is_connected), a
    
    ; Copiar SSID seleccionado a connected_ssid
    ld hl, (selected_ssid_ptr)
    ld de, Wifi.connected_ssid
    ld bc, 32
    ldir
    
    call updateWifiStatus
    ifdef ESXCOMPAT
    call Compat.iwConfig
    endif
    call topClean
    ld b, 50
.ipDelayManual
    halt
    djnz .ipDelayManual
    call ipShowConnected
    setLineColor 4, 107o : setLineColor 7, 107o
    gotoXY 0, 3 : ld hl, msg_done : call Display.putStr
    gotoXY 0, 7 : ld hl, msg_press_key : call Display.putStr
.waitSuccessManual
    halt : call Keyboard.inKey : and a : jr z, .waitSuccessManual
    cp 15 : jp z, exitProgram
    call renderList : jp uiLoop

.connFailedManual
    call tryRecoverESP
    xor a : ld (Wifi.is_connected), a
    call updateWifiStatus
    call ipShowNotConnected
    call topClean
    setLineColor 4, 107o : setLineColor 7, 107o
    gotoXY 0, 3
    ld a, (Wifi.last_error)
    cp 1 : jr z, .errTimeoutManual
    cp 2 : jr z, .errPasswordManual
    cp 3 : jr z, .errNotFoundManual
    cp 4 : jr z, .errConnFailManual
    ld hl, msg_fail_generic
    jr .showFailMsgManual
.errTimeoutManual
    ld hl, msg_fail_timeout
    jr .showFailMsgManual
.errPasswordManual
    ld hl, msg_fail_password
    jr .showFailMsgManual
.errNotFoundManual
    ld hl, msg_fail_notfound
    jr .showFailMsgManual
.errConnFailManual
    ld hl, msg_fail_connfail
.showFailMsgManual
    call Display.putStr
    gotoXY 0, 7 : ld hl, msg_press_key : call Display.putStr
.waitFailManual
    halt : call Keyboard.inKey : and a : jr z, .waitFailManual
    call renderList : jp uiLoop

.msg_manual_title db "Hidden Network (Manual SSID)", 0
.msg_enter_ssid   db "Enter network SSID:", 0

manual_ssid_buffer ds 33
manual_ssid_len    db 0
manual_ssid_cursor db 0

exitProgram:
    call Display.clrscr : ei : ret

cursorDown:
    call hideCursor
    ; Verificar si hay más redes debajo
    ld a, (cursor_position)
    ld hl, offset
    add a, (hl)
    inc a                       ; Siguiente posición absoluta
    ld hl, Wifi.networks_count
    cp (hl)                     ; ¿Hay más redes?
    jp nc, .atEnd               ; No hay más, no mover
    
    ld a, (cursor_position)
    inc a
    cp PER_PAGE
    jr c, .store                ; Dentro de la página
    
    ; Scroll down: verificar que hay más redes
    ld a, (offset)
    add a, PER_PAGE
    ld hl, Wifi.networks_count
    cp (hl)
    jr nc, .atEnd               ; No hay más páginas
    
    ld (offset), a
    xor a : ld (cursor_position), a
    call renderList
    jp uiLoop
    
.store
    ld (cursor_position), a
.atEnd
    call showCursor
    jp uiLoop

cursorUp:
    call hideCursor
    ld a, (cursor_position) : and a : jr z, .page_up
    dec a : ld (cursor_position), a 
.back
    call showCursor
    jp uiLoop
.page_up
    ld a, (offset) : and a : jr z, .back
    sub PER_PAGE
    jr nc, .store_offset        ; No underflow
    xor a                       ; Clamp a 0
.store_offset
    ld (offset), a
    ld a, PER_PAGE - 1 : ld (cursor_position), a
    call renderList
    jr .back

; Page Down - salta una página entera
pageDown:
    call hideCursor
    ld a, (offset)
    add a, PER_PAGE
    ld hl, Wifi.networks_count
    cp (hl)
    jr nc, .lastPage            ; No hay página completa, ir a última
    ld (offset), a
    xor a : ld (cursor_position), a
    call renderList
    jp uiLoop
.lastPage
    ; Ir a la última red.
    ; Si la última ya es visible en la página actual, solo mover el cursor (sin repintar).
    ld a, (Wifi.networks_count)
    and a
    jp z, uiLoop                ; No hay redes
    dec a                       ; Última red (índice)
    ld b, a                     ; B = last_index

    ld a, (offset)
    ld c, a                     ; C = offset actual
    ld a, b
    sub c                       ; A = last_index - offset
    jr c, .needRepaint          ; (seguridad) last_index < offset
    cp PER_PAGE
    jr nc, .needRepaint         ; last_index fuera de la página actual -> repintar

    ld (cursor_position), a     ; cursor_position = last_index - offset
    call showCursor
    jp uiLoop

.needRepaint
    ; Calcular offset para que la última red esté visible
    ld a, b
    sub PER_PAGE - 1
    jr nc, .setOffset
    xor a                       ; Si hay menos de PER_PAGE redes, offset=0
.setOffset
    ld (offset), a
    ; cursor_position = índice - offset
    ld a, b
    ld hl, offset
    sub (hl)
    ld (cursor_position), a
    call renderList
    jp uiLoop

; Page Up - salta una página entera
pageUp:
    call hideCursor
    ld a, (offset)
    and a
    jp z, .firstItem            ; Ya en primera página
    sub PER_PAGE
    jr nc, .setOffset
    xor a                       ; Clamp a 0
.setOffset
    ld (offset), a
    xor a : ld (cursor_position), a
    call renderList
    jp uiLoop
.firstItem
    xor a : ld (cursor_position), a
    call showCursor
    jp uiLoop

findRow:
    ; d = posición en pantalla
    ; Primero obtener el índice real desde display_indices
    ld hl, Wifi.display_indices
    ld e, d
    ld d, 0
    add hl, de
    ld a, (hl)
    ld d, a                     ; D = índice real de la red
    
    ; Ahora buscar el SSID[d] en el buffer
    ld hl, buffer : ld a, d : and a : ret z
    xor a
.loop    
    ld bc, #ffff : cpir : dec d : jr nz, .loop
    ret

; ============================================
; selectItem y conexión
; ============================================
selectItem:
    ld a, (Wifi.networks_count) : and a : jp z, uiLoop
    
    ; Obtener posición en pantalla
    ld a, (cursor_position) : ld hl, offset : add a, (hl)
    ; Convertir a índice real usando display_indices
    call Wifi.getDisplayIndex   ; A = índice real de la red
    ld hl, Wifi.rssi_buffer : ld d, 0 : ld e, a : add hl, de
    ld a, (hl) : and #80 : ld (is_open_network), a
    
    ; Obtener puntero a SSID seleccionado (findRow ya usa display_indices)
    ld a, (cursor_position) : ld hl, offset : add (hl) : ld d, a : call findRow
    ld (selected_ssid_ptr), hl
    
    ; Verificar si ya estamos conectados a esta red
    ld a, (Wifi.is_connected)
    and a
    jr z, .notConnectedYet
    
    ; Comparar SSID seleccionado con connected_ssid
    ld hl, (selected_ssid_ptr)
    ld de, Wifi.connected_ssid
.compareLoop
    ld a, (de)
    ld b, a
    ld a, (hl)
    cp b
    jr nz, .notConnectedYet      ; Diferentes, continuar
    and a
    jr z, .alreadyConnected      ; Ambos terminaron en 0, son iguales
    inc hl
    inc de
    jr .compareLoop

.alreadyConnected
    ; Mostrar mensaje de que ya está conectado
    call hideCursor : call topClean
    gotoXY 0, 3
    ld hl, .msg_already_conn
    call Display.putStr
    gotoXY 1, 5
    ld hl, (selected_ssid_ptr)
    call Display.putStr
    gotoXY 0, 7
    ld hl, msg_press_key
    call Display.putStr
.waitAlready
    halt
    call Keyboard.inKey
    and a
    jr z, .waitAlready
    call renderList
    jp uiLoop

.msg_already_conn db "Already connected to this network:", 0

.notConnectedYet
    call hideCursor : call topClean
    gotoXY 0,3 : ld hl, msg_ssid : call Display.putStr
    gotoXY 1,4
    ld hl, (selected_ssid_ptr)
    call Display.putStr

    ld a, (is_open_network) : and a : jp nz, .connectDirect
    call clearPassBuffer
    gotoXY 0,6 : ld hl, msg_pass : call Display.putStr
    setLineColor 4, 071o : setLineColor 7, 171o
    xor a
    ld (show_password), a       ; Empezar ocultando
    ld (pass_cursor), a         ; Cursor al inicio
    
    ; Dibujar línea inicial vacía con cursor
    gotoXY 1,7
    ld a, 219 : call Display.putC   ; Cursor
    
.waitKey
    ; Esperar tecla (no bloqueante)
    ld b, 5
.waitLoop
    halt
    djnz .waitLoop
    
    call Keyboard.inKeyNoWait
    and a
    jp z, .waitKey              ; Sin tecla, seguir esperando
    
    ; Toggle visibilidad con flecha arriba
    cp Keyboard.KEY_UP
    jp z, .toggleVis
    
    ; Cancelar con EDIT
    cp 7 : jp z, .cancel
    
    ; Mover cursor izquierda (KEY_LEFT = 8)
    cp 8 : jp z, .cursorLeft
    
    ; Mover cursor derecha (KEY_RIGHT = 9)
    cp 9 : jp z, .cursorRight
    
    ; Borrar
    cp Keyboard.KEY_BS : jp z, .removeChar
    
    ; Enter = conectar
    cp 13 : jp z, .connect
    
    ; Filtrar caracteres válidos (solo 32-126)
    cp 32 : jp c, .waitKey
    cp 127 : jp nc, .waitKey
    
    ; === INSERTAR CARÁCTER ===
    ld c, a                     ; Guardar carácter en C
    ld a, (pass_len)
    cp MAX_PASS_LEN
    jp nc, .waitKey             ; Buffer lleno
    
    ; Verificar si insertamos al final o en medio
    ld a, (pass_cursor)
    ld b, a
    ld a, (pass_len)
    cp b
    jr z, .insertAtEnd
    
    ; Insertar en medio: desplazar caracteres a la derecha
    ; Desde pass_len-1 hasta pass_cursor, mover cada uno +1
    ld a, (pass_len)
    ld b, a                     ; B = pass_len (contador)
    ld a, (pass_cursor)
    ld e, a                     ; E = pass_cursor
    
.shiftRight
    ld a, b
    cp e
    jr z, .insertChar           ; Llegamos a la posición del cursor
    
    ; Copiar pass_buffer[b-1] a pass_buffer[b]
    dec b
    ld hl, pass_buffer
    ld d, 0
    push de
    ld e, b
    add hl, de                  ; HL = &pass_buffer[b-1]
    ld a, (hl)
    inc hl                      ; HL = &pass_buffer[b]
    ld (hl), a
    pop de
    inc b
    dec b
    jr .shiftRight

.insertAtEnd
.insertChar
    ; Insertar carácter en posición del cursor
    ld a, (pass_cursor)
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de
    ld (hl), c                  ; Guardar carácter
    
    ; Incrementar longitud
    ld a, (pass_len)
    inc a
    ld (pass_len), a
    
    ; Poner null terminator
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    
    ; Incrementar cursor
    ld a, (pass_cursor)
    inc a
    ld (pass_cursor), a
    
    ; Redibujar todo
    call .redrawAll
    jp .waitKey

.cursorLeft
    ld a, (pass_cursor)
    and a
    jp z, .waitKey              ; Ya está al inicio
    
    dec a
    ld (pass_cursor), a
    call .redrawAll
    jp .waitKey

.cursorRight
    ld a, (pass_cursor)
    ld b, a
    ld a, (pass_len)
    cp b
    jp z, .waitKey              ; Ya está al final
    
    ld a, (pass_cursor)
    inc a
    ld (pass_cursor), a
    call .redrawAll
    jp .waitKey

.toggleVis
    ld a, (show_password)
    xor 1
    ld (show_password), a
    ; Redibujar todo
    call .redrawAll
    jp .waitKey

.removeChar
    ld a, (pass_cursor)
    and a
    jp z, .waitKey              ; Nada que borrar antes del cursor
    
    ; Verificar si borramos al final o en medio
    ld a, (pass_cursor)
    ld b, a
    ld a, (pass_len)
    cp b
    jr z, .deleteAtEnd
    
    ; Borrar en medio: desplazar caracteres a la izquierda
    ; Desde pass_cursor hasta pass_len-1
    ld a, (pass_cursor)
    ld b, a                     ; B = posición actual
    ld a, (pass_len)
    ld c, a                     ; C = pass_len
    
.shiftLeft
    ld a, b
    cp c
    jr z, .finishDelete
    
    ; Copiar pass_buffer[b] a pass_buffer[b-1]
    ld hl, pass_buffer
    ld d, 0
    ld e, b
    add hl, de                  ; HL = &pass_buffer[b]
    ld a, (hl)
    dec hl                      ; HL = &pass_buffer[b-1]
    ld (hl), a
    inc b
    jr .shiftLeft

.deleteAtEnd
.finishDelete
    ; Decrementar longitud
    ld a, (pass_len)
    dec a
    ld (pass_len), a
    
    ; Poner null terminator
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    
    ; Decrementar cursor
    ld a, (pass_cursor)
    dec a
    ld (pass_cursor), a
    
    ; Redibujar todo
    call .redrawAll
    jp .waitKey

; --- Subrutinas de renderizado ---

; Redibuja todo el campo de contraseña
; Orden: [chars 0..pass_cursor-1] [cursor] [chars pass_cursor..pass_len-1]
.redrawAll
    ; Posicionar al inicio
    gotoXY 1,7
    
    ; === Parte 1: Dibujar caracteres ANTES del cursor (0 a pass_cursor-1) ===
    ld a, (pass_cursor)
    and a
    jr z, .drawCursorNow        ; pass_cursor=0, no hay chars antes
    
    ld b, a                     ; B = pass_cursor (cantidad de chars antes)
    ld hl, pass_buffer
    
    ld a, (show_password)
    and a
    jr nz, .drawRealBefore
    
.drawAsterBefore
    push bc
    push hl
    ld a, '*'
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .drawAsterBefore
    jr .drawCursorNow
    
.drawRealBefore
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .drawRealBefore

.drawCursorNow
    ; === Parte 2: Dibujar el cursor ===
    ld a, 219
    call Display.putC
    
    ; === Parte 3: Dibujar caracteres DESPUÉS del cursor (pass_cursor a pass_len-1) ===
    ld a, (pass_len)
    ld b, a
    ld a, (pass_cursor)
    cp b
    jr nc, .clearTrailing       ; pass_cursor >= pass_len, no hay chars después
    
    ; Calcular cuántos chars después: pass_len - pass_cursor
    ld c, a                     ; C = pass_cursor
    ld a, b
    sub c                       ; A = pass_len - pass_cursor
    jr z, .clearTrailing        ; 0 chars después
    
    ld b, a                     ; B = cantidad de chars después
    ; HL ya apunta al buffer en posición pass_cursor (si vinimos de drawRealBefore/drawAsterBefore)
    ; Pero si pass_cursor=0, HL no está inicializado, así que lo hacemos explícito
    ld a, (pass_cursor)
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de                  ; HL = &pass_buffer[pass_cursor]
    
    ld a, (show_password)
    and a
    jr nz, .drawRealAfter
    
.drawAsterAfter
    push bc
    push hl
    ld a, '*'
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .drawAsterAfter
    jr .clearTrailing
    
.drawRealAfter
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .drawRealAfter

.clearTrailing
    ; Limpiar posibles caracteres residuales (2-3 espacios)
    ld a, ' '
    call Display.putC
    ld a, ' '
    call Display.putC
    ret

; Redibuja desde la posición del cursor hacia adelante
; (usado después de insertar/borrar)
.redrawFromCursor
    ; Posicionar en pass_cursor
    ld a, (pass_cursor)
    add a, 1
    ld l, a
    ld h, 7
    ld (Display.coords), hl
    
    ; Primero dibujar el cursor
    ld a, 219
    call Display.putC
    
    ; Calcular cuántos caracteres hay desde pass_cursor hasta el final
    ld a, (pass_len)
    ld b, a
    ld a, (pass_cursor)
    ld c, a
    ld a, b
    sub c                       ; A = pass_len - pass_cursor
    jr z, .clearAfterCursor     ; No hay más caracteres después del cursor
    
    ; Dibujar caracteres desde pass_cursor hasta pass_len
    ld b, a                     ; B = caracteres a dibujar
    ld a, (pass_cursor)
    ld hl, pass_buffer
    ld d, 0
    ld e, a
    add hl, de                  ; HL = &pass_buffer[pass_cursor]
    
    ld a, (show_password)
    and a
    jr nz, .redrawRealFrom
    
.redrawAsterFrom
    push bc
    push hl
    ld a, '*'
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .redrawAsterFrom
    jr .clearAfterCursor
    
.redrawRealFrom
    push bc
    push hl
    ld a, (hl)
    call Display.putC
    pop hl
    inc hl
    pop bc
    djnz .redrawRealFrom

.clearAfterCursor
    ; Limpiar posición después de todo (por si borramos un carácter)
    ld a, ' '
    call Display.putC
    ld a, ' '
    call Display.putC
    ret

.cancel
    setLineColor 4, 107o : setLineColor 7, 107o
    call renderList : jp uiLoop

.connectDirect
    call clearPassBuffer
    setLineColor 4, 071o
    gotoXY 0, 6 : ld hl, msg_open_net : call Display.putStr

.connect
    ; Mostrar asteriscos en vez de contraseña
    gotoXY 1,7
    ld a, (pass_len)
    and a
    jr z, .noAsterisks
    ld b, a
.showConnAsterisks
    push bc
    ld a, '*'
    call Display.putC
    pop bc
    djnz .showConnAsterisks
.noAsterisks
    ld a, ' ' : call Display.putC : ld a,' ' : call Display.putC
    
    ; Inicializar contador de reintentos
    ld a, 3
    ld (conn_retries), a

;    Verificar estado previo
    ld a, (Wifi.is_connected)
    and a
    jr z, .skipUiUpdate

    ; Actualizar UI solo si estaba conectado
    xor a
    ld (Wifi.is_connected), a
    call updateWifiStatus
    call ipShowNotConnected

.skipUiUpdate:

    call Wifi.flushInput
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    call Wifi.checkOkErr
    call Wifi.flushInput

.connectRetry
    gotoXY 1, 10
    ; Limpiar línea primero
    ld b, 30
.clrConnLine
    ld a, ' '
    push bc
    call Display.putC
    pop bc
    djnz .clrConnLine
    
    gotoXY 1, 10
    ; Mostrar intento actual (sin Retry - eso se muestra después del fallo)
    ld a, (conn_retries)
    ld b, a
    ld a, 4
    sub b                       ; 4 - retries = intento (1, 2, 3)
    add a, '0'
    ld (msg_conn_attempt + 12), a
    ld hl, msg_conn_attempt
    call Display.putStr
    
    ; Mostrar opción de cancelar (en línea 12)
    gotoXY 1, 12
    ld hl, msg_break_cancel
    call Display.putStr

    ; AT+CWJAP se envia en varias partes. Para evitar mezclar log y ocultar password,
    ; se mutea el log durante todo el envio.
    ld hl, .log_cwjap_masked
    call Display.putStrLog
    call Uart.logReset
    xor a : ld (Uart.log_enabled), a

    ld a, (Wifi.old_fw) : ld hl, at_start : or a : jr z, .send_cmd : ld hl, at_start_old
.send_cmd
    call Wifi.espSendZ
    ld hl, (selected_ssid_ptr)
    call Wifi.espSendZ
    ld hl, at_middle   : call Wifi.espSendZ
    
    ; Send password (muted)
    ld hl, pass_buffer : call Wifi.espSendZ
    
    ; Send closing quote + CR LF manually (muted)
    ; Esto evita que se loguee la contraseña o el eco antes de tiempo
    ld a, '"' : call Uart.write
    ld a, 13  : call Uart.write
    ld a, 10  : call Uart.write
    
    ; Usar timeout largo para conexión WiFi (puede tardar 5-15 segundos)
    ; LOG SIGUE MUTEADO para evitar eco de contraseña
    call Wifi.checkOkErrLong
    
    ; --- UNMUTE UART LOG ---
    push af                     ; Preservar resultado
    ld a, 1 : ld (Uart.log_enabled), a
    ; Añadir salto de línea al log para separar del comando anterior
    ld hl, .log_newline
    call Display.putStrLog
    pop af
    
    jr nc, .connSuccess         ; CF=0 -> OK
    
    ; Fallo - mostrar "Retry" junto al mensaje actual (línea 10, después de "Connecting (x/3)...")
    gotoXY 20, 10
    ld hl, msg_retry_suffix
    call Display.putStr
    
    ; Verificar si quedan reintentos
    ld a, (conn_retries)
    dec a
    ld (conn_retries), a
    jp z, .connFailedFinal      ; No más reintentos
    
    ; Esperar antes de reintentar, verificando BREAK
    ld b, 100
.retryWait
    halt
    push bc
    call Keyboard.checkBreak
    pop bc
    jr z, .breakPressed         ; Z=1 si BREAK pulsado
    djnz .retryWait
    
    jp .connectRetry

.breakPressed
    ; Usuario canceló con BREAK
    call Wifi.flushInput
    call renderList
    jp uiLoop

.connSuccess
    ld a, 1 : ld (Wifi.is_connected), a
    
    ; Copiar SSID seleccionado a connected_ssid
    ld hl, (selected_ssid_ptr)
    ld de, Wifi.connected_ssid
    ld bc, 32
    ldir
    
    call updateWifiStatus
    ifdef ESXCOMPAT
    call Compat.iwConfig
    endif
    
    call topClean
    
    ; Pequeño delay para que el ESP tenga la IP lista
    ld b, 50
.ipDelay
    halt
    djnz .ipDelay
    call ipShowConnected        ; Mostrar IP después de topClean y delay
    
    setLineColor 4, 107o : setLineColor 7, 107o
    gotoXY 0, 3 : ld hl, msg_done : call Display.putStr
    gotoXY 0, 7 : ld hl, msg_press_key : call Display.putStr
.waitSuccess
    halt : call Keyboard.inKey : and a : jr z, .waitSuccess
    cp 15 : jp z, exitProgram
    call renderList : jp uiLoop

.connFailedFinal
    ; Intentar recuperar ESP si está colgado
    call tryRecoverESP
    
.connFailed
    xor a : ld (Wifi.is_connected), a
    call updateWifiStatus
    call ipShowNotConnected
    call topClean
    setLineColor 4, 107o : setLineColor 7, 107o
    
    ; Mostrar mensaje según código de error
    gotoXY 0, 3
    ld a, (Wifi.last_error)
    cp 1 : jr z, .errTimeout
    cp 2 : jr z, .errPassword
    cp 3 : jr z, .errNotFound
    cp 4 : jr z, .errConnFail
    ; Error genérico (0 o desconocido)
    ld hl, msg_fail_generic
    jr .showFailMsg
    
.errTimeout
    ld hl, msg_fail_timeout
    jr .showFailMsg
.errPassword
    ld hl, msg_fail_password
    jr .showFailMsg
.errNotFound
    ld hl, msg_fail_notfound
    jr .showFailMsg
.errConnFail
    ld hl, msg_fail_connfail
    
.showFailMsg
    call Display.putStr
    gotoXY 0, 7 : ld hl, msg_press_key : call Display.putStr
.waitFail
    halt : call Keyboard.inKey : and a : jr z, .waitFail
    call renderList : jp uiLoop

.log_cwjap_masked db ">> AT+CWJAP (password hidden)", 13, 0

.log_newline db 13, 0

; Intenta recuperar un ESP que no responde
tryRecoverESP:
    ; Enviar +++ para salir de modo transparente
    push hl
    ld hl, .escape_seq
    call Wifi.espSendZ
    
    ; Esperar
    ld b, 50
.wait1
    halt
    djnz .wait1
    
    ; Enviar AT para verificar respuesta
    ld hl, .at_test
    call Wifi.espSendZ
    call Uart.readTimeout
    pop hl
    ret                         ; Retornar aunque falle, lo intentamos
.escape_seq db "+++", 0
.at_test    db "AT", 13, 10, 0

; ============================================
; Diagnósticos
; ============================================
showDiagnostics:
    call topClean
    
    ; Verificar si está conectado
    ld a, (Wifi.is_connected)
    and a
    jr nz, .showMenu
    
    ; No conectado - mostrar error
    gotoXY 0, 3
    ld hl, .msg_not_conn
    call Display.putStr
    gotoXY 0, 5
    ld hl, msg_press_key
    call Display.putStr
.waitNotConn
    halt
    call Keyboard.inKey
    and a
    jr z, .waitNotConn
    call renderList
    jp uiLoop

.showMenu
    gotoXY 0, 3
    ld hl, .msg_diag_title
    call Display.putStr
    gotoXY 0, 5
    ld hl, .msg_diag_opt1
    call Display.putStr
    gotoXY 0, 6
    ld hl, .msg_diag_opt2
    call Display.putStr
    gotoXY 0, 7
    ld hl, .msg_diag_opt3
    call Display.putStr
    gotoXY 0, 8
    ld hl, .msg_diag_opt4
    call Display.putStr
    gotoXY 0, 10
    ld hl, .msg_diag_exit
    call Display.putStr

.diagLoop
    halt
    call Keyboard.inKey
    cp '1' : jp z, doPing
    cp '2' : jp z, doModuleInfo
    cp '3' : jp z, doNetworkInfo
    cp '4' : jp z, doBaudRate
    cp 7  : jr z, .exitDiag         ; EDIT (CAPS+1)
    cp 15 : jr z, .exitDiag         ; EDIT alternativo
    jr .diagLoop

.exitDiag
    ; Reactivar log UART al salir
    ld a, 1
    ld (Uart.log_enabled), a
    call renderList
    jp uiLoop

.msg_not_conn   db "Connect to a network first!", 0
.msg_diag_title db "=== Diagnostics ===", 0
.msg_diag_opt1  db "1. Ping test", 0
.msg_diag_opt2  db "2. Module info (firmware)", 0
.msg_diag_opt3  db "3. Network info (IP/MAC)", 0
.msg_diag_opt4  db "4. UART baud rate", 0
.msg_diag_exit  db "Press EDIT to exit", 0

; Buffer para respuestas de diagnóstico
diag_buffer     ds 64
diag_line       db 0            ; Línea actual en pantalla

; Drena el buffer UART (rápido, sin HALT: evita perder bytes a 115200)
flushUartBuffer:
    ; Leer hasta que no haya tráfico durante un margen corto
    ld de, #4000                ; ~0.2-0.3 s de "silencio" según CPU
.flushWait
    call UartImpl.uartRead      ; Leer todo lo disponible
    jr c, .gotByte
    dec de
    ld a, d
    or e
    jr nz, .flushWait
    ret
.gotByte
    ld de, #4000
    jr .flushWait

; Lee una línea del ESP hasta CR/LF o timeout (sin HALT)
; CF=1 si hay datos, CF=0 si timeout sin datos
readDiagLine:
    ld hl, diag_buffer
    ld c, 60                    ; Max 60 caracteres
    ld de, #FFFF                ; Timeout inicial (~1 s aprox)

.readLoop
    call UartImpl.uartRead
    jr c, .gotByte

    dec de
    ld a, d
    or e
    jr nz, .readLoop

    ; Timeout sin datos
    xor a
    ld (hl), a
    ret                         ; CF=0

.gotByte
    ; Al recibir datos, reducir timeout para cerrar la línea si falta terminador
    ld de, #2000

    ; CR o LF = fin de línea
    cp 13
    jr z, .endLine
    cp 10
    jr z, .endLine

    ; Guardar carácter
    ld (hl), a
    inc hl
    dec c
    jr nz, .readLoop

.endLine
    xor a
    ld (hl), a                  ; Terminar string
    scf                         ; CF=1, hay datos
    ret

; Lee una linea con espera inicial larga (para consultas que a veces tardan)
; CF=1 si hay datos, CF=0 si timeout sin datos
readDiagLineLong:
    ld hl, diag_buffer
    ld c, 60

    ; Espera el primer byte con timeout largo
    call Uart.readTimeoutLong
    jr nc, .timeout

.readLoop
    ; CR o LF = fin de linea
    cp 13
    jr z, .endLine
    cp 10
    jr z, .endLine

    ; Guardar caracter
    ld (hl), a
    inc hl
    dec c
    jr z, .endLine

    ; Leer siguiente byte con timeout medio (más tiempo para Next)
    call Uart.readTimeoutMedium
    jr nc, .endLine
    jr .readLoop

.timeout
    xor a
    ld (hl), a
    or a                        ; CF=0
    ret

.endLine
    xor a
    ld (hl), a
    scf
    ret

; Muestra diag_buffer en la línea actual y avanza
showDiagLine:
    ld a, (diag_line)
    ld h, a
    ld l, 1                     ; Columna 1
    ld (Display.coords), hl
    ld hl, diag_buffer
    call Display.putStr
    ld a, (diag_line)
    inc a
    ld (diag_line), a
    ret

; ------------------------------
; Ping test
; ------------------------------
MAX_IP_LEN = 15                 ; xxx.xxx.xxx.xxx

; Buffer para IP (persistente entre llamadas)
ping_ip_buffer  ds MAX_IP_LEN + 1   ; 16 bytes para IP + null
ping_ip_len     db 0                ; Longitud actual

; Inicializar IP por defecto (se llama una vez)
initPingIP:
    ld hl, .default_ip
    ld de, ping_ip_buffer
    ld bc, 8                    ; "8.8.8.8" + null
    ldir
    ld a, 7
    ld (ping_ip_len), a
    ret
.default_ip db "8.8.8.8", 0

doPing:
    ; Inicializar IP por defecto si está vacía
    ld a, (ping_ip_len)
    and a
    jr nz, .skipInit
    call initPingIP
.skipInit
    
    ; Deshabilitar log UART durante diagnóstico
    xor a
    ld (Uart.log_enabled), a
    
    call topClean
    
    ; Mostrar título y prompt
    gotoXY 1, 3
    ld hl, .msg_ping_title
    call Display.putStr
    
    gotoXY 1, 5
    ld hl, .msg_ip_prompt
    call Display.putStr
    
    gotoXY 1, 9
    ld hl, .msg_ping_help
    call Display.putStr
    
.drawIP
    ; Dibujar IP actual
    gotoXY 1, 7
    ld hl, ping_ip_buffer
    call Display.putStr
    
    ; Borrar resto de línea (MAX_IP_LEN - len espacios)
    ld a, MAX_IP_LEN
    ld hl, ping_ip_len
    sub (hl)                    ; A = 15 - len
    jr z, .noSpaces
    inc a                       ; +1 para el cursor
    ld b, a
.clearSpaces
    push bc
    ld a, ' '
    call Display.putC
    pop bc
    djnz .clearSpaces
.noSpaces

    ; Mostrar cursor
    ld a, (ping_ip_len)
    inc a                       ; Columna 1-based
    ld l, a
    ld h, 7
    ld (Display.coords), hl
    ld a, '_'
    call Display.putC

.waitIPKey
    ld b, 5
.waitIPLoop
    halt
    djnz .waitIPLoop
    
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitIPKey
    
    ; EDIT = cancelar
    cp 7 : jp z, .pingCancel
    cp 15 : jp z, .pingCancel
    
    ; ENTER = ejecutar ping
    cp 13 : jp z, .doPingNow
    
    ; Backspace = borrar
    cp Keyboard.KEY_BS : jp z, .ipBackspace
    
    ; Punto manual
    cp '.'
    jp z, .ipTryAddDot
    
    ; Solo permitir dígitos (0-9)
    cp '0'
    jr c, .waitIPKey            ; < '0'
    cp '9' + 1
    jr nc, .waitIPKey           ; > '9'
    
    ; Es un dígito - verificar si cabe
    ld b, a                     ; Guardar dígito
    ld a, (ping_ip_len)
    cp MAX_IP_LEN
    jp nc, .waitIPKey           ; Buffer lleno
    
    ; Contar dígitos en octeto actual
    push bc
    call .countOctetDigits
    pop bc
    cp 3
    jr c, .ipAddDigit           ; < 3 dígitos, añadir normal
    
    ; Ya hay 3 dígitos - necesitamos punto primero
    ; Verificar si podemos añadir punto (max 3 puntos)
    push bc
    call .countDots
    pop bc
    cp 3
    jp nc, .waitIPKey           ; Ya hay 3 puntos, no más dígitos
    
    ; Verificar espacio para 2 caracteres (punto + dígito)
    ld a, (ping_ip_len)
    cp MAX_IP_LEN - 1
    jp nc, .waitIPKey           ; No hay espacio para 2 chars
    
    ; Añadir punto automático
    push bc
    ld a, '.'
    call .addCharToIP
    pop bc
    
.ipAddDigit
    ; Añadir el dígito
    ld a, b
    call .addCharToIP
    jp .drawIP

.ipTryAddDot
    ; No permitir punto al inicio
    ld a, (ping_ip_len)
    and a
    jp z, .waitIPKey
    
    ; No permitir dos puntos seguidos
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    dec hl                      ; Último carácter
    ld a, (hl)
    cp '.'
    jp z, .waitIPKey            ; Último es punto, no añadir otro
    
    ; Verificar máximo 3 puntos
    push bc
    call .countDots
    pop bc
    cp 3
    jp nc, .waitIPKey           ; Ya hay 3 puntos
    
    ; Verificar espacio
    ld a, (ping_ip_len)
    cp MAX_IP_LEN
    jp nc, .waitIPKey
    
    ; Añadir punto
    ld a, '.'
    call .addCharToIP
    jp .drawIP

; Añade un carácter al buffer IP
.addCharToIP
    push af
    ld a, (ping_ip_len)
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    pop af
    ld (hl), a
    inc hl
    xor a
    ld (hl), a                  ; Null terminator
    ld a, (ping_ip_len)
    inc a
    ld (ping_ip_len), a
    ret

; Cuenta dígitos en el octeto actual (desde último punto)
; Devuelve A = número de dígitos
.countOctetDigits
    ld a, (ping_ip_len)
    and a
    ret z                       ; Vacío, 0 dígitos
    
    ; Recorrer desde el final hacia atrás
    ld b, a                     ; B = longitud
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    dec hl                      ; HL apunta al último carácter
    ld c, 0                     ; Contador de dígitos
    
.countLoop
    ld a, (hl)
    cp '.'
    jr z, .countDone            ; Encontrado punto, terminar
    inc c                       ; Contar dígito
    dec b
    jr z, .countDone            ; Llegamos al inicio
    dec hl
    jr .countLoop
    
.countDone
    ld a, c
    ret

; Cuenta puntos en el buffer
; Devuelve A = número de puntos
.countDots
    ld hl, ping_ip_buffer
    ld c, 0                     ; Contador de puntos
.dotsLoop
    ld a, (hl)
    and a
    jr z, .dotsDone             ; Fin de string
    cp '.'
    jr nz, .dotsNext
    inc c
.dotsNext
    inc hl
    jr .dotsLoop
.dotsDone
    ld a, c
    ret

.ipBackspace
    ld a, (ping_ip_len)
    and a
    jp z, .waitIPKey            ; Ya vacío
    dec a
    ld (ping_ip_len), a
    ld hl, ping_ip_buffer
    ld d, 0
    ld e, a
    add hl, de
    xor a
    ld (hl), a
    jp .drawIP

.pingCancel
    jp showDiagnostics

.doPingNow
    ; Verificar que hay algo escrito
    ld a, (ping_ip_len)
    and a
    jp z, .waitIPKey            ; No permitir IP vacía
    
    call topClean
    gotoXY 1, 3
    ld hl, .msg_pinging
    call Display.putStr
    
    ; Mostrar IP que se va a hacer ping
    ld hl, ping_ip_buffer
    call Display.putStr
    ld hl, .msg_dots
    call Display.putStr
    
    ; Inicializar línea de salida
    ld a, 5
    ld (diag_line), a
    
    ; Drenar buffer antes de enviar comando
    call flushUartBuffer
    
    ; Construir y enviar comando: AT+PING="ip"
    ld hl, .cmd_ping_start
    call Wifi.espSendZ
    ld hl, ping_ip_buffer
    call Wifi.espSendZ
    ld hl, .cmd_ping_end
    call Wifi.espSendZ
    
    ; Leer respuestas
    ld c, 20                    ; Max 20 timeouts
    ld b, 100                   ; Límite absoluto: 100 líneas
.pingLoop
    push bc
    call readDiagLine
    pop bc
    jr nc, .pingTimeout         ; CF=0 = timeout real
    
    ; Decrementar límite absoluto
    dec b
    jr z, .pingDone             ; Límite alcanzado
    
    ; CF=1 = hay línea
    ld a, (diag_buffer)
    and a
    jr z, .pingLoop             ; Línea vacía
    
    ; Verificar si es "OK" o "ERROR" -> fin
    cp 'O'
    jr z, .pingDone
    cp 'E'
    jr z, .pingDone             ; ERROR también termina
    
    ; Filtrar ruido y eco
    cp 'A' : jr z, .pingLoop    ; Eco AT...
    cp '0' : jr z, .pingLoop
    cp '1' : jr z, .pingLoop
    cp 'C' : jr z, .pingLoop    ; CONNECT, CLOSED
    cp 'L' : jr z, .pingLoop    ; LAIN
    cp 'S' : jr z, .pingLoop    ; SEND OK
    
    ; Si empieza con +, verificar si es +IPD
    cp '+'
    jr nz, .pingShow
    ld a, (diag_buffer + 1)
    cp 'I'                      ; +IPD -> ignorar
    jr z, .pingLoop
    
    ; Verificar si es +timeout (error) o +numero (éxito)
    cp 't'                      ; +timeout
    jr z, .pingShowTimeout
    
    ; Formateo ping exitoso: Response time: XX ms
    ld a, (diag_line) : ld h, a : ld l, 1 : ld (Display.coords), hl
    ld hl, .msg_time_lbl
    call Display.putStr
    ld hl, diag_buffer + 1      ; Saltarse el '+'
    call Display.putStr
    ld hl, .msg_time_ms
    call Display.putStr
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .pingLoop

.pingShowTimeout
    ; Mostrar "Request timed out"
    ld a, (diag_line) : ld h, a : ld l, 1 : ld (Display.coords), hl
    ld hl, .msg_timeout
    call Display.putStr
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .pingLoop

.pingShow
    call showDiagLine
    jr .pingLoop
    
.pingTimeout
    dec c
    jp nz, .pingLoop

.pingDone
    gotoXY 1, 12
    ld hl, msg_press_key
    call Display.putStr
.waitPingKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitPingKey
    jp showDiagnostics

.msg_ping_title  db "=== Ping Test ===", 0
.msg_ip_prompt   db "Enter IP address:", 0
.msg_ping_help   db "ENTER=ping, EDIT=cancel", 0
.msg_pinging     db "Pinging ", 0
.msg_dots        db "...", 0
.cmd_ping_start  db "AT+PING=", '"', 0
.cmd_ping_end    db '"', 13, 10, 0
.msg_time_lbl    db "Response time: ", 0
.msg_time_ms     db " ms", 0
.msg_timeout     db "Request timed out", 0

; ------------------------------
; Module info (firmware version)
; ------------------------------
doModuleInfo:
    ; Deshabilitar log UART
    xor a
    ld (Uart.log_enabled), a
    
    call topClean
    gotoXY 1, 3
    ld hl, .msg_module_title
    call Display.putStr
    
    ; Inicializar línea de salida
    ld a, 5
    ld (diag_line), a
    
    ; Drenar buffer antes de enviar comando
    call flushUartBuffer
    
    ; Enviar AT+GMR
    ld hl, .cmd_gmr
    call Wifi.espSendZ
    
    ; Leer y mostrar respuestas
    ld c, 20                    ; Max 20 timeouts
    ld b, 100                   ; Límite absoluto: 100 líneas
.gmrLoop
    push bc
    call readDiagLine
    pop bc
    jr nc, .gmrTimeout          ; CF=0 = timeout real
    
    ; Decrementar límite absoluto
    dec b
    jr z, .gmrDone              ; Límite alcanzado
    
    ; CF=1 = hay línea
    ld a, (diag_buffer)
    and a
    jr z, .gmrLoop              ; Línea vacía, no cuenta como timeout
    
    ; Verificar si es "OK" -> fin
    cp 'O'
    jr z, .gmrDone
    
    ; Filtrar ruido de red y ECO (AT+GMR vs AT version...)
    cp 'A' 
    jr nz, .checkOther
    ; Empieza por A. Ver si es "AT+" (Eco) o "AT v..." (Info)
    ld a, (diag_buffer + 1)
    cp 'T'
    jr nz, .showInfo      ; No es AT...
    ld a, (diag_buffer + 2)
    cp '+'
    jr z, .gmrLoop        ; Es AT+... (Eco) -> Ignorar
    jr .showInfo          ; Es AT ... (Info) -> Mostrar

.checkOther
    cp '+' : jr z, .gmrLoop     ; +IPD, etc
    cp '0' : jr z, .gmrLoop     ; 0,CONNECT
    cp '1' : jr z, .gmrLoop     ; 1,CONNECT
    cp 'C' : jr z, .gmrLoop     ; CONNECT, CLOSED
    cp 'L' : jr z, .gmrLoop     ; LAIN
    cp 'S' : jr z, .gmrLoop     ; SEND OK

.showInfo
    ; Línea válida - mostrar
    call showDiagLine
    jr .gmrLoop                 ; Seguir sin decrementar
    
.gmrTimeout
    dec c
    jr nz, .gmrLoop

.gmrDone
    gotoXY 1, 12
    ld hl, msg_press_key
    call Display.putStr
.waitGmrKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitGmrKey
    jp showDiagnostics

.msg_module_title db "Module firmware:", 0
.cmd_gmr          db "AT+GMR", 13, 10, 0

; ------------------------------
; Network info (IP/MAC)
; ------------------------------
doNetworkInfo:
    ; Deshabilitar log UART
    xor a
    ld (Uart.log_enabled), a
    
    call topClean
    gotoXY 1, 3
    ld hl, .msg_net_title
    call Display.putStr
    
    ; Inicializar línea de salida
    ld a, 5
    ld (diag_line), a
    
    ; Drenar buffer antes de enviar comando
    call flushUartBuffer
    
    ; Enviar AT+CIFSR
    ld hl, .cmd_cifsr
    call Wifi.espSendZ
    
    ; Leer respuestas
    ld c, 20                    ; Max 20 timeouts
    ld b, 100                   ; Límite absoluto: 100 líneas
.cifsrLoop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cifsrTimeout        ; CF=0 = timeout real
    
    ; Decrementar límite absoluto
    dec b
    jr z, .cifsrDone            ; Límite alcanzado
    
    ; CF=1 = hay línea
    ld a, (diag_buffer)
    and a
    jr z, .cifsrLoop            ; Línea vacía, no cuenta
    
    ; Verificar si es "OK" -> fin
    cp 'O'
    jr z, .cifsrDone
    
    ; Filtrar ruido de red y ECO
    cp 'A' : jr z, .cifsrLoop   ; Ignorar eco AT...
    cp '0' : jr z, .cifsrLoop
    cp '1' : jr z, .cifsrLoop
    cp 'C' : jr z, .cifsrLoop   ; CONNECT, CLOSED
    cp 'L' : jr z, .cifsrLoop   ; LAIN
    cp 'S' : jr z, .cifsrLoop   ; SEND OK
    
    ; Si empieza con +, verificar que no sea +IPD
    cp '+'
    jr nz, .cifsrLoop           ; No empieza con +, ignorar
    
    ; --- FORMATEO IP/MAC ---
    ; Buffer contiene algo como +CIFSR:STAIP,"192.168.1.5"
    ; Pos 0: +
    ; Pos 7: S (de STA)
    ; Pos 10: I (de IP) o M (de MAC)
    
    ld a, (diag_buffer + 1)     ; Verificar CIFSR
    cp 'C' : jr nz, .cifsrLoop  ; +IPD o similar -> fuera
    
    ld a, (diag_buffer + 10)    ; Carácter discriminador
    cp 'I' : jr z, .isIP
    cp 'M' : jr z, .isMAC
    jr .cifsrLoop               ; Otro campo (APIP, etc), ignorar o mostrar raw

.isIP
    ld hl, .lbl_ip
    jr .printFmt
.isMAC
    ld hl, .lbl_mac
.printFmt
    ; 1. Posicionar cursor
    ld a, (diag_line) : ld d, a : ld e, 1
    ld (Display.coords), de
    
    ; 2. Imprimir etiqueta
    call Display.putStr
    
    ; 3. Buscar comillas de apertura y cierre para extraer valor
    ld hl, diag_buffer
    call .findQuote             ; HL apunta al primer char tras la comilla
    call .printUntilQuote       ; Imprimir hasta la siguiente comilla
    
    ; 4. Nueva línea
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .cifsrLoop               ; Seguir sin decrementar
    
.cifsrTimeout
    dec c
    jr nz, .cifsrLoop

.cifsrDone
    gotoXY 1, 12
    ld hl, msg_press_key
    call Display.putStr
.waitCifsrKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitCifsrKey
    jp showDiagnostics

; Helpers locales para parseo
.findQuote
    ld a, (hl)
    cp '"' : jr z, .foundQ
    inc hl
    and a : ret z               ; Fin de string sin comillas
    jr .findQuote
.foundQ
    inc hl                      ; Saltar la comilla
    ret

.printUntilQuote
    ld a, (hl)
    and a : ret z               ; Fin de string (seguridad)
    cp '"' : ret z              ; Fin de comillas
    push hl
    call Display.putC
    pop hl
    inc hl
    jr .printUntilQuote

.msg_net_title db "Network information:", 0
.cmd_cifsr     db "AT+CIFSR", 13, 10, 0
.lbl_ip        db "IP Address:  ", 0
.lbl_mac       db "MAC Address: ", 0

; ------------------------------
; UART Baud rate
; ------------------------------
doBaudRate:
    call topClean
    gotoXY 1, 3
	ld hl, msg_baud_title
    call Display.putStr
    
    ; Inicializar línea de salida
    ld a, 5
    ld (diag_line), a
    xor a
    ld (baud_tried_def), a
    ld (baud_tried_plain), a
    ld (baud_have_value), a
    ld (baud_saw_error), a
    ld (baud_recover_tried), a

    
    ; Drenar buffer antes de enviar comando
    call flushUartBuffer
	
	; Ensure the ESP is in AT command mode (not in pass-through/data mode)
	call Wifi.ensureCommandMode
	jp nc, doBaudRate_cmode_ok
	gotoXY 1, 6
	ld hl, msg_no_at
	call Display.putStr
	call waitAnyKey
	jp showDiagnostics

doBaudRate_cmode_ok:
    
    ; Enviar AT+UART_CUR?
    ld hl, cmd_uart_cur
    call Wifi.espSendZ
    
    ; Leer respuestas
    ld c, 4                     ; Max 4 timeouts (cada uno es largo)
    ld b, 100                   ; Límite absoluto: 100 líneas
.baudLoop
    push bc
    call readDiagLineLong
    pop bc
    jp nc, .baudTimeout         ; CF=0 = timeout real
    
    ; Decrementar límite absoluto
    dec b
    jp z, .baudDone             ; Límite alcanzado
    
    ; CF=1 = hay línea
    ld a, (diag_buffer)
    and a
    jp z, .baudLoop             ; Línea vacía, no cuenta
    
    ; Verificar si es "OK" -> fin
    cp 'O'
    jp z, .baudDone
    cp 'E'                      ; ERROR -> probar comandos alternativos
    jp nz, .noErrLine
    ; Registrar que vimos ERROR (si no se obtiene nada, lo mostraremos)
    ld a, 1
    ld (baud_saw_error), a

    ; First ERROR: try to recover by ensuring AT command mode, then retry CUR once
    ld a, (baud_recover_tried)
    and a
    jp nz, .skipRecover
    ld a, 1
    ld (baud_recover_tried), a
    call Wifi.ensureCommandMode
    call flushUartBuffer
    xor a
    ld (baud_tried_def), a
    ld (baud_tried_plain), a
    ld hl, cmd_uart_cur
    call Wifi.espSendZ
    ld c, 4
    ld b, 100
    jp .baudLoop
.skipRecover

    ; 1) Probar AT+UART_DEF? (algunos firmwares no soportan CUR)
    ld a, (baud_tried_def)
    and a
    jp nz, .tryPlain
    ld a, 1
    ld (baud_tried_def), a
    call flushUartBuffer
    ld hl, cmd_uart_def
    call Wifi.espSendZ
    ld c, 4
    ld b, 100
    jp .baudLoop

.tryPlain
    ; 2) Probar AT+UART? (firmwares antiguos)
    ld a, (baud_tried_plain)
    and a
    jp nz, .baudDone
    ld a, 1
    ld (baud_tried_plain), a
    call flushUartBuffer
    ld hl, cmd_uart_plain
    call Wifi.espSendZ
    ld c, 4
    ld b, 100
    jp .baudLoop
.noErrLine
    
    ; Filtrar ruido y ECO
    cp 'A' : jp z, .baudLoop    ; Ignorar eco AT...
    cp '0' : jp z, .baudLoop
    cp 'C' : jp z, .baudLoop
    
    ; Si empieza con +, verificar que no sea +IPD
    cp '+'
    jp nz, .baudLoop            ; No empieza con +, ignorar
    ld a, (diag_buffer + 1)
    cp 'I'                      ; +IPD -> ignorar
    jp z, .baudLoop
    cp 'U'                      ; Check +UART
    jp nz, .baudLoop

    ; --- FORMATEO BAUDRATE ---
    ; Cadena: +UART_CUR:9600,8,1,0,0
    ; Longitud header (+UART_CUR:) es 10 chars, no 11
    
    ld a, (diag_line) : ld h, a : ld l, 1 : ld (Display.coords), hl
    
    ld hl, lbl_baud
    call Display.putStr
    
    ld hl, diag_buffer
    call .skipToColon           ; Saltar hasta ':' (soporta +UART y +UART_CUR)
    call .printUntilComma       ; Imprimir solo el número

    ld a, 1
    ld (baud_have_value), a

    ld a, (diag_line) : inc a : ld (diag_line), a
    jp .baudLoop                ; Seguir sin decrementar

.baudTimeout
    dec c
    jp nz, .baudLoop

.baudDone
    ; Si no se pudo obtener ninguna linea +UART, avisar
    ld a, (baud_have_value)
    and a
    jp nz, .baudDoneHasValue
    gotoXY 1, 5
    ld a, (baud_saw_error)
    and a
    jp z, .noErrMsg
    ld hl, msg_uart_error
    call Display.putStr
    jp .afterErrMsg
.noErrMsg
    ld hl, msg_uart_none
    call Display.putStr
.afterErrMsg
.baudDoneHasValue
    gotoXY 1, 12
    ld hl, msg_press_key
    call Display.putStr
.waitBaudKey
    halt
    call Keyboard.inKey
    and a
    jp z, .waitBaudKey
    jp showDiagnostics

.skipToColon
    ld a, (hl)
    and a : ret z
    cp ':' : jr z, .gotColon
    inc hl
    jr .skipToColon
.gotColon
    inc hl
    ret


.printUntilComma
    ld a, (hl)
    and a : ret z
    cp ',' : ret z
    cp 13  : ret z
    push hl
    call Display.putC
    pop hl
    inc hl
    jr .printUntilComma

msg_baud_title db "UART configuration:", 0
msg_no_at      db "No AT response (still in data mode?)", 0
cmd_uart_cur   db "AT+UART_CUR?", 13, 10, 0
cmd_uart_def   db "AT+UART_DEF?", 13, 10, 0
cmd_uart_plain db "AT+UART?", 13, 10, 0
lbl_baud       db "Baud Rate: ", 0
msg_uart_none db "No UART info (no response).", 0
msg_uart_error db "UART query returned ERROR.", 0

baud_tried_def  db 0
baud_tried_plain db 0
baud_have_value db 0
baud_saw_error  db 0
baud_recover_tried db 0

conn_retries db 0
cmd_disconnect db "AT+CWQAP", 13, 10, 0

; ============================================
; checkAsyncWifi - Detecta eventos WiFi asíncronos
; Busca "DISCONNECT" y "GOT IP" en el stream UART
; Retorna: A = código de evento
;   ASYNC_EVENT_NONE (0) = sin evento
;   ASYNC_EVENT_DISCONNECT (1) = desconexión detectada
;   ASYNC_EVENT_GOTIP (2) = conexión detectada
; ============================================
ASYNC_EVENT_NONE       = 0
ASYNC_EVENT_DISCONNECT = 1
ASYNC_EVENT_GOTIP      = 2

checkAsyncWifi:
    ; NO leer UART si hay operación crítica en curso
    ld a, (Wifi.uart_busy)
    and a
    jr z, .canRead
    xor a                       ; A = ASYNC_EVENT_NONE
    ret
    
.canRead
    ; Intentar leer un byte del UART (no bloqueante)
    call UartImpl.uartRead
    jr c, .gotByte
    xor a                       ; A = ASYNC_EVENT_NONE
    ret
    
.gotByte
    ; A = byte leído
    ; Ignorar caracteres de control (CR, LF, etc)
    cp 32
    jr nc, .validChar
    xor a                       ; A = ASYNC_EVENT_NONE
    ret
    
.validChar
    ; Añadir al buffer circular
    ld c, a                     ; Guardar byte en C
    ld hl, async_buf_idx
    ld e, (hl)
    ld d, 0
    ld hl, async_buffer
    add hl, de
    ld (hl), c                  ; Guardar byte
    
    ; Incrementar índice circular
    ld a, e
    inc a
    cp ASYNC_BUF_SIZE
    jr c, .storeIdx
    xor a                       ; Wrap to 0
.storeIdx
    ld (async_buf_idx), a
    
    ; Incrementar contador de bytes recibidos (hasta ASYNC_BUF_SIZE)
    ld a, (async_buf_count)
    cp ASYNC_BUF_SIZE
    jr nc, .checkPatterns       ; Ya lleno, no incrementar más
    inc a
    ld (async_buf_count), a
    
.checkPatterns
    ; Verificar si tenemos suficientes caracteres
    ld a, (async_buf_count)
    cp 6                        ; Mínimo para "GOT IP" o "DISCON"
    jr nc, .enoughChars
    xor a                       ; A = ASYNC_EVENT_NONE
    ret
    
.enoughChars
    ; Buscar patrones
    call .checkDisconnect
    ret nz                      ; Si NZ, A ya tiene ASYNC_EVENT_DISCONNECT
    call .checkGotIP
    ret                         ; A tiene el resultado (0 o 2)

.checkDisconnect:
    ; Buscar "DISCON" (6 chars)
    ; Calcular posición de inicio considerando wrap-around
    ld a, (async_buf_idx)
    sub 6
    jr nc, .discNoWrap
    add a, ASYNC_BUF_SIZE       ; Wrap: idx + (SIZE - 6)
.discNoWrap
    ; A = posición de inicio del patrón
    ld de, .pat_discon
    call .comparePattern
    jr nz, .notFoundDisc
    
    ; ¡Encontrado DISCONNECT!
    xor a
    ld (async_buf_idx), a       ; Resetear buffer
    ld (async_buf_count), a
    ld a, ASYNC_EVENT_DISCONNECT
    ret                         ; NZ porque A != 0
    
.notFoundDisc
    xor a                       ; Z, A = 0
    ret

.checkGotIP:
    ; Buscar "GOT IP" (6 chars)
    ld a, (async_buf_idx)
    sub 6
    jr nc, .gotNoWrap
    add a, ASYNC_BUF_SIZE
.gotNoWrap
    ld de, .pat_gotip
    call .comparePattern
    jr nz, .notFoundGot
    
    ; ¡Encontrado GOT IP!
    xor a
    ld (async_buf_idx), a
    ld (async_buf_count), a
    ld a, ASYNC_EVENT_GOTIP
    ret
    
.notFoundGot
    xor a                       ; A = ASYNC_EVENT_NONE
    ret

; Compara 6 bytes del buffer circular con patrón
; A = posición inicial en buffer, DE = patrón
; Retorna Z si coincide, NZ si no
.comparePattern
    ld b, 6
.cmpLoop
    push bc
    push de
    
    ; Calcular dirección en buffer (con wrap)
    ld c, a                     ; Guardar índice
    ld hl, async_buffer
    ld d, 0
    ld e, a
    add hl, de
    
    ; Comparar byte
    pop de
    ld a, (de)
    cp (hl)
    pop bc
    ret nz                      ; No coincide
    
    ; Siguiente byte
    inc de
    ld a, c
    inc a
    cp ASYNC_BUF_SIZE
    jr c, .noWrap
    xor a                       ; Wrap
.noWrap
    djnz .cmpLoop
    
    xor a                       ; Z = coincide
    ret

.pat_discon db "DISCON"
.pat_gotip  db "GOT IP"

ASYNC_BUF_SIZE = 16
async_buffer    ds ASYNC_BUF_SIZE
async_buf_idx   db 0
async_buf_count db 0                ; Contador de bytes en buffer (para wrap correcto)

; --------------------------------------------
; waitAnyKey
;   Bloquea hasta que se pulse cualquier tecla.
;   Uso UI (no debe usarse durante parsers de alta velocidad).
; --------------------------------------------
waitAnyKey:
waitAnyKey_loop:
    halt
    call Keyboard.inKey
    and a
    jp z, waitAnyKey_loop
    ret

; ============================================
; Muestra info de redes alineada a la DERECHA en línea 17
; Texto termina en columna 41 (límite seguro de pantalla).
; ============================================
showPageInfo:
    ; --- 1. Calcular datos de paginación ---
    ld a, (Wifi.networks_count)
    and a
    jr nz, .haveNetworks

    ; 0 redes: limpiar línea 17 completa (evita contador obsoleto)
    gotoXY 0, 17
    ld b, 42
.clrLine17
    ld a, ' '
    push bc
    call Display.putC
    pop bc
    djnz .clrLine17
    ret

.haveNetworks
    
    ; Calcular Total pages = ceil(count / PER_PAGE)
    ; = (count - 1) / PER_PAGE + 1 (usando resta repetida)
    dec a                   ; A = count - 1
    ld b, 0
.divTotal
    inc b
    sub PER_PAGE
    jr nc, .divTotal
    ld a, b
    ld (page_total), a

    ; Calcular Current page = offset / PER_PAGE + 1
    ld a, (offset)
    ld b, 0
.divCurrent
    inc b
    sub PER_PAGE
    jr nc, .divCurrent
    ld a, b
    ld (page_current), a

    ; --- 2. Calcular longitud del texto para alinear ---
    ; Base: "X networks detected"
    ; " networks detected" = 18 chars
    ld c, 18
    
    ; Sumar dígitos de networks_count
    ld a, (Wifi.networks_count)
    call getDigitCount      ; Devuelve 1 o 2 en A
    add a, c
    ld c, a                 ; C tiene longitud parcial

    ; Si hay paginación, sumar " (A/B pages)"
    ld a, (page_total)
    cp 2
    jr c, .calcFinish       ; Solo 1 página, terminamos cálculo

    ; " (" + digit + "/" + digit + " pages)"
    ; 2 chars (" (") + page_curr + 1 char ("/") + page_total + 7 chars (" pages)") = 10 + digits
    ld a, c
    add a, 10
    ld c, a
    
    ld a, (page_current)
    call getDigitCount
    add a, c
    ld c, a
    
    ld a, (page_total)
    call getDigitCount
    add a, c
    ld c, a                 ; C = Longitud TOTAL del string

.calcFinish
    ; --- 3. Calcular posición X inicial ---
    ; Queremos terminar en columna 41 (límite derecho)
    ; StartX = 42 - C.
    ld a, 42
    sub c
    ld b, a                 ; B = StartX
    
    ; --- 4. Limpiar línea 17 desde columna 0 hasta StartX ---
    ld a, b
    and a
    jr z, .printInfo        ; Si StartX es 0, no limpiar
    
    push bc
    ld b, a                 ; Cantidad
    gotoXY 0, 17
.clrPre
    ld a, ' '
    push bc
    call Display.putC
    pop bc
    djnz .clrPre
    pop bc                  ; Recuperar B (StartX)

.printInfo
    ; --- 5. Imprimir texto en su posición ---
    ld l, b                 ; L = StartX
    ld h, 17
    ld (Display.coords), hl

    ; Imprimir "Num networks detected"
    ld a, (Wifi.networks_count)
    call printNumber
    ld hl, .msg_net_det
    call Display.putStr

    ; Imprimir paginación si corresponde
    ld a, (page_total)
    cp 2
    ret c

    ld a, '(' : call Display.putC
    ld a, (page_current) : call printNumber
    ld a, '/' : call Display.putC
    ld a, (page_total) : call printNumber
    ld hl, .msg_pages_suff
    call Display.putStr
    ret

.msg_net_det    db " networks detected", 0
.msg_pages_suff db " pages)", 0

; Devuelve en A cuántos dígitos tiene el número en A (0-99)
; 1 si < 10, 2 si >= 10
getDigitCount:
    cp 10
    ld a, 1
    ret c
    inc a
    ret

; Imprime A (0-99) en decimal
printNumber:
    ld c, a
    ld b, 0
    cp 10
    jr c, .oneDigit
    ld d, 0
.div10
    sub 10
    inc d
    cp 10
    jr nc, .div10
    push af
    ld a, d
    add a, '0'
    call Display.putC
    pop af
.oneDigit
    add a, '0'
    jp Display.putC

page_total      db 0
page_current    db 0

; ============================================
; Mensajes y datos
; ============================================
msg_done        db "Connected!", 13, 13, "Now you can use network apps!",13, 0
msg_fail_generic  db "Connection failed!", 13, 13, "Unknown error.", 0
msg_fail_timeout  db "Connection timeout!", 13, 13, "Router not responding.", 0
msg_fail_password db "Wrong password!", 13, 13, "Check password and try again.", 0
msg_fail_notfound db "Network not found!", 13, 13, "AP may be out of range.", 0
msg_fail_connfail db "Connection failed!", 13, 13, "Try again or check router.", 0
msg_press_key   db "Press any key to continue...", 0
msg_conn_attempt db "Connecting (x/3)...", 0
msg_retry_suffix db " Retry", 0
msg_break_cancel db "Press BREAK to cancel", 0
msg_edit_cancel  db "Press EDIT to cancel", 0
msg_open_net    db "Open network (no password needed)", 0
at_start        db 'AT+CWJAP="',0
at_start_old    db 'AT+CWJAP_DEF="',0
at_middle       db '","', 0
msg_ssid        db "Selected SSID:", 0
msg_pass        db "Password (EDIT=cancel, UP=show):", 0

pass_buffer     ds MAX_PASS_LEN + 2
pass_len        db 0
pass_cursor     db 0                ; Posición del cursor en el password
cursor_position db 0
offset          db 0
is_open_network db 0
show_password   db 0                ; Flag para mostrar contraseña
selected_ssid_ptr dw 0              ; Puntero al SSID seleccionado
ui_async_div    db 0                ; Divisor para checkAsyncWifi
autoscan_counter dw 0              ; Contador para auto-rescan (15000 = 5 min)
health_counter  dw 0              ; Contador para health-check periódico (solo invalidar)
force_rescan   db 0              ; 1 => rescan pending after disconnect

msg_head
    ds 13, 196 
    db 180, " NetManZX "
    db VERSION_STRING
    db " ", 195
    ds 13, 196
    db 0

; Barra de estado inferior
msg_log_left
    db "UART log"
    ds 15, 196      
    db 0

msg_wifi_label
    db "WiFi:", 0

    endmodule