    module UI
PER_PAGE = 10
MAX_PASS_LEN = 40           

init:
    call Display.clrscr
    ; Render status bar FIRST to avoid blank white bar flicker
    ld hl, status_scanning_data
    ld a, (hl) : ld (status_color), a
    inc hl : ld (status_text_ptr), hl
    call ipShowScanning         ; Sets IP text + renders full status bar
    ; Banner doble alto: rows 0-1
    setLineColor 0, Display.ATTR_BANNER_TOP
    setLineColor 1, Display.ATTR_BANNER_BOT
    gotoXY 0, 0 : printMsg msg_head
    call Display.stretchRows01
    call drawBadge
    call drawSeparator
    call clearPassBuffer
    ret

; Badge estilo SpectalkZX: triángulo dither con transiciones de color
; Row 0 (top): 4 celdas en bytes 28-31 (escalonado, 1 celda menos)
; Row 1 (bot): 5 celdas en bytes 27-31 (completo)
; Colores Spectrum: rojo, amarillo, verde, azul

badge_pattern:
    db #00, #01, #03, #07, #0F, #1F, #3F, #7F

drawBadge:
    ; Píxeles: row 0, 4 celdas en bytes 28-31
    ld hl, #401C            ; Row 0, scanline 0, byte 28
    ld c, 4
    call .drawCells
    ; Píxeles: row 1, 5 celdas en bytes 27-31
    ld hl, #403B            ; Row 1, scanline 0, byte 27
    ld c, 5
    call .drawCells
    ; Atributos row 0 (top): 4 celdas BRIGHT
    ld hl, #581C            ; Row 0, celda 28
    ld (hl), 01000010b      ; P=black I=red BRIGHT
    inc hl
    ld (hl), 01010110b      ; P=red I=yellow BRIGHT
    inc hl
    ld (hl), 01110100b      ; P=yellow I=green BRIGHT
    inc hl
    ld (hl), 01100001b      ; P=green I=blue BRIGHT
    ; Atributos row 1 (bot): 5 celdas BRIGHT
    ld hl, #583B            ; Row 1, celda 27
    ld (hl), 01000010b      ; P=black I=red BRIGHT
    inc hl
    ld (hl), 01010110b      ; P=red I=yellow BRIGHT
    inc hl
    ld (hl), 01110100b      ; P=yellow I=green BRIGHT
    inc hl
    ld (hl), 01100001b      ; P=green I=blue BRIGHT
    inc hl
    ld (hl), 01001000b      ; P=blue I=black BRIGHT (transición de vuelta)
    ret

; Dibuja patrón dither triangular en C celdas consecutivas
; HL = dirección pantalla (scanline 0), C = número de celdas
.drawCells:
    ld de, badge_pattern
    ld b, 8                 ; 8 scanlines
.scanLoop
    push bc
    push hl
    ld a, (de)
    ld b, c                 ; B = número de celdas
.byteLoop
    ld (hl), a
    inc l
    djnz .byteLoop
    pop hl
    inc h                   ; siguiente scanline
    inc de
    pop bc
    djnz .scanLoop
    ret

; Línea separadora blanca 1px debajo del banner (row 2, scanline 0)
drawSeparator:
    ld a, 2
    ld e, 0
    jp Display.draw_hline_only

; Limpia píxeles de 1 fila de pantalla (8 scanlines × 32 bytes)
; Entrada: A = número de fila (0-23)
; Destruye: AF, BC, DE, HL
clearRowPixels:
    ld d, a : ld e, 0
    call Display.findAddr       ; DE = fila A, scanline 0
    ld b, 8
.crpLoop
    push bc : push de
    ld h, d : ld l, e
    ld (hl), 0
    ld d, h : ld e, l : inc de
    ld bc, 31
    ldir
    pop de : pop bc
    inc d
    djnz .crpLoop
    ret

; ============================================
; statusBarFinalize - Renderiza barra estado doble alto (rows 17-18)
; Lee de: ip_line_buffer, status_text_ptr, ip_value_color, status_color
; ============================================
statusBarFinalize:
    ; Renderizar texto directamente (sin borrar primero = sin flicker)
    gotoXY 0, 18
    ld hl, ip_line_buffer
    call Display.putStr
    ; Rellenar con espacios hasta columna 24 (borra residuos de IP anterior)
.padIP
    ld a, (Display.coords)
    cp 24
    jr nc, .padDone
    ld a, ' '
    call Display.putC
    jr .padIP
.padDone
    gotoXY 24, 18
    ld hl, msg_wifi_label
    call Display.putStr
    gotoXY 30, 18
    ld hl, (status_text_ptr)
    call Display.putStr
    call Display.stretchRows1819
    ; Bajar texto 1px: limpiar scanline 0 de row 18
    ld hl, #5040
    ld de, #5041
    xor a : ld (hl), a
    ld bc, 31
    ldir
    setLineColor 18, Display.ATTR_STATUSBAR
    setLineColor 19, Display.ATTR_STATUS_BOT
    ld a, (ip_value_color)
    call colorIpValueBothRows
    ld a, (status_color)
    jp colorStatusAreaBothRows


; Muestra "IP: Scanning..."
ipShowScanning:
    ld hl, msg_ip_scanning
    call ipSetFromZ
    ld a, Display.ATTR_STATUSBAR
    ld (ip_value_color), a
    jp statusBarFinalize

; Muestra "IP:Disconnected" en rojo
ipShowNotConnected:
    ld hl, msg_ip_disconn
    call ipSetFromZ
    ld a, 172o              ; Rojo sobre blanco brillante
    ld (ip_value_color), a
    jp statusBarFinalize

; Muestra "IP: x.x.x.x" en azul
ipShowConnected:
    call Wifi.getIP
    jr c, ipShowNotConnected
    ld hl, msg_ip_prefix
    call ipSetPrefix
    ld hl, Wifi.ip_buffer
    call ipAppendZ
    ld a, 171o              ; Azul sobre blanco brillante
    ld (ip_value_color), a
    jp statusBarFinalize

; Colorea zona de valor IP (celdas 3-17) en ambas rows 18-19
colorIpValueBothRows:
    ld hl, #5A40 + 3        ; Línea 18, celda 3
    ld b, 15
.loop18
    ld (hl), a
    inc hl
    djnz .loop18
    res 6, a                ; Quitar BRIGHT para row 19
    ld hl, #5A60 + 3        ; Línea 19, celda 3
    ld b, 15
.loop19
    ld (hl), a
    inc hl
    djnz .loop19
    ret

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

; Buffers/mensajes
msg_ip_prefix      db "IP: ", 0
msg_ip_disconn     db "IP: Disconnected", 0
msg_ip_scanning    db "IP: Scanning...", 0
    RTVAR ip_line_buffer, 40

; Colorea zona de estado (celdas 22-31) en ambas rows 18-19
colorStatusAreaBothRows:
    ld hl, #5A40 + 22           ; Línea 18, celda 22
    ld b, 10
.loop18
    ld (hl), a
    inc hl
    djnz .loop18
    res 6, a                    ; Quitar BRIGHT para row 19
    ld hl, #5A60 + 22           ; Línea 19, celda 22
    ld b, 10
.loop19
    ld (hl), a
    inc hl
    djnz .loop19
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
    jr setStatusCommon

; Rutina común para mostrar estado (quiet: solo variables, sin render)
setStatusCommon_q:
    ld a, (hl)
    ld (status_color), a
    inc hl
    ld (status_text_ptr), hl
    ret

; Rutina común para mostrar estado (con render)
; HL = puntero a datos (color, mensaje)
setStatusCommon:
    call setStatusCommon_q
    jp statusBarFinalize

status_color db 0
status_text_ptr dw 0
ip_value_color db Display.ATTR_STATUSBAR

; Datos de estado: color (1 byte) + mensaje
status_scanning_data:
    db Display.ATTR_STATUSBAR   ; Negro sobre blanco brillante
    db "Scanning    ", 0
status_connected_data:
    db 174o                     ; Verde sobre blanco brillante
    db "Connected   ", 0
status_disconn_data:
    db 172o                     ; Rojo sobre blanco brillante
    db "Disconnected", 0
msg_conn_lost      db "Connection lost!", 13, 10, 0

; Actualiza estado según Wifi.is_connected (quiet: sin render)
updateWifiStatus_q:
    ld a, (Wifi.is_connected)
    and a
    ld hl, status_disconn_data
    jr z, setStatusCommon_q
    ld hl, status_connected_data
    jr setStatusCommon_q

; Actualiza estado según Wifi.is_connected (con render)
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

; ============================================
; passwordInput - Entrada de contraseña compartida
; Usa vars: pass_buffer, pass_len, pass_cursor, show_password
; Retorna: CF=0 si ENTER, CF=1 si CANCEL (BREAK)
; ============================================
PASS_LINE_DEFAULT = 7
pass_line   db PASS_LINE_DEFAULT   ; Línea donde se dibuja el password

passwordInput:
    ; Debounce: esperar a que se suelte la tecla anterior
