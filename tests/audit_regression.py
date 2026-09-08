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
STOP = 0x7000


class Run:
    def __init__(self, image, symbols):
        self.s = symbols
        self.m = z80.Z80Machine()
        self.m.set_memory_block(0x8000, image[:symbols.get("static_data_end", symbols["program_end"]) - 0x8000])
        # Minimal IM1 clock: preserve registers and increment ROM FRAMES.
        self.m.set_memory_block(0x38, bytes.fromhex("f5 e5 21 78 5c 34 20 02 23 34 e1 f1 fb c9"))
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
        self.m.pc = int.from_bytes(self.m.memory[self.m.sp:self.m.sp + 2], "little")
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
        m.memory[m.sp:m.sp + 2] = STOP.to_bytes(2, "little")
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

    # Both menu states fit 42 columns and show the full Diagnostics label.
    for name in ("UI.msg_help", "UI.msg_help_conn"):
        r = new()
        line = bytes(r.m.memory[s[name]:s[name] + 64]).split(b"\0")[0]
        assert len(line) <= 42 and line.endswith(b"D:Diagnostics")
        assert b"BREAK" not in line and b"QUIT" not in line

    # A cancellation chord must be released before the menu accepts Quit.
    r = new()
    keys = deque((0x40, 0x40, 0))
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", keys.popleft()))
    r.call("UI.uiLoop", "UI.uiLoopMain")
    assert not keys and r.m.sp == 0xFFE0
    r = new()
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40))
    r.call("UI.uiLoopMain", "start.exitClean")
    assert r.m.sp == 0xFFE0

    r = new()
    released = []
    r.hook("Keyboard.waitBreakRelease", lambda: released.append(True))
    if target == "NEXT":
        reset = s["start.resetPending"] - 5
        r.call("start.exitClean", reset)
        # DI; NEXTREG $02,$01 requests soft reset, never ESP/hard reset.
        assert bytes(r.m.memory[reset:reset + 5]) == b"\xf3\xed\x91\x02\x01"
    else:
        r.m.memory[s["saved_sp"]:s["saved_sp"] + 2] = (0xFFD0).to_bytes(2, "little")
        r.m.memory[0xFFD0:0xFFD2] = STOP.to_bytes(2, "little")
        r.call("start.exitClean")
        assert r.m.sp == 0xFFD2
    assert released == [True]

    if target != "NEXT":
        # Exercise startup capture and the real AY clobber before BASIC return.
        r = new()
        r.m.alt_hl = 0x2758
        r.call("start", "Display.initFontCache")
        saved = int.from_bytes(r.m.memory[s["saved_hl_alt"]:s["saved_hl_alt"] + 2], "little")
        assert saved == 0x2758
        r.call("UartImpl.uartRead")
        if target == "AY":
            assert r.m.alt_hl == 0
        r.hook("Keyboard.waitBreakRelease")
        r.call("start.exitClean")
        assert r.m.alt_hl == 0x2758 and r.m.sp == 0xFFE2 and r.m.iff1

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
    r.m.memory[outer + 1:outer + 3] = b"\x04\x00"
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
            r.m.memory[address:address + 72] = b"\xa5" * 72
            r.feed(b"X" * length + b"\rNEXT\r")
            r.call(reader)
            assert r.m.f & 1, (reader, length)
            assert bytes(r.m.memory[address:address + min(length, 60)]) == b"X" * min(length, 60)
            assert r.m.memory[address + min(length, 60)] == 0
            assert bytes(r.m.memory[address + 61:address + 72]) == b"\xa5" * 11
            r.call(reader)
            assert bytes(r.m.memory[address:address + 5]) == b"NEXT\0", (reader, length)
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

    for entry in ("UI.doPing.pingDone", "UI.doModuleInfo.gmrDone", "UI.doNetworkInfo.cifsrDone"):
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
    assert bytes(r.m.memory[s["buffer"]:s["buffer"] + len(expected) + 1]) == expected + b"\0"
    for rejected in (b"X" * 33, b"bad\\q"):
        r = new()
        for name in ("Wifi.flushInput", "Wifi.espSendZ_CRLF", "Display.putStrLog"):
            r.hook(name)
        r.feed(b'+CWLAP:(3,"' + rejected + b'",-42,"mac",6)\r\n'
               b'+CWLAP:(3,"good",-42,"mac",6)\r\nOK\r\n')
        r.call("Wifi.getList")
        assert not r.m.f & 1 and r.get("Wifi.networks_count") == 1
        assert bytes(r.m.memory[s["buffer"]:s["buffer"] + 5]) == b"good\0"
    r = new()
    r.feed(b'+CWJAP:"' + encoded + b'","00:11:22:33:44:55",6,-42\r\n')
    r.call("Wifi.checkConnection.waitCwJAP")
    assert not r.m.f & 1
    assert bytes(r.m.memory[s["Wifi.connected_ssid"]:s["Wifi.connected_ssid"] + len(expected) + 1]) == expected + b"\0"

    # File ABI mocks preserve short-read RAM leftovers and exercise real validation.
    if target != "AY":
        valid = bytearray(b"NM\x1a\0\x01" + b"ssid\0" + bytes(28) + b"password\0" + bytes(32) + b"\0")
        assert len(valid) == 80
        valid[79] = reduce(int.__xor__, valid[:79])
        cases = [(valid, 80, False, True), (valid, 5, False, False), (valid, 80, True, False)]
        for begin, end in ((5, 38), (38, 79)):
            bad = valid.copy()
            bad[begin:end] = b"X" * (end - begin)
            bad[79] = reduce(int.__xor__, bad[:79])
            cases.append((bad, 80, False, False))
        for data, length, close_error, accepted in cases:
            r = new()
            r.m.set_memory_block(s["Config.cfg_buffer"], valid)

            def esxdos():
                return_address = int.from_bytes(r.m.memory[r.m.sp:r.m.sp + 2], "little")
                operation = r.m.memory[return_address]
                r.m.memory[r.m.sp:r.m.sp + 2] = (return_address + 1).to_bytes(2, "little")
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
                at = int.from_bytes(r.m.memory[r.m.sp:r.m.sp + 2], "little")
                operation = r.m.memory[at]
                r.m.memory[r.m.sp:r.m.sp + 2] = (at + 1).to_bytes(2, "little")
                r.m.f = 0
                if operation == 0x9A:
                    r.m.a = 1
                    r.m.f = int(failure == "open")
                elif operation == 0x9E:
                    writes.append(bytes(r.m.memory[r.m.ix:r.m.ix + 80]))
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
            text = bytes(r.m.memory[r.m.hl:r.m.hl + 80]).split(b"\0")[0]
            r.m.f = int(baud["device"] != baud["local"])
            if text.startswith(b"AT+UART_CUR=") and not r.m.f:
                baud["device"] = 115200
            elif text == b"AT+RST":
                baud["device"] = 9600
        r.hook("Wifi.espSendZCheckOk", command)
        r.hook("Wifi.espSendZ_CRLF", command)
        r.call("Wifi.reset")
        assert not r.m.f & 1 and baud == {"local": 115200, "device": 115200, "scans": 1}

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
        assert counts[0] == counts[1] == s["Uart.DEFAULT_TIMEOUT"] + 1

    # Non-returning screen helpers must never be called as subroutines.
    ui = (ROOT / "src/modules/ui.asm").read_text()
    assert not re.search(r"\bcall\s+(?:pressKeyReturnDiag|pressKeyReturnList)\b", ui, re.I)
    assert "cmd_autoconn_off" not in ui


