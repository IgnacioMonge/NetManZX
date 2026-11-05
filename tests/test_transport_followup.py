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


def check_connection_info(image, symbols, target, overlay=None):
    """CIFSR framing used by the connection-info screen."""

    cipsta = (
        b'+CIPSTA:gateway:"10.0.0.1"\r\n'
        b'+CIPSTA:netmask:"255.255.255.0"\r\nOK\r\n'
    )

    def run_case(cifsr, first=cipsta, fallback=None, fault=False, raw=False):
        r = Run(image, symbols, overlay)
        responses = {
            b"AT+CIFSR": cifsr,
            b"AT+CIPSTA?": (first,) if isinstance(first, bytes) else first,
            b"AT+CIPSTA_CUR?": (cipsta if fallback is None else fallback,),
        }
        commands = []
        current = [b""]
        wire = [deque()]
        reads = {}
        empty_reads = {}

        def send():
            command = _zstr(r.m, r.m.hl)
            commands.append(command)
            current[0] = command
            wire[0] = deque(deque(chunk) for chunk in responses[command])

        def read():
            reads[current[0]] = reads.get(current[0], 0) + 1
            while wire[0] and not wire[0][0]:
                wire[0].popleft()
                if raw and wire[0]:
                    # Real readTimeout must bridge a UART-empty poll per fragment.
                    r.m.a, r.m.f = 0, 0
                    return
            if wire[0]:
                r.m.a, r.m.f = wire[0][0].popleft(), 1
                return
            empty_reads[current[0]] = empty_reads.get(current[0], 0) + 1
            if fault and current[0] == b"AT+CIFSR":
                r.put("Uart.io_error", 1)
            r.m.a, r.m.f = 0, 0

        def flush():
            r.put("Uart.io_error", 0)
            r.m.f = 0

        r.hook("Wifi.espSendZ_CRLF", send)
        r.hook("Wifi.flushInput", flush)
        r.hook("UartImpl.uartRead" if raw else "Uart.readTimeout", read)
        r.call("Wifi.getConnectionInfo")
        assert not r.get("Wifi.uart_busy")
        return r, commands, reads, empty_reads

    # Fragmented complete fields retain their values and stop at terminal OK
    # without paying the normal interbyte timeout.
    chunks = (
        b"\r\n+CIFSR:STA",
        b'IP,"10.0.0.2"\r\n+CIFSR:STAM',
        b'AC,"02:34:56:78:9A:BC"\r\n',
        b"OK\r\n",
    )
    r, commands, _, empty = run_case(chunks)
    assert commands == [b"AT+CIFSR", b"AT+CIPSTA?"]
    assert empty.get(b"AT+CIFSR", 0) == 0
    assert _zstr(r.m, symbols["Wifi.ip_buffer"]) == b"10.0.0.2"
    assert _zstr(r.m, symbols["Wifi.ci_mac"]) == b"02:34:56:78:9A:BC"
    assert _zstr(r.m, symbols["Wifi.ci_gateway"]) == b"10.0.0.1"
    assert _zstr(r.m, symbols["Wifi.ci_netmask"]) == b"255.255.255.0"

    # A complete ERROR ends CIFSR immediately while CIPSTA remains usable.
    r, commands, _, empty = run_case((b"ERROR\r\n",))
    assert commands == [b"AT+CIFSR", b"AT+CIPSTA?"]
    assert empty.get(b"AT+CIFSR", 0) == 0
    assert _zstr(r.m, symbols["Wifi.ip_buffer"]) == b""
    assert _zstr(r.m, symbols["Wifi.ci_mac"]) == b""
    assert _zstr(r.m, symbols["Wifi.ci_gateway"]) == b"10.0.0.1"

    # CIPSTA must use the same framing as CIFSR, including peer-info variants.
    payload = (b'gateway:"6.6.6.6"\r\nOK\r\n'
               b'+CIPSTA:netmask:"1.1.1.1"\r\nERROR\r\n\x00\xff')
    size = str(len(payload)).encode()
    headers = (b'+IPD,' + size + b':', b'+IPD,0,' + size + b':',
               b'+IPD,' + size + b',"192.0.2.1",80:',
               b'+IPD,0,' + size + b',"192.0.2.1",80:')
    for header in headers:
        reply = header + payload + cipsta
        for fragments in ((reply,), tuple(bytes((b,)) for b in reply)):
            r, commands, _, _ = run_case((b'OK\r\n',), first=fragments, raw=True)
            assert commands == [b'AT+CIFSR', b'AT+CIPSTA?']
            assert _zstr(r.m, symbols['Wifi.ci_gateway']) == b'10.0.0.1'
            assert _zstr(r.m, symbols['Wifi.ci_netmask']) == b'255.255.255.0'
            assert r.m.iy == 0x5C3A and r.m.sp == 0xFFE2 and r.m.iff1

    # Noise cannot supply fields or terminal results; _CUR is a valid prefix.
    reply = (b'gateway:"6.6.6.6"\r\nnoise netmask:"1.1.1.1"\r\n'
             b'+CIPSTA:gateway:"10.0.0.1"\r\nOTHER\r\nOKjunk\r\n'
             b'+CIPSTA:netmask:"255.255.255.0"\r\nOK\r\n')
    r, commands, _, _ = run_case((b'OK\r\n',), first=reply)
    assert commands == [b'AT+CIFSR', b'AT+CIPSTA?']
    assert _zstr(r.m, symbols['Wifi.ci_netmask']) == b'255.255.255.0'
    r, commands, _, _ = run_case((b'OK\r\n',), first=b'ERROR\r\n',
                               fallback=cipsta.replace(b'CIPSTA:', b'CIPSTA_CUR:'))
    assert len(commands) == 3
    assert _zstr(r.m, symbols['Wifi.ci_gateway']) == b'10.0.0.1'

    # Reject every truncated IPD header/payload and partial or failed field set.
    framed = headers[0] + payload
    broken = [framed[:n] for n in range(len(framed))] + [
        b'+IPD,x:gateway:"6.6.6.6"\r\nOK\r\n',
        b'+CIPSTA:gateway:"10.0.0.1"\r\nERROR\r\n',
        b'+CIPSTA:gateway:"10.0.0.1"\r\nO',
        b'+CIPSTA:gateway:"10.0.0.1"OK\r\n',
        b'+CIPSTA:gateway:"10.0.0.1',
        b'+CIPSTA:gateway:"1234567890123456"\r\nOK\r\n',
        b'+CIPSTA:gateway:"999.0.0.1"\r\nOK\r\n',
    ]
    for reply in broken:
        r, commands, _, _ = run_case((b'OK\r\n',), first=reply, fallback=b'ERROR\r\n')
        assert commands == [b'AT+CIFSR', b'AT+CIPSTA?', b'AT+CIPSTA_CUR?'], reply
        assert _zstr(r.m, symbols['Wifi.ci_gateway']) == b'', reply
        assert _zstr(r.m, symbols['Wifi.ci_netmask']) == b'', reply


    # Payload and mid-line words cannot impersonate terminal result lines.
    noisy = (
        b"+IPD,4:OK\r\nSEND ERROR\r\n",
        b'+CIFSR:STAIP,"192.0.2.4"\r\n',
        b'+CIFSR:STAMAC,"AA:BB:CC:DD:EE:FF"\r\nOK\r\n',
    )
    r, _, _, empty = run_case(noisy)
    assert empty.get(b"AT+CIFSR", 0) == 0
    assert _zstr(r.m, symbols["Wifi.ip_buffer"]) == b"192.0.2.4"
    assert _zstr(r.m, symbols["Wifi.ci_mac"]) == b"AA:BB:CC:DD:EE:FF"

    # A capped malformed field drains its line before accepting later fields.
    overlong = (
        b'+CIFSR:STAIP,"1234567890123456OK\r\n',
        b'+CIFSR:STAMAC,"11:22:33:44:55:66"\r\nOK\r\n',
    )
    r, _, _, empty = run_case(overlong)
    assert empty.get(b"AT+CIFSR", 0) == 0
    assert _zstr(r.m, symbols["Wifi.ip_buffer"]) == b"1234567890123456"
    assert _zstr(r.m, symbols["Wifi.ci_mac"]) == b"11:22:33:44:55:66"

    # A quote ends the field, not the line; same-line OK remains nonterminal.
    quoted = (
        b'+CIFSR:STAIP,"192.0.2.5"OK\r\n',
        b'+CIFSR:STAMAC,"22:33:44:55:66:77"\r\nOK\r\n',
    )
    r, _, _, empty = run_case(quoted)
    assert empty.get(b"AT+CIFSR", 0) == 0
    assert _zstr(r.m, symbols["Wifi.ip_buffer"]) == b"192.0.2.5"
    assert _zstr(r.m, symbols["Wifi.ci_mac"]) == b"22:33:44:55:66:77"

    # Truncated payload/field reads fail once, recover, and continue bounded.
    for broken in (b"+IPD,8:OK\r\n", b'+CIFSR:STAIP,"10.0'):
        r, commands, reads, empty = run_case((broken,), fault=True)
        assert commands == [b"AT+CIFSR", b"AT+CIPSTA?"]
        assert empty[b"AT+CIFSR"] == 1
        assert reads[b"AT+CIFSR"] <= len(broken) + 1
        assert _zstr(r.m, symbols["Wifi.ci_gateway"]) == b"10.0.0.1"

    # Missing gateway keeps the established CIPSTA_CUR fallback.
    r, commands, _, _ = run_case((b"OK\r\n",), first=b"OK\r\n")
    assert commands == [b"AT+CIFSR", b"AT+CIPSTA?", b"AT+CIPSTA_CUR?"]
    assert _zstr(r.m, symbols["Wifi.ci_gateway"]) == b"10.0.0.1"