.piDebounce
    halt
    call Keyboard.inKeyNoWait
    and a
    jr nz, .piDebounce
; --- Full redraw (solo para toggle e init) ---
.piRedraw
    halt
    ld a, (pass_line)
    ld h, a : ld l, 0
    ld (Display.coords), hl
    ld a, (pass_cursor) : and a : jr z, .piCursor
    ld b, a : ld hl, pass_buffer
    ld a, (show_password) : and a : jr nz, .piRealB
.piAstB
    push bc : push hl : ld a, '*' : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piAstB
    jr .piCursor
.piRealB
    push bc : push hl : ld a, (hl) : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piRealB
.piCursor
    ld a, 127 : call Display.putCBig
    ld a, (pass_len) : ld b, a : ld a, (pass_cursor) : cp b : jr nc, .piClrTail
    ld c, a : ld a, b : sub c : jr z, .piClrTail : ld b, a
    ld a, (pass_cursor) : ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de
    ld a, (show_password) : and a : jr nz, .piRealA
.piAstA
    push bc : push hl : ld a, '*' : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piAstA
    jr .piClrTail
.piRealA
    push bc : push hl : ld a, (hl) : call Display.putCBig : pop hl : inc hl : pop bc : djnz .piRealA
.piClrTail
    ld a, ' ' : call Display.putCBig : ld a, ' ' : call Display.putCBig
    ; putCBig ya escribe doble alto — NO hacer stretch
    jr .piWait

; --- Helpers para renderizado incremental ---
; Posiciona cursor de pantalla en columna B+1, fila pass_line
.piSetPos
    ld a, (pass_line) : ld h, a
    ld l, b
    ld (Display.coords), hl
    ret

; Dibuja char del buffer en posición B (* o real según show_password)
.piDrawBufAt
    call .piSetPos
    ld a, (show_password) : and a
    jr nz, .piDrawReal
    ld a, '*'
    jp Display.putCBig
.piDrawReal
    ld hl, pass_buffer : ld d, 0 : ld e, b : add hl, de
    ld a, (hl)
    jp Display.putCBig

; Dibuja cursor bloque en posición B
.piDrawCurAt
    call .piSetPos
    ld a, 127
    jp Display.putCBig

; Dibuja espacio en posición B
.piDrawSpcAt
    call .piSetPos
    ld a, ' '
    jp Display.putCBig

; EI + jp .piWait (shared tail for incremental handlers)
.piStretchWait
    ei
    jp .piWait

; --- Bucle de espera de tecla ---
.piWait
    ld b, 4
.piWL   halt : djnz .piWL
    call Keyboard.checkBreak : jp z, .piCancel
    call Keyboard.inKeyNoWait : and a : jr z, .piWait
    cp Keyboard.KEY_UP : jp z, .piToggle
    cp 8 : jp z, .piLeft
    cp 9 : jp z, .piRight
    cp Keyboard.KEY_BS : jp z, .piDel
    cp 13 : jp z, .piEnter
    cp 32 : jp c, .piWait
    cp 127 : jp nc, .piWait

    ; --- Insertar carácter ---
    ld c, a
    ld a, (pass_len) : cp MAX_PASS_LEN : jp nc, .piWait
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : cp b
    jr nz, .piInsMid                ; Cursor en medio → full redraw

    ; === APPEND AL FINAL (caso común) ===
    ld a, (pass_cursor) : ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de
    ld (hl), c : inc hl : ld (hl), 0
    ld a, (pass_len) : inc a : ld (pass_len), a
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    ; Render: recargar B de memoria antes de CADA call (drawCBig destruye regs)
    ld a, (pass_cursor) : dec a : ld b, a      ; B = pos del char nuevo
    call .piDrawBufAt
    ld a, (pass_cursor) : ld b, a              ; B = nueva pos cursor
    call .piDrawCurAt
    ld a, (pass_cursor) : inc a : ld b, a      ; B = pos siguiente (limpiar)
    call .piDrawSpcAt
    jp .piWait

    ; Inserción en medio → shift + full redraw
.piInsMid
    ld a, (pass_len) : ld b, a : ld a, (pass_cursor) : ld e, a
.piShR  ld a, b : cp e : jr z, .piIns
    dec b : ld hl, pass_buffer : ld d, 0 : push de : ld e, b : add hl, de
    ld a, (hl) : inc hl : ld (hl), a : pop de : jr .piShR
.piIns  ld a, (pass_cursor) : ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de : ld (hl), c
    ld a, (pass_len) : inc a : ld (pass_len), a
    ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de : xor a : ld (hl), a
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    jp .piRedraw

; --- Cursor izquierda (incremental: 2 celdas) ---
.piLeft ld a, (pass_cursor) : and a : jp z, .piWait
    dec a : ld (pass_cursor), a
    ; Restaurar char en posición vieja (cursor+1)
    ld a, (pass_cursor) : inc a : ld b, a
    call .piDrawBufAt
    ; Cursor en nueva posición
    ld a, (pass_cursor) : ld b, a
    call .piDrawCurAt
    jp .piWait

; --- Cursor derecha (incremental: 2 celdas) ---
.piRight
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : cp b : jp z, .piWait
    ld a, (pass_cursor) : inc a : ld (pass_cursor), a
    ; Restaurar char en posición vieja (cursor-1)
    ld a, (pass_cursor) : dec a : ld b, a
    call .piDrawBufAt
    ; Cursor en nueva posición
    ld a, (pass_cursor) : ld b, a
    call .piDrawCurAt
    jp .piWait

; --- Toggle mostrar/ocultar (full redraw, raro) ---
.piToggle ld a, (show_password) : xor 1 : ld (show_password), a : jp .piRedraw

; --- Borrar carácter ---
.piDel  ld a, (pass_cursor) : and a : jp z, .piWait
    ld b, a : ld a, (pass_len) : cp b : jr z, .piDelEnd
    ; Borrado en medio → shift + full redraw
    ld a, (pass_cursor) : ld b, a : ld a, (pass_len) : ld c, a
.piShL  ld a, b : cp c : jr z, .piDelEnd
    ld hl, pass_buffer : ld d, 0 : ld e, b : add hl, de
    ld a, (hl) : dec hl : ld (hl), a : inc b : jr .piShL
.piDelEnd
    ld a, (pass_len) : dec a : ld (pass_len), a
    ld hl, pass_buffer : ld d, 0 : ld e, a : add hl, de : xor a : ld (hl), a
    ld a, (pass_cursor) : dec a : ld (pass_cursor), a
    ; === BORRADO AL FINAL (caso común): incremental ===
    ld b, a : ld a, (pass_len) : cp b
    jp nz, .piRedraw                ; Si cursor ≠ len → fue delete en medio, full redraw
    ; Cursor == len: render incremental (recargar B de memoria cada vez)
    ld a, (pass_cursor) : ld b, a
    call .piDrawCurAt
    ld a, (pass_cursor) : inc a : ld b, a
    call .piDrawSpcAt
    ld a, (pass_cursor) : add a, 2 : ld b, a
    call .piDrawSpcAt
    jp .piWait

.piEnter or a : ret
.piCancel scf : ret

sti_buf  dw 0
sti_max  db 0
sti_len  db 0
sti_line db 0

topClean:
    call Display.clrListOnly    ; Solo limpia líneas 2-14
    call clearListAttrs
    jp drawSeparator            ; Redibujar separador (incluye ret)

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
    ld a, (Wifi.networks_count)
    and a
    ret z                       ; Sin redes: no pintar cursor
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
    jp z, .noNetworks

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
    call Display.compareStringZ
    pop hl
    jr nz, .noConnAttr
    
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

    ; Avanzar coords a la siguiente línea (X=0, Y++)
    ld hl, Display.coords
    xor a : ld (hl), a
    inc hl : inc (hl)

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


; Muestra texto en doble alto en rows 3-4
; HL = texto, C = color con BRIGHT para row 3
; Row 4 = mismo color sin BRIGHT
showBigMessage:
    push bc
    push hl
    gotoXY 0, 3
    pop hl
    call Display.putStr
    call Display.stretchRows34
    pop bc
    push bc                     ; Preservar color (setAttr destruye BC)
    ld a, 3
    call Display.setAttr        ; Row 3: BRIGHT
    pop bc
    ld a, c : res 6, a : ld c, a
    ld a, 4
    jp Display.setAttr          ; Row 4: sin BRIGHT

; Pantalla de éxito de conexión (bucle infinito)
showConnectedSuccessScreen:
    call topClean
    ld hl, msg_connected_title : ld c, 104o : call showBigMessage
    gotoXY 0, 6 : ld hl, msg_done_body : call Display.putStr
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

    ; Línea separadora debajo del menú
    ld a, 5 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline

    ; Mostrar indicadores de scroll
    call showScrollIndicators

    call showPageInfo

    ; Usar rutina común para dibujar redes
    call renderNetworksCommon
    ld a, (Wifi.networks_count)
    and a
    ret z                       ; Sin redes: no pintar cursor
    jp showCursor

