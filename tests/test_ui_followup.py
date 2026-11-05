"""UI regression checks on assembled code; invoked by audit_regression.py."""
from collections import deque
from audit_regression import Run


def check_menu_priority(image, s, target):
    new = lambda: Run(image, s)

    # Queued keys precede optional ESP work, including both timer boundaries.
    for auto, health in ((0, 499), (14999, 0), (14999, 499)):
        r = new()
        r.put('Wifi.is_connected', 1)
        r.put('Keyboard.BASIC_KEY', ord('a'))
        for name, value in (('UI.autoscan_counter', auto), ('UI.health_counter', health)):
            r.m.memory[s[name]:s[name] + 2] = value.to_bytes(2, 'little')
        def unexpected_maintenance():
            raise AssertionError('queued key waited behind optional ESP work')
        for name in ('Wifi.checkConnection', 'UI.doAutoRescan'):
            r.hook(name, unexpected_maintenance)
        r.call('UI.uiLoopMain', 'UI.cursorDown')
        assert r.get('Keyboard.BASIC_KEY') == 0
        for name in ('UI.autoscan_counter', 'UI.health_counter'):
            assert bytes(r.m.memory[s[name]:s[name] + 2]) == b'\0\0'
        assert r.m.iy == 0x5C3A and r.m.sp == 0xFFE0

    # With no queued key, scheduled work still runs; a forced scan also runs
    # with a queued key, and remains deferred while another UART owner is busy.
    for key, forced, busy in ((0, 0, 0), (ord('a'), 1, 0), (ord('a'), 1, 1)):
        r = new()
        r.put('Keyboard.BASIC_KEY', key)
        r.put('UI.force_rescan', forced)
        r.put('Wifi.uart_busy', busy)
        r.put('Wifi.is_connected', 1)
        events = []
        if not forced:
            for name, value in (('UI.autoscan_counter', 14999), ('UI.health_counter', 499)):
                r.m.memory[s[name]:s[name] + 2] = value.to_bytes(2, 'little')
        def health_check():
            events.append('health')
            r.m.f = 0
        r.hook('Wifi.checkConnection', health_check)
        r.hook('UI.doAutoRescan', lambda: events.append('auto'))
        r.hook('Wifi.getList', lambda: events.append('forced'))
        for name in ('UI.hideCursor', 'UI.normalizeListPosition', 'UI.showPageInfo',
                     'UI.renderNetworksOnly', 'UI.showCursor'):
            r.hook(name)
        r.call('UI.uiLoopMain', 'UI.cursorDown' if key else 'UI.uiLoopMain.noKey')
        assert events == (['auto', 'health'] if not forced else [] if busy else ['forced'])
        assert r.get('UI.force_rescan') == int(bool(forced and busy))
        assert r.m.iy == 0x5C3A and r.m.sp == 0xFFE0

