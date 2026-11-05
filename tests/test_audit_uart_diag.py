"""Warm UART state, diagnostic cancellation, and AY timeout regressions."""

from collections import deque

from audit_regression import Run


def check_init(image, s):
    r = Run(image, s)
    r.hook("UartImpl.init")
    for name in ("log_enabled", "io_error", "tx_pending", "log_lost"):
        r.put("Uart." + name, 1)
    r.m.set_memory_block(s["Uart.log_buf"], b"stale\0" + b"x" * 154)
    r.m.memory[s["Uart.log_ptr"]:s["Uart.log_ptr"] + 2] = (
        s["Uart.log_buf"] + 5
    ).to_bytes(2, "little")
    r.call("Uart.init")
    for name in ("log_enabled", "io_error", "tx_pending", "log_lost"):
        assert r.get("Uart." + name) == 0, "stale " + name
    shown = []
    r.hook("Display.putStrLog", lambda: shown.append(r.m.hl))
    r.call("Uart.logFlushPending")
    assert not shown, "stale buffer rendered after init"
    r.m.a = ord("A")
    r.call("Uart.log_char")
    r.call("Uart.logFlushPending")
    assert shown == [s["Uart.log_buf"]]
    assert bytes(r.m.memory[s["Uart.log_buf"]:s["Uart.log_buf"] + 2]) == b"A\0"


def check_diagnostics(image, s):
    entries = (
        "UI.doModuleInfo.gmrLoop", "UI.doNetworkInfo.cifsrLoop",
        "UI.doConfigSummary.cs_mac_loop", "UI.doConfigSummary.cs_hn_loop",
        "UI.doConfigSummary.cs_fw_loop",
    )
    for entry in entries:
        r = Run(image, s)
        polls, reads = [], []

        def key():
            polls.append(1)
            # A short tap inside the reader, released before the next loop.
            r.m.f = 0x40 if len(polls) == 2 else 0

        def read():
            reads.append(1)
            assert len(reads) == 1, (entry, "read after cancellation")
            r.m.a, r.m.f = 0, 0

        def send():
            raise AssertionError((entry, "AT command after cancellation"))

        r.hook("Keyboard.checkBreak", key)
        r.hook("UartImpl.uartRead", read)
        r.hook("Wifi.espSendZ_CRLF", send)
        r.hook("UI.printAt0")
        r.hook("UI.doConfigSummary.cs_flush")
        r.m.bc = 0x1464
        r.call(entry, "UI.showDiagnostics")
        assert reads == [1] and r.get("Uart.break_hit") == 1
        assert r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A, entry

    # The connection-info query is another cancellable summary transaction.
    r = Run(image, s)
    r.put("Wifi.is_connected", 1)
    r.hook("UI.diagHeader")
    r.hook("Wifi.getConnectionInfo", lambda: r.put("Uart.break_hit", 1))
    r.hook("UI.printAt0", lambda: (_ for _ in ()).throw(
        AssertionError("summary continued after connection-info BREAK")
    ))
    r.call("UI.doConfigSummary", "UI.showDiagnostics")
    assert r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A

    # Silence still follows the existing timeout path and retains CF=0.
    r = Run(image, s)
    r.hook("UI.readDiagLineBC", lambda: setattr(r.m, "f", 0))
    r.put("Uart.break_hit", 0)
    r.call("UI.doConfigSummary.cs_read")
    assert not r.m.f & 1 and r.m.sp == 0xFFE2
    for prefix, timeout, loop in (
        ("doModuleInfo", "gmrTimeout", "gmrLoop"),
        ("doNetworkInfo", "cifsrTimeout", "cifsrLoop"),
    ):
        r = Run(image, s)
        r.m.c = 2
        r.call("UI." + prefix + "." + timeout, "UI." + prefix + "." + loop)
        assert r.m.c == 1 and r.m.sp == 0xFFE0


