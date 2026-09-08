<p align="center">
  <img src="images/netmanzxlogo-white.png" alt="NetManZX" width="520">
</p>

# NetManZX

<p align="center">
  <strong>WiFi network manager for ZX Spectrum</strong><br>
  ZX-Uno / divMMC · AY-UART / ZX-Badaloc · ZX Spectrum Next
</p>

<p align="center">
  <a href="READMEsp.md">Español</a> ·
  <a href="https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.6">Download v1.4.6</a> ·
  <a href="CHANGELOG.md">Changelog</a>
</p>

---

Scan WiFi networks, connect your Spectrum and check the link from one application. NetManZX uses an ESP8266 module connected through a ZX-Uno-compatible, AY-UART or Spectrum Next interface.

## Why NetManZX

| | |
| --- | --- |
| **Networks** | Up to 25 access points, sorted by signal strength; manual connection to hidden networks |
| **Connect** | Password, WPS and reconnection to credentials saved on SD on UNO/Next |
| **Diagnostics** | Ping, firmware, IP/MAC, baud rate, static IP, hostname and configuration summary |
| **Interface** | Double-height text, signal bars, scroll indicators and UART log |
| **Distribution** | TAP for UNO/AY; one self-contained NEX for Spectrum Next |

## What's new in 1.4.6

- **Choose the access point:** networks sharing a name stay separate, and selection connects to the chosen access point.
- **Smoother navigation:** unchanged rows avoid unnecessary redraws, and pending keys are discarded after an automatic scan.
- **More reliable connections:** improved scanning, reconnection, UART recovery, WPS and BREAK cancellation.
- **A smaller, clearer Next edition:** a 37% smaller NEX file, retaining the loading screen and adding more descriptive startup messages.
- **Quit from the menu:** BREAK returns to BASIC on UNO/AY and restarts the machine on Next; elsewhere it still cancels or goes back.
- **Safer saves and diagnostics:** better handling of credential-save failures, with corrected information displays and text fields.

