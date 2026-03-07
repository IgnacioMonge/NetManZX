    module Display
scr_addr = #4000

; ============================================
; Constantes de atributos de color
; Formato: FBPPPIII (Flash, Bright, Paper, Ink)
; ============================================
ATTR_NORMAL      = 107o   ; Blanco sobre negro (lista)
ATTR_HIGHLIGHT   = 160o   ; Negro sobre blanco brillante (cursor)
ATTR_CONNECTED   = 106o   ; Amarillo brillante sobre negro (red conectada)
ATTR_CONN_CURSOR = 061o   ; Azul sobre amarillo (cursor en red conectada)
ATTR_STATUSBAR   = 170o   ; Negro sobre blanco brillante (barra estado)
ATTR_LOG         = 014o   ; Verde sobre azul (ventana log)
ATTR_HEADER      = 117o   ; Blanco brillante sobre azul (cabecera)
ATTR_TITLE       = 116o   ; Amarillo brillante sobre azul (título)
ATTR_RSSI        = 004o   ; Verde sobre negro (barras señal)
ATTR_SSID_INPUT  = 044o   ; Verde sobre negro (SSID seleccionado)
ATTR_PASS_LINE   = 071o   ; Blanco sobre azul
ATTR_PASS_INPUT  = 171o   ; Blanco brillante sobre azul

; a - line number
; c - color
; Pinta toda la línea (32 columnas)
setAttr:
	rrca
	rrca
	rrca
	ld	l,a
	and	31
	or	#58
	ld	h,a
	ld	a,l
	and	252
	ld	l,a

    ld de, hl
    inc de
    ld a, c : ld (hl), a
    ld bc, #1f
    ldir
    ret

; a - line number
; c - color
; Pinta solo las primeras 22 celdas
setAttrPartial:
	rrca
	rrca
	rrca
	ld	l,a
	and	31
	or	#58
	ld	h,a
	ld	a,l
	and	252
	ld	l,a

    ld b, 22
    ld a, c
.loop
    ld (hl), a
    inc hl
    djnz .loop
    ret

putStr:
    ld a, (hl) : and a : ret z
    push hl
    call putC
    pop hl
    inc hl
    jr putStr

putStrLog:
    ld a, (hl) : and a : ret z
    push hl
    call putLogC
    pop hl
    inc hl
    jr putStrLog

putC:
    cp 13 : jr z, .cr
    ld hl, (coords) : ld (drawC.coords), hl
    call drawC
    ld hl, coords
    inc (hl)
    ld a,(hl) : cp 42 : jr nc, .cr
    ret
.cr
    ld hl, coords
    xor a : ld (hl), a
    inc hl : inc (hl)
    ret

; ============================================
; putLogC - Escribe en la ventana de log (Líneas 19-23)
; ============================================
putLogC:
    cp 13 : jr z, .cr
    cp ' ' : ret c
    ld c,a
    
    ; Escribir siempre en línea 23
    ld h, 23
    ld a, (.coord)
    ld l, a
    ld (drawC.coords), hl
    
    ld a,c
    call drawC
    
    ; Avanzar cursor X
    ld hl, .coord : inc (hl) : ld a,(hl)
    cp 42 : ret c

.cr
    xor a : ld (.coord), a
    ; Caer en .scrollLog

.scrollLog
    ; --- SCROLL LOG: Líneas 19-23 (5 líneas) ---
    ; Método: Para cada scanline, copiar líneas 20-23 a 19-22 y limpiar línea 23
    ; Tercio 2: línea 19=#5060, línea 20=#5080, línea 23=#50E0
    
    di
    
    ld b, 8             ; 8 scanlines por fila de texto
    ld hl, #5080        ; Origen: Línea 20, scanline 0
    ld de, #5060        ; Destino: Línea 19, scanline 0

.scrollLoop
    push bc
    push hl
    push de
    
    ; Copiar 4 líneas de texto (128 bytes): líneas 20-23 → 19-22
    ld bc, 128
    ldir
    ; Ahora DE apunta a #5060+128=#50E0 (línea 23) - exactamente donde limpiar
    
    ; Limpiar línea 23 (32 bytes)
    ; DE ya apunta al inicio de línea 23 en este scanline
    ex de, hl           ; HL = dirección a limpiar
    ld b, 32
    xor a
