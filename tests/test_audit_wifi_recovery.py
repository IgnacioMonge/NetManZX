"""CWJAP completion and malformed scan BSSID recovery on assembled code."""

from collections import deque

from audit_regression import Run


def check(image, s, target):
    ssid = s["Wifi.connected_ssid"]
    valid = b'+CWJAP:"new","02:34:56:78:9A:BC",6,-42\r\nOK\r\n'

    def probe(reply, latch=None, budget_at=None):
        r = Run(image, s)
        pending = deque(reply)
        reads = [0]
        r.put("Wifi.is_connected", 1)
        r.m.set_memory_block(ssid, b"old\0")

        def read():
            reads[0] += 1
            if pending:
                r.m.a, r.m.f = pending.popleft(), 1
                if budget_at == reads[0]:
                    r.m.set_memory_block(s["Wifi.byte_limit"], b"\1\0")
            else:
                if latch:
                    r.put(latch, 1)
                r.m.a, r.m.f = 0, 0

        r.hook("Uart.readTimeout", read)
        r.call("Wifi.checkConnection.waitCwJAP")
        assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A
        return r, pending, reads[0]

    def name(r):
        return bytes(r.m.memory[ssid:ssid + 33]).split(b"\0", 1)[0]

    for reply in (
        valid,
        valid.replace(b"CWJAP:", b"CWJAP_CUR:"),
        valid.replace(b"CWJAP:", b"CWJAP_DEF:"),
        b'+CWJAP:"new"\r\nOK\r\n',
        b'+CWJAP:"new"\nOK\r\n',
        b'+CWJAP:"new","bad\nOK\r\n',
    ):
        r, pending, reads = probe(reply)
        assert not r.m.f & 1 and name(r) == b"new", (target, reply)
        assert not pending and reads == len(reply), (target, reply, reads)
    assert r.get("Wifi.connected_bssid_valid") == 0
    r, _, _ = probe(valid)
    assert r.get("Wifi.connected_bssid_valid") == 1
    at = s["Wifi.connected_bssid"]
    assert bytes(r.m.memory[at:at + 6]) == bytes.fromhex("023456789ABC")

    # Every truncation remains failure, including the SSID quote and final LF.
    for cut in range(len(valid)):
        for latch in (None, "Uart.break_hit", "Uart.io_error"):
            r, _, _ = probe(valid[:cut], latch)
            assert r.m.f & 1, (target, cut, latch)
            assert r.get("Wifi.is_connected") == 1
            assert not r.get("Wifi.connected_bssid_valid"), (target, cut, latch)
            if latch:
                assert r.get(latch), (target, cut, latch)
    for cut in (len(b'+CWJAP:"new"'), len(valid) - len(b'\r\nOK\r\n')):
        r, _, _ = probe(valid, budget_at=cut)
        assert r.m.f & 1 and name(r) == b""

    for suffix in (b"", b"O", b"OK\r", b"OKjunk\r\n", b"ERROR\r\n", b"FAIL\r\n"):
        r, _, _ = probe(valid[:-4] + suffix)
        assert r.m.f & 1 and name(r) == b"", (target, suffix)

    # Prefix/quote searches stop on this line so No AP stays authoritative.
    for broken in (b"+CWJAP", b"+CWJAP:2", b"+CWJAP_CUR", b"+CWJAP_CUR:2"):
        for ending in (b"\r\n", b"\n"):
            r, pending, _ = probe(broken + ending + b"No AP\r\n")
            assert r.m.f & 1 and r.m.f & 0x40, (target, broken, ending)
            assert not pending and name(r) == b"old"
            r, pending, _ = probe(broken + ending + valid)
            assert not r.m.f & 1 and name(r) == b"new"
            assert not pending

    # Terminal parsing must retain the shared length-framed +IPD contract.
    payload = b'OK\r\nERROR\r\n+CWJAP:"phantom"\r\n'
    size = str(len(payload)).encode()
    for header in (b'+IPD,' + size + b':', b'+IPD,0,' + size + b':',
                   b'+IPD,' + size + b',"192.0.2.1",80:',
                   b'+IPD,0,' + size + b',"192.0.2.1",80:'):
        r, pending, _ = probe(header + payload + valid)
        assert not r.m.f & 1 and name(r) == b"new" and not pending
        r, pending, _ = probe(valid[:-4] + header + payload + b"OK\r\n")
        assert not r.m.f & 1 and name(r) == b"new" and not pending

    # Only ASCII hex is valid; every rejected byte must survive for recovery.
    hex_values = {value: int(chr(value), 16) for value in b"0123456789ABCDEFabcdef"}
    for value in range(256):
        r = Run(image, s)
        r.m.a = value
        r.m.bc, r.m.de, r.m.hl = 0x1234, 0x5678, 0x9ABC
        r.call("Wifi.loadList.hexNibble")
        expected = hex_values.get(value)
        assert bool(r.m.f & 1) == (expected is not None), (target, value)
        assert r.m.a == (value if expected is None else expected), (target, value)
        assert (r.m.bc, r.m.e, r.m.hl) == (0x1234, 0x78, 0x9ABC), (target, value)
        assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A

    def scan(data, split=False):
        r = Run(image, s)
        for routine in ("Wifi.flushInput", "Display.putStrLog"):
            r.hook(routine)
        chunks = deque(bytes((value,)) for value in data) if split else deque((data,))
        r.hook("Wifi.espSendZ_CRLF")

        def capture():
            assert chunks, (target, data)
            chunk = chunks.popleft()
            start = s["Wifi.scan_rx_buffer"]
            r.m.set_memory_block(start, chunk)
            for field, value in (("scan_rx_read", start), ("scan_rx_write", start + len(chunk))):
                r.m.set_memory_block(s["Wifi." + field], value.to_bytes(2, "little"))
            r.m.f = 1

        r.hook("Wifi.loadList.captureBurst", capture)
        r.call("Wifi.getList")
        assert not r.m.f & 1 and not chunks, (target, data)
        assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A
        return r

    first = b'+CWLAP:(3,"broken",-42,"'
    good = b'+CWLAP:(3,"good",-42,"00:11:22:33:44:55",6)\r\n'
    # Former hex aliases must not hide the genuine AP in either nibble position.
    for value, digit in zip(bytes(range(0x10, 0x1A)) + b"@`", b"012345678999"):
        for position in (0, 1):
            mac = bytearray(b"00:1a:2B:3c:4D:5e")
            mac[position] = value
            malformed_mac = bytes(mac)
            mac[position] = digit
            valid_mac = bytes(mac)
            good_row = good.replace(b"00:11:22:33:44:55", valid_mac)
            duplicate = good_row.replace(b'"good"', b'"duplicate"').replace(
                valid_mac, valid_mac.swapcase()
            )
            data = first + malformed_mac + b'",6)\r\n' + good_row + duplicate + b"OK\r\n"
            for split in (False, True):
                r = scan(data, split)
                assert r.get("Wifi.networks_count") == 2, (target, value, position, split)
                assert r.get("Wifi.bssid_buffer") == 0xFF
                slot = s["buffer"] + s["SSID_SLOT_SIZE"]
                assert bytes(r.m.memory[slot:slot + 5]) == b"good\0"
                at = s["Wifi.bssid_buffer"] + 6
                assert bytes(r.m.memory[at:at + 6]) == bytes.fromhex(
                    valid_mac.decode().replace(":", "")
                )
            # The same helper must keep malformed connected identities unknown.
            reply = valid.replace(b"02:34:56:78:9A:BC", malformed_mac)
            r, pending, _ = probe(reply)
            assert not r.m.f & 1 and name(r) == b"new" and not pending
            assert not r.get("Wifi.connected_bssid_valid"), (target, value, position)

    # Commas at either nibble retain the unknown-identity row and its channel.
    for malformed in (b',6)\r\n', b'0,6)\r\n', b'00:11:,6)\r\n'):
        for split in (False, True):
            r = scan(first + malformed + good + b"OK\r\n", split)
            assert r.get("Wifi.networks_count") == 2
            assert bytes(r.m.memory[s["buffer"]:s["buffer"] + 7]) == b"broken\0"
            slot = s["buffer"] + s["SSID_SLOT_SIZE"]
            assert bytes(r.m.memory[slot:slot + 5]) == b"good\0"
    # LF at either nibble or during recovery cannot consume the following row.
    for malformed in (b'\n', b'0\n', b'00:11:\n', b'g\n', b'g\r\n', b'00:11:g\n'):
        for split in (False, True):
            r = scan(first + malformed + good + b"OK\r\n", split)
            assert r.get("Wifi.networks_count") == 1, (target, malformed)
            assert bytes(r.m.memory[s["buffer"]:s["buffer"] + 5]) == b"good\0"
        r = scan(first + malformed + b"OK\r\n")
        assert r.get("Wifi.networks_count") == 0, (target, malformed)

    # BREAK survives both connection-info fallbacks and its final UART cleanup.
    commands = (b"AT+CIFSR", b"AT+CIPSTA?", b"AT+CIPSTA_CUR?")
    for cancelled in (None,) + commands:
        r = Run(image, s)
        sent = []
        pending = deque()

        def flush():
            r.put("Uart.break_hit", int(cancelled is None))
            r.m.f = 0

        def send():
            command = bytes(r.m.memory[r.m.hl:r.m.hl + 32]).split(b"\0", 1)[0]
            sent.append(command)
            if command == cancelled:
                pending.extend(b'+CIFSR:STAIP,"10.0' if command == commands[0]
                               else b'+CIPSTA:gateway:"10.0')
            else:
                pending.extend(b"ERROR\r\n")

        def read():
            if pending:
                r.m.a, r.m.f = pending.popleft(), 1
            else:
                if sent and sent[-1] == cancelled:
                    r.put("Uart.break_hit", 1)
                r.m.a, r.m.f = 0, 0

        r.hook("Wifi.flushInput", flush)
        r.hook("Wifi.espSendZ_CRLF", send)
        r.hook("Uart.readTimeout", read)
        r.call("Wifi.getConnectionInfo")
        assert sent == ([] if cancelled is None else list(commands[:commands.index(cancelled) + 1]))
        assert r.get("Uart.break_hit") and not r.get("Wifi.uart_busy")
        assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A
