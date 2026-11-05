"""Execution checks for the optional 64-column overlay renderer."""

from hashlib import sha256

from audit_regression import Run


def _pixel_addr(row, scanline, byte=0):
    return ((0x40 | (row & 0x18) | scanline) << 8) | ((row & 7) << 5) | byte


def _set_draw_coords(run, symbols, col, row):
    address = symbols["Display64.drawC.coords"]
    run.m.memory[address:address + 2] = (col | row << 8).to_bytes(2, "little")


def _patterns(packed, char):
    glyph = packed[(char - 32) * 3:(char - 31) * 3]
    return [0] + [nibble for byte in glyph for nibble in (byte >> 4, byte & 15)] + [0]


def check(image, symbols, target):
    run = Run(image, symbols)
    table = symbols["Display64.font64_packed"]
    table_end = symbols["Display64.font64_packed_end"]
    lut_address = symbols["Display64.font64_lut"]

    assert 0x6000 <= symbols["Display64.gotoXY0"] < 0x8000
    assert table_end - table == 96 * 3
    packed = bytes(run.m.memory[table:table_end])
    assert sha256(packed).hexdigest() == "e2db3ca3061ec13896c6d7dbe9264e78409bc0d27e8e80060f4d228aa7f8de89"
    lut = bytes(run.m.memory[lut_address:lut_address + 10])
    assert lut == bytes.fromhex("00 22 44 55 66 88 AA CC EE FF")

    custom = {
        ord("^"): bytes.fromhex("86 22 68"),
        ord("`"): bytes.fromhex("28 88 82"),
        ord("{"): bytes.fromhex("08 82 00"),
        ord("}"): bytes.fromhex("00 28 80"),
        ord("~"): bytes.fromhex("26 66 62"),
        127: bytes.fromhex("99 99 99"),
    }
    for char, glyph in custom.items():
        offset = (char - 32) * 3
        assert packed[offset:offset + 3] == glyph

    # Every glyph at every column replaces exactly one four-pixel cell.
    row = 10
    canary = 0xA5
    for char in range(32, 128):
        patterns = _patterns(packed, char)
        for col in range(64):
            byte_col = col >> 1
            right = col & 1
            for scanline in range(8):
                address = _pixel_addr(row, scanline)
                run.m.memory[address:address + 32] = bytes([canary]) * 32
            run.put("Display.row_active", 0)
            _set_draw_coords(run, symbols, col, row)
            run.m.a = char
            run.call("Display64.drawC")
            for scanline, index in enumerate(patterns):
                expected = bytearray([canary] * 32)
                bits = lut[index]
                if right:
                    expected[byte_col] = (canary & 0xF0) | (bits & 0x0F)
                else:
                    expected[byte_col] = (canary & 0x0F) | (bits & 0xF0)
                address = _pixel_addr(row, scanline)
                assert bytes(run.m.memory[address:address + 32]) == expected, (
                    target, char, col, scanline
                )

    # Out-of-range characters and spaces erase the complete target nibble.
    for char in (0, 31, 32, 128, 255):
        col = 17
        for scanline in range(8):
            address = _pixel_addr(row, scanline)
            run.m.memory[address:address + 32] = bytes([canary]) * 32
        _set_draw_coords(run, symbols, col, row)
        run.m.a = char
        run.call("Display64.drawC")
        for scanline in range(8):
            address = _pixel_addr(row, scanline)
            expected = bytearray([canary] * 32)
            expected[col >> 1] &= 0xF0
            assert bytes(run.m.memory[address:address + 32]) == expected

    # The secondary renderer participates in the existing atomic row staging.
    run = Run(image, symbols)
    row = 6
    char = ord("A")
    col = 63
    run.m.a = row
    run.call("Display.beginRow")
    _set_draw_coords(run, symbols, col, row)
    run.m.a = char
    run.call("Display64.drawC")
    run.call("Display.endRow")
    patterns = _patterns(packed, char)
    for scanline, index in enumerate(patterns):
        address = _pixel_addr(row, scanline)
        assert run.m.memory[address + 31] == (lut[index] & 0x0F)
        assert not any(run.m.memory[address:address + 31])

    # Cursor state wraps at 64 columns and handles carriage returns.
    text = 0xC900
    run.m.memory[text:text + 5] = b"AB\rC\0"
    coords = symbols["Display64.coords"]
    run.m.memory[coords:coords + 2] = (63 | 4 << 8).to_bytes(2, "little")
    run.m.hl = text
    run.call("Display64.putStr")
    assert int.from_bytes(run.m.memory[coords:coords + 2], "little") == (1 | 6 << 8)
