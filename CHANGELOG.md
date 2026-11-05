# NetManZX Changelog

## [Unreleased]

### Changed

- English and Spanish READMEs now focus the feature list on WiFi setup, connection management and troubleshooting.

## [v1.4.7] - 2026-11-05

### Added

- **Time and date on UNO and Spectrum Next.** Press T to view the clock and real-time clock (RTC) status; press Y to synchronize over WiFi using SNTP. A compatible RTC is updated when available. AY does not include the Time screen.
- **Time-zone settings.** Press Z to choose a whole-hour UTC offset from -12 to +14. Daylight-saving changes are adjusted manually.
- **Separate clock settings.** The last synchronization and UTC offset are saved in `NETTIME.CFG`, independently of WiFi credentials. Without an RTC, the last saved synchronization remains available, but the clock does not keep running while the machine is off.

### Changed

- **More networks:** the list keeps the 50 strongest access points instead of 25, sorted by signal strength.
- **Quicker scans and startup:** one active scan pass is used, with a fallback for older ESP firmware. Startup avoids unnecessary recovery waits when the WiFi module is already responding.
- **Clearer signal meters:** bright red, yellow and green bars show signal strength, with dim stripes marking the remaining range. Network details and Configuration Summary use consistent alignment.
- **Smoother controls:** network lists, menus, counters and text fields update only the areas that change. Pending keypresses take priority over optional background work.
- **Quit confirmation:** BREAK from the main menu asks before leaving. Y returns to BASIC on UNO/AY or restarts Spectrum Next; any other key returns to the network list.
- **Cleaner loading:** TAP files load the splash screen last, keeping the loading logo clear of BASIC loading messages.
- **Refreshed guides:** English and Spanish READMEs include the new banner, current controls and nine new emulator screenshots with fictional example networks.

### Fixed

- More reliable scans with long, incomplete or malformed replies. Busy WiFi traffic no longer creates false network entries or false connection-status changes.
- Connection details and Configuration Summary handle fragmented replies more reliably; unavailable IP, gateway, netmask, MAC or firmware information no longer leaves misleading old values on screen.
- BREAK cancels configuration, diagnostics and connection preparation consistently. Held or leftover keys no longer accidentally dismiss quit or time dialogs, and cancelling a failed credential save does not repeat the write.
- Better recovery from stalled transmissions, serial errors and restarting the application. AY receive timeouts release the interface cleanly; Next resets inherited serial settings at startup.
- More reliable startup and return to BASIC on UNO/AY, including repeated use after SD-card operations. Keyboard input works with direct Next loaders as well as NextZXOS.
- Password visibility changes, cursor movement and text editing no longer corrupt neighbouring screen areas. Menu counters, scroll indicators and diagnostic log lines display more consistently.
- Next creates configuration folders correctly when their path includes a drive letter.

### Removed

- Unsupported AY +3DOS/DOT build variants. AY remains fully included as `netmanzx-ay.tap`.

## [v1.4.6] - 2026-09-08

### Added

- Quit with BREAK from the main menu: return to BASIC on UNO/AY, or restart the Spectrum Next. BREAK still cancels or goes back on other screens.
- Select individual access points when several share the same network name. Duplicate scan entries for the same access point are removed; manual and saved connections still use the network name.

### Changed

- Smoother network-list updates, with unchanged rows left in place.
- More descriptive startup messages on Spectrum Next, including WiFi detection and recovery progress.
- Smaller Spectrum Next download: the NEX file is 82,944 bytes, down from 132,096 bytes (37% smaller), retaining the loading screen.
- UART log output is displayed after command exchanges to reduce interference with reception; truncated output is marked.

### Fixed

- Left/right arrows now move one page, like O/P. The last page shows only the remaining networks instead of repeating entries from the previous page.
- Manual rescan clears the previous network count and pagination before displaying "Scanning...", preventing overlapping text.
- More reliable network scans and handling of escaped network names. Invalid or damaged scan responses are rejected, and a network missing from a rescan no longer implies disconnection.
- Pending keystrokes collected during an automatic scan no longer act on the reordered list when the scan finishes or fails. A continuously held key can still repeat.
- Reconnection can proceed when the ESP explicitly rejects a preliminary disconnect. Timeouts, UART faults and cancellation still stop the attempt, with more accurate failure reporting.
- Improved recovery from UART errors and ESP resets, including baud-rate recovery on Next without changing the saved baud rate. Incoming network data is no longer mistaken for AT command replies.
- More reliable connection-state detection, WPS cleanup and BREAK cancellation. WPS preserves the ESP's saved automatic-connection policy.
- Safer credential loading and saving on UNO/Next: malformed files are rejected, and failed saves no longer appear successful in the current session.
- Corrected diagnostic text clipping, firmware and network information, password-field redraws and cancellation when editing a hostname or returning to diagnostics.
- Fixed instability after repeated diagnostic navigation, SD-card operations and returning to BASIC on UNO/AY.

## [v1.4.5] - 2026-05-23

### Changed

- Smaller UNO and AY downloads, with the same features and loading screen.
- Refreshed English and Spanish documentation.

### Fixed

