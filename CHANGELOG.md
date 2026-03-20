# Changelog

All notable changes to NetManZX are documented in this file.

---

## [1.4.2] - "Absolution" - 2026-03-20

### Bug Fixes - UART Drivers
- **Register corruption in UART write** (next.asm, zxuno.asm): `write` functions destroyed BC, DE, HL without preserving them. Added push/pop to match ay.asm discipline. Prevents intermittent bugs in callers
- **Lost byte during TX on ZX-Uno** (zxuno.asm): `.is_recvF` detected incoming bytes during transmission but never read them from the data port. Now reads and buffers the byte before setting `is_recv` flag
- **Unbounded CPIR searches** (ui.asm): Two uses of `ld bc, #FFFF / cpir` for NUL scanning replaced with `ld bc, BUFFER_SIZE` (660 bytes). Prevents runaway memory scan on corrupted buffers

### Bug Fixes - Connection Robustness
- **Auto-rescan destroyed network list on timeout**: `getList` cleared buffers before confirming scan success. Now clears only on first +CWLAP line, preserving previous data on failure
- **Health-check too fragile**: A single failed `checkConnection` invalidated the WiFi state. Now requires 3 consecutive failures (debounce counter). Also, `connected_ssid` is no longer cleared before confirming disconnection
- **doDisconnect was optimistic**: Sent AT+CWQAP with a fixed 100-halt wait, ignoring the response. Now uses `checkOkErr` for proper verification, consistent with the other 3 disconnect paths
- **SSID input red border flash**: `.ssidClearRest` fell through to `.ssidMaxLen` (red border flash) on every partial redraw. Added `jr .ssidFinishDraw` so the flash only triggers at the 32-char limit

### Bug Fixes - UX Flow
- **3rd retry shown before fail screen**: On the 3rd failed connection attempt, "Retry..." was displayed before jumping to the error screen. Now checks remaining retries before showing Retry
- **BREAK during connection showed "Retry..." flash**: BREAK was only checked during the retry wait loop, after "Retry..." was already on screen. Now checks BREAK immediately after connection failure, before any visual feedback
- **"Cancelled" screen had no debounce**: BREAK key was still held when entering the wait loop, causing immediate exit. Added 15-frame debounce for key release
- **Startup "No" -> Diagnostics -> Back showed no networks**: `showDiagnostics` never returns (uses `jp renderListAndLoop`), so the scan in main.asm was never reached. Now `renderListAndLoop` triggers a fresh scan when `networks_count == 0`
- **"No networks found" flash on return from Diagnostics**: `renderList` displayed "No networks found. Press 'R' to rescan." before the automatic scan started. Added `skip_footer` flag to suppress both that message and the footer during the transitional `renderList` call
- **Hostname input buffer overflow**: `passwordInput` allows up to 40 chars but `hn_buf` is only 21 bytes. Now truncates input to 20 characters before copying

### Visual Enhancements
- **"Connecting (x/3)..." in double-height green**: Connection attempt message now uses `showBigMessage` with bright green color (rows 3-4), with "Press BREAK to cancel" on row 6
- **"Retry..." in double-height red**: Shown on rows 8-9 below the cancel message (attempts 1 and 2 only)
- **Unified connection failure screen**: Both manual and normal routes now share `showConnFailScreen` with big red title + detail text + yellow "Press any key" on row 17. Removes duplicated error dispatch code
- **"Cancelled." screen**: New `showCancelledScreen` with double-height red title and "Press any key" prompt
- **"Disconnected." transition**: Screen drawn before updating status bar, eliminating flicker between "Disconnecting..." and "Disconnected."
- **WPS warning in double-height red**: "WPS requires disconnecting first." now uses `showBigMessage` with `ATTR_ALERT`
- **Hidden Network title in double-height green**: "Hidden Network (Manual SSID)" now uses `showBigMessage` with `ATTR_SSID_INPUT`
- **Manual SSID shown in double-height green**: On the password screen, the entered SSID is displayed in stretched green text (rows 4-5) below "Selected SSID:", matching the normal connection flow
- **Hostname confirmation screen**: After setting hostname, shows "Hostname set to:" with the hostname in double-height green, replacing the old inline "Hostname set OK!" message
- **Consistent "Press any key" positioning**: All modal screens (connect success, fail, disconnect, cancel, hostname) use `showPressKey` at row 17

