"""Regression proof for AP identity and malformed diagnostic responses."""

from audit_regression import Run


def check_connection_fields(image, s, target, overlay=None):
    fields = (
        ("ip_buffer", b"IP:         ", b"192.0.2.123"),
        ("ci_gateway", b"Gateway:    ", b"192.0.2.1"),
        ("ci_netmask", b"Mask:       ", b"255.255.255.0"),
        ("ci_mac", b"MAC:        ", b"02:34:56:78:9A:BC"),
    )
    # Both screens must preserve their labels, values and distinct fallbacks.
    for mask in range(16):
        for summary in (False, True):
            r = Run(image, s, overlay)
            expected = Run(image, s, overlay)
            for name in ("UI.hideCursor", "UI.topClean", "UI.showNetDetail",
                         "Wifi.getConnectionInfo"):
                r.hook(name)
            for index, (field, label, value) in enumerate(fields):
                value = value if mask & (1 << index) else b""
                r.m.set_memory_block(s["Wifi." + field], value + b"\0" if value else b"\0stale\0")
                if summary and index == 3:
                    continue
                if summary and index == 1:
                    label = b"GW:         "
                row = (8 if summary else 10) + index
                line = label + (value or (b"(none)" if summary else b"-"))
                expected.m.set_memory_block(s["UI.diag_buffer"], line + b"\0")
                expected.m.a = row
                expected.m.hl = s["UI.diag_buffer"]
                expected.call("UI.printAt0")
            if summary:
                r.call("UI.doConfigSummary.cs_ip", "UI.doConfigSummary.cs_mac")
                rows = range(8, 11)
            else:
                r.call("UI.selectItem.alreadyConnected", "UI.pressKeyReturnList")
                rows = range(10, 14)
            assert r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A
            for row in rows:
                for scanline in range(8):
                    address = ((0x40 | (row & 0x18) | scanline) << 8) | ((row & 7) << 5)
                    assert bytes(r.m.memory[address:address + 32]) == bytes(
                        expected.m.memory[address:address + 32]
                    ), (target, summary, mask, row, scanline)


def check_about(image, s):
    r, expected = Run(image, s), Run(image, s)
    expected.m.hl = s["UI.showAbout.msg_about_title"]
    expected.call("UI.diagHeader")
    for row, name in ((6, "ver"), (7, "build"), (9, "desc"),
                      (10, "author"), (11, "github"), (12, "license")):
        expected.m.a = row
        expected.m.hl = s["UI.showAbout.msg_about_" + name]
        expected.call("UI.printAt0")
    r.call("UI.showAbout", "UI.pressKeyReturnList")
    assert bytes(r.m.memory[0x4000:0x5B00]) == bytes(expected.m.memory[0x4000:0x5B00])
    assert r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A


def check_modal_buffers(image, s):
    r = Run(image, s)
    ping = b"192.0.2.123\0"
    r.m.set_memory_block(s["UI.ping_ip_buffer"], ping)
    r.put("UI.ping_ip_len", len(ping) - 1)
    hostname = b"H" * 20 + b"\0"

    def enter_hostname():
        r.m.set_memory_block(s["UI.pass_buffer"], hostname)
        r.put("UI.pass_len", 20)
        r.m.f &= ~1

    sent = []
    r.hook("UI.passwordInput", enter_hostname)
    r.hook("UI.flushUartBuffer")
    r.hook("Wifi.espSendZ")
    r.hook("Wifi.espSendQuotedZ", lambda: sent.append(bytes(r.m.memory[r.m.hl:r.m.hl + 21])))
    r.hook("Wifi.espSendZCheckOk", lambda: setattr(r.m, "f", r.m.f & ~1))
    r.call("UI.doHostname", "UI.waitKeyReturnDiag")
    assert sent == [hostname]

    # Enter each subsequent editor with the previous modal contents still live.
    r.call("UI.doStaticIP", "UI.ipTextInput")
    assert (r.m.hl, r.m.b, r.get("UI.sti_len"), r.get("UI.sip_buf")) == (
        s["UI.sip_buf"], 15, 0, 0
    )
    r.m.set_memory_block(s["UI.sip_buf"], b"255.255.255.255\0")
    r.call("UI.validateIP")
    assert not r.m.f & 1
    if "UI.zone_buf" in s:
        r.call("UI.showTime.zone", "UI.ipTextInput")
        assert (r.m.hl, r.m.b, r.get("UI.sti_len"), r.get("UI.zone_buf")) == (
            s["UI.zone_buf"], 3, 0, 0
        )
        r.m.set_memory_block(s["UI.zone_buf"], b"+14\0")
        r.call("UI.parseZone")
        assert not r.m.f & 1 and r.get("Sntp.tz") == 14
    assert bytes(r.m.memory[s["UI.ping_ip_buffer"]:s["UI.ping_ip_buffer"] + len(ping)]) == ping
    assert r.get("UI.ping_ip_len") == len(ping) - 1


