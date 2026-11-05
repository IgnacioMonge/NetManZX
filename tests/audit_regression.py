"""Execute assembled routines with mocked UART/firmware, not a Spectrum model.

Requires sjasmplus on PATH and test-only `z80==1.2.0` (pip install z80==1.2.0).
Run with Python 3: tests/audit_regression.py [AY NEXT UNO]. UNO is last by default.
Artifacts stay in build/. Hardware baud/timing and esxDOS paging need device tests.
"""

from collections import deque
from functools import reduce
from pathlib import Path
import re
import subprocess
import sys

import z80

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
STOP = 0x7FFE
COLD_OVERLAY = None  # Next bank 16 or TAP overlay mapped at #6000


def tap_basic_lines(path):
    """Validate the tokenized BASIC loader and return its line numbers."""
    data = Path(path).read_bytes()
    length = int.from_bytes(data[0:2], "little")
    assert data[2] == 0 and data[3] == 0, "BASIC header block"
    payload_len = int.from_bytes(data[14:16], "little")
    start = 2 + length
    body = data[start + 3 : start + 3 + payload_len]
    i = 0
    lines = []
    while i + 4 <= len(body):
        number = int.from_bytes(body[i : i + 2], "big")
        if number == 0:
            break
        size = int.from_bytes(body[i + 2 : i + 4], "little")
        content = body[i + 4 : i + 4 + size]
        assert len(content) == size and content[-1] == 0x0D, f"line {number} terminator"
        for j, byte in enumerate(content):
            if byte == 0x0E:  # hidden number must follow its ASCII digits
                assert j >= 1 and 0x30 <= content[j - 1] <= 0x39, (
                    f"line {number} number marker"
                )
        lines.append(number)
        i += 4 + size
    return lines


def tap_code_blocks(path):
    """Return (address, length) of every CODE block, in tape order."""
    data = Path(path).read_bytes()
    blocks = []
    i = 0
    while i + 4 <= len(data):
        length = int.from_bytes(data[i : i + 2], "little")
        if length and data[i + 2] == 0 and data[i + 3] == 3:
            blocks.append(
                (
                    int.from_bytes(data[i + 16 : i + 18], "little"),
                    int.from_bytes(data[i + 14 : i + 16], "little"),
                )
            )
        i += 2 + length
    return blocks


def tap_code(path, address):
    """Return the payload of the TAP CODE block loaded at address."""
    data = Path(path).read_bytes()
    i = 0
    while i + 4 <= len(data):
        length = int.from_bytes(data[i : i + 2], "little")
        if length and data[i + 2] == 0 and data[i + 3] == 3:
            if int.from_bytes(data[i + 16 : i + 18], "little") == address:
                payload_len = int.from_bytes(data[i + 14 : i + 16], "little")
                start = i + 2 + length + 3  # skip data-block length and flag
                return data[start : start + payload_len]
        i += 2 + length
    raise AssertionError(f"no CODE block at {address:#06x} in {path}")


class Run:
    def __init__(self, image, symbols, overlay=None):
        self.s = symbols
        self.m = z80.Z80Machine()
        self.m.set_memory_block(
            0x8000,
            image[: symbols.get("static_data_end", symbols["program_end"]) - 0x8000],
        )
        overlay = COLD_OVERLAY if overlay is None else overlay
        if overlay:
            # Next bank 16 or the classic preloaded overlay occupies #6000.
            self.m.set_memory_block(0x6000, overlay[:0x2000])
        # Minimal IM1 clock: preserve registers and increment ROM FRAMES.
        self.m.set_memory_block(
            0x38, bytes.fromhex("f5 e5 21 78 5c 34 20 02 23 34 e1 f1 fb c9")
        )
        self.m.iy = 0x5C3A
        self.m.iff1 = self.m.iff2 = True
        self.m.set_input_callback(lambda port: 0xFF)
        self.hooks = {}
        self.rx = deque()
        if "Display.initFontCache" in symbols:
            self.call("Display.initFontCache")
        self.call("Uart.logReset")

    def put(self, symbol, value):
        self.m.memory[self.s[symbol]] = value

    def get(self, symbol):
        return self.m.memory[self.s[symbol]]

    def hook(self, symbol, callback=None):
        address = self.s[symbol] if isinstance(symbol, str) else symbol
        self.hooks[address] = callback or (lambda: None)
        self.m.set_breakpoint(address)

    def ret(self):
        self.m.pc = int.from_bytes(self.m.memory[self.m.sp : self.m.sp + 2], "little")
        self.m.sp += 2

    def feed(self, data):
        self.rx.extend(data)

        def read():
            self.m.bc, self.m.de, self.m.hl = 0xFD3B, 0xFFBF, 0x1234
            ready = bool(self.rx)
            self.m.a = self.rx.popleft() if ready else 0
            self.m.f = int(ready)

        self.hook("UartImpl.uartRead", read)

    def call(self, symbol, stop=STOP):
        m = self.m
        end = self.s[stop] if isinstance(stop, str) else stop
        m.pc = self.s[symbol]
        m.sp = 0xFFE0
        m.memory[m.sp : m.sp + 2] = STOP.to_bytes(2, "little")
        m.set_breakpoint(end)
        for _ in range(2000000):
            events = m.run()
            if m.pc == end:
                m.clear_breakpoint(end)
                return
            if m.pc in self.hooks:
                address = m.pc
                self.hooks[address]()
                if m.pc == address:
                    self.ret()
            if m.halted or events & 8:
                m.on_handle_active_int()
        raise AssertionError(f"{symbol}: did not finish, PC={m.pc:04x}")


