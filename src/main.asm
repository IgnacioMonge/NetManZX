    IFDEF NEXT
        device ZXSPECTRUMNEXT
    ELSE
        device ZXSPECTRUM48
    ENDIF

    IFDEF DOT
        org #8000
    ELSE
        org #8000          
    ENDIF

    ; Global version definition (single source of truth)
    ; V = Mmp...  (M=major, m=minor, p=patch)
    ; Examples: V=12  -> 1.2
    ;           V=121 -> 1.2.1
    ; Optional: VSUB for sub-patch (e.g., V=143 + VSUB=1 -> 1.4.3.1)
    DEFINE V 144

; Platforms with esxDOS (SD card file I/O)
    IFDEF UNO
        DEFINE HAS_ESXDOS
    ENDIF
    IFDEF NEXT
        DEFINE HAS_ESXDOS
    ENDIF

; Global constants
buffer = #C200
stack_top = #FFF0

; Runtime data area: uninitialized buffers placed after the SSID buffer
; to keep them out of the binary. Use RTVAR to allocate.
MAX_NETWORKS    = 25
MAX_SSID_LEN    = 32
BUFFER_SIZE     = (MAX_NETWORKS * (MAX_SSID_LEN + 1))
BUFFER_END      = buffer + BUFFER_SIZE
rt_ptr = BUFFER_END

    MACRO RTVAR name?, size?