def check_nex(image, symbols):
    # Verify the actual file consumed by NextZXOS, including its loading assets.
    nex = (BUILD / "netmanzx.nex").read_bytes()
    palette = (ROOT / "assets/splash.pal").read_bytes()
    screen = (ROOT / "assets/splash.nxi").read_bytes()
    assert nex[:8] == b"NextV1.2"
    assert nex[9] == 2 and nex[10] == 1
    assert {bank for bank, present in enumerate(nex[18:130]) if present} == {0, 2}
    assert int.from_bytes(nex[12:14], "little") == symbols["stack_top"]
    assert int.from_bytes(nex[14:16], "little") == symbols["start"]
    assert nex[134] == 0 and nex[139] == 0
    assert len(palette) == 512 and len(screen) == 49152
    assert nex[512:1024] == palette
    assert nex[1024:1024 + len(screen)] == screen
    payload = nex[1024 + len(screen):]
    assert len(payload) == 2 * 16384
    # Bank 2 precedes bank 0; loading them must reproduce all compiled data.
    assert payload[:16384] == image[:16384]
    data_length = symbols["static_data_end"] - 0xC000
    assert payload[16384:16384 + data_length] == image[16384:16384 + data_length]
    assert not any(payload[16384 + data_length:])


def check_ay_probe():
    stem = BUILD / "ay-timing-probe"
    subprocess.run(["sjasmplus", "--nologo", "--msg=war", "-isrc",
                    f"--outprefix={BUILD}/", f"--sym={stem}.sym",
                    "tests/ay_timing_probe.asm"], cwd=ROOT, check=True)
    symbols = {name: int(value, 16) for name, value in
               re.findall(r"^(\S+): EQU 0x([0-9A-Fa-f]+)$", stem.with_suffix(".sym").read_text(), re.M)}
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
            r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40 if cancel else 0))
            r.m.set_output_callback(lambda port, value: markers.append(value) if port & 255 == 254 else None)
            r.call("probe")
            count = 1 if cancel else 3
            assert len(reads) == count and markers == [2, 4]
            assert bytes(r.m.memory[0x6001:0x6006]) == bytes((int(cancel), count, 0, (count + 1) // 2, 0))
            assert int.from_bytes(r.m.memory[0x6006:0x6009], "little") == 100
            assert int.from_bytes(r.m.memory[0x6009:0x600C], "little") == 100 + count
            assert r.m.alt_hl == 0x2758 and r.m.sp == 0xFFE2 and r.m.iff1
    print("AY timing probe: control-flow checks passed (no hardware timing claim)", flush=True)


def main():
    BUILD.mkdir(exist_ok=True)
    check_ay_probe()
    for target in sys.argv[1:] or ("AY", "NEXT", "UNO"):
        assert target in ("AY", "NEXT", "UNO")
        stem = BUILD / f"audit-{target.lower()}"
        args = ["sjasmplus", "--nologo", "--msg=war", f"-D{target}", "-isrc", "-iassets",
                f"--outprefix={BUILD}/", f"--sym={stem}.sym", f"--raw={stem}.bin"]
        if target != "NEXT":
            args.append("-DTAP")
        subprocess.run(args + ["src/main.asm"], cwd=ROOT, check=True)
        symbols = {name: int(value, 16) for name, value in
                   re.findall(r"^(\S+): EQU 0x([0-9A-Fa-f]+)$", stem.with_suffix(".sym").read_text(), re.M)}
        check(stem.with_suffix(".bin").read_bytes(), symbols, target)
        for module in ("test_ui_followup", "test_display_followup", "test_transport_followup"):
            __import__(module).check(stem.with_suffix(".bin").read_bytes(), symbols, target)
        if target == "NEXT":
            check_nex(stem.with_suffix(".bin").read_bytes(), symbols)
        suffix = "nex" if target == "NEXT" else "tap"
        (BUILD / f"netmanzx.{suffix}").replace(BUILD / f"netmanzx-{target.lower()}.{suffix}")
        print(f"{target}: audit regression checks passed; code headroom {0xC000 - symbols['program_end']} bytes", flush=True)


if __name__ == "__main__":
    main()
