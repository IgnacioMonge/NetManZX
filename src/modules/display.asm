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
ATTR_BANNER_TOP  = 01000111b  ; Blanco sobre negro, BRIGHT (row 0 banner)
ATTR_BANNER_BOT  = 00000111b  ; Blanco sobre negro, sin BRIGHT (row 1 banner)
ATTR_RSSI        = 004o   ; Verde sobre negro (barras señal)
ATTR_SSID_INPUT  = 104o   ; Verde brillante sobre negro (SSID seleccionado)
ATTR_PASS_LINE   = 071o   ; Blanco sobre azul
ATTR_PASS_INPUT  = 171o   ; Blanco brillante sobre azul
ATTR_STATUS_BOT  = 00111000b  ; Negro ink, blanco paper, sin BRIGHT (doble alto bot)

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

putStrBig:
    ld a, (hl) : and a : ret z
    push hl
    call putCBig
    pop hl
    inc hl
    jr putStrBig

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

putCBig:
    cp 13 : jr z, .cr
    ld hl, (coords) : ld (drawCBig.coords), hl
    call drawCBig
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
; putLogC - Escribe en la ventana de log (Líneas 20-23)
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
    ; --- SCROLL LOG: Líneas 20-23 (4 líneas) ---
    ; Método: Para cada scanline, copiar líneas 21-23 a 20-22 y limpiar línea 23
    ; Tercio 2: línea 20=#5080, línea 21=#50A0, línea 23=#50E0

    di

    ld b, 8             ; 8 scanlines por fila de texto
    ld hl, #50A0        ; Origen: Línea 21, scanline 0
    ld de, #5080        ; Destino: Línea 20, scanline 0

.scrollLoop
    push bc
    push hl
    push de
    
    ; Copiar 3 líneas de texto (96 bytes): líneas 21-23 → 20-22
    ld bc, 96
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
    call decompressChar     ; A = char, devuelve DE = glyph_buf
    push de                 ; guardar ptr datos fuente
    ld hl, 0
.coords = $ - 2
    ld b, l
    call calc
    ld d, h
    ld e, l
    ld (.rot_tmp), a
    call findAddr
    push de                 ; guardar dir pantalla
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

; Variables SMC para drawCBig (nivel de módulo, fuera del flujo)
dcb_rot     db 0
dcb_rc_top  db 0
dcb_m1      db 0
dcb_m2      db 0

drawCBig:
    call decompressChar
    push de
    ld hl, 0
.coords = $ - 2
    ld b, l
    call calc
    ld d, h
    ld e, l
    ld (dcb_rot), a
    call findAddr
    push de
    ld a, (dcb_rot)
    ld hl, #03ff
    and a : jr z, .maskReady
.rot_loop
    ex af, af
    ld a, l : rrca : rr h : rr l
    ex af, af
    dec a : jr nz, .rot_loop
.maskReady
    ld a, l : ld (dcb_m1), a
    ld a, h : ld (dcb_m2), a
    pop ix, de
    push ix
    ld a, (dcb_rot)
    ld (dcb_rc_top), a
    ld b, 4
.topLoop
    call .writeOnePair
    inc de
    djnz .topLoop
    ; Calcular base de row Y+1
    pop hl
    ld a, l : add a, 32 : ld l, a
    jr nc, .botBaseReady
    ld a, h : and #F8 : add a, 8 : ld h, a
.botBaseReady
    push hl : pop ix
    ld b, 4
.botLoop
    call .writeOnePair
    inc de
    djnz .botLoop
    ret

; Sub: lee 1 byte del glyph, rota, escribe a 2 scanlines (duplicado)
.writeOnePair
    ld a, (de) : ld h, a : ld l, 0
    ld a, (dcb_rc_top)
    and a : jr z, .noRot
.doRot
    ex af, af
    ld a, l : rrca : rr h : rr l
    ex af, af
    dec a : jr nz, .doRot
