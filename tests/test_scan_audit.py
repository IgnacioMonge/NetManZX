"""Execute scan commit and framed-payload regressions against assembled code."""

from collections import deque

from audit_regression import Run

ACTIVE = b"AT+CWLAP=,,,0,200,200"
BASIC = b"AT+CWLAP"
OK = b"OK\r\n"
ERROR = b"ERROR\r\n"


def check(image, symbols, target):
    s = symbols
    slot = s["SSID_SLOT_SIZE"]
    capacity = s["MAX_NETWORKS"]

    def word(r, symbol):
        at = s[symbol]
        return int.from_bytes(r.m.memory[at : at + 2], "little")

    def set_word(r, symbol, value):
        r.m.set_memory_block(s[symbol], value.to_bytes(2, "little"))

    def ap(name, mac=b"00:11:22:33:44:55", channel=b"6", rssi=b"-42"):
        return b'+CWLAP:(3,"' + name + b'",' + rssi + b',"' + mac + b'",' + channel + b")\r\n"

    def zstr(r, at):
        end = at
        while r.m.memory[end]:
            end += 1
        return bytes(r.m.memory[at:end])

    def execute(data, chunks=None, success=True, idle_after=None, replies=(OK,), fault=False,
                cancel_overflow=False):
        """Run one scan; `replies` supplies the compatibility fallback, if used."""
        r = Run(image, s)
        r.hook("Wifi.flushInput", lambda: r.put("Uart.io_error", 0))
        r.hook("Display.putStrLog")
        if cancel_overflow:
            r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40 if r.get("Wifi.scan_overflow") else 0))
        sentinels = {"saved_sp": b"\x34\x12", "saved_hl_alt": b"\x78\x56",
                     "saved_ret": b"\xbc\x9a"}
        sentinels = {name: value for name, value in sentinels.items() if name in s}
        for name, value in sentinels.items():
            r.m.set_memory_block(s[name], value)
        pending = deque(chunks or ())
        later = deque(replies)
        commands = []

        def command():
            commands.append(zstr(r, r.m.hl))
            if len(commands) == 1 or not later:
                return
            reply = later.popleft()
            if chunks is None:
                r.rx.extend(reply)
            else:
                pending.append(reply)

        r.hook("Wifi.espSendZ_CRLF", command)
        if chunks is None:
            r.feed(data)
            if idle_after is not None:
                paused = [False]

                def split_uart():
                    if not paused[0] and len(r.rx) == len(data) - idle_after:
                        paused[0] = True
                        r.m.f = 0
                        return
                    ready = bool(r.rx)
                    r.m.a = r.rx.popleft() if ready else 0
                    r.m.f = int(ready)

                r.hook("UartImpl.uartRead", split_uart)
        else:
            assert b"".join(chunks) == data

            def capture():
                if not pending:
                    if fault:
                        r.put("Uart.io_error", 1)
                    # A missing terminator must finish as a timeout, not hang.
                    set_word(r, "Wifi.scan_started", (word_at_frames(r) - 1500) & 0xFFFF)
                    r.m.f = 0
                    return
                chunk = pending.popleft()
                start = s["Wifi.scan_rx_buffer"]
                r.m.set_memory_block(start, chunk)
                set_word(r, "Wifi.scan_rx_read", start)
                set_word(r, "Wifi.scan_rx_write", start + len(chunk))
                r.m.f = 1

            r.hook("Wifi.loadList.captureBurst", capture)
        r.call("Wifi.getList")
        assert bool(r.m.f & 1) != success, (target, success)
        assert word(r, "Wifi.readResponseByte.reader") == s["Wifi.readResponseByte.uart"]
        for name, value in sentinels.items():
            assert bytes(r.m.memory[s[name] : s[name] + len(value)]) == value, name
        assert r.m.iy == 0x5C3A
        assert commands[0] == ACTIVE, commands
        if success:
            unread = bytes(r.m.memory[word(r, "Wifi.scan_rx_read") : word(r, "Wifi.scan_rx_write")])
            unread += b"".join(pending) if chunks is not None else bytes(r.rx)
            assert not unread, (target, unread)
        r.commands = commands
        return r

    def word_at_frames(r):
        return int.from_bytes(r.m.memory[0x5C78:0x5C7A], "little")

    def expect(r, names):
        """Committed rows occupy fixed-stride slots in commit order."""
        assert r.get("Wifi.networks_count") == len(names)
        assert word(r, "Wifi.buff_ptr") == s["buffer"] + len(names) * slot
        for i, name in enumerate(names):
            at = s["Wifi.ssid_ptr_table"] + i * 2
            start = s["buffer"] + i * slot
            assert int.from_bytes(r.m.memory[at : at + 2], "little") == start
            assert bytes(r.m.memory[start : start + len(name) + 1]) == name + b"\0"

    # 26 uncommitted 33-byte slots previously reached the saved caller state.
    missing_channel = b'+CWLAP:(3,"' + b"X" * 32 + b'",-42,"00:11:22:33:44:55")\r\n'
    data = missing_channel * 30 + ap(b"good") + OK
    expect(execute(data, [data]), [b"good"])

    # A full list keeps the strongest APs: a weaker row is dropped, a stronger
    # one replaces the weakest committed slot, and the count stays capped.
    names = [f"{i:02}".encode() + b"X" * 30 for i in range(capacity)]
    rows = [ap(name, f"00:11:22:33:44:{i:02X}".encode(), rssi=b"-%d" % (40 + i))
            for i, name in enumerate(names)]
    data = (b"".join(rows)
            + ap(b"beyond capacity", b"00:11:22:33:45:00", rssi=b"-95")
            + ap(b"stronger", b"00:11:22:33:45:01", rssi=b"-30")
            + ap(b"00:11:22:33:45:01 again", b"00:11:22:33:45:01", rssi=b"-10")
            + OK)
    expect(execute(data, [data]), names[:-1] + [b"stronger"])
    r = execute(data, [data])
    assert r.m.memory[s["Wifi.rssi_buffer"] + capacity - 1] == 30
    assert r.m.memory[s["Wifi.channel_buffer"] + capacity - 1] == 6
    at = s["Wifi.bssid_buffer"] + (capacity - 1) * 6
    assert bytes(r.m.memory[at : at + 6]) == bytes.fromhex("001122334501")
    # The scratch slot ends exactly where the runtime variables begin.
    assert s["buffer"] + (capacity + 1) * slot == s["BUFFER_END"]

    # Rejected and duplicate rows must reuse the current uncommitted slot.
    data = (ap(b"first") + missing_channel * 27
            + ap(b"duplicate")
            + ap(b"bad\\q") + ap(b"Y" * 33)
            + b'+CWLAP:(3,"unterminated\r\n'
            + ap(b"second", b"00:11:22:33:44:66") + OK)
    expect(execute(data, [data]), [b"first", b"second"])

    # A timed-out row may leave scratch bytes, but never advance committed data.
    data = ap(b"first") + b'+CWLAP:(3,"' + b"T" * 32 + b'",-42,"00:11:22:33:44:66"'
    expect(execute(data, [data], success=False), [b"first"])

    fake = ap(b"phantom", b"AA:BB:CC:DD:EE:FF")
    payload = b"OK\r\nERROR\r\n" + fake + bytes((0, 255, 13, 10, 43, 58, 34))
    size = str(len(payload)).encode()
    headers = (
        b"+IPD," + size + b":",
        b"+IPD,0," + size + b":",
        b'+IPD,' + size + b',"192.0.2.1",1234:',
        b'+IPD,0,' + size + b',"192.0.2.1",1234:',
    )
    first = ap(b"first")
    second = ap(b"second", b"00:11:22:33:44:66")
    for header in headers:
        framed = header + payload + b"\r\n"
        data = first + framed + second + framed + OK
        # Whole capture and byte-split capture must expose identical AP lists.
        expect(execute(data, [data]), [b"first", b"second"])
        expect(execute(data, [data[i:i + 1] for i in range(len(data))]), [b"first", b"second"])

    # Exercise the actual UART capture path as well as controlled boundaries.
    data = first + headers[0] + payload + b"\r\n" + second + OK
    expect(execute(data), [b"first", b"second"])

    # A payload's fake terminal may yield a burst, never a completed scan.
    prefix = first + b"+IPD,4:OK\r\n"
    data = prefix + second + OK
    expect(execute(data, idle_after=len(prefix)), [b"first", b"second"])
    data = first + b"+IPD,12:OK\r\n"
    expect(execute(data, [data], success=False), [b"first"])

    # Startup and rescans share getList: a successful active scan sends one command.
    for chunks in (None, [first + second + OK]):
        r = execute(first + second + OK, chunks)
        expect(r, [b"first", b"second"])
        assert r.commands == [ACTIVE]

    # UART faults still invalidate a broken capture, rather than report success.
    expect(execute(first, [first], fault=True, success=False), [])

    # Firmware that rejects or ignores the parameters retries only the plain command.
    for rejected in (ERROR, OK):
        for chunks in (None, [rejected]):
            r = execute(rejected, chunks, replies=(second + OK,))
            expect(r, [b"second"])
            assert r.commands == [ACTIVE, BASIC]
    r = execute(OK, [OK], replies=(OK,))
    expect(r, [])
    assert r.commands == [ACTIVE, BASIC]
    r = execute(ERROR, [ERROR], replies=(ERROR,), success=False)
    expect(r, [])
    assert r.commands == [ACTIVE, BASIC]

    # A reply longer than the capture buffer keeps every complete row that fit,
    # drains the remainder and ends the scan without a second pass.
    size = s["Wifi.SCAN_RX_SIZE"]
    rows = []
    while sum(map(len, rows)) <= size + 2 * len(first):
        i = len(rows)
        rows.append(ap(b"ap%03d" % i, b"02:%02X:%02X:00:00:01" % (i >> 8, i & 255),
                       rssi=b"-%d" % (40 + i % 50)))
    data = b"".join(rows) + OK
    r = execute(data, replies=())
    fit = 0
    while sum(map(len, rows[: fit + 1])) <= size:
        fit += 1
    assert r.get("Wifi.scan_overflow") and not r.get("Uart.io_error")
    assert r.get("Wifi.networks_count") == min(fit, capacity)
    assert r.commands == [ACTIVE]
    kept = {zstr(r, s["buffer"] + i * slot) for i in range(r.get("Wifi.networks_count"))}
    assert kept <= {b"ap%03d" % i for i in range(fit)}
    r = execute(data, replies=(), cancel_overflow=True, success=False)
    assert r.m.a == 1 and r.get("Wifi.networks_count") == min(fit, capacity)

    # A terminal line exactly at the capture boundary must not start another pass.
    data = b"\r\n" * ((size - len(first) - len(OK)) // 2) + first + OK
    data = b"\n" * (size - len(data)) + data
    r = execute(data, replies=())
    expect(r, [b"first"])
    assert r.commands == [ACTIVE]

    # Both boot paths converge here, including an already-associated modem.
    for rejected in (False, True):
        r = Run(image, s)
        commands = []

        def command():
            end = r.m.hl
            while r.m.memory[end]:
                end += 1
            commands.append(bytes(r.m.memory[r.m.hl:end]))
            r.m.f = int(rejected)

        r.hook("Wifi.espSendZCheckOk", command)
        r.call("start.forceScan", "UI.renderList")
        assert commands == [b"AT+CWLAPOPT=0,31"]
