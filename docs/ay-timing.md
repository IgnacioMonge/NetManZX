# AY timing bench

This standalone probe measures the current `ay.asm` receiver and, optionally,
the real `Uart.readTimeout` wrapper. It does not alter the production binary.
No physical measurements have been collected yet. The regression runner's
synthetic IM1 clock is not evidence about ULA interrupt loss.

Build from the repository root (sjasmplus on PATH):

```powershell
sjasmplus --nologo -isrc --outprefix=build/ --sym=build/ay-timing-probe.sym tests/ay_timing_probe.asm
```

On the AY/ZX-Badaloc machine, load the resulting `build/ay-timing-probe.tap`:

```basic
CLEAR 32767
LOAD "" CODE
POKE 24576,0
POKE 24588,0: POKE 24589,16
RANDOMIZE USR 32768
```

This runs 4096 raw receiver calls. To exercise the default timeout wrapper,
use mode 1 and 16 calls instead: `POKE 24576,1: POKE 24588,16: POKE 24589,0`.
Reload the probe before each run so driver state starts identically. The probe
performs the production AY initialization, including its baud setup sequence.
Record the board, ROM, clock/turbo setting, video mode and ESP firmware.

Measure the elapsed interval from the border turning red (2) to green (4)
with video timestamps, or timestamp the corresponding ULA port writes with a
logic analyzer. Ignore the initialization and final BREAK-release wait.
An emulator is useful only if its CPU/ULA model delivers finite `/INT` pulses
and exposes elapsed T-states; identify that model and keep its results separate
from hardware observations. Do not derive elapsed time from FRAMES itself.

Run both modes under sustained RX silence, then under controlled 9600-baud
bursts from the attached device. Record transmitted and received byte counts
and the burst/gap pattern; the default-timeout wrapper returns on the first
byte, so its run duration will change under traffic. Sweep the initial phase
relative to vertical sync by repeating runs. Avoid changing the production
baud delay constant for this experiment.

The probe leaves little-endian results in RAM:

| Address | Size | Meaning |
| --- | ---: | --- |
| 24576 (`6000`) | 1 | Input: 0 raw receiver, 1 default timeout |
| 24577 (`6001`) | 1 | Output: 1 if cancelled by BREAK |
| 24578 (`6002`) | 2 | Completed calls |
| 24580 (`6004`) | 2 | Calls returning a byte |
| 24582 (`6006`) | 3 | Starting ROM FRAMES |
| 24585 (`6009`) | 3 | Ending ROM FRAMES |
| 24588 (`600C`) | 2 | Input: number of calls |

Read a 24-bit value with `PEEK a+256*PEEK (a+1)+65536*PEEK (a+2)`.
Compute `ticks = (end-start) modulo 16777216`, then compare with independently
observed frame count, or with elapsed seconds times the measured refresh rate.
Report missing ticks and `1-ticks/expected_ticks`; allow boundary uncertainty
from snapshots and marker writes. Do not assume every machine is exactly 50 Hz.

For BREAK latency, start a long run (e.g. 65535 calls), assert CAPS+SPACE during
silence and during a burst, and timestamp the chord and the green marker.
Repeat at different phases and report min/max, not just an average. Raw mode
checks BREAK after each call; timeout mode also exercises the real internal
poll cadence. This is a driver/wrapper bench, not an end-to-end scan or join
timing measurement: its counter and keyboard instructions change the enabled
interrupt window. Confirm any proposed timing fix with full NetManZX on the
same hardware before changing production constants.