.clrLine
    ld (hl), a
    inc hl
    djnz .clrLine
    
    pop de
    pop hl
    pop bc
    
    ; Avanzar al siguiente scanline (+256 bytes)
    inc h
    inc d
    djnz .scrollLoop
    
    ei
    ret
.coord db 0


drawC:
    ld (.char_tmp),a
    ld hl, 0
.coords = $ - 2
    ld b, l
    call calc
    ld d, h
    ld e, l
    ld (.rot_tmp), a
    call findAddr

;; Get char
    ld a, 0
.char_tmp = $ - 1
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld bc, font
    add hl, bc
    push hl, de
;; Mask rotation
    ld a, (.rot_tmp)
    ld hl, #03ff
    and a : jr z, .drawIt
.rot_loop
    ex af, af
    ld a,l
    rrca
    rr h
    rr l
    ex af, af
    dec a
    jr nz, .rot_loop
.drawIt    
    ld a, l
    ld (.mask1), a
    ld a, h
    ld (.mask2), a
    pop ix, de 
;; Basic draw
    ld a, 0
.rot_tmp = $ - 1
    ld (.rot_cnt), a
    ld b, 8
.printIt
    ld a, (de)
    ld h,a
    ld l,0
    ld a,0
.rot_cnt = $ - 1
    and a : jr z, .skipRot
.rotation
    ex af, af
    ld a, l
    rrca
    rr h
    rr l
    ex af, af
    dec a
    jr nz, .rotation
.skipRot
    ld a, (ix + 1)
    and #0f
.mask1 = $ - 1
    or l
    ld (ix + 1), a
    ld a, (ix)
    and #fc
.mask2 = $ - 1
    or h
    ld (ix), a
    inc ixh
    inc de
    djnz .printIt
    ret

clrTop:
    ld hl, #4000
    ld de, #4001
    ld bc, #fff
    xor a 
    ld (hl),a
    ldir
    ret

; Limpia zona de lista (líneas 2-17)
; Usa el mismo método que el código original: para cada scanline, limpiar todas las líneas de golpe
clrListOnly:
    ; Tercio 0: líneas 2-7 (6 líneas)
    ld hl, #4040            ; Scanline 0, línea 2
    ld b, 8                 ; 8 scanlines
