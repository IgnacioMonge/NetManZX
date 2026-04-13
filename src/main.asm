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
    DEFINE V 143
    DEFINE VSUB 2

; Platforms with esxDOS (SD card file I/O)
    IFDEF UNO
        DEFINE HAS_ESXDOS
    ENDIF
    IFDEF NEXT
        DEFINE HAS_ESXDOS
    ENDIF

; Global constants
buffer = #C100
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

text
    jp start

; Config valid flag — MUST be in bank 2 (#8000-#BFFF), not paged memory
cfg_valid        db 0

    include "modules/display.asm"
    include "modules/wifi.asm"
    include "modules/version.asm"    ; generates VERSION_STRING from V
version_string:
    db VERSION_STRING, 0
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

start:
    ; Zero printer buffer (128K/Next ROM leaves garbage that corrupts
    ; our variables stored there: debug_log, log_ind_data, etc.)
    ld hl, #5B00
    ld de, #5B01
    ld (hl), 0
    ld bc, 255
    ldir

    ld (saved_sp), sp
    ld sp, stack_top

    call UI.init            ; Initialize full screen (IP: Scanning...)

    IFDEF HAS_ESXDOS
    ; Pre-load saved config (enables saved network highlight in list).
    ; esxDOS rst $08 can scribble over printer buffer #5Bxx scratch;
    ; restoreAfterFileIo rearms log indicator, autoscan/health tick
    ; counters and async buffer indices so the subsequent putStrLog
    ; calls and uiLoop start from a clean state.
    call Config.load
    call UI.restoreAfterFileIo
    jr c, .noCfg
    ld a, 1
    ld (cfg_valid), a
.noCfg
    ENDIF

    ; Show log message
    ld hl, .msg_checking
    call Display.putStrLog

    ; Initialize UART
    ld hl, .msg_preparing
    call Display.putStrLog
    call Uart.init

    IFDEF NEXT
    ; Baud rate auto-detection: try AT at 115200, scan if no response
    call Wifi.flushInput
    ld hl, Wifi.S_AT : call Wifi.espSendZ
    call Wifi.checkOkErr
    jr nc, .baudOk

    ; No response at 115200 — scan common baud rates
    ld hl, .msg_baud_scan
    call Display.putStrLog
    call UartImpl.baudScan
    jr c, .baudScanFail

    ; Found ESP at wrong baud — switch to 115200 for this session only
    ld hl, .msg_baud_fix
    call Display.putStrLog
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
    call Display.putStrLog
    call UartImpl.espHardReset
    call Uart.init              ; Reinit UART at 115200
    call Wifi.flushInput
.baudOk:
    ENDIF

    ; Exit transparent mode (if SpecTalkZX or similar left it active)
    ; Requires 1s of prior silence (satisfied: we just started)
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
    call Display.putStrLog
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
    call Display.putStrLog
    
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
    call UI.updateWifiStatus_q  ; Switch from Scanning to Connected (no render)
    call UI.ipShowConnected     ; Show IP (single render)
    
    call UI.showConnectedDialog
    jr nc, .forceScan       ; User chose 'Y' (Reconfigure) -> Scan

    ; User chose 'N' (Keep) -> Diagnostics directly
    jp UI.showDiagnostics

.notConnected
    ; --- Update top and bottom bars ---
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
    call UI.renderList

    ld b, 5                 ; 5 attempts

.scanLoop
    push bc

    ; Only clear network area + show scanning (menu stays visible)
    call UI.clearNetworksArea
    ld a, 17 : ld hl, UI.rescan.scanning_msg : call UI.printAt0

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
    call Display.clrscr
    ld hl, .msg_err_init
    call Display.putStr

.waitExit
    ld hl, .msg_exit
    call Display.putStr
.k  halt
    call Keyboard.inKey
    and a
    jr z, .k
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

; String constants
.msg_checking   db "Checking...", 13, 0
.msg_preparing  db "UART init...", 13, 0
    IFDEF NEXT
.msg_baud_scan  db "Scanning baud rates...", 13, 0
.msg_baud_fix   db "Setting ESP to 115200...", 13, 0
.msg_hw_reset   db "Resetting ESP module...", 13, 0
.at_uart_cur    db "AT+UART_CUR=115200,8,1,0,0", 13, 10, 0
    ENDIF
.msg_query_status db "Checking WiFi status...", 13, 0
.ssid_unknown     db "(unknown)", 0
.msg_init_wifi  db "Initializing WiFi module...", 13, 0
.msg_err_init   db "WiFi Init Failed", 0
.msg_exit       db " Press key", 0
.msg_esp_timeout db "ESP not responding, retrying...", 0
.msg_no_networks db "No networks found, retrying...", 0
.msg_log_timeout db "Scan failed: ESP timeout", 13, 0
.msg_log_empty   db "Scan complete: no networks", 13, 0

; Variables in printer buffer (set before use)
.scan_fail_reason = #5B39
saved_sp = #5B3A  ; dw

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
        SAVENEX AUTO                ; Save all modified pages
        SAVENEX CLOSE

    ELSE

    IFDEF TAP
        ; ============================================
        ; Full TAP format (loader + code)
        ; ============================================

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

        ; Line 20: LOAD ""CODE
        db #00, #14                 ; Line number (20)
        dw line20end - line20start
line20start:
        db #EF                      ; LOAD
        db '"', '"'                 ; ""
        db #AF                      ; CODE
        db #0D
line20end:

        ; Line 30: RANDOMIZE USR 32768
        db #00, #1E                 ; Line number (30)
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

        ; Generate TAP
        emptytap "netmanzx.tap"
        savetap "netmanzx.tap", BASIC, "netmanzx", basic_start, basic_end - basic_start, 10
        savetap "netmanzx.tap", CODE, "netmanzx", text, program_end - text, text

    ELSE
        ; ============================================
        ; Standard +3DOS format
        ; ============================================
        save3dos "netmanzx.cod", text, program_end - text
    ENDIF

    ENDIF   ; NEXT