.noRot
    ; Primera scanline
    ld a, (ix + 1)
    push hl : ld l, a : ld a, (dcb_m1) : and l : pop hl
    or l : ld (ix + 1), a
    ld a, (ix)
    push hl : ld l, a : ld a, (dcb_m2) : and l : pop hl
    or h : ld (ix), a
    inc ixh
    ; Segunda scanline (duplicado, H:L intactos)
    ld a, (ix + 1)
    push hl : ld l, a : ld a, (dcb_m1) : and l : pop hl
    or l : ld (ix + 1), a
    ld a, (ix)
    push hl : ld l, a : ld a, (dcb_m2) : and l : pop hl
    or h : ld (ix), a
    inc ixh
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

    ; 3. Colores línea 18: Status Bar top (BRIGHT)
    ld a, ATTR_STATUSBAR
    ld hl, #5A40            ; Línea 18
    ld de, #5A41
    ld bc, 31
    ld (hl), a
    ldir

    ; 4. Color línea 19: Status Bar bottom (sin BRIGHT)
    ld a, ATTR_STATUS_BOT
    ld hl, #5A60            ; Línea 19
    ld de, #5A61
    ld bc, 31
    ld (hl), a
    ldir

    ; 5. Colores líneas 20-23: Log (Verde sobre Azul)
    ld a, ATTR_LOG
    ld hl, #5A80            ; Línea 20
    ld de, #5A81
    ld bc, 127              ; 4 líneas * 32 - 1 = 127
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
    ; A = B * 6
    add a, a        ; A = B * 2
    ld c, a
    add a, a        ; A = B * 4
    add a, c        ; A = B * 6
    ; L = A / 8, A = A % 8
    ld c, a
    and 7
    ld l, c
    srl l
    srl l
    srl l
    ret

coords dw 0

; ============================================
; decompressChar - Descomprime un carácter de la fuente comprimida
; Entrada: A = código ASCII (32-127, otros → espacio)
; Salida: DE = glyph_buf (8 bytes de fuente descomprimida)
; Destruye: AF, BC, DE, HL
; ============================================
decompressChar:
    sub 32
    cp 96
    jr c, .valid
    xor a                   ; fuera de rango → espacio (índice 0)
.valid:
    ld c, a                 ; C = índice del carácter (0-95)
    ; HL = font_packed + índice × 4
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    ld de, font_packed
    add hl, de
    ; Desempaquetar 4 bytes → 8 scanlines vía LUT
    ld de, glyph_buf
    push bc                 ; preservar C (índice char)
    ld b, 4
.unpack:
    ld a, (hl)
    push hl
    ld c, a                 ; guardar byte empaquetado
    ; Nibble alto → scanline par
    rrca
    rrca
    rrca
    rrca
    and #0F
    ld hl, font_lut
    add a, l
    ld l, a
    adc a, h
    sub l
    ld h, a
    ld a, (hl)
    ld (de), a
    inc de
    ; Nibble bajo → scanline impar
    ld a, c
    and #0F
    ld hl, font_lut
    add a, l
    ld l, a
    adc a, h
    sub l
    ld h, a
    ld a, (hl)
    ld (de), a
    inc de
    pop hl
    inc hl
    djnz .unpack
    pop bc                  ; restaurar C = índice char
    ; Aplicar excepciones (tabla ordenada por índice)
    ld hl, font_exceptions
.excScan:
    ld a, (hl)
    cp #FF
    jr z, .excDone
    cp c
    jr z, .excMatch
    jr nc, .excDone         ; tabla ordenada: si entry > c, no hay más
    inc hl
    inc hl
    inc hl
    jr .excScan
.excMatch:
    inc hl
    ld a, (hl)              ; número de scanline (0-7)
    inc hl
    ld b, (hl)              ; valor real
    inc hl
    push hl
    ld hl, glyph_buf
    ld d, 0
    ld e, a
    add hl, de
    ld (hl), b
    pop hl
    jr .excScan
.excDone:
    ld de, glyph_buf
    ret

glyph_buf: ds 8

; ============================================
; Fuente comprimida 6px - 96 caracteres (ASCII 32-127)
; Formato: nibble-packed con LUT de 16 valores + tabla de excepciones
; ============================================
font_lut:
    db #00, #0C, #10, #18, #1C, #28, #30, #36, #38, #3C, #4C, #54, #60, #6C, #78, #7C