def check(image, s, target):
    check_menu_priority(image, s, target)
    new = lambda: Run(image, s)

    # Status colours affect only their columns on rows 18/19; the second
    # row clears BRIGHT and leaves every other attribute unchanged.
    colours = new()
    for routine, column, width in (('UI.colorIpValueBothRows', 3, 15),
                                   ('UI.colorStatusAreaBothRows', 22, 10)):
        for colour in range(256):
            expected_attrs = bytearray([0xA5]) * 768
            for row, value in ((18, colour), (19, colour & ~0x40)):
                start = row * 32 + column
                expected_attrs[start:start + width] = bytes([value]) * width
            colours.m.memory[0x5800:0x5B00] = bytes([0xA5]) * 768
            colours.m.a, colours.m.f = colour, 0xD7
            colours.m.bc, colours.m.de = 0x7654, 0x9876
            colours.call(routine)
            assert bytes(colours.m.memory[0x5800:0x5B00]) == expected_attrs
            assert (colours.m.f, colours.m.bc, colours.m.de) == (0xD7, 0x54, 0x9876)
            assert colours.m.iy == 0x5C3A and colours.m.sp == 0xFFE2

    prefix = new()
    output = s['UI.ip_line_buffer']
    for text in (b'', b'255.255.255.255', b'Disconnected', b'x' * 35):
        prefix.m.memory[output - 1:output + 41] = bytes([0xA5]) * 42
        prefix.m.set_memory_block(0x5D00, text + b'\0')
        prefix.m.hl = 0x5D00
        prefix.call('UI.ipSetPrefixed')
        assert bytes(prefix.m.memory[output:output + len(text) + 5]) == b'IP: ' + text + b'\0'
        assert prefix.m.memory[output - 1] == prefix.m.memory[output + 40] == 0xA5
        assert prefix.m.iy == 0x5C3A and prefix.m.sp == 0xFFE2

    def scanline(y):
        row, subrow = divmod(y, 8)
        address = ((0x40 | (row & 0x18) | subrow) << 8) | ((row & 7) << 5)
        return address

    # The two main-menu rows occupy 16 pixels centered between the one-pixel
    # separators: five blank scanlines above and five below.
    expected = new()
    expected.m.a = 3
    expected.call('Display.gotoXY0')
    expected.m.hl = s['UI.msg_help']
    expected.call('Display.putStr')
    expected.m.a = 4
    expected.m.hl = s['UI.msg_help2']
    expected.call('UI.printAt0')

    menu = new()
    menu.put('Wifi.networks_count', 1)
    menu.call('UI.renderList', 'UI.renderNetworksCommon')
    assert bytes(menu.m.memory[scanline(16):scanline(16) + 32]) == bytes([0xFF]) * 32
    assert bytes(menu.m.memory[scanline(43):scanline(43) + 32]) == bytes([0xFF]) * 32
    for y in range(17, 22):
        assert not any(menu.m.memory[scanline(y):scanline(y) + 32]), ('top gap', y)
    for y in range(22, 38):
        actual = bytes(menu.m.memory[scanline(y):scanline(y) + 32])
        reference = bytes(expected.m.memory[scanline(y + 2):scanline(y + 2) + 32])
        assert actual == reference, ('menu shift', y)
    for y in range(38, 43):
        assert not any(menu.m.memory[scanline(y):scanline(y) + 32]), ('bottom gap', y)

    # Both menu strings are composed off-screen; the obsolete unshifted rows
    # must never be exposed as an intermediate frame.
    staged = new()
    staged.put('Wifi.networks_count', 1)
    menu_draws = []
    def note_menu_draw():
        row = staged.m.memory[s['Display.coords'] + 1]
        if row in (3, 4):
            menu_draws.append((row, staged.get('Display.row_active')))
    staged.hook('Display.putStr', note_menu_draw)
    staged.call('UI.renderList', 'UI.renderNetworksCommon')
    assert menu_draws == [(3, 1), (4, 1)], menu_draws

    # Horizontal arrows share O/P paging; every page starts on a ten-row boundary.
    dispatch = image[s['UI.uiLoopMain'] - 0x8000:s['UI.rescan'] - 0x8000]
    for key, routine in (('KEY_LEFT', 'pageUp'), ('KEY_RIGHT', 'pageDown')):
        assert bytes((0xFE, s['Keyboard.' + key], 0xCA)) + s['UI.' + routine].to_bytes(2, 'little') in dispatch
    for count in range(26):
        for offset in range(0, max(count, 1), 10):
            for routine, expected in (('pageDown', offset + 10 if offset + 10 < count else offset),
                                      ('pageUp', max(0, offset - 10))):
                r = new()
                r.put('Wifi.networks_count', count)
                r.put('UI.offset', offset)
                for name in ('UI.hideCursor', 'UI.showCursor', 'UI.renderListOnly'):
                    r.hook(name)
                r.call('UI.' + routine, 'UI.uiLoop')
                assert r.get('UI.offset') == expected, (count, offset, routine)
                assert r.get('UI.cursor_position') == 0

    # Both auto-scan outcomes discard input captured against the old list.
    for failed in (False, True):
        r = new()
        r.m.bc, r.m.de, r.m.hl = 0x1234, 0x5678, 0x9ABC
        for name in ('Display.gotoXY0', 'Display.putC', 'UI.hideCursor',
                     'UI.normalizeListPosition', 'UI.renderListOnly'):
            r.hook(name)
        def auto_scan():
            r.put('Keyboard.BASIC_KEY', 13)
            r.m.f = int(failed)
        r.hook('Wifi.getList', auto_scan)
        r.call('UI.doAutoRescan')
        assert not r.get('Keyboard.BASIC_KEY')
        assert (r.m.bc, r.m.de, r.m.hl) == (0x1234, 0x5678, 0x9ABC)

    # Pre-join CWQAP permits only OK or a complete ERROR; BREAK stays cancellation.
    for status, destination in (
            ('OK', 'UI.connectAndReturn.carRetry'),
            ('ERROR', 'UI.connectAndReturn.carRetry'),
            ('TIMEOUT', 'UI.connectAndReturn.carDiscFailed'),
            ('UART', 'UI.connectAndReturn.carDiscFailed'),
            ('FAIL', 'UI.connectAndReturn.carDiscFailed'),
            ('BREAK', 'UI.showCancelledScreen')):
        r = new()
        r.put('Wifi.is_connected', 1)
        for name in ('Wifi.flushInput', 'UI.updateWifiStatus_q', 'UI.ipShowNotConnected'):
            r.hook(name)
        pending = deque({'OK': b'OK\r\n', 'ERROR': b'ERROR\r\n',
                         'FAIL': b'FAIL\r\n'}.get(status, b''))
        def disconnect_read():
            if pending:
                r.m.a, r.m.f = pending.popleft(), 1
            else:
                r.m.f = 0
                if status == 'UART':
                    r.put('Uart.io_error', 1)
                if status == 'BREAK':
                    r.put('Uart.break_hit', 1)
        r.hook('Uart.readTimeout', disconnect_read)
        r.hook('UartImpl.write')
        r.call('UI.connectAndReturn', destination)
        assert r.get('Wifi.reply_status') == s[f'Wifi.REPLY_{status}']
        assert r.m.sp == 0xFFE0
        assert r.get('Wifi.is_connected') == int(status != 'OK')

    # Idle recovery drains faults with or without data, then accepts fresh events.
    for ready in (False, True):
        r = new()
        r.put('UI.async_state', 7)
        first = [True]
        def idle_fault():
            r.m.a, r.m.f = ord('X'), int(first[0] and ready)
            if first[0]:
                r.put('Uart.io_error', 255)  # INC/DEC must also handle a full mask.
                first[0] = False
        r.hook('UartImpl.uartRead', idle_fault)
        r.call('UI.checkAsyncWifi')
        assert r.m.a == 0 and r.m.sp == 0xFFE2
        assert not any(r.get(name) for name in (
            'Uart.io_error', 'Wifi.uart_busy', 'UI.async_state'))
        r.feed(b'WIFI GOT IP\r\n')
        r.call('UI.checkAsyncWifi')
        assert r.m.a == s['UI.ASYNC_EVENT_GOTIP']

    r = new()
    r.put('Wifi.uart_busy', 1)
    r.put('Uart.io_error', 1)
    def forbidden_drain():
        raise AssertionError('async recovery entered a live transaction')
    r.hook('Wifi.flushInput', forbidden_drain)
    r.call('UI.checkAsyncWifi')
    assert r.get('Uart.io_error') and r.get('Wifi.uart_busy')

    # Selection must defend itself, even if navigation state is corrupted.
    for offset, cursor in ((20, 1), (255, 1), (0, 2)):
        r = new()
        r.put('Wifi.networks_count', 2)
        r.put('UI.offset', offset)
        r.put('UI.cursor_position', cursor)
        r.call('UI.selectItem', 'UI.uiLoop')
        assert r.m.sp == 0xFFE0

    # Successful post-WPS scan follows the same normalization as every render.
    r = new()
    r.put('UI.offset', 20)
    r.put('UI.cursor_position', 1)
    r.hook('UI.flushUartBuffer')
    def scan():
        r.put('Wifi.networks_count', 2)
        r.m.f = 0
    r.hook('Wifi.getList', scan)
    r.hook('UI.renderListAndLoop', lambda: setattr(r.m, 'pc', s['UI.renderNetworksCommon']))
    r.call('UI.doWPS.wpsKeyOk', 'UI.renderNetworksCommon.showLoop')
    assert r.get('UI.offset') + r.get('UI.cursor_position') < 2

    # Full password redraw may wrap only AFTER its final trailing space.
    for column, expected in ((40, [(40, 12), (41, 12)]), (41, [(41, 12)])):
        r = new()
        r.m.memory[s['Display.coords']:s['Display.coords'] + 2] = bytes((column, 12))
        draws = []
        r.hook('Display.drawCBig', lambda: draws.append(tuple(r.m.memory[s['Display.coords']:s['Display.coords'] + 2])))
        r.call('UI.passwordInput.piClrTail', 'UI.passwordInput.piWait')
        assert draws == expected, draws

    # Masked full redraw must emit exactly one glyph per password character.
    for cursor in (2, 4):
        r = new()
        r.put('UI.pass_len', 4)
        r.put('UI.pass_cursor', cursor)
        r.put('UI.show_password', 0)
        r.m.set_memory_block(s['UI.pass_buffer'], b'abcd\0')
        glyphs = []
        r.hook('UI.setRowsColor')
        r.hook('Display.putCBigGlyph', lambda: glyphs.append(True))
        r.hook('Display.putCBig')
        r.call('UI.passwordInput.piRedraw', 'UI.passwordInput.piWait')
        assert len(glyphs) == 4, (cursor, len(glyphs))

    # SDK version is a valid GMR line; SEND OK is still noise.
    for line, visible in ((b'SDK version:3.0\0', True), (b'SEND OK\0', False)):
        r = new()
        r.m.set_memory_block(s['UI.diag_buffer'], line)
        r.m.a = line[0]
        shown = []
        r.hook('UI.showDiagLine', lambda: shown.append(True))
        r.call('UI.doModuleInfo.checkOther', 'UI.doModuleInfo.gmrLoop')
        assert bool(shown) == visible

    # Empty GMR prefixes cannot consume the firmware summary result.
    r = new()
    lines = deque((b'\0', b'AT version:1.7.4\0'))
    r.hook('Keyboard.checkBreak', lambda: setattr(r.m, 'f', 0))
    def read_line():
        r.m.set_memory_block(s['UI.diag_buffer'], lines.popleft())
        r.m.f = 1
    r.hook('UI.readDiagLineBC', read_line)
    displayed = []
    r.hook('UI.putStrLimited', lambda: displayed.append(bytes(r.m.memory[r.m.hl:r.m.hl+20]).split(b'\0')[0]))
    r.m.b = 10
    r.call('UI.doConfigSummary.cs_fw_loop', 'UI.doConfigSummary.cs_fw_done')
    assert displayed == [b'1.7.4'] and not lines

    # Every config-summary value starts at six-pixel column 12, the byte-aligned
    # position used by the signal bar.
    summary_labels = (
        'cs_ssid', 'cs_ip_lbl', 'cs_gw_lbl', 'cs_mask_lbl',
        'cs_mac_lbl', 'cs_hn_lbl', 'cs_fw_lbl',
    )
    if target != 'AY':
        summary_labels += ('cs_saved_lbl',)
    for label in summary_labels:
        address = s[f'UI.doConfigSummary.{label}']
        text = bytes(r.m.memory[address:address + 16]).split(bytes(1))[0]
        assert len(text) == 12, (label, text)
    assert s['UI.RSSI_COL_DETAIL'] * 8 == 12 * 6

    # Volatile esxDOS printer RAM can no longer alter a saved ping length.
    assert s['UI.ping_ip_len'] >= s['buffer']
    r = new()
    r.put('UI.ping_ip_len', 255)
    r.call('UI.doPing', 'UI.doPing.skipInit')
    assert r.get('UI.ping_ip_len') == 7

    # Diagnostic output advances past every row actually occupied.
    for length, next_line in ((1, 7), (42, 7), (43, 8), (60, 8)):
        r = new()
        r.put('UI.diag_line', 6)
        r.m.set_memory_block(s['UI.diag_buffer'], b'X' * length + b'\0')
        r.call('UI.showDiagLine')
        assert r.get('UI.diag_line') == next_line, length

    r = new()
    r.put('UI.diag_line', s['UI.DIAG_ROW_LIMIT'] - 1)
    r.m.set_memory_block(s['UI.diag_buffer'], b'X' * 60 + b'\0')
    rows = []
    r.hook('Display.drawCAt.prepared',
           lambda: rows.append(r.m.memory[s['Display.coords'] + 1]))
    r.call('UI.showDiagLine')
    assert rows and max(rows) == s['UI.DIAG_ROW_LIMIT'] - 1
    assert r.get('UI.diag_line') == s['UI.DIAG_ROW_LIMIT']

    # BREAK stops ping both before and during a silent line read.
    r = new()
    reads = []
    r.hook('Keyboard.checkBreak', lambda: setattr(r.m, 'f', 0x40))
    r.hook('UI.readDiagLineBC', lambda: reads.append(True))
    r.m.b, r.m.c = 100, 20
    r.call('UI.doPing.pingLoop', 'UI.showDiagnostics')
    assert not reads

    r = new()
    reads = []
    r.hook('Keyboard.checkBreak', lambda: setattr(r.m, 'f', 0))
    def cancel_ping_read():
        reads.append(True)
        r.put('Uart.break_hit', 1)
        r.m.f = 0
    r.hook('UI.readDiagLineBC', cancel_ping_read)
    r.m.b, r.m.c = 100, 20
    r.call('UI.doPing.pingLoop', 'UI.showDiagnostics')
    assert reads == [True]

    # A baud-reader BREAK aborts the current query and all fallback queries.
    r = new()
    queries = []
    reads = []
    r.hook('UI.diagHeader')
    r.hook('UI.flushUartBuffer')
    r.hook('Wifi.ensureCommandMode', lambda: setattr(r.m, 'f', 0))
    r.hook('Wifi.espSendZ_CRLF', lambda: queries.append(bytes(r.m.memory[r.m.hl:r.m.hl + 32]).split(b'\0')[0]))
    def cancel_baud_read():
        reads.append(True)
        r.put('Uart.break_hit', 1)
        r.m.f = 0
    r.hook('UI.readDiagLineLong', cancel_baud_read)
    r.call('UI.doBaudRate', 'UI.showDiagnostics')
    assert reads == [True] and queries == [b'AT+UART_CUR?']

    r = new()
    r.put('UI.diag_line', 6)
    r.m.hl, r.m.de = s['UI.cmd_uart_cur'], s['UI.lbl_baud_cur']
    r.hook('UI.flushUartBuffer')
    r.hook('Wifi.espSendZ_CRLF')
    def return_baud_value():
        r.m.set_memory_block(s['UI.diag_buffer'], b'+UART_CUR:115200,8,1,0,0\0')
        r.put('Uart.break_hit', 0)
        r.m.f = 1
    r.hook('UI.readDiagLineLong', return_baud_value)
    r.call('UI.baudQueryValue')
    assert r.get('UI.baud_have_value') and r.m.f & 1 and r.m.f & 0x40

    # Every diagnostics transition drains a held cancellation chord.
    r = new()
    releases = []
    r.hook('Keyboard.waitBreakRelease', lambda: releases.append(True))
    r.call('UI.showDiagnostics', 'UI.diagHeader')
    assert releases == [True]

    # Scanned connections retain AP identity; manual/saved routes use SSID only.
    macs = (b'\x00\x11\x22\x33\x44\x55', b'\xaa\xbb\xcc\xdd\xee\xff')
    for index, mac in enumerate(macs):
        r = new()
        r.put('UI.selected_real_idx', index)
        r.m.set_memory_block(s['Wifi.bssid_buffer'] + index * 6, mac)
        r.m.set_memory_block(s['UI.manual_ssid_buffer'], b'SharedSSID\0')
        r.m.set_memory_block(s['UI.pass_buffer'], b'validpassword\0')
        tx = []
        r.hook('UartImpl.write', lambda: tx.append(r.m.a))
        r.m.hl = s['UI.at_start']
        r.call('UI.connectAndReturn.carSend', 'Wifi.checkOkErrLong')
        expected_mac = b':'.join(f'{byte:02X}'.encode() for byte in mac)
        assert bytes(tx) == b'AT+CWJAP="SharedSSID","validpassword","' + expected_mac + b'"\r\n'

    r = new()
    r.put('UI.selected_real_idx', 0xFF)
    r.m.set_memory_block(s['UI.manual_ssid_buffer'], b'Manual\0')
    r.m.set_memory_block(s['UI.pass_buffer'], b'password\0')
    tx = []
    r.hook('UartImpl.write', lambda: tx.append(r.m.a))
    r.m.hl = s['UI.at_start']
    r.call('UI.connectAndReturn.carSend', 'Wifi.checkOkErrLong')
    assert bytes(tx) == b'AT+CWJAP="Manual","password"\r\n'

    for invalid_mac in (b'\0' * 6, b'\xff\0\0\0\0\0'):
        r = new()
        r.put('UI.selected_real_idx', 0)
        r.m.set_memory_block(s['Wifi.bssid_buffer'], invalid_mac)
        r.m.set_memory_block(s['UI.manual_ssid_buffer'], b'Legacy\0')
        r.m.set_memory_block(s['UI.pass_buffer'], b'password\0')
        tx = []
        r.hook('UartImpl.write', lambda: tx.append(r.m.a))
        r.m.hl = s['UI.at_start']
        r.call('UI.connectAndReturn.carSend', 'Wifi.checkOkErrLong')
        assert bytes(tx) == b'AT+CWJAP="Legacy","password"\r\n'

    # Same SSID shows details only for the same AP or unknown current identity.
    selected_mac = b'\x00\x11\x22\x33\x44\x55'
    for current_valid, current_mac, destination in (
            (1, selected_mac, 'UI.selectItem.alreadyConnected'),
            (1, b'\x00\x11\x22\x33\x44\x66', 'UI.selectItem.notConnectedYet'),
            (0, b'\0' * 6, 'UI.selectItem.alreadyConnected')):
        r = new()
        r.put('Wifi.is_connected', 1)
        r.put('Wifi.networks_count', 1)
        r.put('Wifi.display_indices', 0)
        r.m.set_memory_block(s['buffer'], b'Legacy\0')
        r.m.set_memory_block(s['Wifi.connected_ssid'], b'Legacy\0')
        r.m.set_memory_block(s['Wifi.ssid_ptr_table'], s['buffer'].to_bytes(2, 'little'))
        r.m.set_memory_block(s['Wifi.bssid_buffer'], selected_mac)
        r.put('Wifi.connected_bssid_valid', current_valid)
        r.m.set_memory_block(s['Wifi.connected_bssid'], current_mac)
        r.call('UI.selectItem', destination)
        assert r.m.sp == 0xFFE0

    r = new()
    r.put('UI.selected_real_idx', 3)
    r.put('UI.pass_len', 0)
    r.call('UI.manualSSID.connectManual', 'UI.connectAndReturn')
    assert r.get('UI.selected_real_idx') == 0xFF and not r.get('UI.is_reconnect')

    if target != 'AY':
        r = new()
        r.put('UI.selected_real_idx', 3)
        r.hook('UI.doReconnect.rcYN', lambda: setattr(r.m, 'f', 0x40))
        r.hook('Config.copyToBuffers')
        r.call('UI.doReconnect.rcDoConnect', 'UI.connectAndReturn')
        assert r.get('UI.selected_real_idx') == 0xFF and r.get('UI.is_reconnect')

    # Match complete events before later lines arrive; retain split prefixes.
    r = new()
    r.feed(b'WIFI DISCONNECT\r\n0,CLOSED\r\nWIFI GOT IP\r\n')
    r.call('UI.checkAsyncWifi')
    assert r.m.a == 1
    r.call('UI.checkAsyncWifi')
    assert r.m.a == 2
    r.call('UI.checkAsyncWifi')
    assert r.m.a == 0
    for split in range(1, 15):
        r = new()
        data = b'WIFI DISCONNECT'
        r.feed(data[:split])
        r.call('UI.checkAsyncWifi')
        assert r.m.a == 0
        r.feed(data[split:] + b'\r\n0,CLOSED\r\n')
        r.call('UI.checkAsyncWifi')
        assert r.m.a == 1, split
    r = new()
    r.feed(b'WIFI DISCONNECT\r\n')
    r.put('Uart.io_error', 1)
    r.call('UI.checkAsyncWifi')
    assert r.m.a == 0

    # Unchanged visible rows skip composition; selection updates only attributes.
    r = new()
    r.call('UI.init')
    r.put('Wifi.networks_count', 2)
    pointer = s['buffer']
    for index, name in enumerate((b'first', b'second')):
        r.m.set_memory_block(pointer, name + b'\0')
        start = s['Wifi.ssid_ptr_table'] + 2 * index
        r.m.memory[start:start + 2] = pointer.to_bytes(2, 'little')
        r.m.memory[s['Wifi.rssi_buffer'] + index] = 40
        pointer += len(name) + 1
    r.call('Wifi.initDisplayIndices')
    r.call('UI.renderNetworksCommon')
    pixels = bytes(r.m.memory[0x4000:0x5800])
    def unexpected_composition():
        raise AssertionError('unchanged row was recomposed')
    r.hook('Display.beginRow', unexpected_composition)
    r.put('UI.cursor_position', 1)
    r.call('UI.renderNetworksCommon')
    assert bytes(r.m.memory[0x4000:0x5800]) == pixels
    assert r.m.memory[0x58C0] == s['Display.ATTR_NORMAL']
    assert r.m.memory[0x58E0] == s['Display.ATTR_HIGHLIGHT']
    r.m.clear_breakpoint(s['Display.beginRow'])
    del r.hooks[s['Display.beginRow']]
    r.put('Wifi.networks_count', 1)
    r.call('UI.renderNetworksCommon')
    assert all(not any(r.m.memory[0x40E0 + y * 256:0x4100 + y * 256]) for y in range(8))
    r.put('Wifi.networks_count', 2)
    r.call('UI.renderNetworksCommon')
    assert any(r.m.memory[0x40E0 + y * 256] for y in range(8))
    r.call('UI.clearNetworksArea')
    assert all(r.m.memory[s['UI.row_cache'] + i * 32 + 30] == 0 for i in range(10))
    r.call('UI.renderNetworksCommon')
    assert any(r.m.memory[0x40E0 + y * 256] for y in range(8))


    # The row cache is keyed on the bar that gets drawn, not on the raw
    # reading: a 1 dBm wobble that quantises to the same cell count must not
    # force a recompose. rssiCells maps 9 dBm per cell.
    r2 = new()
    for i in range(10):
        r2.m.set_memory_block(s['buffer'] + i * 33, b'NET_' + bytes([48 + i]) + bytes(1))
        addr = s['buffer'] + i * 33
        r2.m.set_memory_block(s['Wifi.ssid_ptr_table'] + i * 2,
                              addr.to_bytes(2, 'little'))
        r2.m.memory[s['Wifi.rssi_buffer'] + i] = 60 + i
    r2.put('Wifi.networks_count', 10)
    r2.put('UI.offset', 0)
    r2.put('Wifi.is_connected', 0)
    r2.call('Wifi.initDisplayIndices')
    r2.call('UI.renderNetworksCommon')
    row = 0x4000 + (6 // 8) * 0x800 + (6 % 8) * 32
    drawn = bytes(r2.m.memory[row:row + 32])
    for i in range(10):
        r2.m.memory[s['Wifi.rssi_buffer'] + i] = 60 + i + 1
    r2.call('UI.renderNetworksCommon')
    assert bytes(r2.m.memory[row:row + 32]) == drawn, 'a 1 dBm wobble changed the bar'
    key_same = r2.m.memory[s['UI.row_cache'] + 29]
    for i in range(10):
        r2.m.memory[s['Wifi.rssi_buffer'] + i] = 60 + i + 20
    r2.call('UI.renderNetworksCommon')
    assert r2.m.memory[s['UI.row_cache'] + 29] != key_same, 'a real level change was missed'

    # RSSI pixels always complete the block. Active cells use two solid 3x6
    # bars; the remainder uses four dim-white 1x6 vertical stripes.
    inactive_patterns = (0xAA,) * 6
    zones = (0x02, 0x02, 0x02, 0x06, 0x06, 0x06, 0x04, 0x04, 0x04)
    assert s['UI.RSSI_COL_LIST'] == 23
    assert s['UI.RSSI_COL_DETAIL'] == 9
    # Byte 9 is pixel 72, exactly where the 6px column 12 starts.
    assert s['UI.RSSI_COL_DETAIL'] * 8 == 12 * 6
    for column in (s['UI.RSSI_COL_LIST'], s['UI.RSSI_COL_DETAIL']):
        for buffered in (False, True):
            bar = new()
            bar.put('UI.drb_col', column)
            if buffered:
                bar.m.a = 10
                bar.call('Display.beginRow')
                starts = [s['Display.row_buffer'] + 32 * scanline + column
                          for scanline in range(1, 7)]
            else:
                bar.m.d, bar.m.e = 10, column
                bar.call('Display.findAddr')
                first = (bar.m.d << 8) | bar.m.e
                starts = [first + 0x100 * scanline for scanline in range(1, 7)]
            for lit in range(1, 10):
                bar.m.a, bar.m.c = 10, lit
                bar.call('UI.drawRssiBlock')
                for start, pattern in zip(starts, inactive_patterns):
                    actual_pixels = bytes(bar.m.memory[start:start + 9])
                    expected_pixels = bytes([0xEE]) * lit + bytes([pattern]) * (9 - lit)
                    assert actual_pixels == expected_pixels, (
                        column, buffered, lit, hex(start), actual_pixels.hex()
                    )
                attrs = 0x5800 + 10 * 32 + column
                expected_attrs = bytes(
                    [zone | 0x40 for zone in zones[:lit]] + [0x07] * (9 - lit)
                )
                actual_attrs = bytes(bar.m.memory[attrs:attrs + 9])
                assert actual_attrs == expected_attrs, (
                    column, buffered, lit, actual_attrs.hex()
                )

    # The detail screens print 12-character labels, so their values and the
    # bar line up in one column.
    for label in ('UI.showNetDetail.nd_sec', 'UI.showNetDetail.nd_chan',
                  'UI.showNetDetail.nd_sig', 'UI.selectItem.ci_ip_lbl',
                  'UI.selectItem.ci_gw_lbl', 'UI.selectItem.ci_mask_lbl',
                  'UI.selectItem.ci_mac_lbl'):
        text = bytes(image[s[label] - 0x8000:s[label] - 0x8000 + 20])
        assert len(text.split(bytes(1))[0]) == 12, label

    # A changed signal affects the exact row key even when the name is unchanged.
    r.put('UI.current_line', 6)
    r.put('UI.current_screen_idx', 0)
    r.m.hl = s['buffer']
    r.call('UI.rowPixelsChanged')
    assert r.m.f & 0x40
    r.put('Wifi.rssi_buffer', 70)
    r.m.hl = s['buffer']
    r.call('UI.rowPixelsChanged')
    assert not r.m.f & 0x40