def check_async_payloads(image, s):
    """Idle polling stays bounded while retaining framing across empty polls."""
    payload = b'x' * 260 + b'WIFI DISCONNECT\r\nWIFI GOT IP\r\n\x00\xff+IPD,0:'
    size = str(len(payload)).encode()
    headers = (b'+IPD,' + size + b':', b'+IPD,0,' + size + b':',
               b'+IPD,' + size + b',"192.0.2.1",80:',
               b'+IPD,0,' + size + b',"192.0.2.1",80:',
               b'+IPD,' + size + b',192.0.2.1,80:')

    def drain(r):
        events = []
        while r.rx:
            before = len(r.rx)
            r.call('UI.checkAsyncWifi')
            assert 0 < before - len(r.rx) <= s['UI.ASYNC_DRAIN_BUDGET']
            if r.m.a:
                events.append(r.m.a)
            assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A and r.m.iff1
        r.call('UI.checkAsyncWifi')
        assert r.m.a == 0
        return events

    for header in headers:
        framed = header + payload
        # Every two-part split, including inside the decimal length and payload.
        for cut in range(len(framed) + 1):
            r = Run(image, s)
            r.feed(framed[:cut])
            assert drain(r) == [], (header, cut)
            r.feed(framed[cut:])
            assert drain(r) == [], (header, cut)
            r.feed(b'WIFI DISCONNECT\r\nWIFI GOT IP\r\n')
            assert drain(r) == [1, 2], (header, cut)
        r = Run(image, s)
        for byte in framed:
            r.feed(bytes((byte,)))
            assert drain(r) == []
        r.feed(b'WIFI GOT IP\r\n')
        assert drain(r) == [2]

    for noise in (b'prefix WIFI DISCONNECT\r\n', b'WIFI GOT IPsuffix\r\n',
                  b'WIFI DISCONNECT\rX\n', b'WIFI GOT IP\n',
                  b'+IPD,0:', b'+IPD,0,0:', b'+IPD,123\r\n', b'+IPD,0,123\r\n'):
        r = Run(image, s)
        r.feed(noise)
        assert drain(r) == [], noise
        r.feed(b'WIFI GOT IP\r\n')
        assert drain(r) == [2], noise

    for bad in (b'+IPD,x:', b'+IPD,:', b'+IPD,65536:', b'+IPD,0,65536:'):
        r = Run(image, s)
        r.feed(bad + b'WIFI GOT IP\r\n')
        assert drain(r) == [], bad
        r.put('Uart.io_error', 1)
        r.call('UI.checkAsyncWifi')
        r.feed(b'WIFI GOT IP\r\n')
        assert drain(r) == [2], bad

    # File operations do not read the UART or end an in-progress payload.
    if 'UI.restoreAfterFileIo' in s:
        r = Run(image, s)
        r.feed(b'+IPD,13:WIFI ')
        assert drain(r) == []
        r.call('UI.restoreAfterFileIo')
        r.feed(b'GOT IP\r\nWIFI DISCONNECT\r\n')
        assert drain(r) == [1]