def check_ay(image, s):
    for late in (False, True):
        r = Run(image, s)
        r.put("UartImpl._secondByte", 0xA5)
        reads, writes = [], []

        def read(port):
            reads.append(port)
            # The byte begins only after the 250 start-bit attempts expire.
            return 0 if late and len(reads) > 251 else 0xFF

        r.m.set_input_callback(read)
        r.m.set_output_callback(lambda port, value: writes.append((port, value)))
        r.call("UartImpl.uartRead")
        assert len(reads) == 251, (late, "post-timeout polls", len(reads))
        assert writes == [(0xFFFD, 0x0E), (0xBFFD, 0xFB), (0xBFFD, 0xFF)]
        assert not r.m.f & 1 and r.m.a == 0
        assert r.get("UartImpl._isSecondByteAvail") == 0
        assert r.get("UartImpl._secondByte") == 0xA5
        assert r.m.sp == 0xFFE2 and r.m.iff1

    # A successful first byte still captures and delivers an adjacent byte.
    r = Run(image, s)
    first, second = 0xA5, 0x3C
    samples = deque([0xFF, 0, 0, 0])
    samples.extend((first >> bit & 1) * 0x80 for bit in range(8))
    samples.extend((0, 0))
    samples.extend((second >> bit & 1) * 0x80 for bit in range(8))
    r.m.set_input_callback(lambda port: samples.popleft() if samples else 0xFF)
    r.call("UartImpl.uartRead")
    assert r.m.f & 1 and r.m.a == first and not samples
    assert r.get("UartImpl._isSecondByteAvail") == 1
    r.m.set_input_callback(lambda port: (_ for _ in ()).throw(
        AssertionError("queued AY byte touched hardware")
    ))
    r.call("UartImpl.uartRead")
    assert r.m.f & 1 and r.m.a == second
    assert r.get("UartImpl._isSecondByteAvail") == 0 and r.m.sp == 0xFFE2


def check_compaction(image, s):
    r = Run(image, s)
    r.hook("UartImpl.write")
    for state in (0, 1):
        for byte in range(256):
            expected = 0 if byte == 10 else 1 if byte == ord("A") else state
            r.put("Uart.tx_pending", state)
            r.m.a = byte
            r.call("Uart.trackTx")
            assert r.get("Uart.tx_pending") == expected, (state, byte)

            r.put("Uart.tx_pending", state)
            r.m.af = byte << 8 | 0xA5
            r.m.bc, r.m.de, r.m.hl = 0x1234, 0x5678, 0x9ABC
            r.call("Uart.write")
            assert r.get("Uart.tx_pending") == expected, (state, byte)
            assert (r.m.af, r.m.bc, r.m.de, r.m.hl) == (
                byte << 8 | 0xA5, 0x1234, 0x5678, 0x9ABC
            )
            assert r.m.sp == 0xFFE2

    # A backend can destroy DE, including while reporting an empty UART.
    for ready_after, cancel, count in ((3, False, 4), (None, False, 2), (None, True, 0x101)):
        r = Run(image, s)
        reads = []

        def read():
            reads.append(1)
            r.m.bc, r.m.de, r.m.hl = 0x1234, 0xABCD, 0x5678
            r.m.a = 0xA5
            r.m.f = int(len(reads) == ready_after)

        r.hook("UartImpl.uartRead", read)
        r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40 if cancel else 0))
        r.m.de = count
        r.call("Uart.poll_block")
        assert len(reads) == (1 if cancel else ready_after or count)
        assert bool(r.m.f & 1) == (ready_after is not None)
        assert bool(r.get("Uart.break_hit")) == cancel
        assert r.m.sp == 0xFFE2

    for data, offset in ((b"+UART:9600\0", 6), (b"no colon\0", 8)):
        r = Run(image, s)
        r.m.set_memory_block(s["UI.diag_buffer"], data)
        r.m.hl = s["UI.diag_buffer"]
        r.call("UI.baudSkipToColon")
        assert r.m.hl == s["UI.diag_buffer"] + offset

    # The shared row renderer must reproduce the old pointer-table menu.
    r, expected = Run(image, s), Run(image, s)
    r.hook("Keyboard.waitBreakRelease")
    expected.m.hl = s["UI.showDiagnostics.msg_diag_title"]
    expected.call("UI.diagHeader")
    for option in range(1, 8):
        expected.m.a = option + 5
        expected.m.hl = s["UI.showDiagnostics.msg_diag_opt" + str(option)]
        expected.call("UI.printAt0")
    expected.m.a, expected.m.e, expected.m.d = 14, 3, s["Display.ATTR_NORMAL"]
    expected.call("Display.draw_hline")
    expected.m.a, expected.m.hl = 15, s["UI.showDiagnostics.msg_diag_exit"]
    expected.call("UI.printAt0")
    r.call("UI.showDiagnostics", "UI.showDiagnostics.diagSet")
    assert bytes(r.m.memory[0x4000:0x5B00]) == bytes(expected.m.memory[0x4000:0x5B00])
    assert r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A


def check(image, s, target):
    check_init(image, s)
    check_diagnostics(image, s)
    check_compaction(image, s)
    if target == "AY":
        check_ay(image, s)