font_packed:
    db #00, #00, #00, #00  ; ' '
    db #33, #33, #30, #30  ; '!'
    db #DD, #00, #00, #00  ; '"'
    db #55, #F5, #F5, #50  ; '#'
    db #39, #C8, #1E, #60  ; '$'
    db #0D, #13, #36, #70  ; '%'
    db #8D, #87, #DD, #70  ; '&'
    db #33, #00, #00, #00  ; '''
    db #13, #66, #63, #10  ; '('
    db #C6, #33, #36, #C0  ; ')'
    db #02, #B8, #B2, #00  ; '*'
    db #02, #2F, #22, #00  ; '+'
    db #00, #00, #00, #36  ; ','
    db #00, #0F, #00, #00  ; '-'
    db #00, #00, #00, #30  ; '.'
    db #11, #33, #36, #60  ; '/'
    db #8D, #DF, #DD, #80  ; '0'
    db #38, #33, #33, #30  ; '1'
    db #8D, #13, #6C, #F0  ; '2'
    db #8D, #13, #1D, #80  ; '3'
    db #14, #9D, #F1, #10  ; '4'
    db #FC, #E1, #1D, #80  ; '5'
    db #8C, #CE, #DD, #80  ; '6'
    db #F1, #33, #36, #60  ; '7'
    db #8D, #D8, #DD, #80  ; '8'
    db #8D, #D9, #13, #60  ; '9'
    db #00, #30, #00, #30  ; ':'
    db #00, #30, #00, #36  ; ';'
    db #01, #36, #63, #10  ; '<'
    db #00, #F0, #F0, #00  ; '='
    db #0C, #63, #36, #C0  ; '>'
    db #8D, #13, #60, #60  ; '?'
    db #30, #AB, #BA, #03  ; '@'
    db #28, #DF, #DD, #D0  ; 'A'
    db #ED, #DE, #DD, #E0  ; 'B'
    db #8D, #CC, #CD, #80  ; 'C'
    db #ED, #DD, #DD, #E0  ; 'D'
    db #FC, #CE, #CC, #F0  ; 'E'
    db #FC, #CE, #CC, #C0  ; 'F'
    db #8D, #CD, #DD, #90  ; 'G'
    db #DD, #DF, #DD, #D0  ; 'H'
    db #93, #33, #33, #90  ; 'I'
    db #11, #11, #1D, #80  ; 'J'
    db #DD, #DE, #DD, #D0  ; 'K'
    db #CC, #CC, #CC, #F0  ; 'L'
    db #0D, #FF, #DD, #D0  ; 'M'
    db #AD, #FF, #FD, #00  ; 'N'
    db #8D, #DD, #DD, #80  ; 'O'
    db #ED, #DE, #CC, #C0  ; 'P'
    db #8D, #DD, #DD, #81  ; 'Q'
    db #ED, #DE, #DD, #D0  ; 'R'
    db #8D, #C8, #1D, #80  ; 'S'
    db #93, #33, #33, #30  ; 'T'
    db #DD, #DD, #DD, #80  ; 'U'
    db #DD, #DD, #D8, #20  ; 'V'
    db #DD, #DF, #FD, #00  ; 'W'
    db #DD, #D8, #DD, #D0  ; 'X'
    db #DD, #D8, #66, #60  ; 'Y'
    db #F1, #36, #CC, #F0  ; 'Z'
    db #86, #66, #66, #80  ; '['
    db #66, #33, #31, #10  ; '\'
    db #83, #33, #33, #80  ; ']'
    db #28, #D0, #00, #00  ; '^'
    db #00, #00, #00, #00  ; '_'
    db #08, #FF, #FF, #80  ; '`' → filled circle (lock indicator)
    db #00, #81, #9D, #90  ; 'a'
    db #CC, #ED, #DD, #E0  ; 'b'
    db #00, #8D, #CD, #80  ; 'c'
    db #11, #9D, #DD, #90  ; 'd'
    db #00, #8D, #FC, #80  ; 'e'
    db #46, #F6, #66, #60  ; 'f'
    db #00, #9D, #D9, #1E  ; 'g'
    db #CC, #ED, #DD, #D0  ; 'h'
    db #30, #83, #33, #30  ; 'i'
    db #30, #33, #33, #30  ; 'j'
    db #CC, #DD, #ED, #D0  ; 'k'
    db #66, #66, #66, #30  ; 'l'
    db #00, #0F, #FD, #D0  ; 'm'
    db #00, #ED, #DD, #D0  ; 'n'
    db #00, #8D, #DD, #80  ; 'o'
    db #00, #ED, #DD, #EC  ; 'p'
    db #00, #9D, #DD, #91  ; 'q'
    db #00, #D0, #CC, #C0  ; 'r'
    db #00, #9C, #81, #E0  ; 's'
    db #26, #F6, #66, #40  ; 't'
    db #00, #DD, #DD, #90  ; 'u'
    db #00, #DD, #D8, #20  ; 'v'
    db #00, #DD, #FD, #00  ; 'w'
    db #00, #DD, #8D, #D0  ; 'x'
    db #00, #DD, #D8, #6C  ; 'y'
    db #00, #F3, #6C, #F0  ; 'z'
    db #36, #6C, #66, #30  ; '{'
    db #33, #33, #33, #30  ; '|'
    db #63, #31, #33, #60  ; '}'
    db #00, #80, #08, #00  ; '~' → hollow circle (open network)
    db #FF, #FF, #FF, #FF  ; DEL → cursor block (0x7C solid)