def check_connection_probe(image, symbols, target, overlay=None):
    """CWJAP fallback timing and definitive disconnect classification."""

    query = b"AT+CWJAP?"
    current_reply = (
        b'+CWJAP:"new","02:34:56:78:9A:BC",6,-42\r\nOK\r\n'
    )

    def run_case(responses, connected=0, ssid=b"old"):
        r = Run(image, symbols, overlay)
        commands = []
        reads = {}
        current = [b""]
        pending = [deque()]
        r.put("Wifi.is_connected", connected)
        r.m.set_memory_block(symbols["Wifi.connected_ssid"], ssid + b"\0")

        def wake():
            assert _zstr(r.m, r.m.hl) == b"AT"
            r.m.f = 0

        def send():
            command = _zstr(r.m, r.m.hl)
            commands.append(command)
            current[0] = command
            pending[0] = deque(responses.get(command, b""))

        def read():
            command = current[0]
            reads[command] = reads.get(command, 0) + 1
            if pending[0]:
                r.m.a, r.m.f = pending[0].popleft(), 1
            else:
                r.m.a, r.m.f = 0, 0

        r.hook("Wifi.flushInput", lambda: setattr(r.m, "f", 0))
        r.hook("Wifi.espSendZCheckOk", wake)
        r.hook("Wifi.espSendZ_CRLF", send)
        r.hook("Uart.readTimeout", read)
        r.call("Wifi.checkConnection")
        assert r.m.iy == 0x5C3A and r.m.sp == 0xFFE2
        return r, commands, reads

    # A complete No AP is authoritative and preserves caller-owned link state.
    r, commands, _ = run_case({query: b"No AP\r\n"}, connected=1)
    assert r.m.f & 1 and commands == [query]
    assert r.get("Wifi.is_connected") == 1
    assert _zstr(r.m, symbols["Wifi.connected_ssid"]) == b"old"
    assert not r.get("Wifi.connected_bssid_valid")

    # A complete ERROR gets one grace poll, then uses the established fallback.
    r, commands, reads = run_case({
        query: b"ERROR\r\n",
        b"AT+CWJAP_CUR?": current_reply,
    })
    assert not r.m.f & 1 and commands == [query, b"AT+CWJAP_CUR?"]
    assert reads[query] == len(b"ERROR\r\n") + 1

    # Each unsupported spelling gets one grace poll before the next variant.
    r, commands, reads = run_case({
        query: b"ERROR\r\n",
        b"AT+CWJAP_CUR?": b"ERROR\r\n",
        b"AT+CWJAP_DEF?": current_reply,
    })
    assert not r.m.f & 1
    assert commands == [query, b"AT+CWJAP_CUR?", b"AT+CWJAP_DEF?"]
    assert reads[query] == reads[b"AT+CWJAP_CUR?"] == len(b"ERROR\r\n") + 1

    # No AP remains definitive when reached through a compatibility fallback.
    r, commands, _ = run_case({
        query: b"ERROR\r\n",
        b"AT+CWJAP_CUR?": b"No AP\r\n",
    }, connected=1)
    assert r.m.f & 1 and commands == [query, b"AT+CWJAP_CUR?"]
    assert r.get("Wifi.is_connected") == 1
    assert _zstr(r.m, symbols["Wifi.connected_ssid"]) == b"old"

    # A stale ERROR does not hide a valid reply already arriving in its grace.
    r, commands, reads = run_case({query: b"ERROR\r\n" + current_reply})
    assert not r.m.f & 1 and commands == [query]
    assert reads[query] == len(b"ERROR\r\n") + len(current_reply)

    # Pure silence keeps the original eight-poll compatibility window.
    r, commands, reads = run_case({b"AT+CWJAP_CUR?": current_reply})
    assert not r.m.f & 1 and commands == [query, b"AT+CWJAP_CUR?"]
    assert reads[query] == 8

    # Payload text, noisy prefixes and incomplete result words stay nonterminal.
    false_lines = (
        (b"noise\r\nERRORjunk\r\nNo APjunk\r\n", 8),
        (b"+IPD,14:No AP\r\nERROR\r\n", 8),
        (b"ERROR\r", 9),
    )
    for noise, empty_reads in false_lines:
        r, commands, reads = run_case({
            query: noise,
            b"AT+CWJAP_CUR?": current_reply,
        })
        assert not r.m.f & 1 and commands == [query, b"AT+CWJAP_CUR?"]
        assert reads[query] == len(noise) + empty_reads, noise

    # Successful parsing owns the connected state and preserves BSSID handling.
    r, commands, _ = run_case({query: current_reply})
    assert not r.m.f & 1 and commands == [query]
    assert r.get("Wifi.is_connected") == 1
    assert _zstr(r.m, symbols["Wifi.connected_ssid"]) == b"new"
    assert r.get("Wifi.connected_bssid_valid")
    assert bytes(r.m.memory[
        symbols["Wifi.connected_bssid"]:symbols["Wifi.connected_bssid"] + 6
    ]) == bytes.fromhex("023456789ABC")

    # Parser failure leaves caller-owned state and UART/BREAK latches observable.
    for latch in ("Uart.io_error", "Uart.break_hit"):
        r = Run(image, symbols, overlay)
        r.put("Wifi.is_connected", 1)
        r.put("Wifi.connected_bssid_valid", 1)
        r.m.set_memory_block(symbols["Wifi.connected_ssid"], b"old\0")
        polls = [0]

        def fault():
            polls[0] += 1
            r.put(latch, 1)
            r.m.f = 0

        r.hook("Uart.readTimeout", fault)
        r.call("Wifi.checkConnection.waitCwJAP")
        assert r.m.f & 1 and polls[0] == 8 and r.get(latch)
        assert r.get("Wifi.is_connected") == 1
        assert _zstr(r.m, symbols["Wifi.connected_ssid"]) == b"old"
        assert not r.get("Wifi.connected_bssid_valid")


