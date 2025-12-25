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

---

### 📦 Build Changes

- Output binary renamed from `netman.cod` to `netmanzx.cod`
- Version string centralized in main.asm
- Support for both +3DOS (.cod) and esxDOS (.dot) formats

---

### 🙏 Credits

- **Original netman-zx**: Alex Nihirash (https://github.com/nihirash/netman-zx)
- **NetManZX enhancements**: M. Ignacio Monge García
- **Development assistance**: Claude (Anthropic)

---

*First Contact - Because every Spectrum deserves to reach the cloud* ☁️