def check(image, s, target):
    new = lambda: Run(image, s)

    if target == "NEXT":
        # Map the overlay before initializing the display or enabling interrupts.
        window = bytes(image[s["start"] - 0x8000 : s["start"] - 0x8000 + 160])
        mapped = window.find(bytes((0xED, 0x91, 0x53, 32)))
        init = s["Display.initFontCache"]
        called = window.find(bytes((0xCD, init & 0xFF, init >> 8)))
        assert mapped != -1 and called != -1 and mapped < called

    # Both menu states fit 42 columns and use the title-case menu labels.
    # Time ships on NEXT and UNO; AY stays without it.
    expected = b"D:Diag" if target == "AY" else b"D:Diag T:Time"
    assert ("UI.showTime" in s) == (target != "AY")
    for name in ("UI.msg_help", "UI.msg_help_conn"):
        r = new()
        line = bytes(r.m.memory[s[name] : s[name] + 64]).split(b"\0")[0]
        assert len(line) <= 42 and line.endswith(expected)
        assert (b"T:Time" in line) == (target != "AY")
        assert b"BREAK" not in line and b"QUIT" not in line

    # A cancellation chord must be released before the menu accepts Quit.
    r = new()
    keys = deque((0x40, 0x40, 0))
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", keys.popleft()))
    r.call("UI.uiLoop", "UI.uiLoopMain")
    assert not keys and r.m.sp == 0xFFE0
    r = new()
    # BREAK asks for confirmation on every target.
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40))
    r.hook("Keyboard.waitBreakRelease")
    r.hook("Keyboard.inKey", lambda: setattr(r.m, "a", ord("n")))
    r.call("UI.uiLoopMain", "UI.renderListAndLoop")
    assert r.m.sp == 0xFFE0

    r = new()
    released = []
    r.hook("Keyboard.waitBreakRelease", lambda: released.append(True))
    if target == "NEXT":
        reset = s["start.resetPending"] - 5
        r.call("start.exitClean", reset)
        # DI; NEXTREG $02,$01 requests soft reset, never ESP/hard reset.
        assert bytes(r.m.memory[reset : reset + 5]) == b"\xf3\xed\x91\x02\x01"
    else:
        r.m.memory[s["saved_sp"] : s["saved_sp"] + 2] = (0xFFD0).to_bytes(2, "little")
        r.m.memory[s["saved_ret"] : s["saved_ret"] + 2] = STOP.to_bytes(2, "little")
        r.m.memory[0xFFD0:0xFFD2] = STOP.to_bytes(2, "little")
        r.call("start.exitClean")
        assert r.m.sp == 0xFFD2
    assert released == [True]

    if target == "UNO":
        # Confirming with Y restores the caller's stack and returns to BASIC.
        r = new()
        r.hook("Keyboard.inKey", lambda: setattr(r.m, "a", ord("y")))
        r.m.memory[s["saved_sp"] : s["saved_sp"] + 2] = (0xFFD0).to_bytes(2, "little")
        r.m.memory[s["saved_ret"] : s["saved_ret"] + 2] = STOP.to_bytes(2, "little")
        r.m.memory[0xFFD0:0xFFD2] = STOP.to_bytes(2, "little")
        r.call("UI.quitConfirm")
        assert r.m.sp == 0xFFD2
    elif target == "NEXT":
        # Confirming on Next requests the same soft reset as exitClean;
        # stop at the branch so the NEXTREG write is only inspected.
        r = new()
        r.hook("Keyboard.inKey", lambda: setattr(r.m, "a", ord("y")))
        quit = s["UI.quitConfirm.hold"] - 5
        r.call("UI.quitConfirm", quit)
        assert bytes(r.m.memory[quit : quit + 5]) == b"\xf3\xed\x91\x02\x01"

    if target != "NEXT":
        # Exercise startup capture and the real AY clobber before exiting.
        r = new()
        r.m.alt_hl = 0x2758
        r.call("start", "Display.initFontCache")
        saved = int.from_bytes(
            r.m.memory[s["saved_hl_alt"] : s["saved_hl_alt"] + 2], "little"
        )
        assert saved == 0x2758
        r.call("UartImpl.uartRead")
        r.hook("Keyboard.waitBreakRelease")
        r.call("start.exitClean")
        assert r.m.alt_hl == 0x2758 and r.m.sp == 0xFFE2 and r.m.iff1
    else:
        # NEX startup must establish the ROM keyboard state and interrupt mode
        # before its first EI; LAST_K is populated by that handler.
        im1 = s["start.irqMode"]
        irq_enable = s["start.irqEnable"]
        assert bytes.fromhex("fd213a5c") in bytes(r.m.memory[im1 - 24 : im1])
        assert bytes(r.m.memory[im1 - 10 : im1 + 2]) == bytes.fromhex(
            "21230522095cfdcb01deed56"
        )
        assert im1 < irq_enable and r.m.memory[irq_enable] == 0xFB

    # Shorten only loop constants; exercise the real clobber/timeout control flow.
    r = new()
    r.feed(b"")
    reads = [0]
    raw_read = r.hooks[s["UartImpl.uartRead"]]

    def counted_read():
        reads[0] += 1
        raw_read()

    r.hook("UartImpl.uartRead", counted_read)
    outer = s["Uart.readTimeoutLong.outer"]
    assert r.m.memory[outer - 2] == 0x06
    r.m.memory[outer - 1] = 3
    r.m.memory[outer + 1 : outer + 3] = b"\x04\x00"
    r.m.bc, r.m.de, r.m.hl = 0x1122, 0x3344, 0x5566
    r.call("Uart.readTimeoutLong")
    assert not r.m.f & 1
    assert reads[0] == 12
    assert (r.m.bc, r.m.de, r.m.hl, r.m.sp) == (0x1122, 0x3344, 0x5566, 0xFFE2)

    # Boundary lengths must not overwrite adjacent RAM or split the next line.
    for reader in ("UI.readDiagLine", "UI.readDiagLineLong"):
        for length in (59, 60, 64, 80, 200):
            r = new()
            address = s["UI.diag_buffer"]
            r.m.memory[address : address + 72] = b"\xa5" * 72
            r.feed(b"X" * length + b"\rNEXT\r")
            r.call(reader)
            assert r.m.f & 1, (reader, length)
            assert bytes(r.m.memory[address : address + min(length, 60)]) == b"X" * min(
                length, 60
            )
            assert r.m.memory[address + min(length, 60)] == 0
            assert bytes(r.m.memory[address + 61 : address + 72]) == b"\xa5" * 11
            r.call(reader)
            assert bytes(r.m.memory[address : address + 5]) == b"NEXT\0", (
                reader,
                length,
            )
        r = new()
        r.feed(b"X" * 1024 + b"\r")
        r.call(reader)
        assert not r.m.f & 1 and r.get("Uart.io_error")

    # Cancellation must branch before any command is sent.
    r = new()
    for name in ("UI.diagHeader", "UI.printAt0", "UI.setPassRows8"):
        r.hook(name)

    def cancel():
        r.put("UI.pass_len", 4)
        r.m.set_memory_block(s["UI.pass_buffer"], b"name\0")
        r.m.f = 1

    r.hook("UI.passwordInput", cancel)
    r.call("UI.doHostname", "UI.showDiagnostics")
    assert r.m.sp == 0xFFE0 and r.get("UI.pass_no_warn") == 0
    assert r.get("UI.passwordInput.max") == s["UI.MAX_PASS_LEN"]

    for reason in (0, 2, 5):
        r = new()
        r.put("Wifi.last_error", reason)
        r.hook("Wifi.ensureCommandMode", lambda: r.put("Wifi.last_error", 0))
        r.call("UI.connectAndReturn.carFailed", "UI.showConnFailScreen")
        assert r.get("Wifi.last_error") == reason and r.m.sp == 0xFFE0

    for entry in (
        "UI.doPing.pingDone",
        "UI.doModuleInfo.gmrDone",
        "UI.doNetworkInfo.cifsrDone",
    ):
        r = new()
        r.hook("UI.showPressKey")
        r.hook("UI.waitAnyKey")
        r.call(entry, "UI.showDiagnostics")
        assert r.m.sp == 0xFFE0, entry

    # A failed partial rescan must not reuse a page beyond the shortened list.
    r = new()
    r.put("UI.offset", 20)
    r.put("UI.cursor_position", 4)
    for name in ("Display.gotoXY0", "Display.putC", "UI.hideCursor"):
        r.hook(name)

    def partial():
        r.put("Wifi.networks_count", 2)
        r.m.f = 1

    r.hook("Wifi.getList", partial)
    r.call("UI.doAutoRescan", "UI.renderListOnly")
    assert r.get("UI.offset") + r.get("UI.cursor_position") < 2

    # Parsers receive encoded fields, consumers must see the original bytes.
    expected = b'a"b,c\\d'
    encoded = b'a\\"b\\,c\\\\d'
    r = new()
    r.hook("Wifi.flushInput")
    r.hook("Wifi.espSendZ_CRLF")
    r.hook("Display.putStrLog")
    r.feed(b'+CWLAP:(3,"' + encoded + b'",-42,"00:11:22:33:44:55",6)\r\nOK\r\n')
    r.call("Wifi.getList")
    assert not r.m.f & 1 and r.get("Wifi.networks_count") == 1
    assert (
        bytes(r.m.memory[s["buffer"] : s["buffer"] + len(expected) + 1])
        == expected + b"\0"
    )
    for rejected in (b"X" * 33, b"bad\\q"):
        r = new()
        for name in ("Wifi.flushInput", "Display.putStrLog"):
            r.hook(name)
        r.hook("Wifi.espSendZ_CRLF")
        r.feed(
            b'+CWLAP:(3,"' + rejected + b'",-42,"mac",6)\r\n'
            b'+CWLAP:(3,"good",-42,"mac",6)\r\nOK\r\n'
        )
        r.call("Wifi.getList")
        assert not r.m.f & 1 and r.get("Wifi.networks_count") == 1
        assert bytes(r.m.memory[s["buffer"] : s["buffer"] + 5]) == b"good\0"
    r = new()
    r.feed(b'+CWJAP:"' + encoded + b'","00:11:22:33:44:55",6,-42\r\nOK\r\n')
    r.call("Wifi.checkConnection.waitCwJAP")
    assert not r.m.f & 1
    assert (
        bytes(
            r.m.memory[
                s["Wifi.connected_ssid"] : s["Wifi.connected_ssid"] + len(expected) + 1
            ]
        )
        == expected + b"\0"
    )

    # File ABI mocks preserve short-read RAM leftovers and exercise real validation.
    if target != "AY":
        valid = bytearray(
            b"NM\x1a\0\x01" + b"ssid\0" + bytes(28) + b"password\0" + bytes(32) + b"\0"
        )
        assert len(valid) == 80
        valid[79] = reduce(int.__xor__, valid[:79])
        cases = [
            (valid, 80, False, True),
            (valid, 5, False, False),
            (valid, 80, True, False),
        ]
        for begin, end in ((5, 38), (38, 79)):
            bad = valid.copy()
            bad[begin:end] = b"X" * (end - begin)
            bad[79] = reduce(int.__xor__, bad[:79])
            cases.append((bad, 80, False, False))
        for data, length, close_error, accepted in cases:
            r = new()
            r.m.set_memory_block(s["Config.cfg_buffer"], valid)

            def esxdos():
                return_address = int.from_bytes(
                    r.m.memory[r.m.sp : r.m.sp + 2], "little"
                )
                operation = r.m.memory[return_address]
                r.m.memory[r.m.sp : r.m.sp + 2] = (return_address + 1).to_bytes(
                    2, "little"
                )
                r.m.f = 0
                if operation == 0x9A:
                    r.m.a = 1
                elif operation == 0x9D:
                    r.m.set_memory_block(s["Config.cfg_buffer"], data[:length])
                    r.m.bc = length
                elif operation == 0x9B:
                    r.m.f = int(close_error)
                else:
                    raise AssertionError(operation)

            r.hook(8, esxdos)
            r.call("Config.load")
            assert bool(r.get("cfg_valid")) == accepted
            assert bool(r.m.f & 1) != accepted

        # A failed replacement must not advertise the new RAM block as saved.
        for failure in ("open", "write", "short", "close", None):
            r = new()
            r.put("cfg_valid", 1)
            r.m.set_memory_block(s["Config.cfg_buffer"], valid)
            r.m.set_memory_block(s["Wifi.connected_ssid"], b"new-network\0")
            r.m.set_memory_block(s["UI.pass_buffer"], b"new-password\0")
            writes = []

            def save_esxdos():
                at = int.from_bytes(r.m.memory[r.m.sp : r.m.sp + 2], "little")
                operation = r.m.memory[at]
                r.m.memory[r.m.sp : r.m.sp + 2] = (at + 1).to_bytes(2, "little")
                r.m.f = 0
                if operation == 0x9A:
                    r.m.a = 1
                    r.m.f = int(failure == "open")
                elif operation == 0x9E:
                    writes.append(bytes(r.m.memory[r.m.ix : r.m.ix + 80]))
                    r.m.bc = 5 if failure == "short" else 80
                    r.m.f = int(failure == "write")
                elif operation == 0x9B:
                    r.m.f = int(failure == "close")
                else:
                    raise AssertionError(operation)

            r.hook(8, save_esxdos)
            if target == "NEXT":
                r.hook("Config.createPath", lambda: setattr(r.m, "f", 1))
            r.call("Config.save")
            assert bool(r.get("cfg_valid")) == (failure is None), failure
            assert bool(r.m.f & 1) == (failure is not None), failure
            if failure is None:
                assert len(writes) == 1 and writes[0][5:17] == b"new-network\0"

    if target == "NEXT":
        # Init owns the ESP selection, prescaler bits 16:14 and the 8N1 frame.
        r = new()
        writes = []
        r.m.set_output_callback(lambda port, value: writes.append((port, value)))
        r.call("UartImpl.init")
        assert writes[:3] == [(0x153B, 0x30), (0x163B, 0x98), (0x163B, 0x18)], writes
        assert [port for port, _ in writes[3:]] == [0x243B, 0x143B, 0x143B], writes

        # Both TX and RX status reads must retain the hardware-cleared error.
        for entry in ("UartImpl.write", "UartImpl.uartRead"):
            r = new()
            r.m.set_input_callback(lambda port: 0x45 if port == 0x133B else ord("O"))
            r.call(entry)
            assert r.get("Uart.io_error")
            r.m.set_input_callback(lambda port: 0)
            r.call("Uart.readTimeoutLong")
            assert not r.m.f & 1

        # Reset restores persisted9600; recovery must normalize both ends again.
        r = new()
        baud = {"local": 115200, "device": 115200, "scans": 0}
        r.hook("UartImpl.init", lambda: baud.update(local=115200))
        r.hook("Wifi.flushInput", lambda: r.put("Uart.io_error", 0))

        def scan():
            baud.update(local=9600, scans=baud["scans"] + 1)
            r.m.f = 0

        r.hook("UartImpl.baudScan", scan)

        def command():
            text = bytes(r.m.memory[r.m.hl : r.m.hl + 80]).split(b"\0")[0]
            r.m.f = int(baud["device"] != baud["local"])
            if text.startswith(b"AT+UART_CUR=") and not r.m.f:
                baud["device"] = 115200
            elif text == b"AT+RST":
                baud["device"] = 9600

        r.hook("Wifi.espSendZCheckOk", command)
        r.hook("Wifi.espSendZ_CRLF", command)
        r.call("Wifi.reset")
        assert not r.m.f & 1 and baud == {"local": 115200, "device": 115200, "scans": 1}

    if target in ("NEXT", "UNO"):
        # Time paths on both targets: RTC loops/BCD, UI/RTC field order and
        # SNTP parsing. Run loads the UNO #6000 overlay the same way as Next.
        r = new()
        r.m.a = 42
        r.call("Rtc.binToBcd")
        assert r.m.a == 0x42
        if target == "NEXT":
            r.call("Rtc.dsSendByte")
            r.call("Rtc.dsReadByte")

        for routine, source, destination in (
            ("UI.timeCopyUiToRtc", "Sntp.fields", "Rtc.buf"),
            ("UI.timeCopyRtcToUi", "Rtc.buf", "UI.rtc_ui_buf"),
        ):
            for flags in range(256):
                r = new()
                fields = bytes((flags, flags ^ 255, 19, 18, 42, 0))
                r.m.set_memory_block(s[source], fields)
                r.m.bc, r.m.de, r.m.hl, r.m.ix = 0x1234, 0x5678, 0x9ABC, 0x2468
                r.m.f = flags
                r.call(routine)
                assert bytes(r.m.memory[s[destination]:s[destination] + 6]) == fields[::-1]
                assert (r.m.a, r.m.f, r.m.bc, r.m.de, r.m.hl, r.m.ix, r.m.iy, r.m.sp) == (
                    fields[0], flags, 0x1234, 0x5678, 0x9ABC, 0x2468, 0x5C3A, 0xFFE2
                )

        # Field formatting must emit ASCII digits, including zero-padded tens.
        r = new()
        r.m.set_memory_block(s["UI.rtc_ui_buf"], bytes((26, 9, 19, 18, 42, 5)))
        r.m.hl = s["UI.rtc_ui_buf"]
        rendered = []
        r.hook("Display.putC", lambda: rendered.append(r.m.a))
        r.call("UI.printFields")
        assert bytes(rendered) == b"19/09/2026 18:42:05"

        r = new()
        limit = s["Wifi.byte_limit"]
        r.m.memory[limit : limit + 2] = (4096).to_bytes(2, "little")
        r.put("Wifi.use_long_timeout", 0)
        r.feed(b"Sat Sep 19 18:42:05 2026\r\n")
        r.call("Sntp.parseTime")
        assert not r.m.f & 1
        assert bytes(r.m.memory[s["Sntp.cmd"] : s["Sntp.cmd"] + 6]) == bytes(
            (26, 9, 19, 18, 42, 5)
        )

        # NETTIME.CFG round trip through the same esxDOS ABI mocks as Config.
        valid_time = b"NT\x01\x02" + bytes((26, 9, 19, 18, 42, 5)) + bytes(5)
        valid_time += bytes((reduce(int.__xor__, valid_time),))
        for failure, accepted in (
            ("open", False),
            ("read", False),
            ("short", False),
            ("close", False),
            (None, True),
        ):
            r = new()
            r.put("Sntp.tz", 7)
            r.m.set_memory_block(s["Sntp.fields"], bytes(6))
            r.m.set_memory_block(s["UI.time_buffer"], b"\xa5" * 16)

            def load_esxdos():
                at = int.from_bytes(r.m.memory[r.m.sp : r.m.sp + 2], "little")
                operation = r.m.memory[at]
                r.m.memory[r.m.sp : r.m.sp + 2] = (at + 1).to_bytes(2, "little")
                r.m.f = 0
                if operation == 0x9A:
                    r.m.a = 1
                    r.m.f = int(failure == "open")
                elif operation == 0x9D:
                    r.m.set_memory_block(
                        s["UI.time_buffer"],
                        valid_time[: 5 if failure == "short" else 16],
                    )
                    r.m.bc = 5 if failure == "short" else 16
                    r.m.f = int(failure == "read")
                elif operation == 0x9B:
                    r.m.f = int(failure == "close")
                else:
                    raise AssertionError(operation)

            r.hook(8, load_esxdos)
            r.call("UI.loadTime")
            assert bool(r.m.f & 1) != accepted, failure
            if accepted:
                assert r.get("Sntp.tz") == 2
                assert bytes(
                    r.m.memory[s["Sntp.fields"] : s["Sntp.fields"] + 6]
                ) == bytes((26, 9, 19, 18, 42, 5))
            else:
                assert r.get("Sntp.tz") == 7

        # saveTime writes signature, tz, fields and checksum; failures surface.
        expected_time = b"NT\x01\xfb" + bytes((26, 9, 19, 18, 42, 5)) + bytes(5)
        expected_time += bytes((reduce(int.__xor__, expected_time),))
        for failure, accepted in (
            ("open", False),
            ("write", False),
            ("short", False),
            ("close", False),
            (None, True),
        ):
            r = new()
            r.put("Sntp.tz", 0xFB)
            r.m.set_memory_block(s["Sntp.fields"], bytes((26, 9, 19, 18, 42, 5)))
            writes = []

            def save_esxdos():
                at = int.from_bytes(r.m.memory[r.m.sp : r.m.sp + 2], "little")
                operation = r.m.memory[at]
                r.m.memory[r.m.sp : r.m.sp + 2] = (at + 1).to_bytes(2, "little")
                r.m.f = 0
                if operation == 0x9A:
                    r.m.a = 1
                    r.m.f = int(failure == "open")
                elif operation == 0x9E:
                    writes.append(bytes(r.m.memory[r.m.ix : r.m.ix + 16]))
                    r.m.bc = 5 if failure == "short" else 16
                    r.m.f = int(failure == "write")
                elif operation == 0x9B:
                    r.m.f = int(failure == "close")
                else:
                    raise AssertionError(operation)

            r.hook(8, save_esxdos)
            if target == "NEXT":
                r.hook("Config.createPath", lambda: setattr(r.m, "f", 1))
            r.call("UI.saveTime")
            assert bool(r.m.f & 1) != accepted, failure
            if accepted:
                assert writes == [expected_time], failure

        # Screen flows must return to the menu after BREAK, a missing WiFi
        # link, an SNTP failure or a NETTIME.CFG write failure.
        def time_screen(entry, calls, connected, sync_ok, save_ok):
            r = new()
            r.put("Wifi.debug_log", 1)
            r.put("Uart.log_enabled", 0)
            r.put("Wifi.is_connected", connected)
            r.put("Rtc.kind", 2 if target == "NEXT" else 1)
            for name in (
                "UI.diagHeader",
                "UI.printAt0",
                "Display.putStr",
                "Display.putC",
                "UI.restoreAfterFileIo",
                "Keyboard.waitBreakRelease",
            ):
                r.hook(name)
            r.hook("UI.loadTime", lambda: setattr(r.m, "f", 1))
            r.hook("Keyboard.inKeyNoWait", lambda: setattr(r.m, "a", ord(" ")))
            r.hook("Rtc.probe", lambda: setattr(r.m, "f", 1))
            r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40))

            def write():
                calls.append("rtc")
                r.m.f = 0

            r.hook("Rtc.writeTime", write)

            def sync():
                calls.append("sync")
                r.m.f = 0 if sync_ok else 1

            def save():
                calls.append("save")
                r.m.f = 0 if save_ok else 1

            r.hook("Sntp.sync", sync)
            r.hook("UI.saveTime", save)
            r.call(entry, "UI.renderListAndLoop")
            assert r.get("Uart.log_enabled") == 1, entry
            return r

        calls = []
        time_screen("UI.showTime", calls, 0, True, True)
        assert calls == [], calls

        calls = []
        time_screen("UI.showTime.sync", calls, 0, True, True)
        assert calls == [], calls

        calls = []
        time_screen("UI.showTime.sync", calls, 1, True, True)
        assert calls == ["sync", "rtc", "save"], calls

        calls = []
        time_screen("UI.showTime.sync", calls, 1, False, True)
        assert calls == ["sync"], calls

        calls = []
        time_screen("UI.showTime.sync", calls, 1, True, False)
        assert calls == ["sync", "rtc", "save"], calls

        # Zone entry must accept '+' and '-' and parse both signs.
        for typed, expected in ((b"+2\r", 2), (b"-2\r", 0xFE), (b"2\r", 2)):
            r = new()
            r.m.set_memory_block(s["UI.zone_buf"], bytes(4))
            r.m.memory[s["UI.sti_mode"]] = 2
            r.m.memory[s["UI.sti_len"]] = 0
            queue = deque(typed)
            r.hook(
                "Keyboard.inKeyNoWait",
                lambda: setattr(r.m, "a", queue.popleft() if queue else 0),
            )
            r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0))
            r.m.hl, r.m.b = s["UI.zone_buf"], 3
            r.call("UI.ipTextInput")
            assert not r.m.f & 1, typed
            entered = typed[:-1] + b"\0"
            assert (
                bytes(r.m.memory[s["UI.zone_buf"] : s["UI.zone_buf"] + len(entered)])
                == entered
            ), typed
            r.call("UI.parseZone")
            assert not r.m.f & 1 and r.m.memory[s["Sntp.tz"]] == expected, typed

        # The SNTP config command must carry the timezone before any option.
        r = new()
        r.put("Sntp.tz", 2)
        r.call("Sntp.buildCfg")
        line = bytes(r.m.memory[s["Sntp.cmd"] : s["Sntp.cmd"] + 56]).split(b"\0")[0]
        assert line == b'AT+CIPSNTPCFG=1,2,"pool.ntp.org","time.google.com"', line
        r.put("Sntp.tz", 0xFE)
        r.call("Sntp.buildCfg")
        line = bytes(r.m.memory[s["Sntp.cmd"] : s["Sntp.cmd"] + 56]).split(b"\0")[0]
        assert line == b'AT+CIPSNTPCFG=1,-2,"pool.ntp.org","time.google.com"', line

        # The big-font editor covers rows 13-14; leaving the zone input must
        # not leave the lower half of its glyphs behind.
        r = new()
        queue = deque(b"z+2\r")
        r.hook(
            "Keyboard.inKeyNoWait",
            lambda: setattr(r.m, "a", queue.popleft() if queue else 0),
        )
        r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0))
        r.hook("UI.waitAnyKey")
        r.hook("Rtc.probe", lambda: setattr(r.m, "f", 1))
        r.hook("UI.restoreAfterFileIo")

        def zone_esxdos():
            at = int.from_bytes(r.m.memory[r.m.sp : r.m.sp + 2], "little")
            operation = r.m.memory[at]
            r.m.memory[r.m.sp : r.m.sp + 2] = (at + 1).to_bytes(2, "little")
            r.m.f = 0
            if operation == 0x9A:
                r.m.a = 1
            elif operation == 0x9D:
                r.m.bc = 0
            elif operation == 0x9E:
                r.m.bc = 16
            elif operation == 0x9B:
                pass
            else:
                raise AssertionError(operation)

        r.hook(8, zone_esxdos)
        r.call("UI.showTime", s["UI.showTime.wait"])

        # The zone editor is its own modal screen in the standard dialog
        # shape: big-font field on rows 8-9 over the input colour band, help
        # on row 11. Sample the screen on every key, keeping the last state
        # before ENTER, when the field actually holds text.
        ATTR_PASS_INPUT = 0o171
        shape = {}

        def drawn(n):
            addr = 0x4000 + (n // 8) * 0x800 + (n % 8) * 32
            return any(
                any(r.m.memory[addr + 0x100 * line : addr + 0x100 * line + 32])
                for line in range(8)
            )

        def snapshot():
            shape["prompt"] = drawn(6)
            shape["field"] = drawn(8)
            shape["tail"] = drawn(9)
            shape["help"] = drawn(11)
            shape["attr8"] = r.m.memory[0x5800 + 8 * 32]
            shape["attr9"] = r.m.memory[0x5800 + 9 * 32]

        r.hook(
            "Keyboard.inKeyNoWait",
            lambda: (snapshot(), setattr(r.m, "a", queue.popleft() if queue else 0)),
        )
        r.call("UI.showTime.zone", s["UI.showTime.wait"])
        assert not queue
        assert shape["prompt"], "zone prompt not on row 6"
        assert shape["field"] and shape["tail"], "zone field not on rows 8-9"
        assert shape["help"], "zone help not on row 11"
        assert (
            shape["attr8"] == ATTR_PASS_INPUT and shape["attr9"] == ATTR_PASS_INPUT
        ), "zone field missing the input colour band"

        # Leaving the editor rebuilds the Time screen: nothing of the dialog
        # survives below the hint row.
        for n in (12, 13, 14):
            assert not drawn(n), f"dialog residue left on row {n}"

        # The Time screen refreshes the clock value once a second and nothing
        # else: the RTC name (row 6) and the zone (row 8) do not change.
        def row(n):
            return 0x4000 + (n // 8) * 0x800 + (n % 8) * 32

        def pixels(run, n):
            return b"".join(
                bytes(run.m.memory[row(n) + 0x100 * line : row(n) + 0x100 * line + 32])
                for line in range(8)
            )

        r = new()
        r.put("Rtc.kind", 1)
        r.put("Rtc.valid", 1)
        reads = []

        def read_rtc():
            reads.append(1)
            r.m.set_memory_block(r.s["Rtc.buf"], bytes((5, 42, 18, 19, 9, 26)))
            r.m.f = 0

        r.hook("Rtc.read", read_rtc)
        r.m.memory[0x5C78] = 50
        r.call("UI.showTime.tick")
        assert reads == [1], "clock not refreshed"
        assert any(pixels(r, 7)), "clock value not drawn"
        assert not any(pixels(r, 6)), "RTC name row repainted"
        assert not any(pixels(r, 8)), "zone row repainted"
        assert r.get("UI.time_last_frame") == 50

        # Below a full second nothing is read and nothing is drawn.
        before = pixels(r, 7)
        r.m.memory[0x5C78] = 99
        r.call("UI.showTime.tick")
        assert reads == [1], "sub-second refresh"
        assert pixels(r, 7) == before

        # A second later the field is overwritten in place: same width, so no
        # clear step is needed and no residue is left.
        def read_later():
            reads.append(1)
            r.m.set_memory_block(r.s["Rtc.buf"], bytes((7, 42, 18, 19, 9, 26)))
            r.m.f = 0

        r.hook("Rtc.read", read_later)
        r.m.memory[0x5C78] = 100
        r.call("UI.showTime.tick")
        assert len(reads) == 2
        assert pixels(r, 7) != before, "clock value not updated"

        # A source that cannot be re-read keeps the value probe captured.
        r = new()
        r.put("Rtc.kind", 3)  # esxDOS driver: Rtc.read returns CF=1
        r.put("Rtc.valid", 1)
        r.m.memory[0x5C78] = 50
        r.call("UI.showTime.tick")
        assert not any(pixels(r, 7)), "unreadable source repainted the clock"

        # Sync results must be visible on the hint row. Regression: clearing
        # the row with clearRowPixels destroyed HL before printAt0.
        for sync_ok in (True, False):
            r = new()
            r.put("Wifi.is_connected", 1)
            r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0))
            r.hook("Keyboard.inKeyNoWait", lambda: setattr(r.m, "a", 0))
            r.hook("UI.loadTime", lambda: setattr(r.m, "f", 1))
            r.hook("Rtc.probe", lambda: setattr(r.m, "f", 1))
            r.hook("Sntp.sync", lambda: setattr(r.m, "f", 0 if sync_ok else 1))
            r.hook("UI.saveTime", lambda: setattr(r.m, "f", 0))
            r.hook("UI.restoreAfterFileIo")
            r.call("UI.showTime", s["UI.showTime.wait"])
            r.call("UI.showTime.sync", s["UI.showTime.msgWait"])
            base = 0x4000 + (11 // 8) * 0x800 + (11 % 8) * 32
            assert any(r.m.memory[base : base + 32]), f"blank sync message ({sync_ok})"

        # Returning from zone input refreshes values without rebuilding the
        # static diagnostic header.
        r = new()
        header_calls = []
        r.hook("UI.loadTime", lambda: setattr(r.m, "f", 1))
        r.hook("UI.restoreAfterFileIo")
        r.hook("Rtc.probe", lambda: setattr(r.m, "f", 1))
        r.hook("UI.diagHeader", lambda: header_calls.append(True))
        for name in (
            "UI.printAt0",
            "Display.putStr",
            "Display.putC",
            "UI.clearRowPixels",
            "Keyboard.keyClick",
        ):
            r.hook(name)
        keys = deque((ord("z"),))
        r.hook(
            "Keyboard.inKeyNoWait",
            lambda: (setattr(r.m, "a", keys.popleft()), setattr(r.m, "f", 0)),
        )
        breaks = deque((0, 0x40))
        r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", breaks.popleft()))
        r.hook("UI.ipTextInput", lambda: setattr(r.m, "f", 0))
        r.hook("UI.parseZone", lambda: setattr(r.m, "f", 0))
        r.hook("UI.persistTime", lambda: setattr(r.m, "f", 0))
        r.call("UI.showTime", "UI.renderListAndLoop")
        assert len(header_calls) == 1

    if target == "UNO":
        counts = []
        for hl in (1, 0xFFFF):
            r = new()
            reads = []
            r.put("UartImpl.is_recv", 1)
            r.m.hl = hl
            r.m.set_input_callback(lambda port: reads.append(port) or 0xC0)
            r.call("UartImpl.write")
            assert r.get("Uart.io_error") and r.m.hl == hl
            counts.append(len(reads))
        assert counts[0] == counts[1] == s["Uart.TX_TIMEOUT"] + 1

        # Real reader: ready flag in CF, data byte intact, DE/HL preserved.
        for status, data in ((0x40, None), (0x80, 0x5A), (0xC0, 0x00)):
            r = new()
            selected, data_reads = [0], []

            def select(port, value):
                if port == 0xFC3B:
                    selected[0] = value

            def read(port):
                if selected[0] == 0xC7:
                    return status
                data_reads.append(port)
                return data

            r.m.set_output_callback(select)
            r.m.set_input_callback(read)
            r.m.de, r.m.hl = 0x1234, 0x5678
            r.call("UartImpl.uartRead")
            assert bool(r.m.f & 1) == (data is not None), status
            assert len(data_reads) == (data is not None), status
            if data is not None:
                assert r.m.a == data
            assert (r.m.de, r.m.hl, r.m.sp) == (0x1234, 0x5678, 0xFFE2)

        # A latched fault ends a timed read before the UART is touched.
        r = new()
        r.put("Uart.io_error", 1)
        r.m.set_input_callback(
            lambda port: (_ for _ in ()).throw(AssertionError("UART polled"))
        )
        r.call("Uart.readTimeout")
        assert not r.m.f & 1 and r.m.sp == 0xFFE2

        # esxDOS driver RTC: packed fields must decode into RTC order.
        r = new()

        def esx_rtc():
            at = int.from_bytes(r.m.memory[r.m.sp : r.m.sp + 2], "little")
            assert r.m.memory[at] == 0x92
            r.m.memory[r.m.sp : r.m.sp + 2] = (at + 1).to_bytes(2, "little")
            r.m.f = 0
            r.m.b, r.m.c, r.m.d, r.m.e = 52, 51, 149, 66

        r.hook(8, esx_rtc)
        r.call("Rtc.probe")
        assert not r.m.f & 1 and r.get("Rtc.kind") == 3
        assert bytes(r.m.memory[s["Rtc.buf"] : s["Rtc.buf"] + 6]) == bytes(
            (4, 42, 18, 19, 1, 6)
        )
        # The esxDOS route is read-only and must not emit I2C traffic.
        r.call("Rtc.writeTime")
        assert r.m.f & 1

        # No RTC on the bus: probe fails cleanly and leaves kind=0.
        r = new()

        def no_rtc():
            at = int.from_bytes(r.m.memory[r.m.sp : r.m.sp + 2], "little")
            r.m.memory[r.m.sp : r.m.sp + 2] = (at + 1).to_bytes(2, "little")
            r.m.f = 1

        r.hook(8, no_rtc)
        r.call("Rtc.probe")
        assert r.m.f & 1 and r.get("Rtc.kind") == 0

        # PCF8563 read path: emulate the chip on #FD3B and verify detection
        # and field decoding. A set VL flag must not be reported as a clock.
        for seconds, detected in ((0x45, True), (0xC5, False)):
            r = new()
            r.hook(8, no_rtc)
            data = bytes((seconds, 0x42, 0x18, 0x19, 0x01, 0x09, 0x26))
            st = {
                "sda": 1,
                "scl": 1,
                "state": "idle",
                "byte": 0,
                "bits": 0,
                "reg": None,
                "idx": 0,
            }

            def pcf_out(port, value):
                if port != 0xFD3B:
                    return
                sda, scl = value & 1, (value >> 1) & 1
                if scl and sda != st["sda"]:
                    if sda:
                        st.update(state="idle", bits=0, byte=0)  # STOP
                    else:
                        st.update(state="addr", bits=0, byte=0)  # START
                elif scl and not st["scl"]:
                    if st["state"] in ("addr", "reg"):
                        st["bits"] += 1
                        if st["bits"] <= 8:
                            st["byte"] = (st["byte"] << 1) | sda
                            if st["bits"] == 8:
                                st["value"] = st["byte"]
                                st["byte"] = 0
                        else:  # 9th clock = master ACK slot
                            st["bits"] = 0
                            value8 = st["value"]
                            if st["state"] == "addr":
                                if value8 == 0xA2:
                                    st["state"] = "reg"
                                elif value8 == 0xA3 and st["reg"] is not None:
                                    st.update(state="read", idx=0)
                                else:
                                    st["state"] = "idle"
                            else:
                                st.update(reg=value8, state="addr")
                    elif st["state"] == "read":
                        if st["bits"] < 8:
                            st["bits"] += 1
                        else:
                            st["bits"] = 0
                            st["idx"] += 1
                            if st["idx"] >= len(data):
                                st.update(state="idle")
                st["sda"], st["scl"] = sda, scl

            def pcf_in(port):
                if port == 0xFD3B and st["state"] == "read" and 1 <= st["bits"] <= 8:
                    bit = (data[st["idx"]] >> (8 - st["bits"])) & 1
                    return 0xFF if bit else 0
                if port == 0xFD3B and st["state"] != "idle" and st["bits"] == 0:
                    return 0  # Chip ACK after the ninth clock.
                return 0xFF

            r.m.set_output_callback(pcf_out)
            r.m.set_input_callback(pcf_in)
            r.call("Rtc.probe")
            if detected:
                assert not r.m.f & 1 and r.get("Rtc.kind") == 1
                assert bytes(r.m.memory[s["Rtc.buf"] : s["Rtc.buf"] + 6]) == bytes(
                    (45, 42, 18, 19, 9, 26)
                )
            else:
                assert r.m.f & 1 and r.get("Rtc.kind") == 0

        # PCF8563 write: sniff the bit-banged bus and check register order.
        r = new()
        r.put("Rtc.kind", 1)
        r.m.memory[s["Rtc.i2c_mask"]] = 1
        r.m.set_memory_block(s["Rtc.buf"], bytes((4, 42, 18, 19, 9, 26)))
        bus = {"sda": 1, "scl": 1, "byte": 0, "bits": 0}
        bytes_out = []

        def i2c_sniff(port, value):
            if port != 0xFD3B:
                return
            sda, scl = value & 1, (value >> 1) & 1
            if scl and sda != bus["sda"]:
                # START/STOP: SDA moves while SCL is high, no data bit.
                bus["byte"], bus["bits"] = 0, 0
            elif scl and not bus["scl"]:
                bus["byte"] = (bus["byte"] << 1) | sda
                bus["bits"] += 1
                if bus["bits"] == 9:
                    bytes_out.append(bus["byte"] >> 1)
                    bus["byte"], bus["bits"] = 0, 0
            bus["sda"], bus["scl"] = sda, scl

        r.m.set_output_callback(i2c_sniff)
        r.m.set_input_callback(lambda port: 0 if port == 0xFD3B else 0xFF)
        r.call("Rtc.writeTime")
        assert not r.m.f & 1
        assert bytes_out == [
            0xA2,
            0,
            0,
            0,
            0xA2,
            0x02,
            0x04,
            0x42,
            0x18,
            0x19,
            0x06,
            0x09,
            0x26,
        ], bytes_out

    # Non-returning screen helpers must never be called as subroutines.
    ui = (ROOT / "src/modules/ui.asm").read_text()
    assert not re.search(
        r"\bcall\s+(?:pressKeyReturnDiag|pressKeyReturnList)\b", ui, re.I
    )
    assert "cmd_autoconn_off" not in ui


def check_nex(image, symbols):
    # Verify the actual file consumed by NextZXOS, including its loading assets.
    nex = (BUILD / "netmanzx.nex").read_bytes()
    palette = (ROOT / "assets/splash.pal").read_bytes()
    screen = (ROOT / "assets/splash.nxi").read_bytes()
    assert nex[:8] == b"NextV1.2"
    assert nex[9] == 3 and nex[10] == 1
    assert {bank for bank, present in enumerate(nex[18:130]) if present} == {0, 2, 16}
    assert int.from_bytes(nex[12:14], "little") == symbols["stack_top"]
    assert int.from_bytes(nex[14:16], "little") == symbols["start"]
    assert nex[134] == 0 and nex[139] == 0
    assert len(palette) == 512 and len(screen) == 49152
    assert nex[512:1024] == palette
    assert nex[1024 : 1024 + len(screen)] == screen
    payload = nex[1024 + len(screen) :]
    assert len(payload) == 3 * 16384
    # Bank 2 precedes bank 0; loading them must reproduce all compiled data.
    assert payload[:16384] == image[:16384]
    data_length = symbols["static_data_end"] - 0xC000
    assert payload[16384 : 16384 + data_length] == image[16384 : 16384 + data_length]
    assert not any(payload[16384 + data_length : 32768])
    # Bank 16 carries the paged cold code assembled at #6000.
    overlay = payload[32768:49152]
    overlay_length = symbols["overlay_end"] - 0x6000
    assert 0 < overlay_length <= 0x2000 and overlay[:overlay_length]
    assert not any(payload[32768 + overlay_length :])


def check_ay_probe():
    stem = BUILD / "ay-timing-probe"
    subprocess.run(
        [
            "sjasmplus",
            "--nologo",
            "--msg=war",
            "-isrc",
            f"--outprefix={BUILD}/",
            f"--sym={stem}.sym",
            "tests/ay_timing_probe.asm",
        ],
        cwd=ROOT,
        check=True,
    )
    symbols = {
        name: int(value, 16)
        for name, value in re.findall(
            r"^(\S+): EQU 0x([0-9A-Fa-f]+)$", stem.with_suffix(".sym").read_text(), re.M
        )
    }
    symbols["program_end"] = symbols["probe_end"]
    for mode in (0, 1):
        for cancel in (False, True):
            r = Run(stem.with_suffix(".bin").read_bytes(), symbols)
            r.hook("Uart.init")
            r.hook("Keyboard.waitBreakRelease")
            r.m.alt_hl = 0x2758
            r.m.memory[0x6000] = mode
            r.m.memory[0x600C:0x600E] = (3).to_bytes(2, "little")
            r.m.memory[0x5C78:0x5C7B] = (100).to_bytes(3, "little")
            reads, markers = [], []

            def read():
                reads.append(1)
                r.m.f = len(reads) & 1
                r.m.memory[0x5C78] += 1
                if cancel and mode:
                    r.put("Uart.break_hit", 1)

            r.hook("Uart.readTimeout" if mode else "UartImpl.uartRead", read)
            r.hook(
                "Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40 if cancel else 0)
            )
            r.m.set_output_callback(
                lambda port, value: markers.append(value) if port & 255 == 254 else None
            )
            r.call("probe")
            count = 1 if cancel else 3
            assert len(reads) == count and markers == [2, 4]
            assert bytes(r.m.memory[0x6001:0x6006]) == bytes(
                (int(cancel), count, 0, (count + 1) // 2, 0)
            )
            assert int.from_bytes(r.m.memory[0x6006:0x6009], "little") == 100
            assert int.from_bytes(r.m.memory[0x6009:0x600C], "little") == 100 + count
            assert r.m.alt_hl == 0x2758 and r.m.sp == 0xFFE2 and r.m.iff1
    print(
        "AY timing probe: control-flow checks passed (no hardware timing claim)",
        flush=True,
    )


def main():
    global COLD_OVERLAY
    BUILD.mkdir(exist_ok=True)
    check_ay_probe()
    import test_dos_audit

    test_dos_audit.check_removed_ay()
    test_dos_audit.check()
    for target in sys.argv[1:] or ("AY", "NEXT", "UNO"):
        assert target in ("AY", "NEXT", "UNO")
        stem = BUILD / f"audit-{target.lower()}"
        args = [
            "sjasmplus",
            "--nologo",
            "--msg=war",
            f"-D{target}",
            "-isrc",
            "-iassets",
            f"--outprefix={BUILD}/",
            f"--sym={stem}.sym",
            f"--raw={stem}.bin",
        ]
        if target != "NEXT":
            args.append("-DTAP")
        subprocess.run(args + ["src/main.asm"], cwd=ROOT, check=True)
        symbols = {
            name: int(value, 16)
            for name, value in re.findall(
                r"^(\S+): EQU 0x([0-9A-Fa-f]+)$",
                stem.with_suffix(".sym").read_text(),
                re.M,
            )
        }
        COLD_OVERLAY = None
        if target == "NEXT":
            nex = (BUILD / "netmanzx.nex").read_bytes()
            payload = nex[1024 + 49152 :]
            COLD_OVERLAY = payload[32768 : 32768 + 8192]
        else:
            COLD_OVERLAY = tap_code(BUILD / "netmanzx.tap", 0x6000)
            assert len(COLD_OVERLAY) == symbols["tap_overlay_end"] - 0x6000
        # When this file runs as a script, test modules import a second copy of
        # this module; keep both instances in sync.
        import audit_regression as _ar

        _ar.COLD_OVERLAY = COLD_OVERLAY
        # --raw is the emitted stream, not a memory image. TAP builds skip the
        # gap below #C000 and ship the static data as its own CODE block, so
        # rebuild the contiguous #8000 view the checks expect.
        raw = stem.with_suffix(".bin").read_bytes()
        code_len = symbols["program_end"] - 0x8000
        data_len = symbols["static_data_end"] - 0xC000
        if target == "NEXT":
            image = raw[: symbols["static_data_end"] - 0x8000]
        else:
            image = (
                raw[:code_len]
                + bytes(0xC000 - symbols["program_end"])
                + raw[code_len : code_len + data_len]
            )
        assert len(image) == symbols["static_data_end"] - 0x8000
        check(image, symbols, target)
        for module in (
            "test_ui_followup",
            "test_editor_optimization",
            "test_display_followup",
            "test_font64",
            "test_transport_followup",
            "test_clock_audit",
            "test_audit_control_flow",
            "test_audit_entry_path",
            "test_audit_wifi_recovery",
            "test_audit_uart_diag",
            "test_ui_audit",
            "test_scan_audit",
        ):
            __import__(module).check(image, symbols, target)
        if target == "NEXT":
            check_nex(image, symbols)
        else:
            lines = tap_basic_lines(BUILD / "netmanzx.tap")
            # Overlay, program, static data, then splash last so its image
            # covers the ROM "Bytes:" messages.
            assert lines == [10, 20, 30, 35, 37, 40, 50], lines
            blocks = tap_code_blocks(BUILD / "netmanzx.tap")
            want = [0x6000, 0x8000, 0xC000, 0x4000]
            assert [address for address, _ in blocks] == want, blocks
            sizes = dict(blocks)
            assert sizes[0x6000] == symbols["tap_overlay_end"] - 0x6000
            assert sizes[0x8000] == symbols["program_end"] - 0x8000
            assert sizes[0xC000] == symbols["static_data_end"] - 0xC000
            assert sizes[0x4000] == 6912
        suffix = "nex" if target == "NEXT" else "tap"
        (BUILD / f"netmanzx.{suffix}").replace(
            BUILD / f"netmanzx-{target.lower()}.{suffix}"
        )
        print(
            f"{target}: audit regression checks passed; code headroom {0xC000 - symbols['program_end']} bytes",
            flush=True,
        )


if __name__ == "__main__":
    main()