### Code Cleanup
- **Dead symbols removed**: `scr_addr`, `dcb_rc_top` (display.asm), `log_overflow` (uart-common.asm - written in 4 places, never read), `read:` alias (next.asm)
- **Duplicate ATTR_NORMAL removed**: Two identical definitions consolidated to one
- **Dead error strings removed**: Old multi-line `msg_fail_generic/timeout/password/notfound/connfail` replaced by unified `showConnFailScreen`

### Size Optimization
- **String deduplication**: Shared `msg_yes_anykey` and `at_quote_crlf` labels (-34 bytes)
- **gotoXY0 function**: 72 of 87 `gotoXY 0, Y` macro calls replaced with `ld a, Y : call Display.gotoXY0` (-66 bytes)
- **espSendZ system**: 16 inline `EspCmd`/`EspCmdOkErr` macros replaced with `ld hl, S_xxx : call espSendZ[CheckOk]` using 13 shared AT command strings (-84 bytes)

### Binary Size
- UNO: 14,966 bytes (was 15,245 in v1.4.1, **-279 bytes**)

---

## [1.4.1] - "Sharp Eye" - 2026-03-17

### Bug Fixes
- **Open network connects without confirmation**: Selecting an open network jumped straight to connection. Now shows network detail + confirmation dialog (Y/N)
- **UART log enabled by default**: Log was active on startup, flooding the log window. Now disabled by default (toggle with L)
- **L key only toggled debug messages, not UART log**: Two separate variables controlled logging. Now L toggles both in sync
- **"Press a key" inconsistent**: Already Connected and WPS screens used custom positioning instead of the standard `showPressKey` (row 17, yellow)
- **"Keep connection" was a dead loop**: Choosing "No" at the startup connected dialog entered an infinite `halt` loop with no exit. Now exits cleanly to BASIC
- **Ghost keypress on startup (128K / +3 / Next)**: ROM key repeat left residual values in BASIC_KEY, causing the connected dialog to immediately select "No" and exit. Added 300ms debounce drain before the dialog
- **Next driver missing `tryFastBaud`**: Baud recovery routine was accidentally removed. Re-added for NextSync compatibility

### Enhancements
- **Autoscan indicator**: Hourglass glyph (custom `^` character) shown at row 17 during background rescan
- **Log status indicator**: Small red filled circle at bottom-right of log area when UART log is active. Flicker-free: pixel data integrated into scroll loop per-scanline
- **L key works globally**: Log toggle now works in main menu, diagnostics, connection screens, WPS wait, and error dialogs
- **Ping display**: "Pinging IP..." now rendered in double-height with color (white label, bright green IP address, no color clash)

### Code Quality
- **All comments translated to English**: Complete audit across all 10 source files
- **Comment quality improved**: Removed redundant comments, fixed `;;` → `;`, improved function documentation
- **Dead code removed**: Old dead-loop screen, duplicate toggle handler, unused WPS string

---

## [1.4.0] - "Double Vision" - 2026-03-17

### New Features

#### Double-Height Display System
- **drawCBig / putCBig / putStrBig**: Flicker-free double-height character renderer using pixel-level operations with self-modifying code for mask rotation
- **Double-height everywhere**: Banner, status bar, password input, SSID input, IP input, hostname input, messages, and titles all use the new double-height renderer
- **stretchRows**: Dedicated stretch routines for banner (rows 0-1), titles (rows 3-4), SSID detail (rows 4-5), and status bar (rows 18-19)

