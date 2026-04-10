# NetManZX Development Changelog

## v1.4.3 (2026-04-10)
Changes from v1.4.2:

### Bugs Fixed (from Gemini/ChatGPT audit, validated by Claude)
- **Hidden SSIDs break `connectedSSIDPresentInList`**: Empty SSID entry (hidden network) caused early abort of the search loop, falsely reporting connected network as missing. Now skips empty entries and continues scanning
- **Hidden networks selectable via ENTER send empty SSID**: Pressing ENTER on a hidden network in the list sent `AT+CWJAP="","pwd"`. Now redirects to the manual SSID entry flow
- **`handleGotIP` overridden by failed `checkConnection`**: Async GOT IP event set `is_connected=1`, but the follow-up SSID query could clear it on failure. Now preserves connection state if SSID query fails
- **ECN >= 6 displayed as "Open"**: Unknown encryption values (WPA3 on ESP32) were mapped to "Open" in the detail screen. Now shows "Unknown"
- **Password renderer overflow at column 42**: Full-length password (40 chars) + cursor + trailing spaces could wrap past column 42 into the next row. `piClrTail` now clamps to column 41
- **`force_rescan` ignores scan failure**: After disconnect, the forced rescan did not check `getList` result. On failure, cursor/offset were adjusted against stale data. Now skips adjustment and repaints existing list
- **`doAutoRescan` ignores scan failure**: Background autoscan did not check `getList` result. On failure, `invalidateConnectedIfMissing` ran against stale data, potentially marking the network as disconnected. Now skips invalidation on failure
- **`getConnectionInfo` does not clear `ip_buffer`**: New routine cleared gateway/mask/MAC buffers but not `ip_buffer`. If AT+CIFSR failed, stale IP was shown in connection info screen
- **`ipShowConnected` falls to "Disconnected" on `getIP` failure**: When `handleGotIP` confirmed connection but `getIP` failed (timing), status bar showed "IP: Disconnected" despite being connected. Now shows "IP: ---" as neutral fallback
- **IX flags corruption in connection result**: Both connection paths (normal and manual SSID) preserved `checkOkErrLong` carry flag in IX across `Display.putStrLog` calls, but `drawC` destroys IX. Connection could branch wrong (success as failure or vice versa). Now stores result in RAM variable
- **`checkConnection` destructive on probe failure**: Query failure cleared `connected_ssid` and `is_connected`, breaking health-checks and `handleGotIP`. Now returns CF without mutating state; callers decide whether to mark disconnected
- **`doAutoRescan` falsely invalidates hidden/missing networks**: Auto-rescan called `invalidateConnectedIfMissing` which could mark a hidden or temporarily absent AP as disconnected. Removed: async DISCONNECT detection is the correct mechanism
- **WPS timeout too short**: WPS enrollment can take up to 120s but used normal long timeout (~30s). Now retries `checkOkErrLong` up to 4 rounds (~120s total) with BREAK check between rounds
- **`reset` ready detection matches partial string**: Matched `eady` instead of full `ready`, risking false match on stray data. Now matches `r`, `e`, `a`, `d`, `y` in sequence
- **SSID copy over-reads past null terminator**: Connected SSID was copied with fixed 33-byte LDIR, reading past the logical string end. Now uses bounded `copyStringZ` that stops at null
- **Ghost network row on rescan**: `clrNetworksOnly` cleared lines 6-14 (9 rows) but `PER_PAGE=10` draws networks on lines 6-15. When rescanning with fewer networks, the 10th row (line 15) was never erased. Extended pixel and attribute clearing to cover all 10 rows (lines 6-15)
- **Scroll indicators invisible**: Arrow characters 24/25 were outside the font range (ASCII 32-127), so `decompressChar` mapped them to space. Repurposed `{`/`}` glyphs as down/up arrows
- **Full screen repaint on page change**: `pageUp`/`pageDown`/`cursorUp`/`cursorDown` page-scroll all called `renderListAndLoop` which redraws help text (rows 3-5). Now uses `renderPageAndLoop` → `renderListOnly` (only rows 6-17)
- **Scroll indicators on wrong row**: Arrows were on row 16 (above "X networks detected") instead of row 17. Moved to row 17 and changed call order: `showPageInfo` before `showScrollIndicators`
- **Password cursor ghost digits**: Cursor LEFT/RIGHT (CAPS+5/CAPS+8) produced ghost digits '5'/'8' when CAPS SHIFT was released before the digit key. Now reads keyboard matrix port directly (`in a, (#FE)`) to wait for physical key release before accepting new input
- **Password cursor rendering**: LEFT/RIGHT now use full field redraw (`.piRedraw`) instead of fragile incremental 2-cell update, matching the robust approach used by the SSID editor
- **Disconnect screen flicker**: Second `topCleanAlertMsg` for "Disconnected" cleared all rows 2-17 causing flash. Now clears only rows 3-4 before redrawing the message
- **Cancel screen auto-dismiss on 128K**: `showCancelledScreen` debounce loop didn't drain BASIC_KEY, allowing residual keypresses to dismiss the screen. Now calls `inKeyNoWait` during drain
- **exitProgram unsafe on Next**: Always used `ld sp,(saved_sp) / ret` which is invalid for .nex (no return address). Now uses `rst 0` on NEXT builds to return to NextZXOS
- **Config save with stale password**: If app started already connected (no password entry), pressing C → Save would write uninitialized pass_buffer. Now checks pass_buffer is non-empty before offering save
- **Config version not validated**: `Config.load` checked signature and checksum but not CFG_VERSION byte. Now rejects incompatible config file versions
- **WPS timeout comment**: Corrected "~30s per round" to "~21s per round" (actual LONG_TIMEOUT_BLOCK timing)