def check(image, symbols, target):
    check_connection_info(image, symbols, target)
    check_connection_probe(image, symbols, target)
    check_async_payloads(image, symbols)
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

    # Commands remain visible and line-terminated while RX logging is muted.
    r = new()
    logs, writes = [], []
    r.put("Wifi.debug_log", 1)
    r.put("Uart.log_enabled", 0)
    r.hook("Display.putStrLog", lambda: logs.append(_zstr(r.m, r.m.hl)))
    r.hook("UartImpl.write", lambda: writes.append(r.m.a))
    r.m.hl = symbols["Wifi.S_AT_CIFSR"]
    r.call("Wifi.espSendZ_CRLF")
    assert logs == [b">> ", b"AT+CIFSR", b"\r"]
    assert bytes(writes) == b"AT+CIFSR\r\n"
    assert not r.get("Uart.tx_pending")

    if target == "NEXT":
        # RX status faults never emit the faulting byte.
        r = new()
        port_writes = []
        r.m.set_input_callback(lambda port: 0x40 if port == 0x133B else 0)
        r.m.set_output_callback(lambda port, value: port_writes.append((port, value)))
        r.m.a = ord("A")
        r.call("UartImpl.write")
        assert r.get("Uart.io_error")
        assert not [value for port, value in port_writes if port == 0x133B]

        # Every failed byte of an escaped quoted command leaves an invalid line,
        # while the failed transaction remains latched for its caller.
        command = b'AT+CWJAP="a\\\"b","secret"'
        wire = command + b"\r\n"
        scratch = symbols["Wifi.scan_rx_buffer"]
        for cut in range(len(wire)):
            r = new()
            r.m.set_memory_block(scratch, command + b"\0")
            emitted = []
            attempts = [0]

            def fault_once():
                if attempts[0] == cut:
                    r.put("Uart.io_error", 1)
                else:
                    emitted.append(r.m.a)
                attempts[0] += 1

            r.hook("UartImpl.write", fault_once)
            r.hook("UartImpl.uartRead", lambda: setattr(r.m, "f", 0))
            r.m.hl = scratch
            r.call("Wifi.espSendZ_CRLF")
            suffix = b"" if cut == 0 else b"#\r\n"
            assert bytes(emitted) == wire[:cut] + suffix, cut
            assert r.get("Uart.io_error") and not r.get("Uart.tx_pending"), cut
            if cut == 8:
                r.call("Wifi.flushInput.flushDone")
                retry_at = len(emitted)
                r.m.hl = symbols["Wifi.S_AT"]
                r.call("Wifi.espSendZ_CRLF")
                assert bytes(emitted) == wire[:cut] + b"#\r\nAT\r\n"
                assert bytes(emitted[retry_at:]) == b"AT\r\n"
                assert not r.get("Uart.io_error") and not r.get("Uart.tx_pending")

        # A failed invalidation stays sticky and later commands remain suppressed.
        r = new()
        r.m.set_memory_block(scratch, command + b"\0")
        emitted = []
        attempts = [0]
        cut = 8

        def persistent_fault():
            if attempts[0] < cut:
                emitted.append(r.m.a)
            else:
                r.put("Uart.io_error", 1)
            attempts[0] += 1

        r.hook("UartImpl.write", persistent_fault)
        r.hook("UartImpl.uartRead", lambda: setattr(r.m, "f", 0))
        r.m.hl = scratch
        r.call("Wifi.espSendZ_CRLF")
        assert bytes(emitted) == wire[:cut]
        assert attempts[0] == cut + 2 and r.get("Uart.tx_pending")
        before = attempts[0]
        r.m.hl = symbols["Wifi.S_AT"]
        r.call("Wifi.espSendZ_CRLF")
        assert bytes(emitted) == wire[:cut]
        assert attempts[0] == before + 1
        assert r.get("Uart.io_error") and r.get("Uart.tx_pending")

        # An RX-only fault has no partial TX line to invalidate.
        r = new()
        poison = []
        r.put("Uart.io_error", 1)
        r.put("Uart.tx_pending", 0)
        r.hook("UartImpl.write", lambda: poison.append(r.m.a))
        r.call("Wifi.flushInput.flushDone")
        assert poison == [] and not r.get("Uart.io_error")

        # Recovery requires observed silence and remains bounded under traffic.
        r = new()
        poison = []
        reads = []
        r.put("Uart.tx_pending", 1)
        r.put("Uart.io_error", 1)
        r.hook("UartImpl.write", lambda: poison.append(r.m.a))
        def continuous_rx():
            reads.append(1)
            r.m.a, r.m.f = ord("N"), 1
        r.hook("UartImpl.uartRead", continuous_rx)
        r.call("Wifi.flushInput.abortLine")
        assert poison == [ord("#"), 13, 10]
        assert len(reads) == 2048 and r.m.f & 1 and r.get("Uart.io_error")
        assert not r.get("Uart.tx_pending")
        assert r.get("Wifi.flushInput.recovering")
        r.call("Wifi.flushInput")
        assert len(reads) == 4096 and r.m.f & 1 and r.get("Uart.io_error")
        assert r.get("Wifi.flushInput.recovering")
        r.hook("UartImpl.uartRead", lambda: setattr(r.m, "f", 0))
        r.call("Wifi.flushInput")
        assert not r.m.f & 1 and not r.get("Uart.io_error")
        assert not r.get("Wifi.flushInput.recovering")

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

    # A nonterminal raw burst retains the 2 s silence fallback.
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

    # A complete OK/ERROR line closes capture on the first empty UART poll.
    # A suffix that is not a whole line must still use the silence fallback.
    terminal_cases = (
        (b"OK\r\n", 1),
        (b"\r\nERROR\r\n", 1),
        (b'+CWLAP:(3,"OK",-42,"mac",6)\r\nOK\r\n', 1),
        (b"SEND OK\r\n", symbols["Wifi.SCAN_GAP_FRAMES"] + 1),
    )
    for response, expected_empty_reads in terminal_cases:
        r = new()
        _word(r.m, symbols["Wifi.scan_started"], 1000)
        _word(r.m, 0x5C78, 1000)
        _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_RX_SIZE"])
        pending = deque(response)
        empty_reads = [0]
        def terminal_read():
            if pending:
                r.m.a, r.m.f = pending.popleft(), 1
                return
            empty_reads[0] += 1
            _word(r.m, 0x5C78, 1000 + empty_reads[0])
            r.m.f = 0
        r.hook("UartImpl.uartRead", terminal_read)
        r.call("Wifi.loadList.captureBurst")
        assert r.m.f & 1
        assert empty_reads[0] == expected_empty_reads, (response, empty_reads[0])
        base = symbols["Wifi.scan_rx_buffer"]
        end = int.from_bytes(
            r.m.memory[symbols["Wifi.scan_rx_write"]:symbols["Wifi.scan_rx_write"] + 2],
            "little",
        )
        assert end == base + len(response)
        assert bytes(r.m.memory[base:end]) == response

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

    # A reply longer than the capture buffer yields the full buffer as a burst
    # without a transport fault; the next capture drains the remainder until
    # the UART is quiet and reports no burst, so the parser ends the scan.
    r = new()
    _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_RX_SIZE"])
    _word(r.m, symbols["Wifi.scan_started"], 1000)
    _word(r.m, 0x5C78, 1000)
    def noise():
        r.m.a, r.m.f = ord("N"), 1
    r.hook("UartImpl.uartRead", noise)
    r.call("Wifi.loadList.captureBurst")
    assert r.m.f & 1 and r.get("Wifi.scan_overflow") and not r.get("Uart.io_error")
    end = symbols["Wifi.scan_rx_buffer"] + symbols["Wifi.SCAN_RX_SIZE"]
    assert int.from_bytes(r.m.memory[symbols["Wifi.scan_rx_write"]:symbols["Wifi.scan_rx_write"] + 2], "little") == end
    remaining = deque(b"NNNN")
    empty_reads = [0]
    _word(r.m, symbols["Wifi.scan_started"], 2000)
    _word(r.m, 0x5C78, 2000)
    def tail_read():
        if remaining:
            r.m.a, r.m.f = remaining.popleft(), 1
            return
        empty_reads[0] += 1
        _word(r.m, 0x5C78, 2000 + empty_reads[0])
        r.m.f = 0
    r.hook("UartImpl.uartRead", tail_read)
    r.call("Wifi.loadList.captureBurst")
    assert not r.m.f & 1 and not remaining and not r.get("Uart.io_error")
    assert empty_reads[0] == symbols["Wifi.SCAN_GAP_FRAMES"]

    # Overflow draining remains cancellable and bounded, even with no idle poll.
    for continuous, cancel in ((True, True), (True, False), (False, True)):
        r = new()
        reads = []
        r.put("Wifi.scan_overflow", 1)
        _word(r.m, symbols["Wifi.byte_limit"], symbols["Wifi.SCAN_BYTE_LIMIT"])
        _word(r.m, symbols["Wifi.scan_started"], 1000)
        _word(r.m, 0x5C78, 1000 + (0 if cancel else symbols["Wifi.SCAN_FRAMES"]))
        r.hook("UartImpl.uartRead", lambda: (reads.append(1), setattr(r.m, "a", ord("N")), setattr(r.m, "f", int(continuous))))
        r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40 if cancel else 0))
        r.call("Wifi.loadList.captureBurst")
        assert len(reads) == 1 and not r.m.f & 1
        assert bool(r.get("Uart.break_hit")) == cancel

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
        assert ready_cycles == 263 and ready_cycles < 303.8
        uart = bytes(r.m.memory[symbols["UartImpl.uartRead"]:symbols["UartImpl.uartRead"] + 64])
        assert b"\x04\xed\x78\x87\xd0" in uart       # INC B; IN A,(C); ADD A,A; RET NC
        assert b"\x05\x3e\xc6\xed\x79\x04\xed\x78\xc9" in uart  # data IN keeps CF; RET

    # Parser deduplicates one BSSID, while equal SSIDs on distinct APs remain.
    r = new()
    for name in ("Wifi.flushInput", "Wifi.espSendZ_CRLF", "Display.putStrLog"):
        r.hook(name)
    rows = (
        b'+CWLAP:(3,"same",-40,"00:11:22:33:44:55",6)\r\n'
        b'+CWLAP:(3,"renamed",-20,"00:11:22:33:44:55",6)\r\n'
        b'+CWLAP:(3,"same",-30,"66:77:88:99:AA:BB",11)\r\nOK\r\n'
    )
    bursts = deque((rows,))
    def capture():
        assert bursts
        burst = bursts.popleft()
        base = symbols["Wifi.scan_rx_buffer"]
        r.m.set_memory_block(base, burst)
        _word(r.m, symbols["Wifi.scan_rx_read"], base)
        _word(r.m, symbols["Wifi.scan_rx_write"], base + len(burst))
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
        r.feed(b'+CWJAP:"same","' + bssid + b'",6,-42\r\nOK\r\n')
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
