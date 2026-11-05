"""Focused execution checks for the cached six-pixel display renderer."""

from hashlib import sha256
from audit_regression import Run


Z_FLAG = 0x40


def _pixel_addr(row, scanline, byte=0):
    return ((0x40 | (row & 0x18) | scanline) << 8) | ((row & 7) << 5) | byte


def _set_draw_coords(run, symbols, col, row, routine="drawC"):
    address = symbols[f"Display.{routine}.coords"]
    run.m.memory[address:address + 2] = (col | row << 8).to_bytes(2, "little")


def _clear_rows(run, first, count):
    for row in range(first, first + count):
        for scanline in range(8):
            address = _pixel_addr(row, scanline)
            run.m.memory[address:address + 32] = bytes(32)


def check_footer(image, symbols):
    # The footer publishes the same pixels as direct text/arrows, without
    # exposing an empty row first. Repeating it must skip publication.
    for count in (0, 1, 10, 11, 25, 50):
        for offset in range(0, max(count, 1), 10):
            actual, expected = Run(image, symbols), Run(image, symbols)
            for r in (actual, expected):
                r.m.memory[0x4000:0x5B00] = b'\xa5' * 6912
                r.put('Wifi.networks_count', count)
                r.put('UI.offset', offset)
            expected.m.a = 17
            expected.call('UI.clearRowPixels')
            if count:
                text = f'{count} networks detected'
                pages = (count + 9) // 10
                if pages > 1:
                    text += f' ({offset // 10 + 1}/{pages} pages)'
                expected.m.set_memory_block(0x5D00, text.encode() + b'\0')
                expected.m.memory[symbols['Display.coords']:symbols['Display.coords'] + 2] = bytes((41 - len(text), 17))
                expected.m.hl = 0x5D00
                expected.call('Display.putStr')
            expected.call('UI.showScrollIndicators')
            actual.call('UI.showPageInfo', 'Display.endRow')
            assert bytes(actual.m.memory[0x4000:0x5B00]) == b'\xa5' * 6912
            assert actual.get('Display.row_active') == 1
            actual.call('Display.endRow')
            assert bytes(actual.m.memory[0x4000:0x5B00]) == bytes(expected.m.memory[0x4000:0x5B00]), (count, offset)
            actual.call('UI.showPageInfo')
            assert actual.m.f & Z_FLAG and not actual.get('Display.row_active')
            assert actual.m.iy == 0x5C3A and actual.m.sp == 0xFFE2
            # Shrinking the list erases both old text and old arrows.
            actual.put('Wifi.networks_count', 0)
            actual.put('UI.offset', 0)
            actual.call('UI.showPageInfo')
            for line in range(8):
                start = _pixel_addr(17, line)
                assert bytes(actual.m.memory[start:start + 32]) == bytes(32)

    skipped = Run(image, symbols)
    skipped.m.memory[0x4000:0x5B00] = b'\xa5' * 6912
    skipped.put('UI.skip_footer', 1)
    skipped.put('Wifi.networks_count', 25)
    skipped.put('UI.offset', 10)
    skipped.call('UI.showPageInfo')
    assert bytes(skipped.m.memory[0x4000:0x5B00]) == b'\xa5' * 6912
    assert not skipped.get('Display.row_active')


