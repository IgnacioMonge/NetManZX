![NetManZX Banner](images/netmanzxlogo-white.png)

# NetManZX

**WiFi Network Manager for ZX Spectrum**

[🇪🇸 Versión en español](READMEsp.md)

## What is NetManZX?

NetManZX is a WiFi network configuration utility for ZX Spectrum computers equipped with ESP8266-based WiFi modules (such as ZX-Badaloc or similar). It provides a user-friendly interface to scan, select, and connect to wireless networks directly from your Spectrum.

## Origin

NetManZX is based on the original [netman-zx](https://github.com/nihirash/netman-zx) project by **Alex Nihirash**. This version has been significantly enhanced with new features, improved reliability, and a better user experience.

## Features

- **Network Scanning**: Automatically discovers available WiFi networks
- **Hidden Network Support**: Manually enter SSID for networks that don't broadcast their name
- **Visual Signal Strength**: 8-level RSSI bars show signal quality for each network
- **Smart Connection Detection**: Detects if already connected and offers to keep or reconfigure
- **Password Entry**: Full keyboard support with show/hide password toggle
- **Disconnect Option**: Disconnect from current network without exiting the application
- **Real-time Status Monitoring**: Automatically detects connection drops and reconnections
- **Detailed Error Messages**: Specific feedback for connection failures (wrong password, AP not found, timeout, etc.)
- **Diagnostics Menu**: 
  - Ping test with configurable IP address
  - Module firmware information
  - Network info (IP/MAC address)
  - UART baud rate display
- **Robust Communication**: 
  - Network traffic filtering during diagnostics
  - Timeout-based termination to prevent hangs
  - Connection retry mechanism with ESP recovery
- **Visual Feedback**: 
  - WiFi status indicator (Scanning/Connected/Disconnected)
  - UART activity log with border color feedback
  - IP address display in status bar
- **Navigation**: Page Up/Down support, scroll indicators

[![NetManZX_1](images/NETMANZX_snap1_th.png)](images/NETMANZX_snap1.png) [![NetManZX_2](images/NETMANZX_snap3_th.png)](images/NETMANZX_snap3.png) [![NetManZX_3](images/NETMANZX_snap5_th.png)](images/NETMANZX_snap5.png)

## Requirements

- ZX Spectrum (48K or higher) or compatible
- ESP8266-based WiFi module (ZX-Badaloc, or similar AY-UART implementations)
- +3DOS compatible system for loading (or tap2wav for tape loading)

## Building

### Prerequisites

- [SjASMPlus](https://github.com/z00m128/sjasmplus) Z80 Cross-Assembler v1.20+

### Compilation

```bash
# Standard build for +3DOS (generates netmanzx.cod)
sjasmplus main.asm

# For TAP format (tape/emulators) - includes BASIC loader
sjasmplus -DTAP main.asm
```

### Output Files

| Format | File | Description |
|--------|------|-------------|
| +3DOS | `netmanzx.cod` | For +3 / +3DOS systems |
| TAP | `netmanzx.tap` | Complete tape file with auto-loading BASIC loader |

### Loading

**+3DOS:**
Put NETMANZX.BAS file loader and netmanzx.cod in the same directory. Run NETMANZX.BAS from the esxDOS file browser.

**TAP (tape/emulators):**
Simply load the TAP file - the BASIC loader will auto-run and load the program automatically.

## Usage

1. **Load the program** on your Spectrum
2. **Wait for network scan** - available networks will appear in a list
3. **Navigate** using cursor keys (up/down) or O/P for page up/down
4. **Select a network** with ENTER (or press H for hidden networks)
5. **Enter password** (if required) - use arrow up to toggle password visibility
6. **Wait for connection** - detailed error messages help troubleshoot failures
7. **Access diagnostics** by pressing 'D' from the network list

### Key Controls

| Key | Action |
|-----|--------|
| ↑/↓ or Q/A | Navigate network list |
| O/P | Page Up/Down |
| ENTER | Select network / Confirm |
| EDIT | Cancel / Back |
| H | Connect to hidden network (manual SSID entry) |
| X | Disconnect from current network |
| D | Diagnostics menu |
| R | Rescan networks |
| BREAK | Cancel connection attempt in progress |

### Diagnostics Menu

- **1. Ping test**: Test connectivity (default: 8.8.8.8, configurable)
- **2. Module info**: Display ESP8266 firmware version
- **3. Network info**: Show current IP and MAC address
- **4. UART baud rate**: Display current communication speed


### Connection Robustness

- **Automatic WiFi Drop Detection**: Asynchronous ESP event parsing detects unexpected disconnections instantly.
- **Idle Connection Health Check**: Periodic AT-based link validation (idle polling) ensures the ESP connection remains alive.
- **UART Busy Protection**: Mutex-style guard prevents background async parsing from stealing bytes during critical operations (scan/connect/getIP).
- **Circular Buffer Pattern Fix**: Reliable detection of ESP events (e.g., DISCONNECT/GOT IP) even across buffer boundaries.
- **Automatic State Recovery**: On link loss, UI transitions to *Disconnected* and schedules a safe rescan.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

## License

This project is open source. Based on original work by Alex Nihirash.

## Copyright

- Original netman-zx: **Alex Nihirash** (https://github.com/nihirash)
- NetManZX enhancements: **M. Ignacio Monge García** (2026)

---

*Made with ❤️ for the ZX Spectrum community*
