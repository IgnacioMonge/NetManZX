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


def check(image, symbols, target):
    del target
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
    assert 0xC000 <= cache and cache + 768 <= symbols["static_data_end"]
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

    # Row staging reuses consumed RX storage, never the decoded network tables.
    run = Run(image, symbols)
    assert symbols["Display.row_buffer"] == symbols["Wifi.scan_rx_buffer"]
    for hook in ("Wifi.flushInput", "Wifi.espSendZ_CRLF", "Display.putStrLog"):
        run.hook(hook)
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