no_net_msg db "No networks found. Press 'R' to rescan.", 0
msg_help   db "Q/A:Nav O/P:Page R:Refresh D:Diag", 0
msg_help_conn db "Q/A:Nav R:Refresh X:Disconn D:Diag", 0
msg_help2  db "H:Hidden W:WPS L:Log I:About", 0

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
    ld a, '~'               ; Abierta (círculo hueco)
    jr .printLock
.locked
    ld a, '`'               ; Cerrada (círculo relleno)
.printLock
    call Display.putC
    
    ; Recuperar RSSI y calcular barras
    ld a, (rssi_value)
    and #7F                 ; A = RSSI (0-127)
    call drawRssiBars

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

current_line db 0
current_screen_idx db 0
conn_row_found db 0             ; Flag: 1 si ya se encontró la red conectada

; ============================================
; showConnectedDialog
; ============================================
showConnectedDialog:
    call topClean
    gotoXY 0, 3 : ld hl, .msg_network : call Display.putStr
    ; SSID en doble alto verde (rows 4-5)
    gotoXY 0, 4
    ld hl, Wifi.connected_ssid
    call Display.putStrBig
    setLineColor 4, Display.ATTR_SSID_INPUT
    setLineColor 5, Display.ATTR_SSID_INPUT
    ; Preguntas
    gotoXY 0, 7 : ld hl, .msg_question : call Display.putStr
    gotoXY 0, 9 : ld hl, .msg_options : call Display.putStr

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

.msg_network   db "Connected to network:", 0
.msg_question  db "Do you want to reconfigure?", 0
.msg_options   db "(Y)es reconfigure / (N)o exit", 0

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
; Si CF=1, A = índice real de la red (0-based)
; ============================================
connectedSSIDPresentInList:
    ld a, (Wifi.networks_count)
    and a
    jr z, .notFound

    ld b, a
    ld c, 0             ; C = índice actual
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
    inc c               ; Siguiente índice
    push bc             ; Preservar B y C
    xor a
    ld bc, #ffff
    cpir                ; HL apunta después del 0
    pop bc              ; Restaurar B y C
    djnz .loopNet

.notFound
    or a
    ret

.found
    ld a, c             ; A = índice real
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
    jp z, .noKey
    
    ; Resetear contador cuando hay actividad del usuario
    ld hl, 0
    ld (autoscan_counter), hl
    ld (health_counter), hl

    cp Keyboard.KEY_UP : jp z, cursorUp
    cp 'q'             : jp z, cursorUp
    cp 'Q'             : jp z, cursorUp
    cp Keyboard.KEY_DN : jp z, cursorDown
    cp 'a'             : jp z, cursorDown
    cp 'A'             : jp z, cursorDown

    cp 'o' : jp z, pageUp
    cp 'O' : jp z, pageUp
    cp 'p' : jp z, pageDown
    cp 'P' : jp z, pageDown

    cp 'r' : jp z, rescan
    cp 'R' : jp z, rescan
    cp 'd' : jp z, showDiagnostics
    cp 'D' : jp z, showDiagnostics
    cp 'h' : jp z, manualSSID
    cp 'H' : jp z, manualSSID
    cp 'x' : jp z, doDisconnect
    cp 'X' : jp z, doDisconnect
    cp 'l' : jp z, toggleDebugLog
    cp 'L' : jp z, toggleDebugLog
    cp 'w' : jp z, doWPS
    cp 'W' : jp z, doWPS
    cp 'i' : jp z, showAbout
    cp 'I' : jp z, showAbout

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
    call updateWifiStatus_q
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
    call updateWifiStatus_q
    call ipShowConnected         ; Actualizar IP en barra superior
    ; Redibujar lista para aplicar atributo de red conectada
    call renderNetworksOnly
    call showCursor
    jp uiLoopMain

rescan:
    call hideCursor
    xor a : ld (cursor_position), a : ld (offset), a
    
    ; Mostrar "Scanning..." en línea 17, col 0
    gotoXY 0, 17
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
    
    ; Verificar que offset sigue siendo válido (offset debe ser < count)
    ld a, c                     ; offset guardado
    ld d, a
    ld a, (Wifi.networks_count)
    cp d
    jr z, .autoResetPos         ; offset == count → inválido
    jr nc, .autoOffsetOK        ; offset < count → OK
    jr .autoResetPos            ; offset > count → resetear
    
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
    call invalidateConnectedIfMissing
    call renderListOnly
    
    pop hl
    pop de
    pop bc
    ret

; ============================================
; ============================================
; doDisconnect - Desconectar de la red actual
; ============================================
doDisconnect:
    ; Verificar si está conectado
    ld a, (Wifi.is_connected)
    and a
    jp z, uiLoop

    ; Confirmación
    call hideCursor : call topClean
    gotoXY 1, 3
    ld hl, .msg_disc_confirm
    call Display.putStr
    gotoXY 1, 5
    ld hl, .msg_disc_yn
    call Display.putStr
.waitDiscConfirm
    halt
    call Keyboard.inKey
    and a : jr z, .waitDiscConfirm
    cp 'y' : jr z, .doDiscNow
    cp 'Y' : jr z, .doDiscNow
    ; Cualquier otra tecla cancela
    call renderList : jp uiLoop

.doDiscNow
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
    call updateWifiStatus_q
    call ipShowNotConnected

    ; Mostrar confirmación en doble alto
    call topClean
    ld hl, .msg_disconnected : ld c, 102o : call showBigMessage
    call showPressKey

.waitDiscKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitDiscKey
    
    call renderList
    jp uiLoop

.msg_disc_confirm  db "Disconnect from WiFi?", 0
.msg_disc_yn       db "(Y)es / any key = cancel", 0
.msg_disconnected  db "Disconnected.", 0

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
    gotoXY 0, 4
    ld hl, .msg_manual_title
    call Display.putStr

    gotoXY 0, 6
    ld hl, .msg_enter_ssid
    call Display.putStr

    ; Mostrar mensaje de cancelación
    gotoXY 0, 11
    ld hl, .msg_ssid_help
    call Display.putStr

    setLineColor 8, Display.ATTR_PASS_INPUT
    setLineColor 9, Display.ATTR_PASS_INPUT

; Repintado completo de SSID (para cursor left)
.drawSSIDFull
    halt
    gotoXY 0, 8
    ; Limpiar línea completa (doble alto)
    ld b, 34
.clearSSIDFull
    ld a, ' '
    push bc
    call Display.putCBig
    pop bc
    djnz .clearSSIDFull

    gotoXY 0, 8

    ; Chars antes del cursor
    ld a, (manual_ssid_cursor)
    and a
    jr z, .ssidFullCursor

    ld b, a
    ld hl, manual_ssid_buffer
.ssidFullBefore
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidFullBefore

.ssidFullCursor
    ld a, 127
    call Display.putCBig

    ; Chars después del cursor
    ld a, (manual_ssid_len)
    ld b, a
    ld a, (manual_ssid_cursor)
    cp b
    jr nc, .ssidFinishDraw

    ld c, a
    ld a, b
    sub c
    jr z, .ssidFinishDraw
    ld b, a

    ld a, (manual_ssid_cursor)
    ld hl, manual_ssid_buffer
    ld d, 0
    ld e, a
    add hl, de

.ssidFullAfter
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidFullAfter
    jr .ssidFinishDraw

; Repintado parcial de SSID (desde cursor, para insertar/borrar)
.drawSSID
    halt
    ; Posicionar al inicio de la línea
    gotoXY 0, 8

    ; Dibujar caracteres antes del cursor
    ld a, (manual_ssid_cursor)
    and a
    jr z, .ssidDrawCursor
    
    ld b, a
    ld hl, manual_ssid_buffer
.ssidDrawBefore
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidDrawBefore

.ssidDrawCursor
    ld a, 127
    call Display.putCBig
    
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
    push bc : push hl
    ld a, (hl) : call Display.putCBig
    pop hl : inc hl : pop bc
    djnz .ssidDrawAfter

.ssidClearRest
    ld a, ' ' : call Display.putCBig
    ld a, ' ' : call Display.putCBig

.ssidFinishDraw
.waitSSIDKey
    ld b, 4
.waitSSIDLoop
    halt
    djnz .waitSSIDLoop

    call Keyboard.checkBreak : jp z, .cancelManual
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitSSIDKey
    
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
    setLineColor 8, 107o
    call renderList
    jp uiLoop

.msg_ssid_help db "BREAK=cancel, L/R=move cursor", 0

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

    setLineColor 4, 071o
    setLineColor 7, Display.ATTR_PASS_INPUT
    setLineColor 8, Display.ATTR_PASS_INPUT
    xor a
    ld (show_password), a
    ld (pass_cursor), a

    ; Entrada de contraseña usando rutina compartida (pass_line=7 = default)
    call passwordInput
    jp c, .cancelManual

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
    call updateWifiStatus_q
    call ipShowNotConnected

.skipUiUpdate

    call Wifi.flushInput
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    call Wifi.checkOkErr
    call Wifi.flushInput

