"""Assembled RTC register-order and transactional SNTP regression checks."""

from collections import deque

from audit_regression import Run


def check(image, symbols, target):
    s = symbols
    new = lambda: Run(image, s)

    if "Rtc.weekday" not in s:
        return

    check_message_clock(image, s, target)

    for date, expected in (
        ((1, 1, 0), 6),       # 2000-01-01 Saturday
        ((29, 2, 0), 2),      # leap day Tuesday
        ((1, 3, 0), 3),       # day after leap day Wednesday
        ((1, 3, 1), 4),       # non-leap boundary Thursday
        ((31, 12, 99), 4),    # 2099-12-31 Thursday
    ):
        r = new()
        day, month, year = date
        r.m.set_memory_block(s["Rtc.buf"], bytes((0, 0, 0, day, month, year)))
        r.call("Rtc.weekday")
        assert r.m.a == expected, (date, r.m.a)

    def zstr(run, address):
        end = address
        while run.m.memory[end]:
            end += 1
        return bytes(run.m.memory[address:end])

    # Invalid RTC bytes are never rendered. A saved SNTP value is preferred;
    # otherwise the field is replaced with dashes.
    r = new()
    r.put("Rtc.kind", 2 if target == "NEXT" else 1)
    r.put("Rtc.valid", 0)
    r.m.set_memory_block(s["Rtc.buf"], bytes((5, 42, 18, 19, 9, 26)))
    strings, fields = [], []
    r.hook("Display.putStr", lambda: strings.append(zstr(r, r.m.hl)))
    r.hook("UI.printFields", lambda: fields.append(r.m.hl))
    r.hook("UI.printZone")
    r.call("UI.showTime.paint")
    assert strings[-1] == b"--" and not fields

    r = new()
    r.put("Rtc.valid", 0)
    r.m.set_memory_block(s["Sntp.fields"], bytes((26, 9, 19, 18, 42, 5)))
    fields = []
    r.hook("Display.putStr")
    r.hook("UI.printFields", lambda: fields.append(r.m.hl))
    r.hook("UI.printZone")
    r.call("UI.showTime.paint")
    assert fields == [s["Sntp.fields"]]

    # A valid clock becoming invalid is cleared once; stable invalid sources
    # keep the fallback unchanged on later ticks.
    r = new()
    r.put("Rtc.valid", 1)
    r.put("UI.time_last_frame", 0)
    r.m.memory[0x5C78] = 50
    cleared, strings = [], []

    def invalid_read():
        r.put("Rtc.valid", 0)
        r.m.f = 1

    r.hook("Rtc.read", invalid_read)
    r.hook("Display.putC", lambda: cleared.append(r.m.a))
    r.hook("Display.putStr", lambda: strings.append(zstr(r, r.m.hl)))
    r.call("UI.showTime.tick")
    assert len(cleared) == 19 and strings == [b"--"]
    r.m.memory[0x5C78] = 100
    r.call("UI.showTime.tick")
    assert len(cleared) == 19 and strings == [b"--"]

    r = new()
    r.put("Rtc.valid", 1)
    r.put("UI.time_last_frame", 0)
    r.m.memory[0x5C78] = 50
    drawn = []
    r.hook("Rtc.read", lambda: setattr(r.m, "f", 1))
    r.hook("Display.putC", lambda: drawn.append(r.m.a))
    r.hook("Display.putStr", lambda: drawn.append(r.m.hl))
    r.call("UI.showTime.tick")
    assert not drawn

    def sync_flow(kind, write_ok=True):
        r = new()
        calls, messages = [], []
        r.put("Wifi.is_connected", 1)
        r.put("Rtc.kind", kind)

        def sync():
            calls.append("sync")
            r.m.set_memory_block(s["Sntp.fields"], bytes((26, 9, 19, 18, 42, 5)))
            r.m.f = 0

        def write():
            calls.append("rtc")
            r.m.f = 0 if write_ok else 1

        def persist():
            calls.append("save")
            r.m.f = 0

        r.hook("Sntp.sync", sync)
        r.hook("Rtc.writeTime", write)
        r.hook("UI.persistTime", persist)
        r.hook("UI.clearRowPixels")
        r.hook("UI.printAt0", lambda: messages.append(zstr(r, r.m.hl)))
        r.call("UI.showTime.sync", "UI.showTime.msgWait")
        return calls, messages[-1]

    calls, message = sync_flow(0)
    assert calls == ["sync", "save"] and message == b"SNTP sync OK."
    calls, message = sync_flow(3)
    assert calls == ["sync", "save"] and message == b"SNTP sync OK."
    writable_kind = 2 if target == "NEXT" else 1
    calls, message = sync_flow(writable_kind, False)
    assert calls == ["sync", "rtc", "save"]
    assert message == b"SNTP OK; RTC write failed."

    if "Rtc.dsWrite" in s:
        original = bytes((4, 42, 18, 19, 9, 26))

        def ds_stops(run):
            bus = {"sda": 1, "scl": 1, "stops": 0}

            def output(port, value):
                if port == 0x113B:
                    if bus["scl"] and not bus["sda"] and value & 1:
                        bus["stops"] += 1
                    bus["sda"] = value & 1
                elif port == 0x103B:
                    bus["scl"] = value & 1

            run.m.set_output_callback(output)
            return bus

        for nack in range(9):
            r = new()
            r.m.set_memory_block(s["Rtc.buf"], original)
            bus = ds_stops(r)
            ack = {"index": 0}

            def ds_nack(_port):
                index = ack["index"]
                ack["index"] += 1
                return int(index == nack)

            r.m.set_input_callback(ds_nack)
            r.call("Rtc.dsWrite")
            assert r.m.f & 1 and ack["index"] == nack + 1 and bus["stops"] == 1
            assert not r.get("Rtc.valid")

        for nack in range(3):
            r = new()
            bus = ds_stops(r)
            ack = {"index": 0}

            def ds_read_nack(_port):
                index = ack["index"]
                ack["index"] += 1
                return int(index == nack)

            r.m.set_input_callback(ds_read_nack)
            r.call("Rtc.dsReadTime")
            assert r.m.f & 1 and ack["index"] == nack + 1 and bus["stops"] == 1
            assert not r.get("Rtc.valid")

        # A stopped oscillator is still detected and writable, but its value
        # remains hidden until SNTP successfully initializes the chip.
        r = new()
        raw = bytes((0x85, 0x42, 0x18, 0x07, 0x19, 0x09, 0x26))
        bits = deque((byte >> bit) & 1 for byte in raw for bit in range(7, -1, -1))
        reads = {"count": 0}

        def halted_ds(_port):
            reads["count"] += 1
            if reads["count"] <= 3:
                return 0
            return bits.popleft()

        r.m.set_input_callback(halted_ds)
        r.call("Rtc.dsProbe")
        assert not r.m.f & 1 and r.get("Rtc.kind") == 2 and not r.get("Rtc.valid")
        r.put("Wifi.is_connected", 1)
        r.m.set_input_callback(lambda _port: 0)
        r.hook(
            "Sntp.sync",
            lambda: (
                r.m.set_memory_block(s["Sntp.fields"], bytes((26, 9, 19, 18, 42, 4))),
                setattr(r.m, "f", 0),
            ),
        )
        r.hook("UI.persistTime", lambda: setattr(r.m, "f", 0))
        r.hook("UI.clearRowPixels")
        r.hook("UI.printAt0")
        r.call("UI.showTime.sync", "UI.showTime.msgWait")
        assert r.get("Rtc.valid")
        assert bytes(r.m.memory[s["Rtc.sbcd"] : s["Rtc.sbcd"] + 7]) == bytes(
            (0x04, 0x42, 0x18, 0x07, 0x19, 0x09, 0x26)
        )

    if "Rtc.pcfWrite" in s:
        original = bytes((4, 42, 18, 19, 9, 26))

        def pcf_stops(run):
            bus = {"sda": 1, "scl": 1, "stops": 0}

            def output(port, value):
                if port != 0xFD3B:
                    return
                sda, scl = value & 1, (value >> 1) & 1
                if scl and bus["scl"] and not bus["sda"] and sda:
                    bus["stops"] += 1
                bus["sda"], bus["scl"] = sda, scl

            run.m.set_output_callback(output)
            return bus

        for nack in range(13):
            r = new()
            r.m.set_memory_block(s["Rtc.buf"], original)
            r.put("Rtc.i2c_mask", 1)
            bus = pcf_stops(r)
            ack = {"index": 0}

            def pcf_nack(_port):
                index = ack["index"]
                ack["index"] += 1
                return int(index == nack)

            r.m.set_input_callback(pcf_nack)
            r.call("Rtc.pcfWrite")
            stops = 1 if nack < 4 else 2
            assert r.m.f & 1 and ack["index"] == nack + 1 and bus["stops"] == stops
            assert not r.get("Rtc.valid") and r.m.iff1

        for nack in range(3):
            r = new()
            r.put("Rtc.i2c_mask", 1)
            bus = pcf_stops(r)
            ack = {"index": 0}

            def pcf_read_nack(_port):
                index = ack["index"]
                ack["index"] += 1
                return int(index == nack)

            r.m.set_input_callback(pcf_read_nack)
            r.call("Rtc.pcfReadTime")
            assert r.m.f & 1 and ack["index"] == nack + 1 and bus["stops"] == 1
            assert not r.get("Rtc.valid") and r.m.iff1

        r = new()
        r.m.set_memory_block(s["Rtc.buf"], original)
        r.put("Rtc.i2c_mask", 1)
        bus = {"sda": 1, "scl": 1, "byte": 0, "bits": 0}
        sent = []

        def sniff(port, value):
            if port != 0xFD3B:
                return
            sda, scl = value & 1, (value >> 1) & 1
            if scl and sda != bus["sda"]:
                bus["byte"] = bus["bits"] = 0
            elif scl and not bus["scl"]:
                bus["byte"] = (bus["byte"] << 1) | sda
                bus["bits"] += 1
                if bus["bits"] == 9:
                    sent.append(bus["byte"] >> 1)
                    bus["byte"] = bus["bits"] = 0
            bus["sda"], bus["scl"] = sda, scl

        r.m.set_output_callback(sniff)
        r.m.set_input_callback(lambda _port: 0)
        r.call("Rtc.pcfWrite")
        assert not r.m.f & 1
        assert sent == [0xA2, 0, 0, 0, 0xA2, 2, 4, 0x42, 0x18, 0x19, 6, 9, 0x26]
        assert r.get("Rtc.valid") and r.m.iff1
        r.m.set_memory_block(s["Rtc.sbcd"], bytes(sent[-7:]))
        r.m.set_memory_block(s["Rtc.buf"], bytes(6))
        r.m.hl, r.m.de = s["Rtc.sbcd"], s["Rtc.buf"]
        r.call("Rtc.pcfToBuf")
        assert not r.m.f & 1
        assert bytes(r.m.memory[s["Rtc.buf"] : s["Rtc.buf"] + 6]) == original

    if "Rtc.dsConv" in s:
        for raw, hour in ((0x52, 0), (0x72, 12), (0x41, 1), (0x61, 13),
                          (0x51, 11), (0x71, 23), (0, 0), (0x18, 18), (0x23, 23),
                          (0x40, None), (0x60, None), (0x53, None), (0x73, None),
                          (0x4A, None), (0x24, None)):
            r = new()
            r.m.set_memory_block(s["Rtc.sbcd"], bytes((5, 0x42, raw, 1, 0x19, 9, 0x26)))
            r.m.hl, r.m.de = s["Rtc.sbcd"], s["Rtc.buf"]
            r.call("Rtc.dsConv")
            assert bool(r.m.f & 1) == (hour is None), (raw, hour, r.m.f)
            if hour is not None:
                assert bytes(r.m.memory[s["Rtc.buf"] : s["Rtc.buf"] + 6]) == bytes(
                    (5, 42, hour, 19, 9, 26)
                )
            assert r.m.iy == 0x5C3A

    if "Sntp.parseTime" not in s:
        return

    old = bytes((25, 12, 31, 23, 59, 58))
    valid = b"Sat Sep 19 18:42:05 2026"
    expected = bytes((26, 9, 19, 18, 42, 5))
    invalid = [
        b"Thu Jan 01 00:00:00 1970",
        b"Sat Sep 19 18:42:05 2100",
        b"Sat Xxx 19 18:42:05 2026",
        b"Sat Sep 00 18:42:05 2026",
        b"Sat Sep 32 18:42:05 2026",
        b"Sat Sep 19 24:42:05 2026",
        b"Sat Sep 19 18:60:05 2026",
        b"Sat Sep 19 18:42:60 2026",
        b"Sat Sep 19 18:42:05 20x6",
    ]

    def response(data):
        r = new()
        r.m.set_memory_block(s["Sntp.fields"], old)
        pending = deque(data)

        def read():
            ready = bool(pending)
            r.m.a = pending.popleft() if ready else 0
            r.m.f = int(ready)

        # Preserve registers exactly as the real response reader does.
        r.hook("Wifi.readResponseByte", read)
        r.hook("Wifi.espSendZ_CRLF")
        return r

    def fields(r):
        return bytes(r.m.memory[s["Sntp.fields"] : s["Sntp.fields"] + 6])

    for text in invalid + [valid[:n] for n in range(len(valid))]:
        r = response(text)
        r.call("Sntp.parseTime")
        assert r.m.f & 1, text
        assert fields(r) == old, text

    for text, ending, succeeds in (
        [(text, b"\r\nOK\r\n", False) for text in invalid]
        + [(valid, b"\r\nERROR\r\n", False), (valid, b"", False),
           (valid, b"\r\nOK\r\n", True)]
    ):
        r = response(b"\r\n+CIPSNTPTIME:" + text + ending)
        r.call("Sntp.query")
        assert bool(r.m.f & 1) != succeeds, (text, ending)
        assert fields(r) == (expected if succeeds else old), (text, ending)
        assert r.m.iy == 0x5C3A


