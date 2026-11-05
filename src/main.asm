; AY's cycle-timed receiver is supported only by the TAP memory layout.
    IFNDEF UNO
    IFNDEF NEXT
    IFNDEF TAP
        ASSERT 0, "AY supports TAP only: use -DAY -DTAP without -DDOT"
        END
    ENDIF
    IFDEF DOT
        ASSERT 0, "AY supports TAP only: use -DAY -DTAP without -DDOT"
        END
    ENDIF
    ENDIF
    ENDIF

    IFDEF NEXT
        device ZXSPECTRUMNEXT
    ELSE
        device ZXSPECTRUM48
    ENDIF

    org #8000

    ; Global version definition (single source of truth)
    ; V = Mmp...  (M=major, m=minor, p=patch)
    ; Examples: V=12  -> 1.2
    ;           V=121 -> 1.2.1
    ; Optional: VSUB for sub-patch (e.g., V=143 + VSUB=1 -> 1.4.3.1)
    DEFINE V 147

; Platforms with esxDOS (SD card file I/O)
    IFDEF UNO
        DEFINE HAS_ESXDOS
    ENDIF
    IFDEF NEXT
        DEFINE HAS_ESXDOS
    ENDIF

; Clock UI availability. Next runs it from its paged #6000 overlay; UNO
; ships it as a TAP CODE block preloaded at #6000 (resident does not fit).
    IFDEF NEXT
        DEFINE HAS_TIME
    ENDIF
    IFDEF UNO
        IFDEF TAP
            DEFINE HAS_TIME
        ENDIF
    ENDIF

; Global constants
buffer = #C800
stack_top = #FFF0

; Runtime data area: uninitialized buffers placed after the SSID buffer
; to keep them out of the binary. Use RTVAR to allocate.
MAX_NETWORKS    = 50          ; Strongest APs kept; UI page digits allow <= 90
MAX_SSID_LEN    = 32
SSID_SLOT_SIZE  = MAX_SSID_LEN + 1
; Fixed-stride SSID slots plus one scratch slot: a row parsed while the list is
; full lands there and replaces the weakest committed AP when it is stronger.
BUFFER_SIZE     = ((MAX_NETWORKS + 1) * SSID_SLOT_SIZE)
BUFFER_END      = buffer + BUFFER_SIZE
rt_ptr = BUFFER_END

    MACRO RTVAR name?, size?
name? = @rt_ptr
@rt_ptr = @rt_ptr + size?
    ENDM

text
    jp start