.connectRetryManual
    ld a, 10
    call clearRowPixels
    gotoXY 0, 10
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

    ; Copiar SSID manual a connected_ssid
    ld hl, manual_ssid_buffer
    ld de, Wifi.connected_ssid
    ld bc, 33                       ; MAX_SSID_LEN + 1 (incluye null terminator)
    ldir
    
    call updateWifiStatus_q
    call topClean
    ld b, 50
.ipDelayManual
    halt
    djnz .ipDelayManual
    call ipShowConnected
    ld hl, msg_connected_title : ld c, 104o : call showBigMessage
    gotoXY 0, 6 : ld hl, msg_done_body : call Display.putStr
    gotoXY 0, 8 : ld hl, msg_press_key : call Display.putStr
.waitSuccessManual
    halt : call Keyboard.inKey : and a : jr z, .waitSuccessManual
    cp 15 : jp z, exitProgram
    call renderList : jp uiLoop

.connFailedManual
    call tryRecoverESP
    xor a : ld (Wifi.is_connected), a
    call updateWifiStatus_q
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

    RTVAR manual_ssid_buffer, 33
manual_ssid_len    db 0
manual_ssid_cursor db 0

exitProgram:
    call Display.clrscr
    ld sp, (saved_sp)
    ei
    ret

; ============================================
; toggleDebugLog - Toggle UART debug log (L key)
; ============================================
toggleDebugLog:
    ld a, (Wifi.debug_log)
    xor 1
    ld (Wifi.debug_log), a
    ; Mostrar estado en log
    ld hl, .msg_log_on
    and a
    jr nz, .tShow
    ld hl, .msg_log_off
.tShow
    call Display.putStrLog
    jp uiLoopMain
.msg_log_on  db "UART log: ON", 13, 0
.msg_log_off db "UART log: OFF", 13, 0

; ============================================
; doWPS - WPS push-button connect (W key)
; ============================================
doWPS:
    ; Si está conectado, pedir confirmación antes de desconectar
    ld a, (Wifi.is_connected)
    and a
    jr z, .wps_start

    call hideCursor : call topClean
    gotoXY 0, 3
    ld hl, .msg_wps_warn
    call Display.putStr
    gotoXY 0, 5
    ld hl, .msg_wps_yn
    call Display.putStr
.wps_confirm
    halt
    call Keyboard.inKey
    and a : jr z, .wps_confirm
    cp 'y' : jr z, .wps_do_disc
    cp 'Y' : jr z, .wps_do_disc
    ; Cancelar
    call renderList : jp uiLoop

.wps_do_disc
    ; Desconectar primero
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    call Wifi.checkOkErr
    xor a : ld (Wifi.is_connected), a
    call updateWifiStatus
    ld b, 75
.wps_disc_wait
    halt
    djnz .wps_disc_wait
    call flushUartBuffer

.wps_start
    call topClean
    gotoXY 1, 4
    ld hl, .msg_wps_prompt
    call Display.putStr
    gotoXY 1, 6
    ld hl, .msg_wps_wait
    call Display.putStr

.wps_send
    ; Enviar AT+WPS=1
    call flushUartBuffer
    ld hl, .cmd_wps
    call Wifi.espSendZ
    ; Esperar respuesta larga (WPS puede tardar ~120s)
    call Wifi.checkOkErrLong
    jr c, .wps_fail
    ; Flush post-WPS (mensajes asíncronos residuales)
    call flushUartBuffer
    ; Verificar conexión
    call Wifi.checkConnection
    jr c, .wps_fail
    ; Éxito
    call updateWifiStatus_q
    call ipShowConnected
    gotoXY 1, 8
    ld hl, .msg_wps_ok
    call Display.putStr
    jr .wps_exit
.wps_fail
    ; WPS fallo deja el ESP en mal estado: resetear para recuperarlo
    call flushUartBuffer
    call Wifi.reset
    ; Esperar a que el ESP se estabilice tras reset
    ld b, 125
.wps_reset_wait
    halt
    djnz .wps_reset_wait
    call flushUartBuffer
    gotoXY 1, 8
    ld hl, .msg_wps_fail
    call Display.putStr
.wps_exit
    gotoXY 1, 10
    ld hl, .msg_wps_key
    call Display.putStr
.wps_waitkey
    halt
    call Keyboard.inKeyNoWait
    and a
    jr z, .wps_waitkey
    ; Esperar antes de escanear (ESP puede necesitar tiempo tras WPS)
    ld b, 100
.wps_scanwait
    halt
    djnz .wps_scanwait
    call flushUartBuffer
    ; Rescan para recuperar la lista de redes
    call Wifi.getList
    call renderList
    jp uiLoop
.msg_wps_warn   db "WPS requires disconnecting first.", 0
.msg_wps_yn     db "(Y)es / any key = cancel", 0
.msg_wps_prompt db "Press WPS button on router", 0
.msg_wps_wait   db "Waiting for WPS...", 0
.msg_wps_ok     db "WPS connected!", 0
.msg_wps_fail   db "WPS failed", 0
.msg_wps_key    db "Press any key", 0
.cmd_wps        db "AT+WPS=1", 13, 10, 0

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
; ============================================
; drawSignalLine - Dibuja "Signal:   ||||||||.." en la línea indicada
; Entrada: A = número de línea
; Usa: selected_real_idx para obtener RSSI
; ============================================
drawSignalLine:
    ld h, a : ld l, 0
    ld (Display.coords), hl
    push af
    ld hl, showNetDetail.nd_sig
    call Display.putStr
    ; Colorear celdas 7-16 de la línea en amarillo
    pop af
    ld l, a : ld h, 0
    add hl, hl : add hl, hl : add hl, hl : add hl, hl : add hl, hl
    ld de, #5800 + 7
    add hl, de
    ld a, Display.ATTR_CONNECTED
    ld b, 10
.clr
    ld (hl), a : inc hl : djnz .clr
    ; Obtener RSSI y dibujar barras
    ld a, (selected_real_idx)
    ld hl, Wifi.rssi_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl) : and #7F
    jp drawRssiBars

; Rutina compartida: calcula y dibuja barras RSSI
; Entrada: A = RSSI (0-127). Coords ya posicionadas.
drawRssiBars:
    ld b, a : ld a, 93 : sub b
    jr nc, .calc
    xor a
.calc
    ld b, 0 : ld c, 6
.div
    inc b : sub c : jr nc, .div
    ld a, b : and a : jr nz, .cmax
    inc a
.cmax
    cp 11 : jr c, .bars
    ld a, 10
.bars
    ld b, a : ld c, a
.full
    ld a, b : and a : jr z, .empty
    push bc : ld a, '|' : call Display.putC : pop bc
    dec b : jr .full
.empty
    ld a, 10 : sub c : ret z
    ld b, a
.emptyL
    push bc : ld a, '.' : call Display.putC : pop bc
    dec b : jr nz, .emptyL
    ret

; ============================================
; showNetDetail - Muestra información detallada de la red seleccionada
; Usa: selected_ssid_ptr, selected_real_idx
; Muestra en líneas 3-8
; ============================================
showNetDetail:
    ; Líneas 4-5: "Selected SSID:  NombreRed" doble alto
    ; 14 chars + 2 espacios = 16 x 6px = 96px = 12 celdas exactas (sin clash)
    gotoXY 0, 4
    ld hl, msg_ssid
    call Display.putStr
    ld a, ' ' : call Display.putC
    ld a, ' ' : call Display.putC
    ld hl, (selected_ssid_ptr)
    ld a, (hl) : and a : jr nz, .nd_printSSID
    ld hl, msg_hidden
.nd_printSSID
    ld b, 24
    call putStrLimited
    call Display.stretchRows45
    ; Row 4: celdas 0-11 blanco BRIGHT, 12-31 verde BRIGHT
    ld hl, #5880
    ld a, Display.ATTR_NORMAL
    ld b, 12
.nd_attr_w4
    ld (hl), a : inc hl : djnz .nd_attr_w4
    ld a, Display.ATTR_SSID_INPUT
    ld b, 20
.nd_attr_g4
    ld (hl), a : inc hl : djnz .nd_attr_g4
    ; Row 5: mismos colores sin BRIGHT
    ld hl, #58A0
    ld a, 007o
    ld b, 12
.nd_attr_w5
    ld (hl), a : inc hl : djnz .nd_attr_w5
    ld a, 004o
    ld b, 20
.nd_attr_g5
    ld (hl), a : inc hl : djnz .nd_attr_g5

    ; Línea 7: Security
    gotoXY 0, 7
    ld hl, .nd_sec
    call Display.putStr
    ld a, (selected_real_idx)
    ld hl, Wifi.ecn_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl)
    ; ECN: 0=OPEN, 1=WEP, 2=WPA-PSK, 3=WPA2-PSK, 4=WPA/WPA2, 5=Enterprise
    cp 6 : jr c, .nd_ecn_ok
    xor a                   ; Valor desconocido -> tratar como Open