See the [changelog](CHANGELOG.md#v146---2026-09-08) for the complete release overview.

## Contents

- [What's new in 1.4.6](#whats-new-in-146)
- [Platforms and requirements](#platforms-and-requirements)
- [Download](#download)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Gallery](#gallery)
- [Features](#features)
- [Controls](#controls)
- [Connection recovery](#connection-recovery)
- [Build from source](#build-from-source)
- [Credits and license](#credits-and-license)

## Platforms and requirements

- ZX Spectrum (48K or higher) or compatible
- ESP8266-based WiFi module:
  - **ZX-Uno**: Built-in UART (default target)
  - **AY-UART**: ZX-Badaloc or similar bit-banged AY-3-8912 implementations
  - **ZX Spectrum Next**: Hardware UART with FIFO
- TAP-compatible loading method (divMMC, esxDOS, emulator, or tap2wav for tape)

## Download

Download ready-to-load binaries from [release v1.4.6](https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.6). Choose the file for your interface:

| Target | File | Description |
|--------|------|-------------|
| UNO | `netmanzx-uno.tap` | ZX-Uno / DivMMC |
| AY | `netmanzx-ay.tap` | AY-UART / ZX-Badaloc |
| NEXT | `netmanzx-next.nex` | ZX Spectrum Next (native NEX) |

## Installation

**TAP (tape/emulators):**
Simply load the TAP file - the BASIC loader will auto-run and load the program automatically.

**NEX (Next):**
Copy `netmanzx-next.nex` to your SD card and launch it from the Next file browser.

## Quick start

1. **Load the program** on your Spectrum
2. **Wait for network scan** - available networks will appear in a list
3. **Navigate** using cursor keys (up/down) or Q/A, O/P for page up/down
4. **Select a network** with ENTER - a detail screen shows security, channel, and signal
5. **Enter password** (if required) - use UP arrow to toggle password visibility
6. **Wait for connection** — BREAK cancels; failures show a reason
7. **Access diagnostics** by pressing D from the network list

## Gallery

*Screenshots from v1.4.4; some text differs in v1.4.6. SSIDs have been blurred for privacy.*

| | | |
|:---:|:---:|:---:|
| [![Splash Next](images/1.4.4/release/01_splash_next.png)](images/1.4.4/release/01_splash_next.png) | [![Network list](images/1.4.4/release/03_network_list.png)](images/1.4.4/release/03_network_list.png) | [![Already connected](images/1.4.4/release/04_already_connected.png)](images/1.4.4/release/04_already_connected.png) |
| *Boot splash (Spectrum Next, Layer 2)* | *Network list with RSSI bars* | *"Already connected" warning (v1.4.4+)* |
| [![Connected](images/1.4.4/release/10_connected.png)](images/1.4.4/release/10_connected.png) | [![Diagnostics](images/1.4.4/release/06_diagnostics_menu.png)](images/1.4.4/release/06_diagnostics_menu.png) | [![Ping test](images/1.4.4/release/07_ping_test.png)](images/1.4.4/release/07_ping_test.png) |
| *Successful connection* | *Diagnostics menu (7 options)* | *Ping test* |
| [![UART baud rate](images/1.4.4/release/08_uart_baud.png)](images/1.4.4/release/08_uart_baud.png) | [![Config summary](images/1.4.4/release/09_config_summary.png)](images/1.4.4/release/09_config_summary.png) | [![About](images/1.4.4/release/11_about.png)](images/1.4.4/release/11_about.png) |
| *UART baud (current / default)* | *Configuration summary* | *About screen* |

## Features

### Network Management

- **Network scanning**: Discover up to 25 WiFi access points, sorted by signal strength, with retries on scan failure. Access points sharing a name remain separate; selection connects to the chosen access point
- **Robust startup detection**: Disables ESP echo early (ATE0) to prevent scan parser failures on cold boot. Multiple scan attempts with diagnostic messages on timeout or empty results
- **Hidden Network Support**: Manually enter SSID for networks that do not broadcast their name
- **Smart Connection Detection**: On startup, detects if already connected to a WiFi and updates the status bar accordingly; cold boot goes straight to the main menu + first scan in all cases. If the "already connected" network is selected from the list, a detail screen shows its info with an `Already connected to this network!` warning in red
- **Connection info screen**: Press ENTER on the already-connected network to view full connection details: IP address, gateway, netmask, and MAC address
- **Save & reconnect** (UNO/NEXT only): Store credentials on SD (`/SYS/CONFIG/NETMAN.CFG` on divMMC, `c:/sys/config/netman.cfg` on Next). C offers reconnection to the saved network; S saves after a successful connection. The saved network is highlighted in cyan
- **Password Entry**: Full keyboard support with show/hide toggle, double-height input with cursor editing (left/right arrow keys)
- **WPS support**: Push-button connection with W and cancellation with BREAK, preserving the ESP's saved automatic-connection policy
- **Disconnect Option**: Disconnect from current network with confirmation dialog, without exiting the application
- **Real-time Status Monitoring**: Automatically detects connection drops and reconnections via async ESP event parsing
- **Connection failure diagnostics**: Specific error messages for connection failures: wrong password, AP not found, timeout, or connection refused
- **BREAK cancellation**: Cancel connection attempts and AT operations. Response time depends on the hardware and operation

### Diagnostics Menu

1. **Ping test** - Test connectivity with configurable target IP (default: 8.8.8.8)
2. **Module info** - Display ESP8266 firmware version and AT command set
3. **Network info** - Show current IP address and MAC address
4. **UART baud rate** - Display `Current:` and `Default:` ESP baud rates separately, so the Next-only session override (`AT+UART_CUR=115200`) is visible without implying that flash was changed
5. **Static IP** - Configure static IP address, gateway, and subnet mask
6. **Hostname** - Set a custom hostname for the ESP module
7. **Config summary** - View all current WiFi settings at a glance (SSID, IP, MAC, hostname, firmware, saved network, app version)

### User Interface

- **Double-height text**: Large banner, status, input and message text, with smoother network-list updates
- **Network detail screen**: View the network name, security, channel and signal strength before connecting
- **Connection progress screen**: "Connecting to..." shows the SSID in double-height yellow text with attempt counter
- **Rainbow badge**: Decorative dither-triangle with color transitions on the banner
- **8-level RSSI signal bars**: Visual WiFi signal strength indicator for each network, with custom lock/open circle glyphs
- **Anti-flicker status bar**: Direct-overwrite rendering with batched updates eliminates visual flickering
- **Scroll indicators**: Visual arrows showing when more networks are available
- **Audible key click**: Clear audible feedback on every keypress during text input

### Other

- **Boot splash screen**: A loading logo on every target, with a colour Layer 2 image on Next. Descriptive startup messages report WiFi initialization and recovery
- **About screen** (I key): Shows version, build date, author, GitHub URL, and license
- **UART debug log**: Toggle with L; a red indicator marks when enabled. Command logs are displayed after the exchange, with a notice when output is truncated
- **Built-in font**: Compact six-pixel-wide text with no external font file required when running the program
- **Three UART backends**: Supports ZX-Uno, AY-UART (ZX-Badaloc), and ZX Spectrum Next hardware
- **Baud rate auto-detection** (Next only): Try 1152000, 2000000, 9600 and 57600 baud if the ESP does not respond at 115200. Restore 115200 for the session without changing the saved baud rate; reset the ESP if recovery requires it
- **NEX format** (Next only): Native `.nex` binary for direct launch without mode selection menu
- **Build date**: Automatically embedded at assembly time via Lua

## Controls

| Key | Action |
|-----|--------|
| Up/Down or Q/A | Navigate network list |
| Left/Right or O/P | Previous/next page |
| ENTER | Select network / Confirm |
| BREAK | Cancel / Back; quit from the main menu |
| H | Connect to hidden network (manual SSID entry) |
| X | Disconnect from current network |
| D | Diagnostics menu |
| R | Rescan networks |
| L | Toggle UART debug log |
| W | WPS push-button connect |
| C | Reconnect to the saved network (UNO/NEXT) |
| S | Save credentials after connection (UNO/NEXT) |
| I | About screen |

From the main menu, BREAK returns to BASIC on UNO/AY. On Next it restarts the machine; it does not restore the previous NextZXOS session.

## Connection recovery

NetManZX monitors ESP connection events and periodically checks the link. Scans and connection commands temporarily pause navigation; BREAK response varies with the UART backend. A background scan discards pending input on completion, but a held key can still repeat.

Next can recover common baud-rate mismatches automatically. On UNO/AY, check the module's baud rate and interface setup if startup cannot communicate with the ESP.

## Build from source

### Prerequisites

- [SjASMPlus](https://github.com/z00m128/sjasmplus) Z80 Cross-Assembler v1.20+
- GNU Make

### Compilation

```bash
# Build for ZX-Uno / DivMMC (default)
make uno

# Build for AY-UART / ZX-Badaloc
make ay

# Build for ZX Spectrum Next
make next

# Build all targets
make all
```



Build outputs are placed in `build/`.

## Credits and license

NetManZX is based on [netman-zx](https://github.com/nihirash/netman-zx), by **Alex Nihirash**.

NetManZX enhancements: **M. Ignacio Monge Garcia — 2025–2026**.

Released under the [MIT license](LICENSE). See the [changelog](CHANGELOG.md) for the version history.

*Made with love for the ZX Spectrum community.*
