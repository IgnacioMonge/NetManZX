# Changelog

All notable changes to NetManZX are documented in this file.

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


## v1.1 - 2025-12-29

### New Features

- **Hidden Network Support (H key)**: Added ability to manually enter SSID for hidden networks that don't appear in scan results. Press 'H' from the network list to enter a custom SSID and password.

- **Disconnect Option (X key)**: New option to disconnect from the current WiFi network without exiting the application. Only available when connected.

- **Async WiFi Status Detection**: The application now automatically detects connection drops and reconnections by monitoring ESP async messages (`WIFI DISCONNECT`, `WIFI GOT IP`). The status bar updates in real-time without user intervention.

- **Already Connected Warning**: When selecting a network you're already connected to, the application now shows a warning message instead of attempting to reconnect.

### UI Improvements

- **Refined Connection Retry Display**: Changed retry message format to show "Retry" only between connection attempts (after failure, during wait), not during the attempt itself. The sequence is now: `Connecting (1/3)...` → fail → `Connecting (1/3)... Retry` → wait → `Connecting (2/3)...` → etc.

- **Added Spacing in Network List**: Added a blank line between the menu options and the network list for better visual separation.

- **Added Spacing in Password Entry**: Added a blank line between the banner and "Selected SSID:" when entering a password.

- **Consistent Cancel Key**: Standardized on EDIT key for canceling text input (SSID and password entry). BREAK key is now reserved exclusively for canceling connection attempts in progress.

- **Status Bar Flicker Fix**: Fixed an issue where the WiFi status indicator ("Connected"/"Disconnected") would flicker when navigating between menus. The status bar now only updates when the connection state actually changes.

- **Dynamic Help Menu**: The help line now shows different options based on connection state:
  - Disconnected: `Q/A:Nav O/P:Page R:Refresh D:Diag`
  - Connected: `Q/A:Nav R:Refresh D:Diag X:Disconn`

### Technical Changes

- `PER_PAGE` reduced from 10 to 9 to accommodate new UI layout
- Network list now starts at line 6 (was line 5)
- Scroll indicators adjusted accordingly
- Main loop changed to non-blocking keyboard read to support async WiFi monitoring
- Added 16-byte circular buffer for async UART message parsing

### Internal Refactoring

- `topClean` no longer redraws the status bar unnecessarily
- Added `selected_ssid_ptr` variable to avoid recalculating SSID pointer
- New messages: `msg_edit_cancel`, `msg_retry_suffix`
- New async detection infrastructure: `checkAsyncWifi`, `async_buffer`, pattern matching for ESP events