.nd_ecn_ok
    ld hl, .ecn_table
    add a, a               ; x2 (cada puntero = 2 bytes)
    ld e, a : ld d, 0 : add hl, de
    ld a, (hl) : inc hl : ld h, (hl) : ld l, a
    call Display.putStr

    ; Línea 8: Channel
    gotoXY 0, 8
    ld hl, .nd_chan
    call Display.putStr
    ld a, (selected_real_idx)
    ld hl, Wifi.channel_buffer
    ld d, 0 : ld e, a : add hl, de
    ld a, (hl)
    and a
    jr z, .nd_chan_unk
    call printNumber
    jr .nd_signal
.nd_chan_unk
    ld a, '-' : call Display.putC

    ; Línea 9: Signal - etiqueta en blanco, barras en amarillo
.nd_signal
    ld a, 9
    jp drawSignalLine              ; Tail call (dibuja "Signal: ||||..." en línea A)

.nd_sec         db "Security: ", 0
.nd_chan        db "Channel:  ", 0
.nd_sig         db "Signal:   ", 0

; Tabla de punteros a nombres de encriptación
.ecn_table
    dw .ecn_open, .ecn_wep, .ecn_wpa, .ecn_wpa2, .ecn_wpa12, .ecn_ent
.ecn_open       db "Open", 0
.ecn_wep        db "WEP", 0
.ecn_wpa        db "WPA-PSK", 0
.ecn_wpa2       db "WPA2-PSK", 0
.ecn_wpa12      db "WPA/WPA2", 0
.ecn_ent        db "WPA2-Ent", 0

; ============================================
; selectItem y conexión
; ============================================
selectItem:
    ld a, (Wifi.networks_count) : and a : jp z, uiLoop
    
    ; Obtener posición en pantalla
    ld a, (cursor_position) : ld hl, offset : add a, (hl)
    ; Convertir a índice real usando display_indices
    call Wifi.getDisplayIndex   ; A = índice real de la red
    ld (selected_real_idx), a
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
    call hideCursor : call topClean
    call showNetDetail
    gotoXY 0, 11
    ld hl, .msg_already_conn
    call Display.putStr
    gotoXY 0, 13
    ld hl, msg_press_key
    call Display.putStr
.waitAlready
    halt
    call Keyboard.inKey
    and a
    jr z, .waitAlready
    call renderList
    jp uiLoop

.msg_already_conn db "Already connected to this network", 0

.notConnectedYet
    call hideCursor : call topClean
    call showNetDetail

    ld a, (is_open_network) : and a : jp nz, .connectDirect
    call clearPassBuffer
    gotoXY 0, 11 : ld hl, msg_pass : call Display.putStr
    setLineColor 12, Display.ATTR_PASS_INPUT
    setLineColor 13, Display.ATTR_PASS_INPUT
    ld a, 12 : ld (pass_line), a
    xor a
    ld (show_password), a
    ld (pass_cursor), a

    call passwordInput
    ; Restaurar pass_line por defecto
    ld a, PASS_LINE_DEFAULT : ld (pass_line), a
    jr nc, .connect
    ; Fall through to cancel

.cancel
    setLineColor 12, Display.ATTR_NORMAL
    setLineColor 13, Display.ATTR_NORMAL
    call renderList : jp uiLoop

.connectDirect
    call clearPassBuffer
    gotoXY 0, 11 : ld hl, msg_open_net : call Display.putStr

.connect
    ; Limpiar zona de password (filas 10-13) — rápido via LDIR
    setLineColor 10, Display.ATTR_NORMAL
    setLineColor 11, Display.ATTR_NORMAL
    setLineColor 12, Display.ATTR_NORMAL
    setLineColor 13, Display.ATTR_NORMAL
    ld d, 10 : ld e, 0 : call Display.findAddr  ; DE = row 10 sl0
    ld b, 8
.clrPwSl
    push bc : push de
    ld h, d : ld l, e
    ld (hl), 0
    ld d, h : ld e, l : inc de
    ld bc, 127          ; 4 filas × 32 bytes - 1
    ldir
    pop de : pop bc
    inc d
    djnz .clrPwSl

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
    call updateWifiStatus_q
    call ipShowNotConnected

.skipUiUpdate:

    call Wifi.flushInput
    ld hl, cmd_disconnect
    call Wifi.espSendZ
    call Wifi.checkOkErr
    call Wifi.flushInput

.connectRetry
    ; Limpiar zona de password/input (filas 11-13) — rápido via LDIR
    setLineColor 11, Display.ATTR_NORMAL
    setLineColor 12, Display.ATTR_NORMAL
    setLineColor 13, Display.ATTR_NORMAL
    ; Limpiar píxeles de filas 11-13 (tercio 1: rows 8-15)
    ; Row 11 sl0 = $48+3*$20 = $4860... usar findAddr
    ld d, 11 : ld e, 0 : call Display.findAddr  ; DE = row 11 sl0
    ld b, 8             ; 8 scanlines
.clrRows
    push bc : push de
    ld h, d : ld l, e
    ld (hl), 0
    ld d, h : ld e, l : inc de
    ld bc, 95           ; 3 filas × 32 bytes - 1
    ldir
    pop de : pop bc
    inc d               ; siguiente scanline
    djnz .clrRows

    gotoXY 0, 11
    ; Mostrar intento actual
    ld a, (conn_retries)
    ld b, a
    ld a, 4
    sub b                       ; 4 - retries = intento (1, 2, 3)
    add a, '0'
    ld (msg_conn_attempt + 12), a
    ld hl, msg_conn_attempt
    call Display.putStr

    ; Mostrar opción de cancelar
    gotoXY 0, 13
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

    ; Fallo - mostrar "Retry" al lado de "Connecting..."
    gotoXY 20, 11
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
    ld bc, MAX_SSID_LEN + 1
    ldir
    
    call updateWifiStatus_q

    call topClean
    ld hl, msg_connected_title : ld c, 104o : call showBigMessage
    gotoXY 0, 6 : ld hl, msg_done_body : call Display.putStr
    gotoXY 0, 8 : ld hl, msg_press_key : call Display.putStr

    ; Delay para que el ESP tenga la IP lista, reintentar si falla
    ld c, 3                 ; 3 intentos de obtener IP
.ipRetry
    ld b, 50                ; ~1s de espera
.ipDelay
    halt
    djnz .ipDelay
    call Wifi.getIP
    jr nc, .ipGot           ; CF=0 → IP obtenida
    dec c
    jr nz, .ipRetry         ; Reintentar
.ipGot
    call ipShowConnected
.waitSuccess
    halt : call Keyboard.inKey : and a : jr z, .waitSuccess
    cp 15 : jp z, exitProgram
    call renderList : jp uiLoop

.connFailedFinal
    ; Intentar recuperar ESP si está colgado
    call tryRecoverESP
    
.connFailed
    xor a : ld (Wifi.is_connected), a
    call updateWifiStatus_q
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
    jp Wifi.ensureCommandMode

; ============================================
; Diagnósticos
; ============================================
DIAG_ITEMS = 7
DIAG_FIRST_LINE = 6
ATTR_DIAG_TITLE = 00000100b  ; Verde sobre negro (BRIGHT 0)

; "Press any key..." en línea 17, col 0, amarillo
ATTR_PRESS_KEY = 01000110b  ; Amarillo brillante sobre negro
showPressKey:
    setLineColor 17, ATTR_PRESS_KEY
    gotoXY 0, 17
    ld hl, msg_press_key
    jp Display.putStr

; Cabecera estándar para pantallas de diagnóstico
; HL = puntero a título. Limpia pantalla, título doble alto verde.
diagHeader:
    push hl
    call topClean
    pop hl
    ld c, 104o              ; Verde BRIGHT sobre negro
    jp showBigMessage

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
    call showPressKey
.waitNotConn
    halt
    call Keyboard.inKey
    and a
    jr z, .waitNotConn
    call renderList
    jp uiLoop

.showMenu
    ld hl, .msg_diag_title
    call diagHeader
    ; Opciones (sin números)
    gotoXY 0, 6
    ld hl, .msg_diag_opt1
    call Display.putStr
    gotoXY 0, 7
    ld hl, .msg_diag_opt2
    call Display.putStr
    gotoXY 0, 8
    ld hl, .msg_diag_opt3
    call Display.putStr
    gotoXY 0, 9
    ld hl, .msg_diag_opt4
    call Display.putStr
    gotoXY 0, 10
    ld hl, .msg_diag_opt5
    call Display.putStr
    gotoXY 0, 11
    ld hl, .msg_diag_opt6
    call Display.putStr
    gotoXY 0, 12
    ld hl, .msg_diag_opt7
    call Display.putStr
    ; Línea separadora debajo de los items
    ld a, 13 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline
    gotoXY 0, 14
    ld hl, .msg_diag_exit
    call Display.putStr
    ; Cursor inicial
    xor a : ld (.diag_cursor), a
    call .showDiagCursor

.diagLoop
    ld b, 3