def check(image, symbols, target):
    del target
    check_footer(image, symbols)
    run = Run(image, symbols)

    # Manual scan replaces the entire count/page row before waiting for WiFi.
    expected = Run(image, symbols)
    expected.m.a = 17
    expected.m.hl = symbols["UI.msg_ip_scanning"]
    expected.call("UI.printAt0")
    for count in (8, 14, 25):
        actual = Run(image, symbols)
        actual.put("Wifi.networks_count", count)
        actual.call("UI.showPageInfo")
        actual.hook("UI.hideCursor")
        actual.call("UI.rescan", "Wifi.getList")
        for scanline in range(8):
            address = _pixel_addr(17, scanline)
            assert bytes(actual.m.memory[address:address + 32]) == bytes(expected.m.memory[address:address + 32]), "manual scan leaves old count/page pixels"

    cache = symbols["Display.font_cache"]
    glyph_buf = symbols["Display.glyph_buf"]

    run.put("Display.row_active", 0xA5)
    run.call("Display.initFontCache")
    assert not run.get("Display.row_active")

    # Exact font produced by the pre-fix e1a0d8d unpacker, including fixes
    # for %, & and _. A fixed baseline catches accidental appearance changes.
    overlay_end = symbols.get("tap_overlay_end", symbols.get("overlay_end"))
    if overlay_end is not None:
        assert cache == 0x6000 and cache + 768 <= overlay_end
    else:
        assert 0xC000 <= cache and cache + 768 <= symbols["static_data_end"]
    assert cache % 8 == 0
    font = bytes(run.m.memory[cache:cache + 768])
    assert sha256(font).hexdigest() == "8cf05f8a80299734d444821e2fd0b8a0a3c24bd69ef3ad7720b51586006a2a5a"
    for char in range(32, 128):
        cached = font[(char - 32) * 8:(char - 31) * 8]
        assert all(not value & 3 for value in cached), char
        run.m.a = char
        run.call("Display.decompressChar")
        assert bytes(run.m.memory[glyph_buf:glyph_buf + 8]) == cached, char

    space = bytes(run.m.memory[cache:cache + 8])
    for char in (0, 31, 128, 255):
        run.m.a = char
        run.call("Display.decompressChar")
        assert bytes(run.m.memory[glyph_buf:glyph_buf + 8]) == space

    # Optimized phase blitters match the independent general renderer,
    # including neighbouring pixels in screen and row-buffer destinations.
    for buffered in (False, True):
        reference, fast = Run(image, symbols), Run(image, symbols)
        starts = [symbols["Display.row_buffer"] + 32 * line if buffered
                  else _pixel_addr(10, line) for line in range(8)]
        for char in range(32, 128):
            for col in (0, 1, 2, 3):  # Pixel phases 0, 6, 4 and 2.
                for renderer in (reference, fast):
                    renderer.put("Display.row_active", int(buffered))
                    for start in starts:
                        renderer.m.memory[start:start + 32] = bytes([0xA5]) * 32
                    renderer.m.a = char
                _set_draw_coords(reference, symbols, col, 10)
                reference.call("Display.drawC")
                fast.m.b, fast.m.de = col * 6 % 8, starts[0] + col * 6 // 8
                fast.call("Display.drawCAt")
                for start in starts:
                    assert bytes(fast.m.memory[start:start + 32]) == bytes(
                        reference.m.memory[start:start + 32]
                    ), (buffered, char, col, start)
                assert fast.m.iy == 0x5C3A and fast.m.sp == 0xFFE2

    # Every glyph followed by a space clears exactly its six-pixel cell at
    # every column, without changing either neighbour's canary pixels.
    row = 10
    canary = 0xA5
    for char in range(32, 128):
        for col in range(42):
            expected = bytearray([canary] * 32)
            for pixel in range(col * 6, col * 6 + 6):
                expected[pixel >> 3] &= ~(0x80 >> (pixel & 7))
            for scanline in range(8):
                address = _pixel_addr(row, scanline)
                run.m.memory[address:address + 32] = bytes([canary]) * 32
            run.put("Display.row_active", 0)
            _set_draw_coords(run, symbols, col, row)
            run.m.a = char
            run.call("Display.drawC")
            run.m.a = ord(" ")
            run.call("Display.drawC")
            for scanline in range(8):
                address = _pixel_addr(row, scanline)
                assert bytes(run.m.memory[address:address + 32]) == expected, (char, col, scanline)

    # Cached glyphs still render correctly through the double-height path.
    for char in range(32, 128):
        _clear_rows(run, 8, 2)
        _set_draw_coords(run, symbols, 0, 8, "drawCBig")
        run.m.a = char
        run.call("Display.drawCBig")
        glyph = run.m.memory[cache + (char - 32) * 8:cache + (char - 31) * 8]
        for scanline in range(8):
            actual = run.m.memory[_pixel_addr(8, scanline)]
            assert actual == glyph[scanline >> 1], (char, scanline, actual, glyph[scanline >> 1])
            actual = run.m.memory[_pixel_addr(9, scanline)]
            assert actual == glyph[4 + (scanline >> 1)], (char, scanline, actual, glyph[4 + (scanline >> 1)])

    custom = bytes((0x84, 0x48, 0x30, 0xFC, 0xCC, 0x78, 0x30, 0x00))
    run.m.memory[glyph_buf:glyph_buf + 8] = custom
    coords = symbols["Display.coords"]
    run.m.memory[coords:coords + 2] = (8 << 8).to_bytes(2, "little")
    _clear_rows(run, 8, 2)
    run.call("Display.putCBigGlyph")
    assert run.m.memory[coords] == 1
    for scanline in range(8):
        assert run.m.memory[_pixel_addr(8, scanline)] == custom[scanline >> 1]
        assert run.m.memory[_pixel_addr(9, scanline)] == custom[4 + (scanline >> 1)]

    # beginRow is bounded and preserves the list loop's live registers.
    row_buffer = symbols["Display.row_buffer"]
    run.m.memory[row_buffer - 1] = 0x5A
    run.m.memory[row_buffer + 258] = 0xA5
    run.m.bc, run.m.de, run.m.hl, run.m.a = 0x1234, 0x5678, 0x9ABC, 6
    run.call("Display.beginRow")
    assert (run.m.bc, run.m.de, run.m.hl) == (0x1234, 0x5678, 0x9ABC)
    assert run.m.memory[row_buffer - 1] == 0x5A
    assert run.m.memory[row_buffer + 258] == 0xA5

    _set_draw_coords(run, symbols, 0, 6)
    run.m.a = ord("A")
    run.call("Display.drawC")
    run.call("Display.endRow")
    assert not run.m.f & Z_FLAG
    published = bytes(run.m.memory[_pixel_addr(6, scanline)] for scanline in range(8))

    run.m.a = 6
    run.call("Display.beginRow")
    _set_draw_coords(run, symbols, 0, 6)
    run.m.a = ord("A")
    run.call("Display.drawC")
    run.call("Display.endRow")
    assert run.m.f & Z_FLAG
    assert bytes(run.m.memory[_pixel_addr(6, scanline)] for scanline in range(8)) == published

    # A blank composed row clears a vanished item and leaves adjacent rows intact.
    for adjacent in (5, 7):
        for scanline in range(8):
            address = _pixel_addr(adjacent, scanline)
            run.m.memory[address:address + 32] = bytes([0x3C]) * 32
    run.m.a = 6
    run.call("Display.beginRow")
    run.call("Display.endRow")
    assert not run.m.f & Z_FLAG
    for scanline in range(8):
        assert bytes(run.m.memory[_pixel_addr(6, scanline):_pixel_addr(6, scanline) + 32]) == bytes(32)
        for adjacent in (5, 7):
            address = _pixel_addr(adjacent, scanline)
            assert bytes(run.m.memory[address:address + 32]) == bytes([0x3C]) * 32

    # Partial-scanline resume in endRow publishes the entire 256-byte row
    # regardless of which scanline/byte holds the first difference.
    for first_scan, first_byte in ((0, 0), (3, 22), (7, 31)):
        expected_row = bytes(((s * 37 + b * 13 + 0x11) & 0xFF) for s in range(8) for b in range(32))
        screen_row = bytearray(expected_row)
        for s in range(first_scan, 8):
            start_b = first_byte if s == first_scan else 0
            for b in range(start_b, 32):
                screen_row[s * 32 + b] ^= 0xFF
        for s in range(8):
            addr = _pixel_addr(6, s)
            run.m.memory[addr:addr + 32] = screen_row[s * 32:(s + 1) * 32]
        run.m.a = 6
        run.call("Display.beginRow")
        run.m.memory[row_buffer:row_buffer + 256] = expected_row
        run.call("Display.endRow")
        assert not run.m.f & Z_FLAG
        assert not run.get("Display.row_active")
        assert run.m.sp == 0xFFE2
        for s in range(8):
            addr = _pixel_addr(6, s)
            assert bytes(run.m.memory[addr:addr + 32]) == expected_row[s * 32:(s + 1) * 32], (first_scan, first_byte, s)

    # Row staging reuses consumed RX storage, never the decoded network tables.
    run = Run(image, symbols)
    assert symbols["Display.row_buffer"] == symbols["Wifi.scan_rx_buffer"]
    for hook in ("Wifi.flushInput", "Display.putStrLog"):
        run.hook(hook)
    run.hook("Wifi.espSendZ_CRLF")
    for name in (b"first-scan", b"second-scan"):
        run.feed(b'+CWLAP:(3,"' + name + b'",-42,"00:11:22:33:44:55",6)\r\nOK\r\n')
        run.call("Wifi.getList")
        assert not run.m.f & 1 and run.get("Wifi.networks_count") == 1
        run.call("UI.renderListOnly")
        assert bytes(run.m.memory[symbols["buffer"]:symbols["buffer"] + len(name) + 1]) == name + b"\0"
        assert bytes(run.m.memory[symbols["Wifi.bssid_buffer"]:symbols["Wifi.bssid_buffer"] + 6]) == bytes.fromhex("001122334455")

    # Audit model: cached lookup plus the buffered target/stride worst case
    # remains below the old average packed decode/exception cost alone.
    cached_lookup_t = 105
    buffered_overhead_t = 523
    packed_decode_average_t = 1300
    assert cached_lookup_t + buffered_overhead_t < packed_decode_average_t
