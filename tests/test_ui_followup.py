"""UI regression checks on assembled code; invoked by audit_regression.py."""
from collections import deque
from audit_regression import Run


def check(image, s, target):
    new = lambda: Run(image, s)

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
        r.put('UI.async_buf_idx', 7)
        r.put('UI.async_buf_count', 4)
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
            'Uart.io_error', 'Wifi.uart_busy', 'UI.async_buf_idx', 'UI.async_buf_count'))
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
    r.hook('Display.drawC', lambda: rows.append(r.m.memory[s['Display.drawC.coords'] + 1]))
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
        r.put('UI.selected_real_idx', 0)
        r.m.set_memory_block(s['Wifi.bssid_buffer'], selected_mac)
        r.put('Wifi.connected_bssid_valid', current_valid)
        r.m.set_memory_block(s['Wifi.connected_bssid'], current_mac)
        r.call('UI.selectItem.sameSSID', destination)
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