.diagWait
    halt : djnz .diagWait
    call Keyboard.checkBreak : jr z, .exitDiag
    call Keyboard.inKeyNoWait
    and a : jr z, .diagLoop
    cp Keyboard.KEY_UP : jr z, .diagUp
    cp 'q' : jr z, .diagUp
    cp 'Q' : jr z, .diagUp
    cp Keyboard.KEY_DN : jr z, .diagDown
    cp 'a' : jr z, .diagDown
    cp 'A' : jr z, .diagDown
    cp 13 : jr z, .diagSelect
    jr .diagLoop

.diagUp
    ld a, (.diag_cursor)
    and a : jr z, .diagLoop
    call .hideDiagCursor
    ld hl, .diag_cursor
    dec (hl)
    call .showDiagCursor
    jr .diagLoop

.diagDown
    ld a, (.diag_cursor)
    cp DIAG_ITEMS - 1 : jr z, .diagLoop
    call .hideDiagCursor
    ld hl, .diag_cursor
    inc (hl)
    call .showDiagCursor
    jr .diagLoop

.diagSelect
    ld a, (.diag_cursor)
    and a : jp z, doPing
    cp 1 : jp z, doModuleInfo
    cp 2 : jp z, doNetworkInfo
    cp 3 : jp z, doBaudRate
    cp 4 : jp z, doStaticIP
    cp 5 : jp z, doHostname
    cp 6 : jp z, doConfigSummary
    jr .diagLoop

.showDiagCursor:
    ld c, Display.ATTR_HIGHLIGHT
    jr .diagCursorAttr
.hideDiagCursor:
    ld c, Display.ATTR_NORMAL
.diagCursorAttr:
    ld a, (.diag_cursor)
    add a, DIAG_FIRST_LINE
    jp Display.setAttrPartial

.exitDiag
    ; Reactivar log UART al salir
    ld a, 1
    ld (Uart.log_enabled), a
    call renderList
    jp uiLoop

.diag_cursor    db 0
.msg_not_conn   db "Connect to a network first!", 0
.msg_diag_title db "DIAGNOSTICS", 0
.msg_diag_opt1  db "Ping test", 0
.msg_diag_opt2  db "Module info (firmware)", 0
.msg_diag_opt3  db "Network info", 0
.msg_diag_opt4  db "UART baud rate", 0
.msg_diag_opt5  db "Static IP config", 0
.msg_diag_opt6  db "Set hostname", 0
.msg_diag_opt7  db "Config summary", 0
.msg_diag_exit  db "Q/A:Move ENTER:Select BREAK:Exit", 0

; Buffer para respuestas de diagnóstico
    RTVAR diag_buffer, 64
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
    ld l, 0
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
    RTVAR ping_ip_buffer, MAX_IP_LEN + 1
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
    
    ld hl, .msg_ping_title
    call diagHeader

    gotoXY 0, 6
    ld hl, .msg_ip_prompt
    call Display.putStr
    setLineColor 8, Display.ATTR_PASS_INPUT
    setLineColor 9, Display.ATTR_PASS_INPUT

    gotoXY 0, 11
    ld hl, .msg_ping_help
    call Display.putStr

.drawIP
    ; Dibujar IP actual directamente en doble alto
    halt
    di
    gotoXY 0, 8
    ld hl, ping_ip_buffer
    call Display.putStrBig

    ; Borrar resto de línea (MAX_IP_LEN - len espacios)
    ld a, MAX_IP_LEN
    ld hl, ping_ip_len
    sub (hl)
    jr z, .noSpaces
    inc a
    ld b, a
.clearSpaces
    push bc
    ld a, ' ' : call Display.putCBig
    pop bc
    djnz .clearSpaces
.noSpaces

    ; Mostrar cursor
    ld a, (ping_ip_len)
    ld l, a
    ld h, 8
    ld (Display.coords), hl
    ld a, '_'
    call Display.putCBig
    ei

.waitIPKey
    ld b, 4
.waitIPLoop
    halt
    djnz .waitIPLoop

    call Keyboard.checkBreak : jp z, .pingCancel
    call Keyboard.inKeyNoWait
    and a
    jr z, .waitIPKey

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
    gotoXY 0, 3
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
    ld a, (diag_line) : ld h, a : ld l, 0 : ld (Display.coords), hl
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
    ld a, (diag_line) : ld h, a : ld l, 0 : ld (Display.coords), hl
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
    call showPressKey
.waitPingKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitPingKey
    jp showDiagnostics

.msg_ping_title  db "PING TEST", 0
.msg_ip_prompt   db "Enter IP address:", 0
.msg_ping_help   db "ENTER=ping, BREAK=cancel", 0
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

    ld hl, .msg_module_title
    call diagHeader

    ; Inicializar línea de salida
    ld a, 6
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
    call showPressKey
.waitGmrKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitGmrKey
    jp showDiagnostics

.msg_module_title db "MODULE INFO", 0
.cmd_gmr          db "AT+GMR", 13, 10, 0

; ------------------------------
; Network info
; ------------------------------
doNetworkInfo:
    xor a
    ld (Uart.log_enabled), a
    call topClean

    ; Mostrar detalle de la red conectada
    call connectedSSIDPresentInList
    jr nc, .ni_no_idx
    ld (selected_real_idx), a       ; Índice para ECN/Channel/Signal
    ld hl, Wifi.connected_ssid
    ld (selected_ssid_ptr), hl
    call showNetDetail
    jr .ni_detail_done
.ni_no_idx
    ; SSID no en la lista: mostrar solo nombre, sin Security/Channel/Signal falsos
    gotoXY 0, 4
    ld hl, .ni_ssid_lbl : call Display.putStr
    ld hl, Wifi.connected_ssid : call Display.putStr
.ni_detail_done
    ld a, 10 : ld e, 3 : ld d, Display.ATTR_NORMAL
    call Display.draw_hline
    ld a, 11
    ld (diag_line), a

    call flushUartBuffer
    ld hl, .cmd_cifsr
    call Wifi.espSendZ
    ld c, 20
    ld b, 100
.cifsrLoop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cifsrTimeout
    dec b
    jr z, .cifsrDone
    ld a, (diag_buffer)
    and a
    jr z, .cifsrLoop
    cp 'O' : jr z, .cifsrDone
    cp 'A' : jr z, .cifsrLoop
    cp '0' : jr z, .cifsrLoop
    cp '1' : jr z, .cifsrLoop
    cp 'C' : jr z, .cifsrLoop
    cp 'L' : jr z, .cifsrLoop
    cp 'S' : jr z, .cifsrLoop
    cp '+' : jr nz, .cifsrLoop
    ld a, (diag_buffer + 1)
    cp 'C' : jr nz, .cifsrLoop
    ld a, (diag_buffer + 10)
    cp 'I' : jr z, .isIP
    cp 'M' : jr z, .isMAC
    jr .cifsrLoop

.isIP
    ld hl, .lbl_ip
    jr .printFmt
.isMAC
    ld hl, .lbl_mac
.printFmt
    ld a, (diag_line) : ld d, a : ld e, 0
    ld (Display.coords), de
    call Display.putStr
    ld hl, diag_buffer
    call .findQuote
    call .printUntilQuote
    ld a, (diag_line) : inc a : ld (diag_line), a
    jr .cifsrLoop

.cifsrTimeout
    dec c
    jr nz, .cifsrLoop

.cifsrDone
    call showPressKey
.waitCifsrKey
    halt
    call Keyboard.inKey
    and a
    jr z, .waitCifsrKey
    jp showDiagnostics

.findQuote
    ld a, (hl)
    cp '"' : jr z, .foundQ
    inc hl
    and a : ret z
    jr .findQuote
.foundQ
    inc hl : ret

.printUntilQuote
    ld a, (hl)
    and a : ret z
    cp '"' : ret z
    push hl : call Display.putC : pop hl
    inc hl
    jr .printUntilQuote

.cmd_cifsr     db "AT+CIFSR", 13, 10, 0
.lbl_ip        db "IP:  ", 0
.lbl_mac       db "MAC: ", 0
.ni_ssid_lbl   db "Connected: ", 0

; ------------------------------
; UART Baud rate
; ------------------------------
doBaudRate:
    ld hl, msg_baud_title
    call diagHeader

    ; Inicializar línea de salida
    ld a, 6
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
	gotoXY 0, 6
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
    
    ld a, (diag_line) : ld h, a : ld l, 0 : ld (Display.coords), hl
    
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
    gotoXY 0, 6
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
    call showPressKey
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

msg_baud_title db "UART BAUD RATE", 0
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

; ============================================
; doStaticIP - Static IP configuration (option 5)
; ============================================
doStaticIP:
    ld hl, .sip_title
    call diagHeader
    gotoXY 0, 6
    ld hl, .sip_prompt : call Display.putStr
    setLineColor 8, Display.ATTR_PASS_INPUT
    setLineColor 9, Display.ATTR_PASS_INPUT
    gotoXY 0, 11
    ld hl, .sip_help : call Display.putStr

    ; Entrada de IP (solo dígitos y puntos)
    ld hl, sip_buf
    ld b, 15                    ; Max IP length (xxx.xxx.xxx.xxx)
    ld a, 8 : ld (sti_line), a
    xor a : ld (sti_len), a
    ld (sip_buf), a
    call ipTextInput
    jp c, showDiagnostics       ; Cancelado

    ; Verificar que hay algo
    ld a, (sti_len) : and a : jp z, showDiagnostics

    ; Validar formato IP
    call validateIP
    jr nc, .sip_valid
    gotoXY 0, 9
    ld hl, .sip_badformat : call Display.putStr
    call waitAnyKey
    jp showDiagnostics