#### Network Detail Screen
- **showNetDetail**: New screen shown when selecting a network, displaying SSID in double-height cyan text, security type (WPA2-PSK, WPA-PSK, WEP, Open), WiFi channel number, and signal strength with graphical bars
- **Password input** moved to network detail screen with double-height input field at rows 12-13

#### Visual Enhancements
- **Rainbow badge**: Decorative dither-triangle with color transitions replacing the old banner lines
- **1px separator**: White pixel line at row 2 scanline 0 between banner and content
- **Custom font glyphs**: Filled circle (backtick) and hollow circle (tilde) for locked/open network indicators
- **Status bar anti-flicker**: Direct-overwrite rendering with quiet update variants (updateWifiStatus_q, setStatusCommon_q) for batched single-render updates
- **Status bar text 1px lower**: Scanline 0 of row 18 cleared after stretch for cleaner appearance

#### Compressed Font System
- **Nibble-packed font**: Built-in compressed font with decompressChar, font_packed data, font_lut lookup table, and font_exceptions for special cases
- **No external dependency**: Eliminates the need for external font.bin binary file

#### New Screens and Features
- **About screen** (I key): Shows version (with UART backend), build date (auto-generated via Lua os.date), description, author, GitHub URL, and MIT license
- **WPS confirmation dialog**: When already connected, shows warning "WPS requires disconnecting first" with Y/N choice before proceeding
- **Build date**: Automatically embedded at assembly time via Lua os.date("%d/%m/%Y")

#### BREAK Detection
- **poll_block**: Checks BREAK every 256 iterations (~5ms) for near-instant cancellation during AT command responses
- **readTimeoutLong**: Checks BREAK between blocks (~370ms each) for responsive cancellation during long operations
- **Connection attempts**: AT+CWJAP can be cancelled immediately via BREAK

#### Platform Improvements
- **NextSync baud recovery** (Next build only): Detects if ESP was left at 1152000 baud by NextSync, tries AT at 115200, falls back to tryFastBaud + AT+RST for automatic recovery
- **IP retry on connect**: 3 attempts with 1-second intervals after successful WiFi association
- **flushInput drain limit**: 1024-byte maximum prevents infinite loop when ESP sends continuous data

### Bug Fixes
- **showBigMessage**: gotoXY was destroying HL (text pointer), causing garbage text from ROM
- **showBigMessage**: setAttr clobbers BC, causing row 4 to be invisible (black on black)
- **Color values**: 044o/042o were green-on-green (paper=green, not black) - fixed attribute values
- **Lock/open indicators**: Used chars 7/9 (outside font range) - replaced with custom backtick/tilde glyphs
- **passwordInput fall-through**: .piClrTail fell through into .piSetPos causing immediate return
- **passwordInput register corruption**: Incremental handlers assumed B/C preserved after putCBig - B now reloaded from memory before each call
- **setStatusDisconnected**: Fell through to _q variant (no render) - added explicit ret
- **drawSSIDFull fall-through**: Fell through into drawSSID causing double redraw
- **Password rows**: Rows 12-13 not cleaned on .connect path before showing "Connecting..." message
- **Connecting message**: "Retry" displayed on wrong row
- **.piRedraw corruption**: Called stretchRowPair after putCBig causing double-stretch visual corruption
- **drawCBig third-crossing**: `inc h` replaced with `and #F8 : add a, 8` for correct next-third calculation
- **Network Info wrong data**: Showed wrong network data when connected SSID was not in scan list

### Optimizations
- **Dead code removed** (~70B): clrTop, clearRow18Pixels, stretchRowPair, dcb_rc_bot, rssi_bars
- **RSSI bar rendering deduplicated**: Shared drawRssiBars routine (~45B saved)
- **SSID comparison**: Uses compareStringZ in renderNetworksCommon (~20B saved)
- **clearRowPixels**: Shared LDIR-based row clearing routine (17x faster than putC clearing loops)
- **Blocking read removed**: Unused blocking read routines removed from all three UART drivers (AY, UNO, NEXT)
- **Redundant instructions**: Removed unnecessary `or a` after `and a`, dead computations, and redundant push/pop pairs