def check_message_clock(image, s, target):
    """SNTP results keep ticking until a key acknowledges the message."""
    r = Run(image, s)
    r.put("Wifi.is_connected", 1)
    r.put("Rtc.kind", 2 if target == "NEXT" else 1)
    r.put("Rtc.valid", 1)
    r.put("UI.time_last_frame", 0)
    r.m.memory[0x5C78] = 0
    synchronized = bytes((26, 9, 29, 18, 42, 5))
    fields, reads, screens = [], [], []
    polls = 0

    def sync():
        r.m.set_memory_block(s["Sntp.fields"], synchronized)
        r.m.f = 0

    def read():
        reads.append(r.m.memory[0x5C78])
        r.m.memory[s["Rtc.buf"]] = 5 + len(reads)
        r.m.f = 0

    def paint():
        fields.append(bytes(r.m.memory[r.m.hl:r.m.hl + 6]))
        r.m.step_over_breakpoint()

    def pixels(row):
        base = 0x4000 + row // 8 * 0x800 + row % 8 * 32
        return b"".join(bytes(r.m.memory[base + y * 256:base + y * 256 + 32])
                        for y in range(8))

    def key():
        nonlocal polls
        polls += 1
        assert fields and fields[0] == synchronized, "clock stays stale after SNTP until a key"
        screen = (pixels(6), pixels(8), pixels(11))
        if not screens:
            screens.append(screen)
            assert any(screen[2]), "result message is blank"
        assert screen == screens[0], "clock tick repainted the RTC, zone or result"
        r.m.a = ord(" ") if polls == 125 else 0
        assert polls <= 125, "result acknowledgement did not return"

    r.hook("Sntp.sync", sync)
    r.hook("Rtc.writeTime", lambda: setattr(r.m, "f", 0))
    r.hook("UI.persistTime", lambda: setattr(r.m, "f", 0))
    r.hook("Rtc.read", read)
    r.hook("UI.printFields", paint)
    r.hook("Keyboard.inKeyNoWait", key)
    r.call("UI.showTime.sync", "UI.showTime.redraw")
    assert len(reads) >= 2, "clock did not advance while the result waited for a key"
    assert all((b - a) & 255 >= 50 for a, b in zip(reads, reads[1:]))
    assert fields[-1][-1] == 5 + len(reads)
    assert r.m.iy == 0x5C3A and r.m.sp == 0xFFE0 and r.m.iff1
    r.call("UI.showTime.redraw", "UI.showTime.wait")
    assert pixels(11) != screens[0][2], "acknowledgement did not restore the menu hint"