### Enhancements
- **Baud rate auto-detection (Next only)**: If the ESP doesn't respond at 115200, scans 1152000, 9600, and 57600 baud using video-timing-aware prescaler tables. When found, permanently fixes to 115200 via `AT+UART_DEF` + `AT+RST`. Handles NextSync leftovers, factory ESPs, and user misconfigurations. Zero overhead on normal boot
- **Network name in connecting screen**: "Connecting to..." / "Reconnecting to..." now shows the SSID in double-height yellow text, with attempt counter. Overflow guard for long SSIDs
- **Audible key click**: Key click changed from barely-audible single pulse to clear 8-cycle burst at ~3.4 kHz. Affects all key input
- **Connection info screen**: Pressing ENTER on the already-connected network now shows full connection details: IP address (AT+CIFSR), gateway and netmask (AT+CIPSTA? with AT+CIPSTA_CUR? fallback), and MAC address (AT+CIFSR). Fields show "-" if the query fails (firmware compatibility)
- **Band indicator in network detail**: Channel line now shows "(2.4 GHz)" or "(5 GHz)" derived from the channel number (1-14 = 2.4, 15+ = 5)
- **Connection failure diagnostics**: The "Connection failed!" screen now shows the specific failure reason from the ESP error code: timeout, wrong password, AP not found, or connection refused
- **NEX format for Next**: Next build now generates native `.nex` file instead of `.tap`, eliminating the NextZXOS mode selection menu. Exit uses `rst 0` to return cleanly to NextZXOS
- **Save & Reconnect (C key, UNO/NEXT only)**: New `config.asm` module saves WiFi credentials to `/SYS/CONFIG/NETMAN.CFG` via esxDOS. Press C from main menu to reconnect to saved network or save current connection
- **Save prompt on connection success**: "(S)ave to file or any key to exit..." after successful connection (UNO/NEXT only)
- **Saved network in Config Summary**: Diagnostics → Config Summary now shows saved network SSID (or "(none)") on UNO/NEXT builds
- **Footer text improvements**: Connected mode footer now shows full "D:Diagnostics" instead of truncated "D:Diag"
- **`make all` includes AY**: Target `all` now builds all three platforms (UNO + AY + NEXT)

