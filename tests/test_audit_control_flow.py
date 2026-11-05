"""Assembled SNTP, quit and CR-compatible diagnostic regressions."""
from collections import deque

from audit_regression import Run, STOP


def zstr(r, address):
    return bytes(r.m.memory[address:address + 64]).split(b"\0", 1)[0]


def word(r, symbol, value):
    address = r.s[symbol]
    r.m.memory[address:address + 2] = value.to_bytes(2, "little")


def check_sntp(image, s):
    old = bytes((25, 12, 31, 23, 59, 58))
    valid = b"+CIPSNTPTIME:Sat Sep 19 18:42:05 2026\r\nOK\r\n"
    invalid = b"+CIPSNTPTIME:Thu Jan 01 00:00:00 1970\r\nOK\r\n"
    for reply, success, timeout in (
        (b"ERROR\r\n", False, False), (b"OK\r\n", False, False),
        (invalid, False, False), (valid, True, False),
        (b"OKjunk\r\nERRORjunk\r\n" + valid, True, False),
        (b"+IPD,11:OK\r\nERROR\r\n" + valid, True, False),
        (b"O", False, True), (b"OK\r", False, True),
        (b"ERROR\r", False, True),
    ):
        r = Run(image, s)
        r.m.set_memory_block(s["Sntp.fields"], old)
        pending, idle = deque(reply), []

        def read():
            ready = bool(pending)
            if not ready:
                idle.append(True)
            r.m.a = pending.popleft() if ready else 0
            r.m.f = int(ready)

        r.hook("Uart.readTimeout", read)
        r.hook("Wifi.espSendZ_CRLF")
        r.call("Sntp.query")
        assert bool(r.m.f & 1) != success, reply
        assert bool(idle) == timeout, (reply, len(idle))
        assert not pending and not r.get("Wifi.uart_busy")
        expected = bytes((26, 9, 19, 18, 42, 5)) if success else old
        assert bytes(r.m.memory[s["Sntp.fields"]:s["Sntp.fields"] + 6]) == expected
        assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A and r.m.iff1

    # The same flags select fallback, success and cancellation; no abort may
    # leave the retry counter on the return stack.
    for phase, configs, queries, success in (
        ("config", 1, 0, False), ("fallback_cancel", 2, 0, False),
        ("settle", 1, 0, False), ("query", 1, 1, False),
        ("pause", 1, 1, False), ("retry", 1, 3, False),
        ("success", 1, 2, True), ("fallback", 2, 1, True),
        ("config_error", 2, 0, False),
    ):
        r = Run(image, s)
        calls = {"config": 0, "query": 0, "pause": 0}

        def config():
            calls["config"] += 1
            cancel = phase == "config" or (phase == "fallback_cancel" and calls["config"] == 2)
            failed = cancel or phase == "config_error" or (
                phase in ("fallback", "fallback_cancel") and calls["config"] == 1
            )
            r.put("Uart.break_hit", int(cancel))
            r.m.f = int(failed)

        def query():
            calls["query"] += 1
            r.put("Uart.break_hit", int(phase == "query"))
            r.m.f = int(not (phase == "fallback" or (phase == "success" and calls["query"] == 2)))

        def keyboard():
            pause = calls["query"] > 0
            calls["pause"] += int(pause)
            r.m.f = 0x40 if phase == "settle" or (phase == "pause" and pause) else 0

        r.hook("Wifi.espSendZCheckOk", config)
        r.hook("Sntp.query", query)
        r.hook("Keyboard.checkBreak", keyboard)
        r.call("Sntp.sync")
        assert (calls["config"], calls["query"]) == (configs, queries), (phase, calls)
        assert bool(r.m.f & 1) != success, phase
        if phase == "pause":
            assert calls["pause"] == 1
        assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A and r.m.iff1, phase


def check_quit(image, s, target):
    r = Run(image, s)
    polls, keys = [], []
    r.put("Keyboard.BASIC_KEY", ord(" "))

    def keyboard():
        polls.append(True)
        r.m.f = 0x40 if len(polls) <= 3 else 0

    def key():
        assert len(polls) >= 4 and r.get("Keyboard.BASIC_KEY") == 0
        keys.append(True)
        r.m.a = ord("n")

    r.hook("Keyboard.checkBreak", keyboard)
    r.hook("Keyboard.inKey", key)
    r.call("UI.quitConfirm", "UI.renderListAndLoop")
    assert keys == [True] and r.m.sp == 0xFFE0
    assert r.m.iy == 0x5C3A and r.m.iff1

    r = Run(image, s)
    released = []
    r.hook("Keyboard.waitBreakRelease", lambda: released.append(True))
    r.hook("Keyboard.inKey", lambda: setattr(r.m, "a", ord("y")))
    if target == "NEXT":
        reset = s["UI.quitConfirm.hold"] - 5
        r.call("UI.quitConfirm", reset)
        assert bytes(r.m.memory[reset:reset + 5]) == b"\xf3\xed\x91\x02\x01"
    else:
        word(r, "saved_sp", 0xFFD0)
        word(r, "saved_ret", STOP)
        word(r, "saved_hl_alt", 0x2758)
        r.m.alt_hl = 0x1234
        r.call("UI.quitConfirm")
        assert r.m.sp == 0xFFD2 and r.m.alt_hl == 0x2758 and r.m.iff1
    assert released == [True, True]

    if target == "UNO":
        r = Run(image, s)
        word(r, "saved_sp", 0xFFDE)  # IRQ pushes here while the harness SP is FFE0.
        word(r, "saved_ret", STOP)
        word(r, "saved_hl_alt", 0x2758)
        r.m.alt_hl = 0x1234
        r.call("UI.exitRestore", "UI.exitRestore.stackSwitch")
        pc = r.m.pc
        r.m.on_handle_active_int()
        assert not r.m.iff1 and r.m.pc == pc
        assert bytes(r.m.memory[0xFFDE:0xFFE0]) == STOP.to_bytes(2, "little")
        assert r.m.alt_hl == 0x2758 and r.m.iy == 0x5C3A


