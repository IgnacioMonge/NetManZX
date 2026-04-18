# NetManZX Development Changelog

## v1.4.4 (2026-04-18)
Changes from v1.4.3.1:

### New Features
- **Boot splash screen on all targets**: NetManZX now paints a loading screen before the UI appears. Next: 48 KB Layer 2 image (`assets/splash.nxi`) painted by the NEX loader, with custom 9-bit palette loaded from a dedicated 8 KB page (`SPLASH_PAL_BANK=24`) — runtime saves the current slot-6 bank via NextReg $56 read, maps the palette bank, streams 512 bytes through NextReg $44 (autoinc), restores the prior bank. The NextReg select+read pair is wrapped in `DI`/`EI` so the 50 Hz ROM handler cannot clobber the selected register between the `out` and the `in`. UNO/AY: 6912-byte SCR (`assets/splash.scr`) staged at #E000 in assembly memory, emitted as a separate TAP CODE block at load address #4000. BASIC loader rewritten to hide ROM `Bytes: ...` messages (`BORDER 0: PAPER 0: INK 0` before both LOADs) and now runs `LOAD ""SCREEN$` + `LOAD ""CODE` + `RANDOMIZE USR 32768`. At startup we `ld iy, #5C3A` as insurance against loaders that leave IY elsewhere (ROM IM 1 handler crashes otherwise)
- **Status messages rendered on splash, not in log area**: init-time strings (`Checking...` / `UART init...` / `Probing ESP...` / `Scanning baud rates...` / `Setting ESP to 115200...` / `Resetting ESP module...` / `Configuring ESP...` / `Checking WiFi status...` / `Initializing WiFi module...`) now appear centered on ULA row 20 in white INK on black PAPER, rendered with the existing 6 px font via new `splashInit` / `splashMsg` / `splashEnd` helpers in `main.asm`. Each message clears row 20 pixels and recomputes `col = (42 - len) / 2` so successive messages don't ghost. On Next the Layer 2 clip window (NextReg $18 with `$1C` bit 0 reset, 4-write sequence X1/X2/Y1/Y2, Y2=159) hides L2 below pixel row 159 so the ULA message strip shows through from under the splash image. On UNO/AY the SCR already lives in ULA, so rows 20-23 are overwritten directly. `splashInit` also sets a `Display.splash_mode` flag that short-circuits `Display.putStrLog`, silencing all internal Wifi/UART log writes while the splash is up (otherwise they would try to scroll the main-UI log area over the splash). After init succeeds, a shared `.enterMainUi` helper runs `Config.load` (esxDOS platforms) + `UI.restoreAfterFileIo` + `splashEnd` (clears `splash_mode`, restores L2 clip to full 0..191, clears the L2 visible bit in port `$123B` on Next) + `UI.init`, then the main menu appears and the first scan kicks off. On init failure (`.initFailed`) the error is shown centered on row 20 and the splash stays up until any key — no `Display.clrscr` on the error path. Removed the old 2 s post-splash hold loops (redundant now that init itself provides the visibility window) and the `.msg_exit` / `.msg_err_init`-in-clrscr error pattern. `buffer` base moved `#C100` → `#C200` (+256 B code budget) to fit the new helpers. A follow-up audit added `DI`/`EI` around the NextReg select+read pair inside `setBaudFromTable` (drivers/next.asm) for the same IRQ-race reason as the palette loader