- Loading and saving settings no longer disrupts reconnection, network highlighting, logging or the return to BASIC.
- WPS, disconnect, static-IP and hostname operations check their results and report failures more reliably.
- Continuous noise from the WiFi module no longer traps the application in an endless wait.
- More reliable communication and reset handling on UNO, AY and Next.
- Corrected configuration-folder creation, stale IP text, overlong startup messages and incomplete log lines. Background link checks no longer clutter the UART log.

## [v1.4.4] - 2026-04-18

### Added

- A loading splash screen on all three targets, with startup progress messages.
- Separate current and saved default baud-rate values in diagnostics.
- Diagnostics for module information, baud rate, static IP, hostname and configuration are available without an active WiFi connection.

### Changed

- Startup goes straight to the network list, including when WiFi is already connected.
- BREAK consistently cancels or goes back in dialogs.
- Clearer WPS, connection, timeout and cancellation messages; diagnostics use consistent key feedback and input styling.
- Cleaner splash-to-menu transitions, open-network indicators and hostname editing.

### Fixed

- WPS waits for an actual connection instead of reporting success as soon as the request is accepted. Cancellation and timeout restore the module for subsequent use.
- Older ESP firmware can fall back to a basic scan when extended scans return no results. Empty scans finish correctly, and interrupted scans no longer erase the previous network list.
- WiFi modules left in access-point mode are prepared correctly for scanning and connecting.
- Disconnect failures are reported accurately, and connection-loss notifications are detected more reliably.
- Cancelling a connection or leaving its success screen no longer triggers an unintended return to BASIC. Returning after SD-card operations is more reliable.
- Improved AY, UNO and Next communication, timeout and reset handling; continuous serial noise no longer causes an endless wait.
- Corrected log interference on diagnostic screens, splash colours and flashes, and transient empty-list messages during startup.

## [v1.4.3.1] - 2026-04-11

### Added

- Saved networks are highlighted in cyan on UNO and Next; the connected network keeps its yellow highlight.

### Changed

- Network capacity increased from 20 to 25.
- Next baud-rate recovery changes the speed for the current session only, preserving the module's saved default and avoiding an unnecessary restart.
- Faster clearing and updating of the network list.

### Fixed

- Maximum-length network names no longer overwrite neighbouring data.
- Connection and disconnection notifications are received more reliably on UNO and AY.

## [v1.4.3] - 2026-04-10

### Added

- Save WiFi credentials to SD and reconnect on UNO/Next, with a save prompt after a successful connection and the saved network listed in Configuration Summary.
- Automatic baud-rate detection and recovery on Spectrum Next.
- A native NEX download for Spectrum Next.
- Connection details showing IP address, gateway, netmask and MAC address for the active network.
- Clearer connection-failure reasons, network names and attempt counts during connection, and audible feedback during text entry.

### Changed

- Smaller program files and smoother page navigation.
- The combined build includes UNO, AY and Next.
- WPS allows more time for enrollment, and network details identify the reported channel band and unknown security types more clearly.

### Fixed

- More reliable connection-result detection and status checks. Failed queries or scans no longer falsely mark a hidden or temporarily absent network as disconnected.
- Hidden networks selected from the list correctly open manual name entry.
- Corrected stale connection details, leftover list rows, missing or misplaced scroll indicators, and password-cursor display and input.
- Residual keypresses no longer dismiss cancellation dialogs unexpectedly; connection and disconnection screens have fewer redraw artefacts.
- Saved settings reject incompatible files and avoid saving an unentered password. Next leaves the application through the correct restart path.

## [v1.4.2] - 2026-03-20

### Changed

- More consistent network discovery, with a fallback for older WiFi firmware.
- Faster text rendering, network sorting and text editing.
- Clearer double-height dialogs, immediate disconnect feedback and consistent prompts. Input limits are indicated by a brief border flash.
- Connection screens wait until IP lookup has finished before inviting a keypress. Keeping an existing connection opens diagnostics.
- More reliable background link checks and scan-timeout handling.

### Fixed

- BREAK cancels text input instead of inserting a space.
- Corrected serial communication failures on UNO and Next and startup state on 128K-compatible machines.
- Limited waits for malformed module replies and removed leftover startup log text.

### Security

- Passwords are no longer exposed in the UART log during connection attempts.

## [v1.4.1] - 2026-03-17

### Added

- An hourglass during background scans and a red indicator when the UART log is enabled.
- Log toggling from the main menu, diagnostics and connection screens.
- A larger, clearer ping display.

### Fixed

- Open networks ask for confirmation before connecting.
- UART logging starts disabled, and L reliably changes its state.
- Keeping an existing connection no longer leaves the application stuck.
- More consistent prompts, fewer unwanted startup keypresses and restored Next communication recovery.

[Unreleased]: https://github.com/IgnacioMonge/NetManZX/compare/v1.4.7...main
[v1.4.7]: https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.7
[v1.4.6]: https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.6
[v1.4.5]: https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.5
[v1.4.4]: https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.4
[v1.4.3.1]: https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.3.1
[v1.4.3]: https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.3
[v1.4.2]: https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.2
[v1.4.1]: https://github.com/IgnacioMonge/NetManZX/releases/tag/v1.4.1
