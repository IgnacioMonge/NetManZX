"""Focused transport/scan checks, called by audit_regression.py."""
from collections import deque

from audit_regression import Run


def _word(machine, address, value):
    machine.memory[address:address + 2] = value.to_bytes(2, "little")


def _zstr(machine, address):
    data = bytes(machine.memory[address:address + 256])
    return data.split(b"\0", 1)[0]


def _feed_timeout(run, data):
    pending = deque(data)

    def read():
        if pending:
            run.m.a, run.m.f = pending.popleft(), 1
        else:
            run.m.a, run.m.f = 0, 0

    run.hook("Uart.readTimeout", read)
    return pending


def check(image, symbols, target):
    new = lambda: Run(image, symbols)

    # Exact terminal lines classify failures without losing CWJAP detail.
    cases = (
        (b"OK\r\n", "OK", 0),
        (b"ERROR\r\n", "ERROR", 6),
        (b"FAIL\r\n", "FAIL", 6),
        (b"+CWJAP:2\r\nFAIL\r\n", "FAIL", 2),
        (b"+CWJAP:3\r\nERROR\r\n", "ERROR", 3),
        (b"", "TIMEOUT", 0),
        (b"ERROR\r", "TIMEOUT", 0),
        (b"FAIL\r", "TIMEOUT", 0),
        (b"ERRORjunk\r\n", "TIMEOUT", 0),
        (b"ERROR\rX\n", "TIMEOUT", 0),
        (b"OK\rX\n", "TIMEOUT", 0),
    )
    for reply, status, detail in cases:
        r = new()
        logs = []
        r.put("Wifi.debug_log", 1)
        r.hook("Display.putStrLog", lambda: logs.append(_zstr(r.m, r.m.hl)))
        r.put("Uart.break_hit", 1)  # A prior transaction cannot cancel this one.
        pending = _feed_timeout(r, reply)
        r.call("Wifi.checkOkErr")
        assert r.get("Wifi.reply_status") == symbols[f"Wifi.REPLY_{status}"], reply
        assert r.get("Wifi.last_error") == detail, reply
        assert bool(r.m.f & 1) == (status != "OK")
        assert not pending and not r.get("Wifi.uart_busy")
        assert logs == ([] if status == "TIMEOUT" else [f"<< {status}\r\n".encode()])

    # Faults at every byte boundary, including the final LF, remain failures.
    for reply in (b"OK\r\n", b"ERROR\r\n", b"FAIL\r\n", b"noise\r\n", b"+CWJAP:2\r\n"):
        for cut in range(len(reply)):
            for latch, status in (("Uart.io_error", "UART"), ("Uart.break_hit", "BREAK")):
                r = new()
                pending = deque(reply[:cut])
                def fault_read():
                    if pending:
                        r.m.a, r.m.f = pending.popleft(), 1
                    else:
                        r.put(latch, 1)
                        r.m.f = 0
                r.hook("Uart.readTimeout", fault_read)
                r.call("Wifi.checkOkErr")
                assert r.m.f & 1 and not r.get("Wifi.uart_busy")
                assert r.get("Wifi.reply_status") == symbols[f"Wifi.REPLY_{status}"]

    # Sticky faults suppress every later physical TX until explicit recovery.
    r = new()
    writes = []
    r.hook("UartImpl.write", lambda: writes.append(r.m.a))
    r.put("Uart.io_error", 1)
    r.m.a = ord("X")
    r.call("Uart.write")
    assert writes == []

    # A ready byte carrying a hardware fault is rejected by both wrappers.
    for entry in ("Uart.readTimeout", "Uart.readTimeoutLong"):
        r = new()
        def bad_byte():
            r.m.a, r.m.f = ord("X"), 1
            r.put("Uart.io_error", 1)
        r.hook("UartImpl.uartRead", bad_byte)
        r.call(entry)
        assert not r.m.f & 1 and r.get("Uart.io_error")

    # The shared response boundary preserves parser pointers and counters.
    for available, limit in ((True, 1), (False, 1), (False, 0)):
        r = new()
        r.put("Wifi.use_long_timeout", 0)
        _word(r.m, symbols["Wifi.byte_limit"], limit)
        reads = []
        def response_read():
            reads.append(1)
            r.m.a, r.m.f = (ord("X"), 1) if available else (0, 0)
        r.hook("Uart.readTimeout", response_read)
        r.m.bc, r.m.de, r.m.hl = 0x1122, 0x3344, 0x5566
        r.call("Wifi.readResponseByte")
        assert (r.m.bc, r.m.de, r.m.hl) == (0x1122, 0x3344, 0x5566)
        assert bool(r.m.f & 1) == available and len(reads) == int(bool(limit))

    # Framed network payload cannot masquerade as an AT command result.
    framed_results = (
        (b"+IPD,4:OK\r\nERROR\r\n", True),
        (b"+IPD,0,4:OK\r\nOK\r\n", False),
        (b'+IPD,5,"1.2.3.4",80:ERROROK\r\n', False),
        (b'+IPD,0,4,"1.2.3.4",80:OK\r\nERROR\r\n', True),
        (b"+IPD,4:" + bytes((0, 13, 10, 255)) + b"OK\r\n", False),
    )
    for reply, fails in framed_results:
        r = new()
        pending = _feed_timeout(r, reply)
        r.call("Wifi.checkOkErr")
        assert bool(r.m.f & 1) == fails, reply
        assert not pending, reply

    # Truncated or malformed IPD framing fails closed.
    for reply in (b"+IPD,4:OK\r", b"+IPD,12:OK\r\nERROR\r\n",
                  b"+IPD,x:garbage\r\nOK\r\n"):
        r = new()
        _feed_timeout(r, reply)
        r.call("Wifi.checkOkErr")
        assert r.m.f & 1, reply

    # CIFSR selects STAIP, consumes its terminal result, and rejects no address.
    for reply, expected, fails in (
            (b'+CIFSR:APIP,"192.168.4.1"\r\n+CIFSR:STAIP,"10.0.0.2"\r\nOK\r\n', b"10.0.0.2", False),
            (b'+CIFSR:STAIP,"0.0.0.0"\r\nOK\r\n', b"0.0.0.0", True)):
        r = new()
        r.hook("UartImpl.write")
        pending = _feed_timeout(r, reply)
        r.call("Wifi.getIP")
        assert bool(r.m.f & 1) == fails
        assert _zstr(r.m, symbols["Wifi.ip_buffer"]) == expected
        assert not pending and not r.get("Wifi.uart_busy")

    for address in (b"", b"a.a.a.a", b"256.1.2.3", b"1.2.3", b"1..2.3",
                    b"1.2.3.4.5", b"1.2.3.4\x00junk"):
        r = new()
        r.hook("UartImpl.write")
        _feed_timeout(r, b'+CIFSR:STAIP,"' + address + b'"\r\nOK\r\n')
        r.call("Wifi.getIP")
        assert r.m.f & 1 and not r.get("Wifi.uart_busy"), address

    # Startup cannot infer association from a configured station IP alone.
    for connected in (False, True):
        r = new()
        r.hook("splashMsg")
        def association():
            r.put("Wifi.is_connected", int(connected))
            r.m.f = int(not connected)
        r.hook("Wifi.checkConnection", association)
        def unexpected_ip():
            raise AssertionError("IP configuration is not association evidence")
        r.hook("Wifi.getIP", unexpected_ip)
        r.call("start.cwmodeOk", "start.alreadyConnected" if connected else "Wifi.init")
        assert r.get("Wifi.is_connected") == int(connected)

    # A timeout inside the STAIP suffix aborts the nested matcher cleanly.
    r = new()
    r.hook("UartImpl.write")
    staged = deque(b'+CIFSR:STA')
    staged.append(None)
    staged.extend(b'IP,"10.0.0.2"\r\nOK\r\n')
    def staged_ip():
        value = staged.popleft()
        if value is None:
            r.m.a, r.m.f = 0, 0
        else:
            r.m.a, r.m.f = value, 1
    r.hook("Uart.readTimeout", staged_ip)
    r.call("Wifi.getIP")
    assert r.m.f & 1 and _zstr(r.m, symbols["Wifi.ip_buffer"]) == b""
    assert not r.get("Wifi.uart_busy")

    # Join uses one 20 s frame deadline through bounded short polls.
    r = new()
    start_frame = 1000
    _word(r.m, 0x5C78, start_frame)
    elapsed = [0]
    tail = deque(b"K\r\n")
    polls, tail_reads = [], []
    def delayed_join():
        if elapsed[0] < 15 * 50:
            polls.append(1)
            elapsed[0] += 50
            _word(r.m, 0x5C78, start_frame + elapsed[0])
            if elapsed[0] == 15 * 50:
                r.m.a, r.m.f = ord("O"), 1
            else:
                r.m.a, r.m.f = 0, 0
        else:
            tail_reads.append(1)
            r.m.a, r.m.f = tail.popleft(), 1
    r.hook("Uart.readTimeout", delayed_join)
    r.call("Wifi.checkOkErrLong")
    assert not r.m.f & 1 and elapsed[0] == 15 * 50
    assert len(polls) == 15 and len(tail_reads) == 3 and not tail

    r = new()
    _word(r.m, 0x5C78, start_frame)
    elapsed = [0]
    def silent_join():
        elapsed[0] += 50
        _word(r.m, 0x5C78, start_frame + elapsed[0])
        r.m.f = 0
    r.hook("Uart.readTimeout", silent_join)
    r.call("Wifi.checkOkErrLong")
    assert r.m.f & 1 and elapsed[0] == symbols["Wifi.JOIN_FRAMES"]
    assert r.get("Wifi.reply_status") == symbols["Wifi.REPLY_TIMEOUT"]

    # Exhausting the byte cap terminates immediately without polling/spinning.
    r = new()
    r.put("Wifi.use_long_timeout", 1)
    _word(r.m, symbols["Wifi.byte_limit"], 0)
    reads = []
    r.hook("Uart.readTimeout", lambda: reads.append(1))
    r.call("Wifi.readLongResponseByte")
    assert not r.m.f & 1 and reads == []

    # Even a ready byte cannot enter the parser once the operation expired.
    r = new()
    _word(r.m, symbols["Wifi.byte_limit"], 1)
    r.put("Wifi.use_long_timeout", 1)
    started = symbols["Wifi.joinBudgetLeft.started"]
    _word(r.m, started, start_frame)
    _word(r.m, 0x5C78, start_frame + symbols["Wifi.JOIN_FRAMES"])
    reads = []
    r.hook("Uart.readTimeout", lambda: (reads.append(1), setattr(r.m, "a", ord("O")), setattr(r.m, "f", 1)))
    r.call("Wifi.readResponseByte")
    assert not r.m.f & 1 and reads == []

    # Retry recovery establishes CRLF + quiet drain + a successful AT probe.
    r = new()
    flushes, writes, probes = [], [], []
    r.put("Uart.io_error", 1)
    r.hook("Wifi.flushInput", lambda: (flushes.append(1), r.put("Uart.io_error", 0)))
    r.hook("UartImpl.write", lambda: writes.append(r.m.a))
    def probe():
        probes.append(_zstr(r.m, r.m.hl))
        r.m.f = 0
    r.hook("Wifi.espSendZCheckOk", probe)
    r.call("Wifi.prepareRetry")
    assert not r.m.f & 1 and writes == [13, 10] and probes == [b"AT"] and len(flushes) == 2

    # Command-mode recovery always normalizes transparent mode off.
    r = new()
    probes = []
    r.hook("Wifi.flushInput")
    def command_mode_probe():
        probes.append(_zstr(r.m, r.m.hl))
        r.m.f = 0
    r.hook("Wifi.espSendZCheckOk", command_mode_probe)
    r.call("Wifi.ensureCommandMode")
    assert not r.m.f & 1 and probes == [b"AT", b"AT+CIPMODE=0"]

    # Raw scan capture keeps a burst in RAM and ends only after 2 s silence.
    r = new()
    _word(r.m, symbols["Wifi.scan_started"], 1000)
    _word(r.m, 0x5C78, 1000)
    _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_RX_SIZE"])
    reads = [0]
    def raw_read():
        reads[0] += 1
        if reads[0] == 1:
            r.m.a, r.m.f = ord("+"), 1
        else:
            if reads[0] == 3:
                _word(r.m, 0x5C78, 1100)
            r.m.f = 0
    r.hook("UartImpl.uartRead", raw_read)
    r.call("Wifi.loadList.captureBurst")
    assert r.m.f & 1 and r.m.memory[symbols["Wifi.scan_rx_buffer"]] == ord("+")
    assert int.from_bytes(r.m.memory[symbols["Wifi.scan_rx_write"]:symbols["Wifi.scan_rx_write"] + 2], "little") == symbols["Wifi.scan_rx_buffer"] + 1

    # Total deadline is one wrapping-safe 30 s operation budget.
    r = new()
    r.m.hl = 1
    _word(r.m, symbols["Wifi.byte_limit"], 1)
    _word(r.m, symbols["Wifi.scan_started"], 1000)
    _word(r.m, 0x5C78, 2499)
    r.call("Wifi.loadList.scanBudgetLeft")
    assert r.m.f & 1
    _word(r.m, 0x5C78, 2500)
    r.call("Wifi.loadList.scanBudgetLeft")
    assert not r.m.f & 1

    # Hardware fault and BREAK abort raw capture before any parser exposure.
    r = new()
    _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_RX_SIZE"])
    r.hook("UartImpl.uartRead", lambda: (r.put("Uart.io_error", 1), setattr(r.m, "f", 0)))
    r.call("Wifi.loadList.captureBurst")
    assert not r.m.f & 1 and r.get("Uart.io_error")
    r = new()
    _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_RX_SIZE"])
    r.hook("UartImpl.uartRead", lambda: setattr(r.m, "f", 0))
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40))
    r.call("Wifi.loadList.captureBurst")
    assert not r.m.f & 1 and r.get("Uart.break_hit")

    # Continuous input observes BREAK and the total deadline at page boundaries.
    boundary_reads = (-symbols["Wifi.scan_rx_buffer"]) & 0xFF or 256
    r = new()
    reads = []
    _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_RX_SIZE"])
    r.hook("UartImpl.uartRead", lambda: (reads.append(1), setattr(r.m, "a", ord("X")), setattr(r.m, "f", 1)))
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40))
    r.call("Wifi.loadList.captureBurst")
    assert len(reads) == boundary_reads and r.get("Uart.break_hit") and not r.m.f & 1

    r = new()
    reads = []
    _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_RX_SIZE"])
    _word(r.m, symbols["Wifi.scan_started"], 1000)
    _word(r.m, 0x5C78, 1000 + symbols["Wifi.SCAN_FRAMES"])
    r.hook("UartImpl.uartRead", lambda: (reads.append(1), setattr(r.m, "a", ord("X")), setattr(r.m, "f", 1)))
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0))
    r.call("Wifi.loadList.captureBurst")
    assert len(reads) == boundary_reads and not r.get("Uart.break_hit") and not r.m.f & 1

    # Continuous noise is bounded at 12000 bytes and is explicitly rejected.
    r = new()
    _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_RX_SIZE"])
    def noise():
        r.m.a, r.m.f = ord("N"), 1
    r.hook("UartImpl.uartRead", noise)
    r.call("Wifi.loadList.captureBurst")
    assert not r.m.f & 1 and r.get("Wifi.scan_overflow") and r.get("Uart.io_error")
    end = symbols["Wifi.scan_rx_buffer"] + symbols["Wifi.SCAN_RX_SIZE"]
    assert int.from_bytes(r.m.memory[symbols["Wifi.scan_rx_write"]:symbols["Wifi.scan_rx_write"] + 2], "little") == end

    # The measured noncontended UNO ready-byte path remains below one 115200 frame.
    if target == "UNO":
        r = new()
        base = symbols["Wifi.scan_rx_buffer"]
        _word(r.m, symbols["Wifi.loadList.capturePtr"], base)
        r.m.set_input_callback(lambda _port: 0x80)
        r.m.pc = symbols["Wifi.loadList.captureLoop"]
        r.m.ticks_to_stop = 1_000_000
        r.m.set_breakpoint(symbols["UartImpl.uartRead"])
        r.m.run()
        assert r.m.pc == symbols["UartImpl.uartRead"]
        r.m.clear_breakpoint(symbols["UartImpl.uartRead"])
        r.m.set_breakpoint(symbols["Wifi.loadList.captureLoop"])
        r.m.run()
        assert r.m.pc == symbols["Wifi.loadList.captureLoop"]
        ready_cycles = 1_000_000 - r.m.ticks_to_stop
        assert ready_cycles == 281 and ready_cycles < 303.8
        uart = bytes(r.m.memory[symbols["UartImpl.uartRead"]:symbols["UartImpl.uartRead"] + 64])
        assert b"\x04\xed\x78\xe6\x80" in uart       # INC B; IN A,(C); AND 80h
        assert b"\x05\x3e\xc6\xed\x79\x04\xed\x78" in uart

    # Parser deduplicates one BSSID, while equal SSIDs on distinct APs remain.
    r = new()
    for name in ("Wifi.flushInput", "Wifi.espSendZ_CRLF", "Display.putStrLog"):
        r.hook(name)
    rows = (
        b'+CWLAP:(3,"same",-40,"00:11:22:33:44:55",6)\r\n'
        b'+CWLAP:(3,"renamed",-20,"00:11:22:33:44:55",6)\r\n'
        b'+CWLAP:(3,"same",-30,"66:77:88:99:AA:BB",11)\r\nOK\r\n'
    )
    supplied = [False]
    def capture():
        assert not supplied[0]
        supplied[0] = True
        base = symbols["Wifi.scan_rx_buffer"]
        r.m.set_memory_block(base, rows)
        _word(r.m, symbols["Wifi.scan_rx_read"], base)
        _word(r.m, symbols["Wifi.scan_rx_write"], base + len(rows))
        r.m.f = 1
    r.hook("Wifi.loadList.captureBurst", capture)
    r.call("Wifi.getList")
    assert not r.m.f & 1 and r.get("Wifi.networks_count") == 2
    names = []
    for index in range(2):
        r.m.a = index
        r.call("Wifi.getSSIDPointer")
        names.append(_zstr(r.m, r.m.hl))
    assert names == [b"same", b"same"]

    # CWJAP preserves the current AP identity only for a valid BSSID field.
    for bssid, valid in ((b"00:11:22:33:44:55", True), (b"not-a-mac", False)):
        r = new()
        r.feed(b'+CWJAP:"same","' + bssid + b'",6,-42\r\n')
        r.call("Wifi.checkConnection.waitCwJAP")
        assert not r.m.f & 1 and _zstr(r.m, symbols["Wifi.connected_ssid"]) == b"same"
        assert bool(r.get("Wifi.connected_bssid_valid")) == valid
        if valid:
            assert bytes(r.m.memory[symbols["Wifi.connected_bssid"]:symbols["Wifi.connected_bssid"] + 6]) == bytes.fromhex("001122334455")
    r = new()
    r.put("Wifi.connected_bssid_valid", 1)
    r.feed(b"No AP\r\n")
    r.call("Wifi.checkConnection.waitCwJAP")
    assert r.m.f & 1 and not r.get("Wifi.connected_bssid_valid")

    # Equal RSSI entries retain scan order; the shrinking bubble bound sorts all.
    r = new()
    r.put("Wifi.networks_count", 5)
    r.m.set_memory_block(symbols["Wifi.rssi_buffer"], bytes((30, 20, 20, 10, 40)))
    r.call("Wifi.initDisplayIndices")
    r.call("Wifi.sortNetworks")
    assert bytes(r.m.memory[symbols["Wifi.display_indices"]:symbols["Wifi.display_indices"] + 5]) == bytes((3, 1, 2, 0, 4))

    # Logging is deferred on every target and reports bounded-buffer loss.
    r = new()
    shown = []
    r.hook("Display.putStrLog", lambda: shown.append(_zstr(r.m, r.m.hl)))
    for _ in range(symbols["Uart.LOG_BUF_SIZE"] + 8):
        r.m.a = ord("L")
        r.call("Uart.log_char")
    r.call("Uart.logFlushPending")
    assert len(shown[0]) == symbols["Uart.LOG_BUF_SIZE"] - 1
    assert b"UART log truncated" in shown[1]