### Bugs Fixed
- **BREAK on "Connected!" screen crashed to BASIC with "L BREAK into program, 50:1"**: `connSuccessScreen.cssWait` explicitly called `Keyboard.checkBreak : jp z, exitProgram` in its input loop, so pressing CAPS+SPACE on the success screen invoked the UNO/AY exit path (`ld sp,(saved_sp) : ei : ret`) while CAPS+SPACE was still held. BASIC resumed with the BREAK latch set and raised `L BREAK into program, 50:1`. On Next the same path ran `rst 0` and fell back to NextZXOS with an ambiguous exit. Removed the BREAK-exit shortcut entirely — on a post-connection success screen it is the wrong affordance (the user just succeeded; there is no "cancel"). `inKeyNoWait` naturally ignores BREAK because BREAK is a keyboard-matrix read, not a `BASIC_KEY` code, so the loop simply keeps waiting for any other key or the documented `S`/`L` shortcuts
- **Async DISCONNECT events dropped before reaching handler** (from ChatGPT audit Z80-01): `checkPatternCommon` in `ui.asm` returned `Z=1` on both the found and not-found paths because the SMC sequence `ld a, 0 / .eventCode = $ - 1 / ret` does not touch flags — `Z` stayed pegged from the earlier `xor a`. `checkAsyncWifi` expected `NZ` to mean "pattern found" and fell through to the GOT-IP check on real `"DISCON"` matches, so `handleDisconnect` was never called and link loss left `Wifi.is_connected`, SSID, and status bar stale until a later polling path corrected them. Added `or a` after the SMC slot to set `NZ` when the event code is non-zero
- **UNO/AY exit stack pointer corrupted by esxDOS file I/O** (from ChatGPT audit Z80-02): `saved_sp` lived at `#5B3A`, inside the printer buffer that `Config.load` / `Config.save` via `rst $08` explicitly declares volatile — and `UI.restoreAfterFileIo` did not re-arm it. After any config I/O, the non-NEXT exit path (`ld sp, (saved_sp) : ei : ret`) could read garbage and return to BASIC with a corrupted stack pointer, jumping into undefined memory. Moved `saved_sp` out of `#5B00-#5BFF` entirely into an RTVAR at `#C000+`. `.scan_fail_reason` stays at `#5B39` (boot-only scratch, no file I/O between set and read)
- **Failed rescan destroyed the previously stable network list** (from ChatGPT audit Z80-03): `getList` called `clearScanBuffers` on the first `+CWLAP` — which LDIR-wiped the whole 825-byte SSID buffer — before any AP record was fully committed. Any later timeout in `.loadAp` went straight to `.scanTimeout` with no rollback, so a scan that failed after the first partial result replaced the old list with partial or empty data. Split the routine: new `resetScanPointers` only resets `buff_ptr` / `rssi_ptr` / `ecn_ptr` / `chan_ptr` / `networks_count` without touching buffer bytes, and the first `+CWLAP` now calls it instead of the full wipe. Old SSID bytes beyond the live count remain latent in memory (masked by `networks_count`); new APs overwrite from slot 0. Mid-scan timeout now shows the partial new list (or nothing, if no AP was parsed yet) instead of a full wipe. `clearScanBuffers` is retained for the confirmed 0-networks success path (OK with no `+CWLAP`)
- **WPS "too-short timeout" + false successes + empty list after fail**: Three coupled bugs in `doWPS`. (1) `AT+WPS=1` ack-es `OK` immediately (enters WPS mode), the old code treated that as WPS completion and ran `checkConnection` before the user could press the router button → almost-zero effective wait. (2) With `CWAUTOCONN=1` and `SYSSTORE=1`, the ESP silently re-joined the last flash-saved AP in the background → the next WPS attempt reported "connected!" without any WPS actually happening. (3) On failure, `Wifi.reset` was called but not the full `Wifi.init`, so `ATE0`/`CWMODE`/`CWAUTOCONN` were not re-sent after `AT+RST` — subsequent `getList` saw echoed `AT+CWLAP` lines and returned an empty list. Rewrote `doWPS` end-to-end: wraps the whole flow in `SYSSTORE=0` (RAM-only) so nothing persists to flash, sets `CWAUTOCONN=0` so background re-join can't spoof success, sends `AT+WPS=1` + real ~60 s polling loop of `checkConnection` with BREAK cancel, restores `CWAUTOCONN=1` + `SYSSTORE=1` on any exit path, and calls full `Wifi.init` on timeout (not plain `reset`)
- **Pre-WPS `AT+CWQAP` wiped flash SSID**: The first cut of the WPS rewrite sent `AT+CWQAP` in pre-WPS to force a clean disconnect. With the initial `SYSSTORE=1` active, `CWQAP` cleared the saved AP credentials from flash — so after a WPS cancel, the next cold boot had nothing to autoconnect to and came up as "IP: disconnected". Removed the `CWQAP` entirely; wrapping in `SYSSTORE=0` is sufficient to keep any change RAM-only
- **WPS cancel left stale IP in status bar**: BREAK during WPS wait cleared `is_connected=0` but didn't touch the IP buffer or re-render the status bar → main menu showed a valid IP next to "WiFi: DISCONNECTED". `ipShowNotConnected` + `updateWifiStatus_q` now run on both cancel and fail paths
- **WPS save prompt on success was nonsense**: WPS success fed into `connSuccessScreen` which on esxDOS offers the user `(S)ave` — but the local `pass_buffer` is empty after WPS (credentials live only in ESP flash), so a save would have written garbage. Reused the existing `is_reconnect` flag (already suppresses the save prompt on the reconnect path) around the WPS success `connSuccessScreen` call
- **Open-network glyph "squashed"** (reported by user): `~` (hollow circle lock indicator for open networks) rendered as 4 rows tall while `` ` `` (filled circle, closed) rendered as 6 — visually shorter by 2 scanlines. Repositioned the packed pattern to use rows 1-6 and added two exception-table entries for rows 2 and 5 (`#44` = `.X...X`) so the ring is symmetric with the filled circle
- **Extended scan hangs on old ESP firmware**: `AT+CWLAP=,,,,200,1500` on ESP firmware v1.5.4 (and similar) returns `OK` with no `+CWLAP` lines instead of `ERROR`. The code ignored the first OK and waited for scan results that never came, causing a long timeout. Now detects OK-without-results during extended scan and immediately falls back to basic `AT+CWLAP` (reported by johnyo)
- **CWMODE=2 after AT+RESTORE blocks scanning**: If the ESP was in AP mode (CWMODE=2, e.g. after `AT+RESTORE`), `getIP` detected the soft-AP IP (192.168.4.1) as a valid connection, skipping initialization. Now forces `AT+CWMODE=1` early in startup before any connection check, with `AT+CWMODE_DEF=1` fallback for old firmware (reported by Hood)
- **ESC key (CS+4) never worked**: All `cp 15` checks relied on BASIC_KEY, which doesn't capture control key codes from the keyboard handler. Replaced with `Keyboard.checkBreak` (CAPS SHIFT+SPACE) in dialogs. No exit key from main menu — reset to leave (reported by Hood)
- **Async DISCONNECT pattern never matched**: `checkAsyncWifi` only compared the last 6 bytes in the circular buffer against "DISCON", but "WIFI DISCONNECT" ends with "ONNECT". Pattern was never found; health-check was the sole disconnect detector (~10 s delay). Now scans all valid buffer positions via shared `scanBuffer` routine
- **AY UART exx imbalance**: `uartRead` returned with shadow registers active (5 unbalanced `exx`), corrupting `poll_block`'s timeout counter. External timeout values (`DEFAULT_TIMEOUT`, `MEDIUM_TIMEOUT`, `LONG_TIMEOUT`) were non-functional on AY. Added `exx` at both return paths to restore main register set
- **AY `write()` push/pop restored wrong registers**: `exx` before `pop bc, de, hl` at end of transmit loop sent pops to shadow set instead of main. Removed the stray `exx`
- **Missing IY reload before M_P3DOS in `createPath`**: `rst $08` / `F_OPEN` may corrupt IY on divMMC. Subsequent `M_P3DOS` call for directory creation used potentially invalid IY. Added `ld iy, #5C3A` before the call (Next only)
- **esxDOS corrupts printer buffer counters**: `Config.save` via `rst $08` may corrupt printer buffer variables. `autoscan_counter`, `health_counter`, and async buffer state are now reset after save
- **BREAK during AT+CWJAP racy** (from Codex audit): `readTimeoutLong` collapsed BREAK and timeout into a single CF=0 exit, so `checkOkErrLong` could not tell them apart. `connectAndReturn` re-read the physical key port afterwards, but the window between read return and check was long enough (log flush, register restore, display output) that users who released BREAK mid-delay got a silent retry instead of a cancel. Fixed with a dedicated `Uart.break_hit` latch set by `poll_block` / `readTimeoutLong` and consumed in `connectAndReturn` before the live re-read. Cancel is now reliable regardless of key release timing
- **`doDisconnect` ignored `AT+CWQAP` result** (from Codex audit): Local state (`Wifi.is_connected`) was cleared and screen redrawn as "Disconnected" even on ESP timeout or ERROR. Now branches to a new "Disconnect failed." red screen on fail and keeps the old state; next `checkConnection` resyncs
- **Empty basic scan misreported as timeout** (from Codex audit): After fallback from extended to basic `AT+CWLAP`, the first OK was skipped as a "stray echo from prior command" and the routine waited for a second OK that never came (0 networks → timeout). ATE0 is sent at boot so the stray-OK skip was dead code. Removed `ok_ignored` entirely; a basic-scan OK without prior `+CWLAP` is now accepted as a valid empty result
- **Volatile `#5Bxx` state not rearmed across all file-I/O paths** (from Codex audit): The `Config.save` success path already restored `autoscan_counter` / `health_counter` / `async_buf_idx` / `async_buf_count` inline, but the save-failure path, `doReconnect`'s `Config.load`, `main.asm`'s startup `Config.load`, and the Connection Status screen's `Config.load` all skipped it — and none of them restored `Display.putLogC_coord` (#5B36) or re-ran `updateLogIndicator`. esxDOS `rst $08` can scribble any of these. Introduced a shared `UI.restoreAfterFileIo` helper (preserves AF so callers can `jr c`) and called it after every `Config.load` / `Config.save` return. Helper also resets the log cursor column so subsequent `Display.putStrLog` starts clean