font_exceptions:
    db 32, 1, #24  ; '@' línea 1
    db 32, 6, #20  ; '@' línea 6
    db 45, 0, #44  ; 'M' línea 0
    db 46, 6, #64  ; 'N' línea 6
    db 55, 6, #44  ; 'W' línea 6
    db 63, 7, #7E  ; '_' línea 7
    db 74, 7, #70  ; 'j' línea 7
    db 77, 2, #68  ; 'm' línea 2
    db 82, 3, #70  ; 'r' línea 3
    db 87, 6, #44  ; 'w' línea 6
    db 94, 3, #44  ; '~' línea 3 (hollow circle)
    db 94, 4, #44  ; '~' línea 4 (hollow circle)
    db #FF          ; fin de tabla

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

; ============================================
; stretchRows01 - Estira row 0 a doble alto en rows 0-1
; Debe llamarse DESPUÉS de renderizar texto/gráficos en row 0
; Cada scanline se duplica: top 4 → row 0, bottom 4 → row 1
; Destruye: AF, BC, DE, HL
; ============================================
stretchRows01:
    ld hl, #4700        ; src: row0 scanline 7
    ld de, #4720        ; dst: row1 scanline 7
    call stretchFour
    ld hl, #4300        ; src: row0 scanline 3
    ld de, #4700        ; dst: row0 scanline 7
    jp stretchFour

; Estira row 18 a doble alto en rows 18-19
stretchRows1819:
    ld hl, #5740        ; src: row18 scanline 7
    ld de, #5760        ; dst: row19 scanline 7
    call stretchFour
    ld hl, #5340        ; src: row18 scanline 3
    ld de, #5740        ; dst: row18 scanline 7
    jp stretchFour

; Estira row 4 a doble alto en rows 4-5
stretchRows45:
    ld hl, #4780        ; src: row4 scanline 7
    ld de, #47A0        ; dst: row5 scanline 7
    call stretchFour
    ld hl, #4380        ; src: row4 scanline 3
    ld de, #4780        ; dst: row4 scanline 7
    jp stretchFour

; Estira row 3 a doble alto en rows 3-4
stretchRows34:
    ld hl, #4760        ; src: row3 scanline 7
    ld de, #4780        ; dst: row4 scanline 7
    call stretchFour
    ld hl, #4360        ; src: row3 scanline 3
    ld de, #4760        ; dst: row3 scanline 7
    ; fall through

stretchFour:
    ld b, 4
.sloop:
    push bc
    push hl
    push de
    ld bc, 32
    ldir                ; copiar src → dst_high
    pop de
    pop hl
    push hl
    dec d               ; dst_low = dst_high - 256
    push de
    ld bc, 32
    ldir                ; copiar src → dst_low (duplicar)
    pop de
    pop hl
    dec h               ; src -= 256
    dec d               ; dst_high siguiente = dst_low - 256
    pop bc
    djnz .sloop
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