.loopT0
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 191              ; 192 bytes (6 líneas * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    ld bc, #100             ; Siguiente scanline (+256)
    add hl, bc
    pop bc
    djnz .loopT0
    
    ; Tercio 1: líneas 8-15 (8 líneas)
    ld hl, #4800            ; Scanline 0, línea 8
    ld b, 8
.loopT1
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 255              ; 256 bytes (8 líneas * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    ld bc, #100
    add hl, bc
    pop bc
    djnz .loopT1
    
    ; Tercio 2: líneas 16-17 (2 líneas)
    ld hl, #5000            ; Scanline 0, línea 16
    ld b, 8
.loopT2
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 63               ; 64 bytes (2 líneas * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    ld bc, #100
    add hl, bc
    pop bc
    djnz .loopT2
    ret

; Limpia solo el área de redes (líneas 6-14) - muy rápido con LDIR
clrNetworksOnly:
    ; Tercio 0: líneas 6-7 (2 líneas)
    ; Línea 6 empieza en $40C0 (scanline 0) 
    ld hl, #40C0
    ld b, 8                 ; 8 scanlines
.loopN0
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 63               ; 64 bytes (2 líneas * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    ld bc, #100
    add hl, bc
    pop bc
    djnz .loopN0
    
    ; Tercio 1: líneas 8-14 (7 líneas)
    ld hl, #4800
    ld b, 8
.loopN1
    push bc
    push hl
    ld d, h : ld e, l : inc de
    ld bc, 223              ; 224 bytes (7 líneas * 32)
    xor a : ld (hl), a
    ldir
    pop hl
    ld bc, #100
    add hl, bc
    pop bc
    djnz .loopN1

    ; Limpiar atributos del área de redes (líneas 6-14)
    ; Evita que queden colores residuales (p.ej. red conectada) tras un rescan.
    ld a, ATTR_NORMAL
    ld hl, #58C0             ; 0x5800 + (6 * 32)
    ld de, #58C1
    ld bc, 287               ; 9 líneas * 32 - 1
    ld (hl), a
    ldir
    ret

clrscr:
    xor a
    out (#fe), a

    ; 1. Limpiar píxeles
    ld hl, #4000
    ld de, #4001
    ld bc, #17ff
    ld (hl),a
    ldir

    ; 2. Colores líneas 0-17: Blanco sobre Negro (lista + info)
    ld a, ATTR_NORMAL
    ld hl, #5800
    ld de, #5801
    ld bc, 575              ; 18 líneas * 32 - 1 = 575
    ld (hl), a
    ldir
    
    ; 3. Colores línea 18: Status Bar (Negro sobre Blanco)
    ld a, ATTR_STATUSBAR
    ld hl, #5A40            ; Línea 18
    ld de, #5A41
    ld bc, 31
    ld (hl), a
    ldir

    ; 4. Colores líneas 19-23: Log (Verde sobre Azul)
    ld a, ATTR_LOG
    ld hl, #5A60            ; Línea 19
    ld de, #5A61
    ld bc, 159              ; 5 líneas * 32 - 1 = 159
    ld (hl), a
    ldir
    ret

findAddr:
    LD A,D
    AND 7
    RRCA
    RRCA
    RRCA
    OR E
    LD E,A
    LD A,D
    AND 24
    OR #40
    LD D,A
    ret

; ============================================
; calc - Calcula offset X en pixels
; in:   b - x column (0-41)
; out:  l - byte column (0-31)
;       a - pixel offset (0-7)
; ============================================
calc:
    ld a, b
    and a
    jr z, .zero
    
    ; A = B * 6
    add a, a        ; A = B * 2
    ld c, a         ; Guardar
    add a, a        ; A = B * 4
    add a, c        ; A = B * 6
    
    ; L = A / 8, A = A % 8
    ld c, a
    and 7           ; A % 8
    ld l, c
    srl l
    srl l
    srl l           ; L = Total / 8
    ret

.zero
    xor a
    ld l, a
    ret

coords dw 0
font incbin "../../assets/font.bin"

; ============================================
; compareStringZ - Compara dos strings Z-terminated
; Entrada: HL, DE = punteros a strings
; Salida:  Z=1 si iguales, Z=0 si diferentes
; Preserva: HL, DE, BC
; ============================================
compareStringZ:
    push hl
    push de
    push bc
.loop
    ld a, (de)
    ld c, a
    ld a, (hl)
    cp c
    jr nz, .different       ; Diferentes -> Z=0
    and a
    jr z, .equal            ; Ambos 0 -> iguales, Z=1
    inc hl
    inc de
    jr .loop
.equal
    pop bc
    pop de
    pop hl
    xor a                   ; Z=1
    ret
.different
    pop bc
    pop de
    pop hl
    or 1                    ; Z=0 (A nunca será 0)
    ret

; ============================================
; draw_hline - Línea horizontal de 1 pixel a lo ancho de pantalla
; Entrada: A = fila (0-23), E = scanline (0-7), D = atributo
; Destruye: AF, BC, DE, HL
; ============================================
draw_hline:
    push de
    call draw_hline_only
    pop de
    ; Atributos
    ld a, c
    ld l, 0
    srl a : rr l
    srl a : rr l
    srl a : rr l
    or #58
    ld h, a
    ld a, d
    ld b, 32
.attr
    ld (hl), a
    inc l
    djnz .attr
    ret

; draw_hline_only - Solo píxeles, sin tocar atributos
; Entrada: A = fila (0-23), E = scanline (0-7)
; Destruye: AF, BC, HL. Preserva C = fila
draw_hline_only:
    ld c, a
    and #18
    ld h, a
    ld a, c
    and #07
    rrca
    rrca
    rrca
    ld l, a
    ld a, h
    or #40
    add a, e
    ld h, a
    ld a, #FF
    ld b, 32
.fill
    ld (hl), a
    inc l
    djnz .fill
    ret

    endmodule

    macro setLineColor line, color
    ld a, line, c, color
    call Display.setAttr
    endm

    macro gotoXY x, y
    ld hl, x or (y<<8)
    ld (Display.coords), hl
    endm

    macro printMsg ptr
    ld hl, ptr : call Display.putStr
    endm