---

## [1.3.0] - "Clean Sweep" - 2026-03-07

### New Features

#### Diagnostics Menu Expanded (options 5-7)
- **Static IP configuration**: Set a static IP address, gateway, and subnet mask via AT+CIPSTA
- **Hostname configuration**: Set a custom hostname for the ESP module via AT+CWHOSTNAME
- **Config summary**: View all current WiFi configuration at a glance (SSID, IP, MAC, hostname, DNS, baud rate)

#### New Key Bindings
- **L key**: Toggle UART debug log display on/off
- **W key**: Initiate WPS push-button connection

#### UI Enhancements
- **Pixel-drawn banner**: Cyan horizontal lines flanking the title with proper attribute separation (no color clash)
- **Centered IP bar**: IP address centered on line 1 with blue background
- **Status bar partial separator**: Pixel line between "UART log" and "WiFi:" labels
- **BREAK key replaces EDIT**: All cancel operations now use BREAK (CAPS+SPACE) instead of EDIT (CAPS+1), which is the standard ZX Spectrum convention

### Bug Fixes
- **Critical: `exitProgram` crash**: Program now correctly restores the saved stack pointer before returning to BASIC, preventing infinite loops/crashes
- **Diagnostics menu blocking**: Changed from blocking `inKey` to non-blocking `inKeyNoWait`, allowing BREAK to work at any time
- **Uppercase Q/A navigation**: Added missing uppercase key checks for cursor up/down
- **IP buffer off-by-one**: Increased `ip_buffer` from 16 to 17 bytes to safely accommodate the null terminator in worst case
- **UART parser desync**: When scan finds more than MAX_NETWORKS, the parser now drains the current line before returning to the main loop, preventing desynchronization
- **IP bar overflow**: Fixed `drawIpBar` writing 2 extra characters into the next screen line (44→42 spaces)

### Code Cleanup
- **Removed dead code**: `simpleTextInput` routine (unused), `esxdos.asm` module (not part of build), `compat.asm` module and reconnect flow (feature gated behind undefined flag)
- **Removed build artifacts**: `.cod` and `.lst` files no longer ship in `src/`
- **Added `.gitignore`**: Build outputs excluded from version control

### Memory Layout Refactored
- **RTVAR macro**: Runtime variables (uninitialized buffers) allocated after the SSID buffer at #C000, keeping them out of the binary
- **Stack relocated**: Moved from #BFFE to #FFF0, freeing ~1KB of code space
- **Build-time safety checks**: `ASSERT` guards verify code doesn't overlap buffers and runtime vars don't reach the stack

---

## [1.2.1] - "Pulse Check" - 2026-02-22

### New Features

- **Periodic Connection Health-Check**: When idle, NetManZX periodically queries the ESP (`AT+CWJAP?`, with `_CUR`/`_DEF` fallbacks) to verify that the connection is still valid. If the query fails, the UI is immediately marked as disconnected and an automatic rescan is triggered.

### Improvements

- **Much lower keyboard latency in the network list**: The UI loop was reorganized to prioritize keyboard handling and avoid unnecessary work while navigating.
- **Full key mapping restored**: Arrow keys and Q/A for navigation, O/P for page up/down, plus all action keys (R, H, D, X, Enter, Esc).
- **More efficient Page Down rendering**: The list is redrawn only when a page boundary is crossed, avoiding redundant full-screen redraws.
- **Network counter and page info on line 17**: Right-aligned indicator shows `X networks detected` and, when applicable, `(A/B pages)`.

### Bug Fixes