### UX polish
- **"Already connected to this network!" in bright red**: The detail screen row-15 message (shown when the user selects a network that is already the active connection) was rendered in the default white-on-black and lacked visual emphasis. Now ends in `!` and paints row 15 with `ATTR_ALERT` (bright red INK on black PAPER) to make the "no-op" feedback unmissable
- **Next splash no longer "recolors" a frame later**: The `.nex` loading screen now stores `splash.pal` directly in the `SAVENEX SCREEN L2` block, so NextZXOS shows the Layer 2 splash with its final palette immediately. Previously the loader displayed the image with the default Layer 2 palette first, and `start:` then uploaded `splash.pal`, producing a brief but visible second pass where the same image appeared to repaint itself in different colours
- **Removed "Already connected — Reconfigure?" dialog**: Cold-boot flow now goes straight to the main menu + first scan regardless of connection state. Previously, if the ESP was already joined to an AP from a prior session, `main.asm` called `UI.showConnectedDialog` which asked `(Y)es reconfigure / (N)o diagnostics` and branched. Users found this redundant — the main menu already exposes D:Diagnostics and R:Refresh, so the forced fork was extra friction for no new capability. `.alreadyConnected` now `jr .forceScan` after updating the status bars; `showConnectedDialog` (~40 lines + 3 strings) deleted from `ui.asm`. Net ≈ -150 bytes per target
- **Transient "No networks found." ghost on boot**: First `UI.renderList` ran before the first scan, so `Wifi.networks_count=0` painted `no_net_msg` ("No networks found. Press 'R' to rescan.") on row 6 for one frame before the scan loop cleared the area and showed `Scanning...`. Wrapped the startup render in `ld a,1 : ld (UI.skip_footer),a` + `xor a : ld (UI.skip_footer),a`, reusing the existing flag that `renderListAndLoop` already uses for the same reason. The msg now only appears when an actual scan returned 0 networks
- **"Sweep" of the menu area on first reveal (Next)**: With the old `.enterMainUi` calling `splashEnd` before `UI.init`, the Layer 2 splash vanished first and the user then saw `clrscr` → banner → badge → separator → status bar → `renderList`'s `topClean` → help text → scan setup paint incrementally over ULA. Moved `splashEnd` out of `.enterMainUi` and down into `.forceScan` right after the first `"Scanning..."` string is printed. `UI.init` + `updateWifiStatus` + `ipShow*` + `renderList` + `clearNetworksArea` + scanning msg now all run with L2 still covering, so the splash cuts straight to the fully composed "Scanning" state. `splashEnd` itself is idempotent on subsequent scan-loop passes (sets L2 clip to 0..191 and clears `$123B` bit 1 — already that state after first call). UNO/AY unaffected (no L2 to cover the render)
- **White flash in splash message strip on UNO/AY**: `splashInit` used to set attrs `%00000111` (white INK / black PAPER) before clearing pixels. The SCR splash has pixel content at rows 20-23 (part of the image); for one frame the attribute change made those pixels render as bright white ink on black paper, then the pixel clear blanked them. Now paints attrs `%00000000` first (ink=paper=black, all invisible), clears pixels, then sets only row 20 to `%00000111` in preparation for text rendering. Rows 21-23 stay fully black throughout
- **Splash too brief on Next**: L2 image + palette load + `splashInit` complete in well under a second, so the user never got to see the splash art before status messages started overwriting row 20. Added `IFDEF NEXT` 50-halt hold (~1 s at 50 Hz) between `splashInit` and the first `splashMsg` call. UNO/AY unchanged (boot is slower there due to BASIC loader + separate SCR load)