.sip_valid
    ; Enviar AT+CIPSTA_CUR="ip"
    call flushUartBuffer
    ld hl, .sip_cmd : call Wifi.espSendZ
    ld hl, sip_buf : call Wifi.espSendZ
    ld hl, .sip_end : call Wifi.espSendZ
    call Wifi.checkOkErr
    jr c, .sip_fail
    ; Actualizar IP en pantalla
    call Wifi.getIP
    call ipShowConnected
    gotoXY 0, 9
    ld hl, .sip_ok : call Display.putStr
    jr .sip_wait
.sip_fail
    gotoXY 0, 9
    ld hl, .sip_err : call Display.putStr
.sip_wait
    call waitAnyKey
    jp showDiagnostics

.sip_title     db "STATIC IP CONFIG", 0
.sip_prompt    db "Enter IP (empty=cancel):", 0
.sip_help      db "ENTER=accept, BREAK=cancel", 0
.sip_ok        db "IP set OK!", 0
.sip_err       db "Failed to set IP", 0
.sip_badformat db "Invalid IP format!", 0
.sip_cmd       db "AT+CIPSTA_CUR=\"", 0
.sip_end       db "\"", 13, 10, 0
    RTVAR sip_buf, 16

; ============================================
; ipTextInput - Entrada de texto para IPs (solo dígitos y puntos)
; HL = buffer, B = max_len, A = línea pantalla
; Usa: (sti_len) para longitud actual
; Retorna: CF=0 si ENTER, CF=1 si CANCEL
; ============================================
ipTextInput:
    ld (sti_buf), hl
    ld a, b : ld (sti_max), a
.itiRedraw
    halt
    di
    ld a, (sti_line)
    ld h, a : ld l, 0 : ld (Display.coords), hl
    ld hl, (sti_buf)
    call Display.putStrBig
    ld a, '_' : call Display.putCBig
    ld a, ' ' : call Display.putCBig
    ld a, ' ' : call Display.putCBig
    ei
.itiWait
    ld b, 4
.itiWL  halt : djnz .itiWL
    call Keyboard.checkBreak : jr z, .itiCancel
    call Keyboard.inKeyNoWait : and a : jr z, .itiWait
    cp 13 : jr z, .itiEnter
    cp Keyboard.KEY_BS : jr z, .itiBS
    ; Only accept '0'-'9' and '.'
    cp '.' : jr z, .itiAccept
    cp '0' : jr c, .itiWait
    cp '9'+1 : jr nc, .itiWait
.itiAccept
    ld c, a
    ld a, (sti_len) : ld b, a : ld a, (sti_max) : cp b : jr z, .itiWait
    ld a, (sti_len) : ld hl, (sti_buf) : ld d, 0 : ld e, a : add hl, de
    ld (hl), c : inc hl : ld (hl), 0
    ld a, (sti_len) : inc a : ld (sti_len), a
    jr .itiRedraw
.itiBS  ld a, (sti_len) : and a : jr z, .itiWait
    dec a : ld (sti_len), a
    ld hl, (sti_buf) : ld d, 0 : ld e, a : add hl, de : ld (hl), 0
    jp .itiRedraw
.itiEnter or a : ret
.itiCancel scf : ret

; ============================================
; validateIP - Validates IP address in sip_buf
; Checks: exactly 3 dots, no leading/trailing/consecutive dots,
;         each octet 0-255, no empty octets
; Returns: CF=0 valid, CF=1 invalid
; ============================================
validateIP:
    ld hl, sip_buf
    ld c, 0                     ; Dot count
    ld d, 0                     ; Current octet value
    ld e, 0                     ; Digits in current octet

.vip_loop
    ld a, (hl)
    and a : jr z, .vip_end      ; End of string
    cp '.'
    jr z, .vip_dot
    ; Digit: accumulate octet value
    sub '0'
    ld b, a                     ; B = new digit
    ; D = D * 10 + B
    ld a, d
    add a, a                    ; *2
    jr c, .vip_bad
    add a, a                    ; *4
    jr c, .vip_bad
    add a, d                    ; *5
    jr c, .vip_bad
    add a, a                    ; *10
    jr c, .vip_bad
    add a, b                    ; + digit
    jr c, .vip_bad              ; >255
    ld d, a
    inc e                       ; One more digit
    ld a, e : cp 4 : jr nc, .vip_bad  ; Max 3 digits per octet
    inc hl
    jr .vip_loop

.vip_dot
    ; Check no empty octet (no digits before dot)
    ld a, e : and a : jr z, .vip_bad
    inc c                       ; Count dot
    ld a, c : cp 4 : jr nc, .vip_bad  ; Too many dots
    ld d, 0 : ld e, 0          ; Reset octet
    inc hl
    jr .vip_loop

.vip_end
    ; Must have digits in last octet
    ld a, e : and a : jr z, .vip_bad
    ; Must have exactly 3 dots
    ld a, c : cp 3 : jr nz, .vip_bad
    or a : ret                  ; CF=0, valid

.vip_bad
    scf : ret                   ; CF=1, invalid

; ============================================
; doHostname - Set hostname (option 6)
; ============================================
doHostname:
    ld hl, .hn_title
    call diagHeader
    gotoXY 0, 6
    ld hl, .hn_prompt : call Display.putStr
    setLineColor 8, Display.ATTR_PASS_INPUT
    setLineColor 9, Display.ATTR_PASS_INPUT
    gotoXY 0, 11
    ld hl, .hn_help : call Display.putStr

    call clearPassBuffer
    ld a, 1 : ld (show_password), a     ; Mostrar texto (no asteriscos)
    ld a, 8 : ld (pass_line), a
    call passwordInput
    ld a, PASS_LINE_DEFAULT : ld (pass_line), a
    jp c, showDiagnostics

    ld a, (pass_len) : and a : jp z, showDiagnostics

    ; Copiar pass_buffer a hn_buf
    ld hl, pass_buffer
    ld de, hn_buf
    ld a, (pass_len) : ld b, a
.hn_copy
    ld a, (hl) : ld (de), a
    inc hl : inc de
    djnz .hn_copy
    xor a : ld (de), a                 ; Null-terminate

    call flushUartBuffer
    ld hl, .hn_cmd : call Wifi.espSendZ
    ld hl, hn_buf : call Wifi.espSendZ
    ld hl, .hn_end : call Wifi.espSendZ
    call Wifi.checkOkErr
    jr c, .hn_fail
    gotoXY 0, 10
    ld hl, .hn_ok : call Display.putStr
    jr .hn_wait
.hn_fail
    gotoXY 0, 10
    ld hl, .hn_err : call Display.putStr
.hn_wait
    call waitAnyKey
    jp showDiagnostics

.hn_title   db "SET HOSTNAME", 0
.hn_prompt  db "Enter hostname:", 0
.hn_help    db "ENTER=accept, BREAK=cancel", 0
.hn_ok      db "Hostname set OK!", 0
.hn_err     db "Failed to set hostname", 0
.hn_cmd     db "AT+CWHOSTNAME=\"", 0
.hn_end     db "\"", 13, 10, 0
    RTVAR hn_buf, 21

; ============================================
; doConfigSummary - Show all config (option 7)
; ============================================
doConfigSummary:
    ld hl, .cs_title
    call diagHeader

    ; SSID conectado
    gotoXY 0, 6
    ld hl, .cs_ssid : call Display.putStr
    ld a, (Wifi.is_connected) : and a : jr z, .cs_no_ssid
    ld hl, Wifi.connected_ssid : call Display.putStr
    jr .cs_ip
.cs_no_ssid
    ld hl, .cs_none : call Display.putStr

.cs_ip
    ; IP - usar readDiagLine para consumir respuesta AT+CIFSR completa
    gotoXY 0, 7
    ld hl, .cs_ip_lbl : call Display.putStr
    call .cs_flush
    ld hl, .cs_ip_cmd : call Wifi.espSendZ
    ld b, 8
.cs_ip_loop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cs_ip_done
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_ip_done
    cp '+' : jr nz, .cs_ip_next
    ; Buscar STAIP (no STAMAC): buscar "," seguido de '"' y un dígito
    ld hl, diag_buffer
    call .cs_find_colon
    jr nc, .cs_ip_next
    inc hl                          ; skip ':'
    ; Buscar primera '"'
.cs_ip_fq
    ld a, (hl) : and a : jr z, .cs_ip_next
    cp '"' : jr z, .cs_ip_gq
    inc hl : jr .cs_ip_fq
.cs_ip_gq
    inc hl
    ; Comprobar si el contenido tiene '.' (IP) o ':' (MAC)
    push hl