- **Automatic drop detection made robust**: Async parsing now correctly detects disconnection/reconnection markers across circular-buffer boundaries (e.g., `"DISCON"` / `"GOT IP"`), preventing missed events.
- **UART contention fixed**: Added a `uart_busy` mutex to prevent `checkAsyncWifi` from consuming bytes during critical operations (scan/connect/getIP).
- **getIP hang prevention**: Replaced blocking reads with `readTimeout` and enforced a maximum byte budget to avoid stalls.
- **Selection clamping after rescan**: When a rescan returns fewer APs than before, `offset`/`cursor_position` are clamped so the highlight never lands on a non-existing row.
- **Stale counters removed**: When `networks_count == 0`, line 17 is fully cleared to avoid displaying outdated values after rescans.

---

## [1.1.0] - 2025-12-29

### New Features

- **Hidden Network Support (H key)**: Added ability to manually enter SSID for hidden networks that don't appear in scan results. Press 'H' from the network list to enter a custom SSID and password.

- **Disconnect Option (X key)**: New option to disconnect from the current WiFi network without exiting the application. Only available when connected.

- **Async WiFi Status Detection**: The application now automatically detects connection drops and reconnections by monitoring ESP async messages (`WIFI DISCONNECT`, `WIFI GOT IP`). The status bar updates in real-time without user intervention.

- **Already Connected Warning**: When selecting a network you're already connected to, the application now shows a warning message instead of attempting to reconnect.

---

### UI Improvements

- **Refined Connection Retry Display**: Changed retry message format to show "Retry" only between connection attempts (after failure, during wait), not during the attempt itself. The sequence is now: `Connecting (1/3)...` → fail → `Connecting (1/3)... Retry` → wait → `Connecting (2/3)...` → etc.

- **Added Spacing in Network List**: Added a blank line between the menu options and the network list for better visual separation.

- **Added Spacing in Password Entry**: Added a blank line between the banner and "Selected SSID:" when entering a password.

- **Consistent Cancel Key**: Standardized on EDIT key for canceling text input (SSID and password entry). BREAK key is now reserved exclusively for canceling connection attempts in progress.

- **Status Bar Flicker Fix**: Fixed an issue where the WiFi status indicator ("Connected"/"Disconnected") would flicker when navigating between menus. The status bar now only updates when the connection state actually changes.

- **Dynamic Help Menu**: The help line now shows different options based on connection state:
  - Disconnected: `Q/A:Nav O/P:Page R:Refresh D:Diag`
  - Connected: `Q/A:Nav R:Refresh D:Diag X:Disconn`

---

### Technical Changes

- `PER_PAGE` reduced from 10 to 9 to accommodate new UI layout
- Network list now starts at line 6 (was line 5)
- Scroll indicators adjusted accordingly
- Main loop changed to non-blocking keyboard read to support async WiFi monitoring
- Added 16-byte circular buffer for async UART message parsing

---

### Internal Refactoring

- `topClean` no longer redraws the status bar unnecessarily
- Added `selected_ssid_ptr` variable to avoid recalculating SSID pointer
- New messages: `msg_edit_cancel`, `msg_retry_suffix`
- New async detection infrastructure: `checkAsyncWifi`, `async_buffer`, pattern matching for ESP events

---

## [1.0.0] - "First Contact" - 2025-12-25

### 🎄 Initial Release

This is the first release of **NetManZX**, a complete rewrite and enhancement of the original netman-zx by Alex Nihirash.

---

### ✨ New Features

#### User Interface
- **Redesigned banner**: New "NetManZX" branding with version display
- **Title highlighting**: Application name and version displayed in yellow for visibility
- **8-level RSSI signal bars**: Visual WiFi signal strength indicator for each network
- **WiFi status indicator**: Real-time status display (Scanning/Connected/Disconnected) with color coding
- **IP address bar**: Dedicated status bar showing current IP or connection state
- **Scroll indicators**: Visual arrows (↑↓) showing when more networks are available
- **Page navigation**: O/P keys for Page Up/Down through network lists
- **Password visibility toggle**: Press ↑ to show/hide password while typing

#### Diagnostics Menu
- **Ping test**: Test network connectivity with configurable target IP
  - Default IP: 8.8.8.8 (Google DNS)
  - Smart IP input: Auto-inserts dots after 3 digits per octet
  - Validates IP format (max 3 digits per octet, max 3 dots)
  - Formatted output: "Response time: XX ms" or "Request timed out"