def check(image, s, target):
    check_connection_fields(image, s, target)
    check_about(image, s)
    check_modal_buffers(image, s)
    assert 0x6000 <= s["UI.diagHeader"] < 0x8000
    if target == "AY":
        # The AY bit-banged receiver must keep fetching from uncontended RAM.
        for reader in ("readDiagLineBC", "readDiagLine", "drainDiagLine", "readDiagLineLong"):
            assert 0x8000 <= s["UI." + reader] < s["program_end"]

    def setup(names, macs, connected, known=True):
        r = Run(image, s)
        r.call("UI.init")
        r.put("Wifi.networks_count", len(names))
        r.put("Wifi.is_connected", 1)
        r.put("Wifi.connected_bssid_valid", int(known))
        r.m.set_memory_block(s["Wifi.connected_ssid"], b"shared\0")
        r.m.set_memory_block(s["Wifi.connected_bssid"], connected)
        pointer = s["buffer"]
        for index, (name, mac) in enumerate(zip(names, macs)):
            r.m.set_memory_block(pointer, name + b"\0")
            r.m.set_memory_block(
                s["Wifi.ssid_ptr_table"] + 2 * index,
                pointer.to_bytes(2, "little"),
            )
            r.m.set_memory_block(s["Wifi.bssid_buffer"] + 6 * index, mac)
            r.m.memory[s["Wifi.rssi_buffer"] + index] = 40
            pointer += len(name) + 1
        r.call("Wifi.initDisplayIndices")
        return r

    # Disconnect retains the last SSID; diagnostics must respect live state.
    for connected in (0, 1):
        for listed in (False, True):
            r = setup([b"shared"] if listed else [], [bytes(6)] if listed else [],
                      bytes(6), known=False)
            r.put("Wifi.is_connected", connected)
            shown = []
            r.hook("UI.showNetDetail", lambda: shown.append(b"details"))
            r.hook("Display.putStr", lambda: shown.append(
                bytes(r.m.memory[r.m.hl:r.m.hl + 64]).split(b"\0")[0]))
            r.call("UI.doNetworkInfo", "UI.flushUartBuffer")
            expected = ([b"details"] if connected and listed else
                        [b"Connected: ", b"shared" if connected else b"(none)"])
            assert shown == expected, (target, connected, listed, shown)

    def present(r, expected):
        r.call("UI.connectedSSIDPresentInList")
        assert bool(r.m.f & 1) == (expected is not None), (target, expected)
        if expected is not None:
            assert r.m.a == expected, (target, r.m.a, expected)

    def render(r, expected_row):
        r.call("UI.renderNetworksCommon")
        assert r.get("UI.conn_row_found") == (
            255 if expected_row is None else expected_row
        ), target
        count = min(10, r.get("Wifi.networks_count") - r.get("UI.offset"))
        for row in range(count):
            selected = row == r.get("UI.cursor_position")
            connected = row == expected_row
            attr = (
                "ATTR_CONN_CURSOR" if selected and connected else
                "ATTR_HIGHLIGHT" if selected else
                "ATTR_CONNECTED" if connected else "ATTR_NORMAL"
            )
            assert r.m.memory[0x5800 + (row + 6) * 32] == s["Display." + attr], (
                target, row, attr
            )

    first = bytes.fromhex("021122334455")
    second = bytes.fromhex("0266778899aa")
    absent = bytes.fromhex("02bbccddeeff")
    r = setup([b"shared", b"shared"], [first, second], second)
    present(r, 1)
    render(r, 1)
    pixels = bytes(r.m.memory[0x4000:0x5800])

    def unexpected_composition():
        raise AssertionError("AP identity changed attributes but recomposed pixels")

    r.hook("Display.beginRow", unexpected_composition)
    r.m.set_memory_block(s["Wifi.connected_bssid"], first)
    present(r, 0)
    render(r, 0)
    assert bytes(r.m.memory[0x4000:0x5800]) == pixels
    r.m.set_memory_block(s["Wifi.connected_bssid"], absent)
    present(r, None)
    render(r, None)
    r.put("Wifi.connected_bssid_valid", 0)
    present(r, 0)
    render(r, 0)

    # Older scan formats omit BSSIDs: preserve the existing SSID fallback.
    for missing in (bytes(6), bytes([255]) * 6):
        r = setup([b"shared", b"shared"], [missing, second], second)
        present(r, 0)
        render(r, 0)

    # Diagnostic lookup returns the real index; page rendering uses display order.
    names = [b"shared"] + [f"net{i}".encode() for i in range(1, 10)] + [b"shared", b"last"]
    macs = [first] * 10 + [second, absent]
    r = setup(names, macs, second)
    order = [11, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 10]
    r.m.set_memory_block(s["Wifi.display_indices"], bytes(order))
    present(r, 10)
    render(r, None)
    r.put("UI.offset", 10)
    render(r, 1)

    # Exercise both real routines: no quote must leave HL on the terminator.
    for text, expected in (
        (b"+CIFSR:STAIP,\0stale previous address\0", b""),
        (b'prefix"192.0.2.1"\0old tail\0', b"192.0.2.1"),
        (b"\0stale previous address\0", b""),
    ):
        r = Run(image, s)
        r.m.set_memory_block(s["UI.diag_buffer"], text)
        r.m.hl = s["UI.diag_buffer"]
        printed = bytearray()
        r.hook("Display.putC", lambda: printed.append(r.m.a))
        r.call("UI.doNetworkInfo.findQuote")
        r.call("UI.printClean")
        assert bytes(printed) == expected, (target, bytes(printed))


    # AUD-01: Held BREAK cancelling the timezone editor or SNTP must be released
    # and stale BASIC_KEY cleared before returning to the parent loop.
    if "UI.showTime" in s:
        r = Run(image, s)
        polls = []
        r.m.set_input_callback(
            lambda port: (polls.append(port), 254 if len(polls) <= 6 else 255)[1]
            if port & 255 == 254 else 255
        )
        r.call("UI.showTime.zone", "UI.showTime.wait")
        assert len(polls) > 6 and r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A

        r = Run(image, s)
        r.put("Wifi.is_connected", 1)
        r.hook("Wifi.espSendZCheckOk", lambda: setattr(r.m, "f", 0))
        r.m.set_input_callback(lambda port: 254 if port & 255 == 254 else 255)
        r.call("UI.showTime.sync", "UI.showTime.msgWait")
        r.m.set_input_callback(lambda port: 255)
        r.m.memory[0x5C08] = ord(" ")
        reads = []
        def read_key():
            reads.append(1)
            r.m.a = r.m.memory[0x5C08] or (ord("x") if len(reads) == 3 else 0)
            r.m.memory[0x5C08] = 0
        r.hook("Keyboard.inKeyNoWait", read_key)
        r.call("UI.showTime.msgWait", "UI.showTime.redraw")
        assert len(reads) == 3 and r.m.sp == 0xFFE0 and r.m.iy == 0x5C3A

    # AUD-02: Disconnecting clears stale IP/GW/netmask in Config Summary, and
    # entering Config Summary disconnected after cancelling Module Info with a
    # trailing OK still flushes before querying MAC.
    r = Run(image, s)
    stale = (b"192.0.2.123", b"192.0.2.1", b"255.255.255.0")
    for name, value in zip(("ip_buffer", "ci_gateway", "ci_netmask"), stale):
        r.m.set_memory_block(s["Wifi." + name], value + b"\0")
    r.put("Wifi.is_connected", 1)
    r.hook("UI.updateWifiStatus_q")
    r.hook("Display.putStrLog")
    r.call("UI.doMarkDisconnected")
    r.feed(b"OK\r\n")
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0x40))
    r.call("UI.doModuleInfo.gmrLoop", "UI.showDiagnostics")
    assert bytes(r.rx) == b"OK\r\n"
    r.hook("Keyboard.checkBreak", lambda: setattr(r.m, "f", 0))
    shown, mac_printed = [], []
    r.hook("Display.putStr", lambda: shown.append(
        bytes(r.m.memory[r.m.hl:r.m.hl + 64]).split(b"\0", 1)[0]
    ))
    r.hook("UI.printClean", lambda: mac_printed.append(
        bytes(r.m.memory[r.m.hl:r.m.hl + 64]).split(b"\0", 1)[0]
    ))
    r.hook("Wifi.espSendZ_CRLF", lambda: r.rx.extend(b'+CIPSTAMAC:"AA:BB:CC:DD:EE:FF"\r\nOK\r\n'))
    r.call("UI.doConfigSummary", "UI.doConfigSummary.cs_mac_done")
    assert not any(value in shown for value in stale), (target, shown)
    assert mac_printed == [b'AA:BB:CC:DD:EE:FF"'], (target, mac_printed)

    # AUD-03: Pressing S after Config.save failure dismisses instead of retrying.
    if "Config.save" in s:
        for firmware_byte in (0, 255):
            r = Run(image, s)
            r.put("UI.is_reconnect", 0)
            def fail_save():
                r.put("UI.is_reconnect", firmware_byte)
                r.m.f = 1
            r.hook("Config.save", fail_save)
            r.call("UI.connSuccessScreen.cssSave", "UI.connSuccessScreen.cssWait")
            assert r.get("UI.is_reconnect") == 1
            r.hook("Keyboard.inKeyNoWait", lambda: setattr(r.m, "a", ord("S")))
            r.call("UI.connSuccessScreen.cssWait")
            assert r.m.sp == 0xFFE2 and r.m.iy == 0x5C3A

    # AUD-04: Uart.init and Next setBaudFromTable clear Wifi.flushInput.recovering.
    r = Run(image, s)
    r.put("Wifi.flushInput.recovering", 1)
    r.hook("UartImpl.init")
    r.call("Uart.init")
    assert r.get("Wifi.flushInput.recovering") == 0
    if target == "NEXT":
        r = Run(image, s)
        r.put("Wifi.flushInput.recovering", 1)
        r.m.hl = s["UartImpl.baudTable"]
        r.call("UartImpl.setBaudFromTable")
        assert r.get("Wifi.flushInput.recovering") == 0