### Enhancements
- **Baud diagnostics label clarity**: `CUR:` / `DEF:` → `Current:` / `Default:` on the UART baud rate screen
- **UART log muted on entry to every diagnostic handler**: `doPing` / `doModuleInfo` / `doNetworkInfo` already did this, but `doBaudRate` / `doStaticIP` / `doHostname` / `doConfigSummary` did not, so logged AT traffic spilled across their layouts when the user had `L` on. Added `xor a : ld (Uart.log_enabled), a` at entry. Exit already restored the previous state via `showDiagnostics.exitDiag`
- **BREAK polling inside long AT loops**: `doModuleInfo.gmrLoop`, `doNetworkInfo.cifsrLoop`, and `doConfigSummary`'s MAC/hostname/firmware loops now poll `Keyboard.checkBreak` per iteration and exit to `showDiagnostics` on cancel. Previously, a slow or stuck ESP forced the user to wait out the full C/B timeout
- **`showDiagnostics` "Connect first" gate removed**: Baud rate, module info (AT+GMR), static IP config, hostname, and config summary do not require an active WiFi connection and are now accessible from a cold-boot disconnected state. Handlers that truly need a connection (`doPing`, `doNetworkInfo`) fail their underlying AT query naturally with a timeout screen
- **Audible keyclick on diagnostics menu**: The main menu already had `Keyboard.keyClick` after `inKeyNoWait`; `showDiagnostics.diagLoop` now mirrors it for parity
- **Hostname input field in blue, not red**: `passwordInput` with `show_password=1` (visible plaintext) forced `ATTR_PASS_EXPOSED` (bright red on white) as a "password is visible" warning. Hostname is not a secret, so the red warning was misleading. Added `pass_no_warn` flag (default 0, set by `doHostname` around its `passwordInput` call) that forces `ATTR_PASS_INPUT` (bright blue on white) even when `show_password=1`. Reverts to 0 on exit so other password flows are untouched
- **WPS UX polish**: "Press WPS button on router..." prompt now rendered in double-height bright yellow (rows 3-4, `showBigMessage` with `ATTR_CONNECTED`). Footer on row 6 reuses the existing global `msg_break_cancel` string. On cancel, reuses the shared `showCancelledScreen` (red "Cancelled." double-height + press-any-key). On success, reuses the shared `connSuccessScreen` (green "Connected!") so WPS success and manual-connect success look identical. Real WPS polling timeout is ~60 s (40 rounds × ~1.5 s)
- **`WPS timeout!` on real timeout**: Dedicated big-red double-height message (`ATTR_ALERT`) when the ~60 s WPS window elapses without a connection, followed by a standard "Press any key" and return to main menu
- **Baud diagnostics distinguish current vs default speed**: The diagnostics screen no longer shows a single ambiguous "Baud Rate" value. It now queries and prints `CUR` and `DEF` separately when supported, with legacy `AT+UART?` fallback on older firmware. This makes the Next-only session override (`AT+UART_CUR=115200`) visible without implying that flash-stored defaults were changed