### Code Size Optimization (-1008 bytes net vs v1.4.2)
- **`connectAndReturn` shared routine**: 3 identical connection retry loops → one shared routine (-539 bytes)
- **`printAt0` helper**: 58 instances of `gotoXY0` + `putStr` → `printAt0` (-160 bytes)
- **`pressKeyReturnList` / `pressKeyReturnDiag` / `waitKeyReturnDiag`**: 13 inline wait+jump sequences → shared helpers (-48 bytes)
- **`waitAnyKey` shared**: 8 inline halt+inKey loops → shared routine (-32 bytes)
- **`stretchRowPair` generic**: 4 stretch functions (69 bytes) → 1 generic helper + 4 stubs (-31 bytes)
- **LDIR merge in `getConnectionInfo`**: 4 clear loops → single LDIR over 69 contiguous bytes (-27 bytes)
- **`EspCmd` macro → `espSendZ`**: 3 inline expansions → calls to existing strings (-24 bytes)
- **`logIfEnabled` helper**: 3 debug_log check blocks → helper, dead push/pop removed (-18 bytes)
- **`debounce15` helper**: 5 identical drain loops → shared routine (-16 bytes)
- **`setBaudFromTable` (Next)**: init and tryFastBaud share baud setup (-16 bytes)
- **`setPassRows8` helper**: 4 identical setRowsColor calls → helper (-15 bytes)
- **`doReconnect` tail merge**: Two identical branches merged (-15 bytes)
- **`topCleanAlertMsg`**: 4 instances factored (-12 bytes)
- **Redundant `ld iy,#5C3A`**: 4 unnecessary reloads removed from esxDOS calls (-12 bytes)
- **`getSSIDAtCursor` helper**: 3 address calculations → shared routine (-10 bytes)
- **Other micro-optimizations**: Redundant instructions, tail calls, shared epilogues, factored constants (-37 bytes)

---

## v1.4.2 "Absolution"
Changes from v1.4.1:

### Bugs Fixed
- **BREAK key interpreted as space in input fields**: Pressing BREAK (CAPS SHIFT + SPACE) in password, SSID, IP, or ping input could insert a space character instead of cancelling. Two causes: (1) `checkBreak` read hardware ports but didn't clear the stale SPACE (32) that the ROM interrupt writes to BASIC_KEY; (2) BREAK was only checked after all 4 HALT frames, so brief presses or early CAPS SHIFT release went undetected. Fix: `checkBreak` now clears BASIC_KEY when BREAK is detected, and all 4 input loops (`passwordInput`, `manualSSID`, `pingIP`, `ipTextInput`) now check BREAK every frame inside the HALT loop instead of only after it
- **Password visible in UART log**: When connecting with password and log enabled, `espSendZ` checked `Wifi.debug_log` (not muted) and logged the password via `logTxMasked` which only masks strings starting with "AT+CWJAP". Now both `Uart.log_enabled` and `Wifi.debug_log` are saved/muted before AT+CWJAP send and restored afterwards. Fixed in both connection paths (normal and manual SSID)
- **`byte_limit` never decremented in `checkOkErrCommon`**: The 2000-byte safety limit meant to prevent infinite loops when parsing ESP responses was initialized and checked but never decremented, making the protection dead code. The loop could only exit via UART timeout. Now decremented on every byte read
- **Startup log messages persist on screen**: Init messages ("Checking...", "UART init...", "Checking wifi status...") remained in the log area (rows 20-23) after startup if UART log was disabled, since no traffic would scroll them off. Now cleared by scrolling the log area 4 times after the network list is rendered
- **ZX-Uno UART byte lost on receive**: `uartWrite` interrupt could set `is_recv=1` before reading the incoming byte, causing it to be overwritten by the next byte. Now reads the byte immediately into `byte_buff` before signaling
- **Next UART register corruption in uartWrite**: BC, DE not preserved across uartWrite, could corrupt caller registers. Now push/pop BC, DE
- **128K/Next ROM leaves garbage in printer buffer**: Variables stored in #5B00-#5BFF (debug_log, log_ind_data, etc.) could start with garbage values from the 128K ROM. Now zeroed with LDIR at startup
- **`log_overflow` variable was redundant**: Overflow flag in uart-common.asm was set but never used for recovery. Removed; overflowing chars are now silently discarded

