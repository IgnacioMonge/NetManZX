"""Caller-stack, directory-prefix, clock-log and retry-cancellation regressions."""

from audit_regression import Run, STOP


def word(r, address, value):
    r.m.memory[address:address + 2] = value.to_bytes(2, "little")


def check_entry(image, s, target):
    if target == "NEXT":
        return  # NEX exits by soft reset, without a BASIC caller.
    for pointer in (0x7FE8, s["Wifi.connected_ssid"], 0xFFDE, 0xFFF0):
        r = Run(image, s)
        r.m.alt_hl = 0x2758

        def enter():
            r.m.sp = pointer
            word(r, pointer, STOP)
            r.m.pc = s["start"]

        r.hook("text", enter)
        r.call("text", "Display.initFontCache")
        assert int.from_bytes(r.m.memory[s["saved_sp"]:s["saved_sp"] + 2], "little") == pointer
        assert int.from_bytes(r.m.memory[s["saved_ret"]:s["saved_ret"] + 2], "little") == STOP
        assert r.m.sp == s["stack_top"] - 2
        # Exercise restoration independently of whether startup already cleared it.
        word(r, pointer, 0x1234)
        r.hook(0x1234, lambda: (_ for _ in ()).throw(
            AssertionError("exit used the overwritten caller return")
        ))
        r.hook("Keyboard.waitBreakRelease")
        r.call("start.exitClean")
        assert r.m.sp == pointer + 2 and r.m.alt_hl == 0x2758 and r.m.iff1


def check_path(image, s, target):
    if target != "NEXT":
        return
    for filename in ("Config.cfg_filename", "UI.time_filename"):
        for mode in ("first", "created", "failed"):
            r = Run(image, s)
            address = s[filename]
            original = bytes(r.m.memory[address:address + 64]).split(b"\0", 1)[0]
            opened, directories = [], []

            def api():
                ret = int.from_bytes(r.m.memory[r.m.sp:r.m.sp + 2], "little")
                operation = r.m.memory[ret]
                word(r, r.m.sp, ret + 1)
                if operation == 0x9A:
                    opened.append(bytes(r.m.memory[r.m.ix:r.m.ix + len(original)]))
                    assert r.m.ix == address and r.m.b == 0x0A
                    r.m.a = 3
                    r.m.f = int(mode == "failed" or (mode == "created" and len(opened) == 1))
                else:
                    assert operation == 0x94 and r.m.de == 0x01B1 and r.m.c == 7
                    assert r.m.a == 2 and r.m.iy == 0x5C3A
                    pointer = r.m.alt_hl
                    path = bytes(r.m.memory[pointer:pointer + 64]).split(b"\xff", 1)[0]
                    directories.append(path)
                    # M_P3DOS may destroy both main and alternate registers.
                    r.m.bc, r.m.de, r.m.hl = 0x1234, 0x5678, 0x9ABC
                    r.m.alt_bc, r.m.alt_de, r.m.alt_hl = 0x2345, 0x6789, 0xABCD
                    r.m.f = 1

            r.hook(8, api)
            r.m.hl = address
            r.call("Config.createPath")
            assert opened == [original] * (1 if mode == "first" else 2)
            assert directories == ([] if mode == "first" else [b"c:/sys", b"c:/sys/config"])
            assert bytes(r.m.memory[address:address + len(original) + 1]) == original + b"\0"
            assert bool(r.m.f & 1) == (mode == "failed")
            assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A


def check_time_and_retry(image, s, target):
    for cancel in (False, True):
        r = Run(image, s)

        def prepare():
            r.put("Uart.break_hit", int(cancel))
            r.m.f = 1

        r.hook("Wifi.prepareRetry", prepare)
        if cancel:
            r.hook("UI.connectAndReturn.carFailed", lambda: (_ for _ in ()).throw(
                AssertionError("retry BREAK reached UART failure")
            ))
        stop = "UI.connectAndReturn.carDiscCancelled" if cancel else "UI.connectAndReturn.carFailed"
        r.call("UI.connectAndReturn.carRetry", stop)
        assert r.m.sp == 0xFFE0

    if "Sntp.sync" not in s:
        return
    for failed in (False, True):
        r = Run(image, s)
        r.put("Wifi.debug_log", 1)
        flushed = []

        def sync():
            assert r.get("Uart.log_enabled") == 1
            r.m.memory[s["Uart.log_buf"]] = ord("X")
            word(r, s["Uart.log_ptr"], s["Uart.log_buf"] + 1)
            r.m.f = int(failed)

        r.hook("Sntp.sync", sync)
        r.hook("Display.putStrLog", lambda: flushed.append(r.m.hl))
        r.hook("UI.printAt0")
        r.hook("UI.clearRowPixels")
        stop = "UI.showTime.syncFail" if failed else "UI.timeCopyUiToRtc"
        r.call("UI.showTime.syncGo", stop)
        assert not r.get("Uart.log_enabled") and r.get("Wifi.debug_log") == 1
        assert flushed == [s["Uart.log_buf"]]
        assert r.m.sp == (0xFFE0 if failed else 0xFFDE)


def check(image, s, target):
    check_entry(image, s, target)
    check_path(image, s, target)
    check_time_and_retry(image, s, target)