### Code Size Optimization
- **`jp` → `jr` sweep** (quick-win pass, no behavior/layout change): converted short-range local jumps in `ui.asm` (`passwordInput` rejects and `.piWait` returns, ping IP input rejects and `.waitIPKey` returns, open-network confirm `.cancel` branches) and in `wifi.asm` (`checkOkErr` dispatcher plus OK/ERROR/FAIL sub-paths where targets fit in ±127). Verified by letting sjasmplus flag out-of-range and reverting only the ones that overflowed
- **Dedup `cmd_cifsr`**: Removed UI-local `.cmd_cifsr db "AT+CIFSR",13,10,0`; network-info path now reuses `Wifi.S_AT_CIFSR` (-11 bytes)
- **Net: -47 bytes per target** (AY/UNO/NEXT all identical, changes are in shared code). NEXT free code space: 93 → 140 bytes

## v1.4.3.1 (2026-04-11)
Changes from v1.4.3:

### Bugs Fixed (from Gemini 2.5 Pro audit, validated by Claude)
- **`copyStringZ` off-by-one buffer overflow**: Loop counter was `MAX_SSID_LEN + 1` (33), so a 32-char string without null terminator would write a safety null at byte 34, overflowing the 33-byte `manual_ssid_buffer` into the next RTVAR. Fixed counter to `MAX_SSID_LEN` (32)
- **`checkAsyncWifi` missed async events on ZX-Uno**: Read only 1 byte per call (every ~80ms), but at 115200 baud full messages arrive in ~1.5ms. On backends without FIFO (ZX-Uno, AY), intermediate bytes were lost and DISCONNECT/GOT IP patterns never matched. Now drains all pending bytes in a loop on each call