### Enhancements
- **Extended WiFi scan**: Uses `AT+CWLAP=,,,,200,1500` (200-1500ms dwell time per channel) for more consistent network discovery. Falls back to basic `AT+CWLAP` if the ESP firmware returns ERROR (unsupported)
- **Scan parser CR/LF fix**: CR/LF characters in the scan response now return to `loadList` (long timeout) instead of staying in `.continueLoad` (medium timeout), preventing premature timeouts during extended scans
- **Disconnect confirmation in double-height**: "Disconnect from WiFi?" now rendered in double-height red text (rows 3-4) using `showBigMessage`. Y/N prompt moved to row 6
- **"Disconnecting..." feedback**: Immediate double-height red message shown after pressing Y in disconnect dialog, before the 2-second ESP wait. Replaces frozen screen during disconnect
- **Connect: "Press any key" timing fixed**: Message now appears after IP lookup completes, not before. Previously the prompt showed during the 1-3s IP retry loop, making keypresses appear unresponsive
- **Manual connect: screen transition improved**: IP delay now happens before clearing the screen, so the previous screen stays visible during the wait and the result appears all at once
- **Max-length border flash**: Red border flash (2 frames) when typing at max password (40 chars) or SSID (32 chars) length. Consistent with AY driver border flash style
- **`showPressKeyAt(row)`**: New parametric version of `showPressKey` for arbitrary rows. 4 inline sites unified, all now use consistent yellow attribute. `showPressKey` (row 17) falls through to `showPressKeyAt`
- **UART log: always-visible RX results**: `<< OK`, `<< ERROR`, `<< FAIL` messages now always appear in the log area regardless of LOG toggle state. TX command logging (`>> AT...`) remains gated by `debug_log` (LOG ON only) to protect passwords and reduce noise
- **"Keep connection" goes to diagnostics**: When user chooses "No" (keep) at the already-connected startup dialog, now opens diagnostics screen instead of exiting to BASIC
- **Left/right arrow keys**: KEY_LEFT (8) and KEY_RIGHT (9) added to keyboard.asm for cursor navigation
- **AY driver tail call**: `call setSpeed : ret` → `jp setSpeed` in init (-1 byte)
- **ZX-Uno uartWrite preserves registers**: BC, DE, HL now saved/restored across uartWrite

### Performance
- **`drawC` mask table lookup**: Replaced mask rotation loop (~150T avg) with 8-byte precomputed lookup table (~40T). Masks for all 4 pixel offsets (0,2,4,6) stored as constant pairs
- **`drawC` unrolled shift dispatch**: Replaced per-scanline rotation loop (avg 166T×8=1328T) with unrolled `SRL H : RR L` chain using self-modifying `jr` dispatch. Fall-through layout: shift6→shift4→shift2→shift0. Average cost now 60T×8=480T (~64% faster)
- **`drawCBig` same optimizations**: Mask table shared with `drawC`, shift chain in `.writeOnePair`. Same ~960T savings per double-height character
- **`decompressChar` fast LUT**: `font_lut` aligned to 16 bytes (ALIGN 16). High byte of HL loaded once per packed byte, low byte indexed directly. Eliminates full 16-bit HL addition per nibble. ~180T saved per character
- **`putStr` fast path**: Inlined `putC` coordinate logic. Loads coords into BC once, updates C (column) directly, stores BC to `drawC.coords` via `ld (nn), bc`. Eliminates per-character memory load/store overhead. ~42T saved per character
- **Password/SSID shift loops optimized**: All 4 shift loops (`.piShR`, `.piShL`, `.ssidShiftRight`, `.ssidShiftLeft`) now maintain HL across iterations instead of recalculating `buffer + index` each time. 97 → 56 T-states per iteration (~42% faster)
- **`sortNetworks` inner loop optimized**: HL pointer to `display_indices` maintained across iterations, `sort_index` variable eliminated. Saves ~75 T-states per comparison
- **Total rendering speedup**: ~1180 T-states saved per character (~47% faster). Full screen render reduced from ~14 frames to ~7.5 frames