def check_summary(image, s):
    # Preserve the readers' CR, LF and CRLF contracts, including truncated lines.
    for reader in ("UI.readDiagLine", "UI.readDiagLineLong"):
        for ending in (b"\r", b"\n", b"\r\n"):
            for length in (5, 60, 80):
                r = Run(image, s)
                r.feed(b"x" * length + ending + b"next" + ending)
                expected = [b"x" * min(length, 60), b"next"]
                if ending == b"\r\n":
                    expected = [expected[0], b"", expected[1], b""]
                for line in expected:
                    r.call(reader)
                    assert r.m.f & 1 and zstr(r, s["UI.diag_buffer"]) == line
                assert not r.rx and r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A

    for ending in (b"\r", b"\n", b"\r\n"):
        for field, budget, reply, value in (
            ("mac", 8, b'+CIPSTAMAC:"11:22:33:44:55:66"', b"11:22:33:44:55:66"),
            ("hn", 6, b'+CWHOSTNAME:"host"', b"host"),
        ):
            r = Run(image, s)
            prefix = [b"AT+query?", b"", b"WIFI CONNECTED", b"WIFI GOT IP"]
            prefix += [b"noise"] * (budget - 4)
            data = ending.join(prefix + [reply, b"OK", b""])
            pending = deque(byte for item in data for byte in (item, None))
            shown = []

            def read():
                byte = pending.popleft() if pending else None
                r.m.a, r.m.f = (byte, 1) if byte is not None else (0, 0)

            r.hook("UartImpl.uartRead", read)
            r.hook("UI.printClean", lambda: shown.append(zstr(r, r.m.hl).split(b'"')[0]))
            r.m.bc = budget * 256 + 64
            r.call("UI.doConfigSummary.cs_" + field + "_loop", "UI.doConfigSummary.cs_" + field + "_done")
            assert shown == [value], (ending, field, shown)
            assert r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A

    for field, budget in (("mac", 8), ("hn", 6), ("fw", 10)):
        r = Run(image, s)
        r.feed(b"\r" * 256)
        r.m.bc = budget * 256 + 64
        r.call("UI.doConfigSummary.cs_" + field + "_loop", "UI.doConfigSummary.cs_" + field + "_done")
        assert len(r.rx) == 192 and r.m.b == budget, field

        r = Run(image, s)
        r.feed(b"noise\r" * (budget + 1))
        r.hook("UI.putStrLimited")
        r.m.bc = budget * 256 + 64
        r.call("UI.doConfigSummary.cs_" + field + "_loop", "UI.doConfigSummary.cs_" + field + "_done")
        if field != "fw":  # Firmware intentionally displays only its first content line.
            assert bytes(r.rx) == b"noise\r", field

    r = Run(image, s)
    r.feed(b"\r" * 256)
    polls = []

    def cancel():
        polls.append(True)
        r.m.f = 0x40 if len(polls) == 3 else 0

    r.hook("Keyboard.checkBreak", cancel)
    r.m.bc = 0x0840
    r.call("UI.doConfigSummary.cs_mac_loop", "UI.showDiagnostics")
    assert len(r.rx) == 254 and r.m.sp == 0xFFE0

    for ending in (b"\r", b"\n", b"\r\n"):
        r = Run(image, s)
        r.feed(ending.join((b"AT version:1.7.4", b"SDK version:3.0", b"compile time:today", b"OK", b"")))
        r.hook("UI.putStrLimited")
        r.hook("UI.printAt0")
        r.hook("Display.putStr")
        if "Config.load" in s:
            r.hook("Config.load", lambda: setattr(r.m, "f", 1))
        r.m.bc = 0x0A40
        r.call("UI.doConfigSummary.cs_fw_loop", "UI.pressKeyReturnDiag")
        assert not r.rx and r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A


def check(image, s, target):
    check_summary(image, s)
    check_quit(image, s, target)
    if "Sntp.query" in s:
        check_sntp(image, s)