.cs_ip_chk
    ld a, (hl) : and a : jr z, .cs_ip_notip
    cp '"' : jr z, .cs_ip_notip
    cp '.' : jr z, .cs_ip_isip
    inc hl : jr .cs_ip_chk
.cs_ip_isip
    pop hl
    call .cs_printClean
    jr .cs_ip_next
.cs_ip_notip
    pop hl
.cs_ip_next
    djnz .cs_ip_loop
.cs_ip_done

.cs_mac
    ; MAC - enviar AT+CIPSTAMAC?
    gotoXY 0, 8
    ld hl, .cs_mac_lbl : call Display.putStr
    call .cs_flush
    ld hl, .cs_mac_cmd : call Wifi.espSendZ
    ld b, 8
.cs_mac_loop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cs_mac_done
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_mac_done
    cp '+' : jr nz, .cs_mac_next
    ; Buscar línea con ':' (la MAC tiene ':')
    ld hl, diag_buffer
    call .cs_find_colon
    jr nc, .cs_mac_next
    ; Encontrado, buscar el contenido después del ':'
    inc hl
    ; Si el primer char es '"', saltar
    ld a, (hl) : cp '"' : jr nz, .cs_mac_pr
    inc hl
.cs_mac_pr
    call .cs_printClean
.cs_mac_next
    djnz .cs_mac_loop
.cs_mac_done

    ; Hostname - AT+CWHOSTNAME?
    gotoXY 0, 9
    ld hl, .cs_hn_lbl : call Display.putStr
    call .cs_flush
    ld hl, .cs_hn_cmd : call Wifi.espSendZ
    ld b, 6
.cs_hn_loop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cs_hn_done
    ld a, (diag_buffer) : cp '+' : jr nz, .cs_hn_skip
    ld hl, diag_buffer
    call .cs_find_colon
    jr nc, .cs_hn_skip
    inc hl
    ld a, (hl) : cp '"' : jr nz, .cs_hn_pr
    inc hl
.cs_hn_pr
    call .cs_printClean
    jr .cs_hn_done
.cs_hn_skip
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_hn_done
    djnz .cs_hn_loop
.cs_hn_done

    ; Firmware
    gotoXY 0, 10
    ld hl, .cs_fw_lbl : call Display.putStr
    call .cs_flush
    ld hl, .cs_fw_cmd : call Wifi.espSendZ
    ld b, 10
.cs_fw_loop
    push bc
    call readDiagLine
    pop bc
    jr nc, .cs_fw_done
    ld a, (diag_buffer) : cp 'O' : jr z, .cs_fw_done
    cp 'E' : jr z, .cs_fw_done
    ; Filtrar eco "AT+GMR": comprobar si 4º carácter es 'G'
    ld a, (diag_buffer + 3) : cp 'G' : jr z, .cs_fw_next
    ; Saltar prefijo "AT version:" si existe
    ld hl, diag_buffer
    ld a, (hl) : cp 'A' : jr nz, .cs_fw_print
    ld a, (diag_buffer + 2) : cp ' ' : jr nz, .cs_fw_print
    ; Avanzar HL pasando "AT version:"
    ld de, 11 : add hl, de
.cs_fw_print
    ld b, 30 : call putStrLimited
    jr .cs_fw_done
.cs_fw_next
    djnz .cs_fw_loop
.cs_fw_done

    ; Version del programa
    gotoXY 0, 11
    ld hl, .cs_ver_lbl : call Display.putStr
    ld hl, version_string : call Display.putStr

    call showPressKey
    call waitAnyKey
    jp showDiagnostics

; Espera y flush - asegura que la respuesta AT anterior se ha consumido
.cs_flush
    ld b, 10
.cs_flush_w
    halt
    djnz .cs_flush_w
    jp flushUartBuffer

; Helper: busca ':' en string HL. CF=1 si encontrado (HL apunta al ':')
.cs_find_colon
    ld a, (hl) : and a : ret z  ; CF=0
    cp ':' : jr z, .cs_fc_found
    inc hl : jr .cs_find_colon
.cs_fc_found
    scf : ret

; Helper: imprime string hasta 0, '"', CR o LF
.cs_printClean
    ld a, (hl) : and a : ret z
    cp '"' : ret z
    cp 13 : ret z
    cp 10 : ret z
    push hl : call Display.putC : pop hl
    inc hl : jr .cs_printClean

.cs_title   db "CONFIG SUMMARY", 0
.cs_ssid    db "SSID: ", 0
.cs_ip_lbl  db "IP:   ", 0
.cs_mac_lbl db "MAC:  ", 0
.cs_hn_lbl  db "Host: ", 0
.cs_fw_lbl  db "FW:   ", 0
.cs_ver_lbl db "App:  NetManZX v", 0
.cs_none    db "(none)", 0
.cs_ip_cmd  db "AT+CIFSR", 13, 10, 0
.cs_mac_cmd db "AT+CIPSTAMAC?", 13, 10, 0
.cs_hn_cmd  db "AT+CWHOSTNAME?", 13, 10, 0
.cs_fw_cmd  db "AT+GMR", 13, 10, 0

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
    RTVAR async_buffer, ASYNC_BUF_SIZE
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
    ld a, 17
    call clearRowPixels
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
    ; 1 space + 1 "(" + page_curr + 1 "/" + page_total + 7 " pages)" = 11 + digits
    ld a, c
    add a, 11
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
    
    ; --- 4. Limpiar línea 17 completa ---
    push bc
    ld a, 17
    call clearRowPixels
    pop bc

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

    ld a, ' ' : call Display.putC
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
; About screen (I key)
; ============================================
showAbout:
    ld hl, .msg_about_title
    call diagHeader

    gotoXY 0, 6
    ld hl, .msg_about_ver
    call Display.putStr
    gotoXY 0, 7
    ld hl, .msg_about_build
    call Display.putStr
    gotoXY 0, 9
    ld hl, .msg_about_desc
    call Display.putStr
    gotoXY 0, 10
    ld hl, .msg_about_author
    call Display.putStr
    gotoXY 0, 11
    ld hl, .msg_about_github
    call Display.putStr
    gotoXY 0, 12
    ld hl, .msg_about_license
    call Display.putStr
    call showPressKey

.aboutWait
    halt
    call Keyboard.inKey
    and a
    jr z, .aboutWait
    call renderList
    jp uiLoop

.msg_about_title db "ABOUT NETMANZX", 0
.msg_about_ver:
    IFDEF UNO
        db "Version ", VERSION_STRING, " (ZX-Uno)", 0
    ELSE
        IFDEF NEXT
            db "Version ", VERSION_STRING, " (Next)", 0
        ELSE
            db "Version ", VERSION_STRING, " (AY)", 0
        ENDIF
    ENDIF
.msg_about_build db "Build: ", BUILD_DATE, 0
.msg_about_desc  db "WiFi manager for ZX Spectrum", 0
.msg_about_author db "By Ignacio Monge Garcia", 0
.msg_about_github db "github.com/IgnacioMonge/NetManZX", 0
.msg_about_license db "License: MIT", 0

; ============================================
; Mensajes y datos
; ============================================
msg_connected_title db "Connected!", 0
msg_done_body       db "Now you can use network apps!", 0
msg_fail_generic  db "Connection failed!", 13, 13, "Unknown error.", 0
msg_fail_timeout  db "Connection timeout!", 13, 13, "Router not responding.", 0
msg_fail_password db "Wrong password!", 13, 13, "Check password and try again.", 0
msg_fail_notfound db "Network not found!", 13, 13, "AP may be out of range.", 0
msg_fail_connfail db "Connection failed!", 13, 13, "Try again or check router.", 0
msg_press_key   db "Press any key to continue...", 0
msg_conn_attempt db "Connecting (x/3)...", 0
msg_retry_suffix db " Retry", 0
msg_break_cancel db "Press BREAK to cancel", 0
msg_open_net    db "Open network (no password needed)", 0
at_start        db 'AT+CWJAP="',0
at_start_old    db 'AT+CWJAP_DEF="',0
at_middle       db '","', 0
msg_ssid        db "Selected SSID:", 0
msg_pass        db "Password (BREAK=cancel, UP=show):", 0

    RTVAR pass_buffer, MAX_PASS_LEN + 2
pass_len        db 0
pass_cursor     db 0                ; Posición del cursor en el password
cursor_position db 0
offset          db 0
is_open_network db 0
show_password   db 0                ; Flag para mostrar contraseña
selected_ssid_ptr dw 0              ; Puntero al SSID seleccionado
selected_real_idx db 0              ; Índice real de la red seleccionada
ui_async_div    db 0                ; Divisor para checkAsyncWifi
autoscan_counter dw 0              ; Contador para auto-rescan (15000 = 5 min)
health_counter  dw 0              ; Contador para health-check periódico (solo invalidar)
force_rescan   db 0              ; 1 => rescan pending after disconnect

msg_head
    db "NetManZX "
    db VERSION_STRING
    db " - Network manager", 0

msg_wifi_label
    db "WiFi:", 0

    endmodule