### Code Quality
- **Dead code removed**: `ATTR_PASS_LINE` constant (zero references)
- **Magic number attributes replaced**: 21 raw octal attribute values replaced with 6 new named constants (`ATTR_NORMAL`, `ATTR_NORMAL_DIM`, `ATTR_ALERT`, `ATTR_STATUS_DISC`, `ATTR_STATUS_CONN`, `ATTR_INPUT_LINE`) plus reuse of existing constants (`ATTR_SSID_INPUT`, `ATTR_RSSI`, `ATTR_PASS_INPUT`)
- **Section separators standardized**: All files now use `; ============================================` (44 `=`). Replaced dash variants (30/44/60/65 dashes) across next.asm, uart-common.asm, wifi.asm, ui.asm, main.asm
- **Code label naming standardized**: 38 snake_case code-flow labels renamed to camelCase across wifi.asm (9), main.asm (18), ui.asm (11). Data labels (`.msg_*`, `.cmd_*`) intentionally kept as snake_case for visual distinction

---

## v1.4.1 "Sharp Eye"
Changes from v1.4.0:

### Bugs Fixed
- **Open network connects without confirmation**: Selecting an open network went straight to connection, disconnecting immediately. Now shows network detail + "(Y)es connect / (N)o cancel" confirmation dialog
- **UART log enabled by default**: `log_enabled` was `db 1`, now `db 0`. Users can still toggle with L key
- **"Press a key" inconsistent in Already Connected screen**: Used `gotoXY 0, 13` with plain text instead of `showPressKey` (row 17, yellow, standard convention)
- **"Press any key" inconsistent in WPS screen**: Same issue — now uses `showPressKey` for consistency
- **`showConnectedSuccessScreen` was a dead loop**: If user chose "No" (keep connection) at startup, entered `halt : jr .deadLoop` with no exit. Now exits cleanly to BASIC via `exitProgram`
- **Next driver missing `tryFastBaud`**: Reverted driver lacked baud recovery routine needed by main.asm NEXT build. Re-added `tryFastBaud` to fix compilation
- **L key only toggled `debug_log`, not `log_enabled`**: Two separate variables controlled logging. Now L toggles both in sync, so the UART log actually shows traffic when enabled

### Enhancements
- **Autoscan visual indicator**: Shows hourglass glyph (^) at row 17 col 0 during automatic background rescan, cleared by `renderListOnly` afterwards
- **Hourglass custom glyph**: New 6px font glyph for `^` character — hourglass shape for scanning feedback
- **Log indicator**: Small red filled circle at row 23 byte 31 (bottom-right of log area). Flicker-free: indicator data is integrated into the scroll loop per-scanline, so it's never absent from the screen. Red ink attribute when ON, normal log color when OFF
- **L key works globally**: Log toggle (L) now works in main menu, diagnostics menu, connection success/fail screens, WPS wait, and "not connected" dialog. Blocked in "Already connected" Y/N dialog. Main menu shows "UART log: ON/OFF" message; other screens toggle silently
- **Ping display improved**: "Pinging IP..." now rendered in double-height on rows 4-5. "Pinging " in white, IP address in bright green. 8 chars × 6px = 48px = 6 cells boundary — no color clash

### Code Quality
- **All comments translated to English**: Complete audit and translation of all Spanish comments across all 10 source files (main.asm, display.asm, wifi.asm, ui.asm, uart-common.asm, keyboard.asm, version.asm, next.asm, zxuno.asm, ay.asm)
- **Comment quality improved**: Removed redundant/obvious comments, fixed inconsistent styles (;; → ;), improved function documentation headers
- **Dead code removed**: `showConnectedSuccessScreen` body (dead loop + messages), `toggleDebugLog` from main menu (now handled globally via `toggleLogQuiet`), `.msg_wps_key` string
- **Version bumped to 1.4.1**

### Size Comparison (program_end)
| Target | v1.4.0 | v1.4.1 | Delta |
|--------|--------|--------|-------|
| UNO    |        |        |       |
| AY     |        |        |       |
| NEXT   |        |        |       |