- **Module info**: Display ESP8266 firmware version and AT command set
- **Network info**: Show current IP address and MAC address with parsed output
- **UART baud rate**: Display current communication speed

#### Connection Management
- **Smart connection detection**: On startup, detects existing WiFi connection
- **Keep or reconfigure dialog**: Option to maintain current connection or scan for new networks
- **Detailed error messages**: Specific feedback for connection failures:
  - "Connection timeout! - Router not responding"
  - "Wrong password! - Check password and try again"
  - "Network not found! - AP may be out of range"
  - "Connection failed! - Try again or check router"
- **Connection retry mechanism**: 3 automatic retries with user feedback
- **ESP recovery**: Automatic recovery attempt if ESP becomes unresponsive
- **Disconnect before connect**: Prevents network traffic interference during connection

---

### 🔧 Technical Improvements

#### Communication Robustness
- **ATE0 echo disable**: ESP echo disabled at initialization for cleaner communication
- **Network traffic filtering**: Filters async messages (+IPD, CONNECT, CLOSED, LAIN) during operations
- **Dual termination system**: Diagnostics terminate on OK/ERROR OR line limit OR timeout
- **HALT-based timeouts**: Predictable timing using Z80 HALT instruction
- **Pre-command buffer flush**: 1-second UART drain before sending diagnostic commands
- **Long timeout for connections**: Extended timeout (FFFF) for AT+CWJAP command
- **Byte limit protection**: Maximum 2000 bytes processed to prevent infinite loops

#### Code Quality
- **11 compilation errors fixed**: All syntax and range errors from original code resolved
- **Jump range fixes**: All `jr` instructions verified or converted to `jp` where needed
- **Register preservation**: Proper BC/HL preservation in display and utility functions
- **Optimized LDIR operations**: Efficient memory operations for screen clearing
- **Unified status functions**: Consolidated setStatusConnected/Disconnected/Scanning

#### Display System
- **Screen corruption fix**: Proper attribute handling prevents visual glitches
- **Partial line coloring**: Status bars don't overwrite RSSI indicators
- **Non-blocking keyboard**: Password input uses polling instead of blocking calls
- **Clean screen transitions**: Proper clearing between dialogs and menus

---

### 📝 Changes from Original netman-zx

| Feature | Original | NetManZX |
|---------|----------|----------|
| Signal strength | Not shown | 8-level RSSI bars |
| Connection status | Basic | Color-coded indicator |
| Error messages | Generic "Failed" | Specific error codes |
| Diagnostics | None | Full diagnostic menu |
| Navigation | Basic | Page Up/Down, indicators |
| Password entry | Basic | Show/hide toggle |
| IP display | None | Status bar with IP |
| Ping test | None | Configurable IP |
| Timeout handling | Basic | Robust dual-termination |
| ESP recovery | None | Automatic recovery |

---

### 🐛 Bug Fixes

- Fixed password input blocking entire system
- Fixed screen corruption when scrolling network list
- Fixed RSSI bars overwriting network names
- Fixed connection timeout being too short
- Fixed diagnostic commands hanging on network traffic
- Fixed EDIT key not working in diagnostics menu
- Fixed ping showing "Response time: timeout ms" instead of proper message
- Fixed infinite loops when ESP sends continuous data
- Fixed password being visible in UART log during connection

---

### 📦 Build Changes

- Output binary renamed from `netman.cod` to `netmanzx.cod`
- Version string centralized in main.asm
- Support for +3DOS (.cod) and TAP formats
- TAP includes auto-loading BASIC loader

---

### 🙏 Credits

- **Original netman-zx**: Alex Nihirash (https://github.com/nihirash/netman-zx)
- **NetManZX enhancements**: M. Ignacio Monge García
- **Development assistance**: Claude (Anthropic)

---

*First Contact - Because every Spectrum deserves to reach the cloud* ☁️