### Enhancements
- **Baud scan uses `AT+UART_CUR` instead of `AT+UART_DEF` (Next)**: No longer permanently modifies the ESP's flash-stored baud rate. Sets 115200 for the current session only, respecting existing ESP configuration. Eliminates the 3-second `AT+RST` reboot wait
- **MAX_NETWORKS raised from 20 to 25**: Reduces the chance of missing networks in dense environments (apartment buildings, offices). Each network costs 37 bytes; total increase ~185 bytes in runtime buffers
- **Saved network highlighted in list (UNO/NEXT)**: If a config file exists, the saved SSID is shown in cyan in the network list. Connected network (yellow) takes priority if it's the same. Config is loaded once at startup and also marked valid after saving

### Code Size Optimization
- **`clrNetworksOnly` / `clrListOnly` monolithic LDIR**: The middle screen third (lines 8-15, $4800-$4FFF) is contiguous in memory. Replaced 8-iteration push/pop/ldir scanline loop with a single 2048-byte LDIR in both routines

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
- **Baud rate auto-detection (Next only)**: If the ESP doesn't respond at 115200, scans 1152000, 2000000, 9600, and 57600 baud using video-timing-aware prescaler tables. When found, permanently fixes to 115200 via `AT+UART_DEF` + `AT+RST`. Falls back to hardware ESP reset (NextReg $02) if no known rate matches. Handles NextSync/NextSync-fast leftovers, factory ESPs, and user misconfigurations. Zero overhead on normal boot
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