; Config valid flag — MUST be in bank 2 (#8000-#BFFF), not paged memory
cfg_valid        db 0

    include "modules/display.asm"
    include "modules/wifi.asm"
    module Display
; Rows are composed only after getList has consumed the captured response.
row_buffer = Wifi.scan_rx_buffer
    endmodule
    include "modules/version.asm"    ; generates VERSION_STRING from V
    include "modules/ui.asm"
; Return state lives in resident immediates, outside relocation and runtime RAM.
saved_sp = UI.exitRestore.callerStack
saved_ret = UI.exitRestore.callerReturn
    IFNDEF NEXT
saved_hl_alt = UI.exitRestore.callerAltHL
    ENDIF
    include "modules/uart-common.asm"
    include "modules/keyboard.asm"

    ; Config save/load (esxDOS) - only for platforms with SD card
    IFDEF HAS_ESXDOS
        include "modules/config.asm"
    ENDIF
    IFDEF NEXT
    include "modules/rtc.asm"
    include "modules/sntp.asm"
    ENDIF

    ; ============================================
    ; UART backend selection (SjASMPlus compatible)
    ;
    ; Build defines:
    ;   -DUNO  : ZX-Uno compatible UART (e.g., divMMC+ESP-12 boards such as DivTIESUS)
    ;   -DNEXT : ZX Spectrum Next UART
    ;   -DAY -DTAP : AY-3-8912 UART (TAP only)
    ;
    ; Without a backend define, AY is selected and still requires -DTAP.
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
    ; Loader IY may be invalid; UART init reenables IRQs after restoration.
    di
    ld (saved_sp), sp
    pop hl
    ld (saved_ret), hl
    ld sp, stack_top
    IFNDEF NEXT
    ; AY uses HL' internally; BASIC's USR caller needs its original value.
    exx
    ld (saved_hl_alt), hl
    exx
    ENDIF
    IFDEF UNO
    IFNDEF TAP
    ; The contiguous +3DOS load stages diagnostics in future runtime RAM.
    ; Caller state is resident, outside the staged diagnostic image.
.overlayGuard
    jr .copyOverlay
.copyOverlay
    ld hl, dos_overlay_source
    ld de, dos_overlay
    ld bc, dos_overlay_end - dos_overlay
    ldir
    ; Warm re-entry must keep the overlay: its staging area now holds runtime data.
    ld a, .overlayDone - .copyOverlay
    ld (.overlayGuard + 1), a
.overlayDone
    ENDIF
    ENDIF
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
    ld hl, Wifi.connected_ssid
    ld de, Wifi.connected_ssid + 1
    ld (hl), a
    ld bc, Wifi.debug_log - Wifi.connected_ssid
    ldir
    ld (Wifi.old_fw), a
    ld (UI.cursor_position), a
    ld (UI.offset), a
    ld (UI.force_rescan), a
    ld (UI.diag_cursor), a
    ld (UI.ping_ip_len), a
    ld (UI.async_state), a
    IFDEF HAS_TIME
    ld (Sntp.tz), a
    ld (Rtc.kind), a
    ld hl, Sntp.fields
    ld de, Sntp.fields + 1
    ld bc, 5
    ld (hl), a
    ldir
    ENDIF

    IFDEF NEXT
    ; Map cold UI, diagnostics, Time and font64 before any overlay call.
    nextreg $53, 32
    ENDIF

    ; ROM IM 1 handler expects IY = #5C3A. Some loaders leave IY elsewhere;
    ; reloading it avoids interrupt-time crashes when we EI later.
    ld iy, #5C3A
    IFDEF NEXT
    ; Direct NEX loaders may not initialise the ROM keyboard state.
    ld hl, #0523             ; REPPER=5, REPDEL=35
    ld (#5C09), hl
    set 3, (iy + 1)          ; FLAGS: L mode returns ASCII instead of tokens
.irqMode:
    im 1
    ENDIF

    call Display.initFontCache

    IFDEF NEXT
    ; The NEX loader already installed the Layer 2 palette from the file.
    nextreg $43, 0           ; Restore default palette selection only
.irqEnable:
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
    call UartImpl.recoverBaud
    jr nc, .baudOk

.baudScanFail:
    ; Not found at any scanned rate — hardware ESP reset
    ; Probe again after reset: the persisted baud may differ.
    ld hl, .msg_hw_reset
    call splashMsg
    call UartImpl.espHardReset
    jp c, .initFailed
.baudOk:
    ENDIF

    ; Probe AT first; only run +++ passthrough recovery when needed.
    ld hl, .msg_esp_config
    call splashMsg
    call Wifi.ensureCommandMode

    ; Disable echo early — ESP default is echo ON after power-on.
    ; Without this, AT+CWLAP responses include the echoed command,
    ; breaking the scan parser. Must happen before any scan path.
    ld hl, Wifi.S_ATE0 : call Wifi.espSendZ_CRLF
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

    ; A configured IP alone does not prove station association.
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
    ; Normalize inherited scan fields even when an existing connection skips init.
    ; Old firmware may reject this command; its defaults already include channel.
    ld hl, Wifi.S_AT_CWLAPOPT : call Wifi.espSendZCheckOk
    ld a, (Uart.io_error)
    and a
    jp nz, .initFailed

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
    
    jr nc, .scanComplete
    and a
    jp nz, .scanCancelled  ; BREAK: stop without timeout/retry noise
    jr .scanTimeout

.scanComplete
    
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

.scanCancelled
    pop bc
    jr .showList

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
    call Keyboard.waitBreakRelease
    IFDEF NEXT
        ; NEX has no preserved dot-command caller; request a soft reset.
        di
        nextreg #02, #01
.resetPending
        jr .resetPending
    ELSE
        jp UI.exitRestore
    ENDIF

; Shared transition from splash to main menu. Loads saved config on esxDOS
; platforms, restores printer-buffer scratch, then draws the main UI while
; the Next splash is still covering the incremental ULA render. splashEnd is
; called later from .forceScan to reveal the fully composed first screen.
.enterMainUi:
    IFDEF HAS_ESXDOS
    call Config.load
    call UI.restoreAfterFileIo
    ENDIF
    jp UI.init                  ; draw main UI while L2 still covering

; String constants
.msg_checking   db "Checking...", 13, 0
.msg_query_status db "Checking WiFi status...", 13, 0
.msg_init_wifi    db "Initializing WiFi module...", 13, 0
.msg_err_init     db "Init failed", 0
.msg_esp_timeout  db "ESP timeout", 0
.msg_no_networks  db "No networks", 0
.msg_log_timeout  db "Scan timeout", 13, 0
.msg_log_empty    db "No networks", 13, 0

; Variables in printer buffer (set before use)
; Only boot-time scratch — no file I/O between set and read, so esxDOS
; clobbering is a non-issue here.
.scan_fail_reason = #5B39


    IFDEF UNO
    IFNDEF TAP
    ; UNO +3DOS has code space and #6000 overlay headroom, while its #C000
    ; font/string span before #C800 is tight.
    DEFINE REPLY_DATA_RESIDENT
    DEFINE DIAG_STRINGS_OVERLAY
    include "modules/reply-data.asm"
    ENDIF
    ENDIF

program_end:

    ; Build-time safety checks
    ASSERT program_end <= #C000               ; code must stay out of paged RAM
    ASSERT program_end <= buffer              ; code must not overlap SSID buffer
    ASSERT rt_ptr <= stack_top - 64           ; runtime vars must not reach stack
    IFDEF UNO
    ASSERT program_end <= #C000 - 256         ; keep 256 B headroom on UNO
    ENDIF

; Static strings precede the SSID buffer; TAP/NEX font data uses the overlay.
    IFDEF TAP
    ; The TAP ships code and static data as separate CODE blocks, so the gap
    ; below #C000 never reaches the file. Padding it would cost as many bytes
    ; as the resident image has free.
    ORG #C000
    ELSE
    ; +3DOS and the NEX bank image want one contiguous span.
    defs #C000 - $, 0
    ENDIF
    IFNDEF NEXT
    IFNDEF TAP
    include "modules/font-data.asm"
    ENDIF
    ENDIF
    include "modules/ui-strings.asm"
    IFNDEF REPLY_DATA_RESIDENT
    include "modules/reply-data.asm"
    ENDIF

static_data_end:
    ASSERT static_data_end <= buffer

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

        ; Stage the palette before SCREEN reads it. This page is build-only;
        ; the loader reads the 512-byte palette block directly from the NEX.
SPLASH_PAL_PAGE = 24
        MMU 6, SPLASH_PAL_PAGE, $C000 : ORG $C000
        INCBIN "splash.pal"
        SAVENEX SCREEN L2 18, 0, SPLASH_PAL_PAGE, 0

        ; Paged cold code. Assemble the cold UI routines into 16K bank 16
        ; (8K page 32); start maps page 32 into MMU slot 3 (#6000). Keeps the
        ; resident image under its #C000 ceiling.
        MMU 3, 32, $6000
        ORG #6000
        include "modules/font-data.asm"
        module UI
        include "modules/cold-ui.asm"
        include "modules/diag-ui.asm"
        include "modules/quit-ui.asm"
        include "modules/time-core.asm"
        include "modules/time-ui.asm"
        endmodule
        include "modules/font64.asm"
overlay_end:
        ASSERT overlay_end <= #8000

        ; Only program and runtime-data banks belong in the resident payload.
        ; AUTO would also duplicate the staged splash and palette banks.
        SAVENEX BANK 2, 0
        SAVENEX BANK 16
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

        ; TAP overlay at #6000: fonts and diagnostics; UNO also carries Time,
        ; SNTP and RTC here so the resident image fits below #C000. AY keeps
        ; the diagnostic UART reader resident. Runtime limit is the program at
        ; #8000; the BASIC loader is staged after the splash image so this
        ; overlay can use the whole 8K hole.
        ORG #6000
tap_overlay:
        include "modules/font-data.asm"
        IFDEF HAS_TIME
        include "modules/sntp.asm"
        include "modules/rtc.asm"
        module UI
        include "modules/diag-ui.asm"
        include "modules/quit-ui.asm"
        include "modules/time-core.asm"
        include "modules/time-ui.asm"
        endmodule
        ELSE
        module UI
        include "modules/diag-ui.asm"
        include "modules/quit-ui.asm"
        endmodule
        ENDIF
        include "modules/font64.asm"
tap_overlay_end:
        ASSERT tap_overlay_end <= #8000

        ; BASIC loader staged after the splash SCR (assembly scratch only).
        ORG splash_scr + 6912
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
        ; Black-on-black hides ROM "Bytes: ..." messages until the final
        ; screen block replaces the complete display.
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

        ; The screen image is loaded LAST so the ROM "Bytes:" messages of the
        ; preceding CODE blocks cannot cut its top. Line numbers stay
        ; ascending; block order in the TAP matches this sequence.
        ; CODE blocks, in order: overlay #6000, program #8000, static data
        ; #C000. Each carries its own address, so a bare LOAD ""CODE lands
        ; it where it belongs.
        ; Line 30: LOAD ""CODE  (overlay)
        db #00, #1E                 ; Line number (30)
        dw line30end - line30start
line30start:
        db #EF                      ; LOAD
        db '"', '"'                 ; ""
        db #AF                      ; CODE
        db #0D
line30end:

        ; Line 35: LOAD ""CODE  (program)
        db #00, #23                 ; Line number (35)
        dw line35end - line35start
line35start:
        db #EF                      ; LOAD
        db '"', '"'                 ; ""
        db #AF                      ; CODE
        db #0D
line35end:

        ; Line 37: LOAD ""CODE  (static data)
        db #00, #25                 ; Line number (37)
        dw line37end - line37start
line37start:
        db #EF                      ; LOAD
        db '"', '"'                 ; ""
        db #AF                      ; CODE
        db #0D
line37end:

        ; Line 40: LOAD ""SCREEN$  (image last: covers all previous messages)
        db #00, #28                 ; Line number (40)
        dw line40end - line40start
line40start:
        db #EF                      ; LOAD
        db '"', '"'                 ; ""
        db #AA                      ; SCREEN$
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

        ; Generate TAP. Block order must match the BASIC loader: the splash
        ; screen is last so it covers the loader messages.
        emptytap "netmanzx.tap"
        savetap "netmanzx.tap", BASIC, "netmanzx", basic_start, basic_end - basic_start, 10
        savetap "netmanzx.tap", CODE, "overlay",  tap_overlay, tap_overlay_end - tap_overlay, #6000
        savetap "netmanzx.tap", CODE, "netmanzx", text, program_end - text, text
        savetap "netmanzx.tap", CODE, "data",     #C000, static_data_end - #C000, #C000
        savetap "netmanzx.tap", CODE, "splash",   splash_scr, 6912, #4000

    ELSE
        ; ============================================
        ; Standard +3DOS format
        ; ============================================
        IFDEF UNO
dos_overlay_source:
        DISP #6000
dos_overlay:
        module UI
        include "modules/diag-ui.asm"
        include "modules/quit-ui.asm"
        endmodule
        UNDEFINE DIAG_STRINGS_OVERLAY
        DEFINE UI_DIAG_STRINGS_PASS
        include "modules/ui-strings.asm"
dos_overlay_end:
        ASSERT dos_overlay_end <= #8000
        ENT
        ENDIF
dos_payload_end:
        ASSERT dos_payload_end <= stack_top - 64
        save3dos "netmanzx.cod", text, dos_payload_end - text
    ENDIF

    ENDIF   ; NEXT

    ; Overlay modules also allocate runtime state.
    ASSERT rt_ptr <= stack_top - 64