name? = @rt_ptr
@rt_ptr = @rt_ptr + size?
    ENDM

    ; saved_sp: original BASIC stack pointer. Must live outside printer
    ; buffer (#5B00-#5BFF) because esxDOS rst $08 scribbles that area
    ; during Config.load/save, and the UNO/AY exit path reads saved_sp
    ; to return to BASIC.
    RTVAR saved_sp, 2

text
    jp start

; Config valid flag — MUST be in bank 2 (#8000-#BFFF), not paged memory
cfg_valid        db 0

    include "modules/display.asm"
    include "modules/wifi.asm"
    include "modules/version.asm"    ; generates VERSION_STRING from V
    include "modules/ui.asm"
    include "modules/uart-common.asm"
    include "modules/keyboard.asm"

    ; Config save/load (esxDOS) - only for platforms with SD card
    IFDEF HAS_ESXDOS
        include "modules/config.asm"
    ENDIF

    ; ============================================
    ; UART backend selection (SjASMPlus compatible)
    ;
    ; Build defines:
    ;   -DUNO  : ZX-Uno compatible UART (e.g., divMMC+ESP-12 boards such as DivTIESUS)
    ;   -DNEXT : ZX Spectrum Next UART
    ;   -DAY   : AY-3-8912 UART (ZX-Badaloc and similar)
    ;
    ; If none is provided, AY is used as a safe default.
    ; ============================================
    IFDEF UNO
        include "drivers/zxuno.asm"
    ELSE
        IFDEF NEXT
            include "drivers/next.asm"
        ELSE
            include "drivers/ay.asm"
        ENDIF
    ENDIF

; ============================================
; Splash message area (rows 20-23, ULA)
; ============================================
; Init-time status strings are rendered centered on ULA row 20, white INK
; on black PAPER. On Next, Layer 2 clip window hides L2 below pixel row
; 159 so the ULA message shows through from under the splash image. On
; UNO/AY the SCR is in ULA so rows 20-23 are overwritten directly.
SPLASH_ROW      = 20
SPLASH_ATTR     = #5A80          ; row 20 attr origin
SPLASH_PIX      = #5080          ; row 20 pixel origin (third 3, scanline 0)
SPLASH_L2_Y2    = 159            ; L2 clip bottom; 159 exposes rows 20..23

; Prep attrs + clear pixels for rows 20-23. Next: set L2 clip.
splashInit:
    ld a, 1
    ld (Display.splash_mode), a ; suppress Display.putStrLog writes
    ; Paint attrs all-black first (ink=paper=black) so any lingering SCR
    ; pixels at rows 20-23 stay invisible while we clear pixel memory.
    ; Without this, switching attrs to white-ink before clearing pixels
    ; would flash the SCR pixel content as white on UNO/AY.
    ld hl, SPLASH_ATTR
    ld (hl), %00000000
    ld de, SPLASH_ATTR + 1
    ld bc, 4 * 32 - 1           ; 4 rows (20..23) of attrs
    ldir
    ld hl, SPLASH_PIX
    ld b, 8
.clrLoop:
    push hl
    push bc
    xor a
    ld (hl), a
    ld e, l : ld d, h : inc de
    ld bc, 4 * 32 - 1           ; 128 bytes: rows 20..23 on this scanline
    ldir
    pop bc
    pop hl
    inc h                       ; next scanline = +$100
    djnz .clrLoop
    ; Row 20 = white INK / black PAPER for text rendering (pixels 0 = black)
    ld hl, SPLASH_ATTR
    ld (hl), %00000111
    ld de, SPLASH_ATTR + 1
    ld bc, 31
    ldir
    IFDEF NEXT
    ; L2 clip window uses NextReg $18 with 4 sequential writes (X1,X2,Y1,Y2).
    ; Reg $1C bit 0 resets the write index. DI/EI wraps the 5-write sequence
    ; so a future IM 1 handler that touches $18 cannot desync the index.
    di
    nextreg $1C, 1
    nextreg $18, 0              ; X1
    nextreg $18, 255            ; X2
    nextreg $18, 0              ; Y1
    nextreg $18, SPLASH_L2_Y2   ; hide L2 for pixel rows 160..191
    ei
    ENDIF
    ret

; HL = null-terminated string (CR terminates early).
; Clears row 20 pixels, then renders centered with 6px font.
splashMsg:
    push hl
    ld b, 0
.lenLoop:
    ld a, (hl)
    and a : jr z, .lenDone
    cp 13 : jr z, .lenDone
    inc b : inc hl
    jr .lenLoop
.lenDone:
    pop hl
    ld a, 42
    sub b                       ; A = 42 - len
    jr nc, .startOk
    xor a                       ; Overlong messages start at column 0
.startOk:
    srl a                       ; /2
    ld c, a                     ; C = start column
    push hl
    push bc
    ld hl, SPLASH_PIX
    ld b, 8
.rowClr:
    push hl : push bc
    xor a : ld (hl), a
    ld e, l : ld d, h : inc de
    ld bc, 31                   ; 32 bytes = one char row
    ldir
    pop bc : pop hl
    inc h
    djnz .rowClr
    pop bc
    pop hl
    ld b, SPLASH_ROW
.rndLoop:
    ld a, (hl)
    and a : ret z
    cp 13 : ret z
    push hl
    push bc
    ld (Display.drawC.coords), bc
    call Display.drawC
    pop bc
    pop hl
    inc c
    inc hl
    jr .rndLoop

; Restore L2 clip (Next) and hide Layer 2 so UI.init's ULA draw is
; visible. Caller should call UI.init next.
splashEnd:
    xor a
    ld (Display.splash_mode), a ; Display.putStrLog resumes normal logging
    IFDEF NEXT
    di                          ; protect 5-write clip sequence
    nextreg $1C, 1              ; reset L2 clip index
    nextreg $18, 0              ; X1
    nextreg $18, 255            ; X2
    nextreg $18, 0              ; Y1
    nextreg $18, 191            ; Y2 (full L2 visible)
    ei
    ld bc, $123B
    xor a
    out (c), a                  ; clear Layer 2 visible bit
    ENDIF
    ret

start:
    ; Zero printer buffer (128K/Next ROM leaves garbage that corrupts
    ; our variables stored there: log_ind_data, putLogC_coord, etc.)
    ld hl, #5B00
    ld de, #5B01
    ld (hl), 0
    ld bc, 255
    ldir

    ; Zero RTVAR state migrated out of the printer buffer (esxDOS-safe).
    ; RTVAR space is uninitialised at boot, so do this explicitly.
    xor a
    ld (Wifi.networks_count), a
    ld (Wifi.is_connected), a
    ld (Wifi.debug_log), a
    ld (UI.cursor_position), a
    ld (UI.offset), a

    ld (saved_sp), sp
    ld sp, stack_top

    ; ROM IM 1 handler expects IY = #5C3A. Some loaders leave IY elsewhere;
    ; reloading it is cheap insurance against interrupt-time crashes when
    ; we EI later.
    ld iy, #5C3A

    IFDEF NEXT
    ; Program Layer 2 first palette from splash.pal. Palette lives in its
    ; own 8K page (SPLASH_PAL_BANK); map it briefly into slot 6 ($C000),
    ; stream 512 bytes through NextReg $44, then restore slot 6's prior
    ; bank. DI during the NextReg sequence to keep the select/value pair
    ; atomic across any background IM 1 handler that might touch them.
    di
    ld bc, $243B
    ld a, $56                ; MMU slot 6 mapping register
    out (c), a
    ld b, $25
    in a, (c)
    ld (.slot6Save), a
    nextreg $56, SPLASH_PAL_BANK

    nextreg $43, %00010000   ; palette select = L2 first, autoinc on
    nextreg $40, 0           ; palette index = 0
    ld hl, $C000
    ld bc, 512
.palLoop:
    ld a, (hl)
    nextreg $44, a           ; two writes per entry, index auto-advances
    inc hl
    dec bc
    ld a, b
    or c
    jr nz, .palLoop
    nextreg $43, 0           ; restore default palette select

    ld a, 0
.slot6Save = $ - 1
    nextreg $56, a           ; restore prior slot 6 bank
    ei
    ENDIF

    ; Prep the ULA message strip under the splash. Status/error lines render
    ; centered on row 20 while the splash image stays visible behind/around it.
    call splashInit

    IFDEF NEXT
    ; Hold splash ~1s (50 frames at 50Hz) so the Layer 2 image is readable
    ; before status messages start appearing.
    ld b, 50
.splashHold
    halt
    djnz .splashHold
    ENDIF

    ; Show log message
    ld hl, .msg_checking
    call splashMsg

    ; Initialize UART
    ld hl, .msg_preparing
    call splashMsg
    call Uart.init

    IFDEF NEXT
    ; Baud rate auto-detection: try AT at 115200, scan if no response
    ld hl, .msg_probe_esp
    call splashMsg
    call Wifi.flushInput
    ld hl, Wifi.S_AT : call Wifi.espSendZ
    call Wifi.checkOkErr
    jr nc, .baudOk

    ; No response at 115200 — scan common baud rates
    ld hl, .msg_baud_scan
    call splashMsg
    call UartImpl.baudScan
    jr c, .baudScanFail

    ; Found ESP at wrong baud — switch to 115200 for this session only
    ld hl, .msg_baud_fix
    call splashMsg
    call Wifi.flushInput
    ld hl, .at_uart_cur : call Wifi.espSendZ
    call Wifi.checkOkErr        ; OK at detected baud
    call Uart.init              ; Switch local UART to 115200
    call Wifi.flushInput
    jr .baudOk

.baudScanFail:
    ; Not found at any scanned rate — hardware ESP reset
    ; Forces ESP back to default baud (115200)
    ld hl, .msg_hw_reset
    call splashMsg
    call UartImpl.espHardReset
    call Uart.init              ; Reinit UART at 115200
    call Wifi.flushInput
.baudOk:
    ENDIF

    ; Exit transparent mode (if SpecTalkZX or similar left it active)
    ; Requires 1s of prior silence (satisfied: we just started)
    ld hl, .msg_esp_config
    call splashMsg
    call Wifi.exitTransparent

    ; Disable echo early — ESP default is echo ON after power-on.
    ; Without this, AT+CWLAP responses include the echoed command,
    ; breaking the scan parser. Must happen before any scan path.
    call Wifi.flushInput
    ld hl, Wifi.S_ATE0 : call Wifi.espSendZ
    call Wifi.checkOkErr

    ; Ensure station mode — CWMODE=2 (AP mode, e.g. after AT+RESTORE)
    ; blocks scanning. Must be set before any connection check.
    ld hl, Wifi.S_AT_CWMODE : call Wifi.espSendZCheckOk
    jr nc, .cwmodeOk
    ld hl, Wifi.S_AT_CWMODE_DEF : call Wifi.espSendZCheckOk
.cwmodeOk

    ; Check if already connected
    ld hl, .msg_query_status
    call splashMsg
    call Wifi.checkConnection
    jr nc, .alreadyConnected  ; CF=0 means connected

    ; Fallback: some firmwares don't respond to CWJAP? but have an IP assigned.
    ; If a valid IP exists, consider it connected.
    call Wifi.getIP
    jr c, .noPreconn
    ld a, 1
    ld (Wifi.is_connected), a
    ld hl, Wifi.connected_ssid
    ld a, (hl)
    and a
    jr nz, .alreadyConnected
    ; Unknown SSID -> show placeholder
    ld hl, .ssid_unknown
    ld de, Wifi.connected_ssid
    call UI.copyStringZ
    jr .alreadyConnected

.noPreconn
    ; --- NOT CONNECTED: full initialization ---
    ld hl, .msg_init_wifi
    call splashMsg
    
    call Wifi.init
    jp c, .initFailed
    
    ; Warm-up delay
    ld b, 125
.warmup
    halt
    djnz .warmup

    ; Final connection check
    call Wifi.checkConnection
    jr c, .notConnected
    
.alreadyConnected:
    ; --- CASE: CONNECTED ---
    call .enterMainUi           ; Config.load + UI.init (L2 still covering)
    call UI.updateWifiStatus_q  ; Switch from Scanning to Connected (no render)
    call UI.ipShowConnected     ; Show IP (single render)
    jr .forceScan

.notConnected
    ; --- Update top and bottom bars ---
    call .enterMainUi           ; Config.load + UI.init (L2 still covering)
    call UI.updateWifiStatus_q  ; Ensure bottom bar is RED (no render)
    call UI.ipShowNotConnected  ; Set "IP: not connected" (single render)

.forceScan
    ; --- CASE: NOT CONFIGURED / RESCAN ---

    ; CRITICAL: Reset UI variables before new scan
    xor a
    ld (UI.cursor_position), a
    ld (UI.offset), a
    ld (.scan_fail_reason), a    ; 0=ok, 1=timeout, 2=no networks

    ; Show full menu frame ONCE (help text + separator stay visible during scan)
    ; Suppress "No networks found" on this first render — scan has not run yet
    ld a, 1 : ld (UI.skip_footer), a
    call UI.renderList
    xor a : ld (UI.skip_footer), a

    ld b, 5                 ; 5 attempts

.scanLoop
    push bc

    ; Only clear network area + show scanning (menu stays visible)
    call UI.clearNetworksArea
    ld a, 17 : ld hl, UI.rescan.scanning_msg : call UI.printAt0

    ; Reveal fully-composed UI at once: on Next, L2 was hiding the sweep
    ; from clrscr + renderList. Idempotent on subsequent scanLoop passes.
    call splashEnd

    call Wifi.getList
    
    jr c, .scanTimeout     ; CF=1 -> Communication error
    
    ld a, (Wifi.networks_count)
    and a
    jr nz, .scanSuccess    ; Networks found -> proceed

    ; 0 networks found
    ld a, 2
    ld (.scan_fail_reason), a
    jr .retryWait

.scanTimeout
    ld a, 1
    ld (.scan_fail_reason), a
    
.retryWait
    pop bc
    push bc
    
    ; Show retry message based on failure type
    ld a, 8 : call Display.gotoXY0
    ld a, (.scan_fail_reason)
    cp 1
    jr nz, .showNoNetworks
    ld hl, .msg_esp_timeout
    jr .showRetryMsg
.showNoNetworks
    ld hl, .msg_no_networks
.showRetryMsg
    call Display.putStr
    
    ld b, 50                ; Longer wait so message is visible
.w  halt
    djnz .w
    
    pop bc
    djnz .scanLoop
    
    jr .endScan

.scanSuccess
    pop bc
    xor a
    ld (.scan_fail_reason), a    ; Success

.endScan
    ; If no networks found, log the reason
    ld a, (Wifi.networks_count)
    and a
    jr nz, .showList
    
    ld a, (.scan_fail_reason)
    cp 1
    jr nz, .logNoNetworks
    ld hl, .msg_log_timeout
    jr .logReason
.logNoNetworks
    ld hl, .msg_log_empty
.logReason
    call Display.putStrLog

.showList
    call UI.renderList
    ; Clear startup messages from log area (list already visible)
    ld b, 4
.clearLog
    push bc
    ld a, 13 : call Display.putLogC
    pop bc
    djnz .clearLog

    jp   UI.uiLoop

.initFailed
    ld hl, .msg_err_init
    call splashMsg              ; stays on splash, row 20 centered
.waitExit
    xor a
    ld (Keyboard.BASIC_KEY), a
.k  halt
    ld a, (Keyboard.BASIC_KEY)
    and a
    jr z, .k
    xor a
    ld (Keyboard.BASIC_KEY), a
    ; Fall through to exit_clean

.exitClean
    IFDEF NEXT
        ei
        rst 0               ; Return to NextZXOS
    ELSE
        ld sp, (saved_sp)
        ei
        ret                 ; Return to BASIC
    ENDIF

; Shared transition from splash to main menu. Loads saved config on esxDOS
; platforms, restores printer-buffer scratch, then draws the main UI while
; the Next splash is still covering the incremental ULA render. splashEnd is
; called later from .forceScan to reveal the fully composed first screen.
.enterMainUi:
    IFDEF HAS_ESXDOS
    call Config.load
    call UI.restoreAfterFileIo
    jr c, .emNoCfg
    ld a, 1
    ld (cfg_valid), a
.emNoCfg
    ENDIF
    jp UI.init                  ; draw main UI while L2 still covering

; String constants
.msg_checking   db "Checking...", 13, 0
.msg_preparing  db "UART init...", 13, 0
    IFDEF NEXT
.msg_probe_esp  db "Probing ESP...", 13, 0
.msg_baud_scan  db "Scanning baud rates...", 13, 0
.msg_baud_fix   db "Setting ESP to 115200...", 13, 0
.msg_hw_reset   db "Resetting ESP module...", 13, 0
.at_uart_cur    db "AT+UART_CUR=115200,8,1,0,0", 13, 10, 0
    ENDIF
.msg_esp_config   db "Configuring ESP...", 13, 0
.msg_query_status db "Checking WiFi status...", 13, 0
.ssid_unknown     db "(unknown)", 0
.msg_init_wifi  db "Initializing WiFi module...", 13, 0
.msg_err_init   db "WiFi Init Failed", 0
.msg_esp_timeout db "ESP not responding, retrying...", 0
.msg_no_networks db "No networks found, retrying...", 0
.msg_log_timeout db "Scan failed: ESP timeout", 13, 0
.msg_log_empty   db "Scan complete: no networks", 13, 0

; Variables in printer buffer (set before use)
; Only boot-time scratch — no file I/O between set and read, so esxDOS
; clobbering is a non-issue here. saved_sp moved to RTVAR (see top of file).
.scan_fail_reason = #5B39

program_end:

    ; Build-time safety checks
    ASSERT program_end <= buffer              ; code must not overlap SSID buffer
    ASSERT rt_ptr <= stack_top - 64           ; runtime vars must not reach stack

    IFDEF NEXT
        ; ============================================
        ; NEX format (native Next, no mode menu)
        ; ============================================
        SAVENEX OPEN "netmanzx.nex", start, stack_top
        SAVENEX CORE 2, 0, 0       ; Minimum core version
        SAVENEX CFG 0               ; Border black

        ; Boot splash: load 48 KB Layer 2 image into 8K pages 18..23
        ; (= 16K banks 9..11, default Layer 2 memory). SAVENEX SCREEN L2
        ; (no args) flags these pages as the NEX loading screen — the
        ; NextZXOS loader paints them to Layer 2 before program entry.
        MMU 6, 18, $C000 : ORG $C000 : INCBIN "splash.nxi",      0, $2000
        MMU 6, 19, $C000 : ORG $C000 : INCBIN "splash.nxi", $2000, $2000
        MMU 6, 20, $C000 : ORG $C000 : INCBIN "splash.nxi", $4000, $2000
        MMU 6, 21, $C000 : ORG $C000 : INCBIN "splash.nxi", $6000, $2000
        MMU 6, 22, $C000 : ORG $C000 : INCBIN "splash.nxi", $8000, $2000
        MMU 6, 23, $C000 : ORG $C000 : INCBIN "splash.nxi", $A000, $2000

        ; Store the Layer 2 loading screen with its final palette so the
        ; loader shows the splash in the correct colours immediately, instead
        ; of first using the default palette and then being recoloured at
        ; runtime when start: uploads splash.pal.
        SAVENEX SCREEN L2 18, 0, SPLASH_PAL_BANK, 0

        ; Splash palette in its own 8K page. Runtime maps this bank into
        ; slot 6 long enough to copy 512 bytes into the L2 first palette,
        ; then restores the previous bank. Placed AFTER SAVENEX SCREEN L2
        ; so NextZXOS does not try to paint it onto Layer 2.
SPLASH_PAL_BANK = 24
        MMU 6, SPLASH_PAL_BANK, $C000 : ORG $C000
        INCBIN "splash.pal"

        SAVENEX AUTO                ; Save all modified pages
        SAVENEX CLOSE

    ELSE

    IFDEF TAP
        ; ============================================
        ; Full TAP format (loader + splash + code)
        ; ============================================

        ; Stage splash SCR at #E000 (scratch area, outside main code).
        ; savetap picks up these bytes and emits a CODE block that
        ; LOAD ""SCREEN$ reads into #4000 at load time.
        ORG #E000
splash_scr:
        INCBIN "splash.scr"         ; 6912 bytes: 6144 pixels + 768 attrs

        ; Define BASIC loader in temporary area
        ORG #6000
basic_start:
        ; Line 10: CLEAR 32767
        db #00, #0A                 ; Line number (10) big-endian
        dw line10end - line10start  ; Content length
line10start:
        db #FD                      ; CLEAR
        db '3','2','7','6','7'      ; "32767" as text
        db #0E, #00, #00            ; Number marker
        dw 32767                    ; Numeric value
        db #00                      ; Exponent
        db #0D                      ; ENTER
line10end:

        ; Line 20: BORDER 0: PAPER 0: INK 0
        ; Black-on-black hides ROM "Bytes: ..." messages during both
        ; subsequent LOADs. SCR attrs already on-screen are unaffected.
        db #00, #14                 ; Line number (20)
        dw line20end - line20start
line20start:
        db #E7                      ; BORDER
        db '0'
        db #0E, #00, #00, #00, #00, #00
        db #3A                      ; ':'
        db #DA                      ; PAPER
        db '0'
        db #0E, #00, #00, #00, #00, #00
        db #3A
        db #D9                      ; INK
        db '0'
        db #0E, #00, #00, #00, #00, #00
        db #0D
line20end:

        ; Line 30: LOAD ""SCREEN$
        db #00, #1E                 ; Line number (30)
        dw line30end - line30start
line30start:
        db #EF                      ; LOAD
        db '"', '"'                 ; ""
        db #AA                      ; SCREEN$
        db #0D
line30end:

        ; Line 40: LOAD ""CODE
        db #00, #28                 ; Line number (40)
        dw line40end - line40start
line40start:
        db #EF                      ; LOAD
        db '"', '"'                 ; ""
        db #AF                      ; CODE
        db #0D
line40end:

        ; Line 50: RANDOMIZE USR 32768
        db #00, #32                 ; Line number (50)
        dw line50end - line50start
line50start:
        db #F9                      ; RANDOMIZE
        db #C0                      ; USR
        db '3','2','7','6','8'      ; "32768"
        db #0E, #00, #00
        dw 32768
        db #00
        db #0D
line50end:
basic_end:

        ; Generate TAP
        emptytap "netmanzx.tap"
        savetap "netmanzx.tap", BASIC, "netmanzx", basic_start, basic_end - basic_start, 10
        savetap "netmanzx.tap", CODE, "splash",   splash_scr, 6912, #4000
        savetap "netmanzx.tap", CODE, "netmanzx", text, program_end - text, text

    ELSE
        ; ============================================
        ; Standard +3DOS format
        ; ============================================
        save3dos "netmanzx.cod", text, program_end - text
    ENDIF

    ENDIF   ; NEXT
