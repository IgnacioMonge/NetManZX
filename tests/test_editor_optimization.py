"""Assembled regression checks for the incremental text editors."""

from collections import deque

from audit_regression import Run


SCREEN = slice(0x4000, 0x5B00)
CURSOR = 127
BS = 12


def _new(image, symbols, overlay):
    run = Run(image, symbols, overlay=overlay)
    run.m.memory[0x4000:0x5800] = bytes(0x1800)
    run.m.memory[0x5800:0x5B00] = b"\xa5" * 0x300
    return run


def _screen(run):
    return bytes(run.m.memory[SCREEN])


def _put_big(run, symbols, value):
    run.m.a = value
    run.call("Display.putCBig")


def _full_reference(run, symbols, row, data, cursor, masked=False):
    run.m.memory[symbols["Display.coords"] : symbols["Display.coords"] + 2] = bytes(
        (0, row)
    )
    shown = b"*" * len(data) if masked else data
    for value in shown[:cursor]:
        _put_big(run, symbols, value)
    _put_big(run, symbols, CURSOR)
    for value in shown[cursor:]:
        _put_big(run, symbols, value)
    _put_big(run, symbols, ord(" "))
    _put_big(run, symbols, ord(" "))


def _keyboard(run, keys, cancelled=False):
    queue = deque(keys)
    run.hook(
        "Keyboard.inKeyNoWait",
        lambda: setattr(run.m, "a", queue.popleft() if queue else 0),
    )
    run.hook(
        "Keyboard.checkBreak",
        lambda: setattr(run.m, "f", 0x40 if cancelled else 0),
    )
    run.hook("Keyboard.keyClick")
    return queue


def _count_big_calls(run, symbols):
    calls = []

    def count(name):
        calls.append(name)
        run.m.step_over_breakpoint()

    for name in ("Display.putCBig", "Display.putCBigGlyph"):
        run.hook(name, lambda name=name: count(name))
    return calls


def _machine_ok(run, returned=False):
    assert run.m.iy == 0x5C3A
    assert run.m.sp == (0xFFE2 if returned else 0xFFE0)


def _set_password(run, symbols, data, cursor, visible):
    run.m.set_memory_block(symbols["UI.pass_buffer"], data + b"\0")
    run.put("UI.pass_len", len(data))
    run.put("UI.pass_cursor", cursor)
    run.put("UI.show_password", int(visible))
    run.put("UI.pass_no_warn", 0)
    run.put("UI.pass_line", 7)


def _password_reference(run, symbols, data, cursor, visible):
    _set_password(run, symbols, data, cursor, visible)
    run.call("UI.passwordInput.piRedraw", "UI.passwordInput.piWait")


def _password_checks(image, symbols, overlay):
    data = bytes((ord("a") + i % 26 for i in range(40)))
    for visible in (False, True):
        for entry, cursor, result in (
            ("UI.passwordInput.piLeft", 20, 19),
            ("UI.passwordInput.piRight", 20, 21),
            ("UI.passwordInput.piLeft", 40, 39),
            ("UI.passwordInput.piRight", 39, 40),
        ):
            actual = _new(image, symbols, overlay)
            expected = _new(image, symbols, overlay)
            _password_reference(actual, symbols, data, cursor, visible)
            _password_reference(expected, symbols, data, cursor, visible)
            _keyboard(actual, (0,))
            calls = _count_big_calls(actual, symbols)
            actual.call(entry, "UI.passwordInput.piWait")
            _password_reference(expected, symbols, data, result, visible)
            assert actual.get("UI.pass_cursor") == result
            assert _screen(actual) == _screen(expected), (visible, entry, cursor)
            assert len(calls) == 2, (entry, calls)
            _machine_ok(actual)

    # Moving beyond either boundary changes neither state nor display.
    for entry, cursor in (
        ("UI.passwordInput.piLeft", 0),
        ("UI.passwordInput.piRight", len(data)),
    ):
        run = _new(image, symbols, overlay)
        _password_reference(run, symbols, data, cursor, False)
        before = _screen(run)
        calls = _count_big_calls(run, symbols)
        run.call(entry, "UI.passwordInput.piWait")
        assert run.get("UI.pass_cursor") == cursor and _screen(run) == before
        assert not calls

    # Middle insertion/deletion and mask toggle retain the full-redraw result.
    cases = (
        ("UI.passwordInput.piInsMid", b"abcde", 2, ord("X"), b"abXcde", 3),
        ("UI.passwordInput.piDel", b"abcde", 3, 0, b"abde", 2),
    )
    for entry, before, cursor, char, after, result_cursor in cases:
        actual = _new(image, symbols, overlay)
        expected = _new(image, symbols, overlay)
        _password_reference(actual, symbols, before, cursor, True)
        _password_reference(expected, symbols, before, cursor, True)
        actual.m.c = char
        actual.call(entry, "UI.passwordInput.piWait")
        _password_reference(expected, symbols, after, result_cursor, True)
        assert bytes(
            actual.m.memory[
                symbols["UI.pass_buffer"] : symbols["UI.pass_buffer"] + len(after) + 1
            ]
        ) == after + b"\0"
        assert _screen(actual) == _screen(expected)
        _machine_ok(actual)

    actual = _new(image, symbols, overlay)
    expected = _new(image, symbols, overlay)
    _password_reference(actual, symbols, b"secret", 3, False)
    _password_reference(expected, symbols, b"secret", 3, False)
    actual.call("UI.passwordInput.piToggle", "UI.passwordInput.piWait")
    _password_reference(expected, symbols, b"secret", 3, True)
    assert actual.get("UI.show_password") == 1
    assert _screen(actual) == _screen(expected)

    # Both password limits reject one extra byte before touching the buffer.
    for limit in (40, 20):
        run = _new(image, symbols, overlay)
        full = b"x" * limit
        _password_reference(run, symbols, full, limit, False)
        run.m.memory[symbols["UI.passwordInput.max"]] = limit
        _keyboard(run, (ord("Z"),))
        run.call("UI.passwordInput.piWait", "UI.passwordInput.piMaxLen")
        assert run.get("UI.pass_len") == limit
        assert bytes(run.m.memory[symbols["UI.pass_buffer"] : symbols["UI.pass_buffer"] + limit + 1]) == full + b"\0"
        _machine_ok(run)

    # BREAK returns carry without disturbing the ROM-owned IY or stack.
    run = _new(image, symbols, overlay)
    _set_password(run, symbols, b"", 0, False)
    _keyboard(run, (0,), cancelled=True)
    run.call("UI.passwordInput")
    assert run.m.f & 1
    _machine_ok(run, returned=True)


def _set_ssid(run, symbols, data, cursor):
    run.m.set_memory_block(symbols["UI.manual_ssid_buffer"], data + b"\0")
    run.put("UI.manual_ssid_len", len(data))
    run.put("UI.manual_ssid_cursor", cursor)


def _ssid_checks(image, symbols, overlay):
    def prepared(data, cursor):
        actual = _new(image, symbols, overlay)
        expected = _new(image, symbols, overlay)
        for run in (actual, expected):
            _set_ssid(run, symbols, data, cursor)
            _full_reference(run, symbols, 8, data, cursor)
        return actual, expected

    for entry, cursor, result in (
        ("UI.manualSSID.ssidCursorLeft", 3, 2),
        ("UI.manualSSID.ssidCursorRight", 2, 3),
    ):
        actual, expected = prepared(b"abcdef", cursor)
        calls = _count_big_calls(actual, symbols)
        actual.call(entry, "UI.manualSSID.waitSSIDKey")
        _set_ssid(expected, symbols, b"abcdef", result)
        _full_reference(expected, symbols, 8, b"abcdef", result)
        assert _screen(actual) == _screen(expected)
        assert len(calls) == 2
        _machine_ok(actual)

    # Append and middle insert use the end and changed-suffix paths.
    for before, cursor, after in (
        (b"abc", 3, b"abcX"),
        (b"abcde", 2, b"abXcde"),
    ):
        actual, expected = prepared(before, cursor)
        calls = _count_big_calls(actual, symbols)
        actual.m.c = ord("X")
        if cursor == len(before):
            actual.call("UI.manualSSID.ssidDoInsert", "UI.manualSSID.waitSSIDKey")
        else:
            actual.m.b = len(before)
            actual.m.e = cursor
            actual.m.hl = symbols["UI.manual_ssid_buffer"] + len(before)
            actual.call("UI.manualSSID.ssidShiftRight", "UI.manualSSID.waitSSIDKey")
        result_cursor = cursor + 1
        _set_ssid(expected, symbols, after, result_cursor)
        _full_reference(expected, symbols, 8, after, result_cursor)
        assert _screen(actual) == _screen(expected)
        assert len(calls) == (2 if cursor == len(before) else len(after) - result_cursor + 4)
        _machine_ok(actual)

    # Backspace at end repaints two cells; middle backspace repaints its suffix.
    for before, cursor, after in (
        (b"abcde", 5, b"abcd"),
        (b"abcde", 3, b"abde"),
    ):
        actual, expected = prepared(before, cursor)
        calls = _count_big_calls(actual, symbols)
        actual.call("UI.manualSSID.removeSSIDChar", "UI.manualSSID.waitSSIDKey")
        result_cursor = cursor - 1
        _set_ssid(expected, symbols, after, result_cursor)
        _full_reference(expected, symbols, 8, after, result_cursor)
        assert _screen(actual) == _screen(expected)
        assert len(calls) == (2 if cursor == len(before) else len(after) - result_cursor + 3)
        _machine_ok(actual)

    run, _ = prepared(b"x" * 32, 32)
    _keyboard(run, (ord("Z"),))
    run.call("UI.manualSSID.waitSSIDKey", "UI.manualSSID.ssidMaxLen")
    assert run.get("UI.manual_ssid_len") == 32
    assert bytes(run.m.memory[symbols["UI.manual_ssid_buffer"] : symbols["UI.manual_ssid_buffer"] + 33]) == b"x" * 32 + b"\0"

    run, _ = prepared(b"abc", 1)
    _keyboard(run, (), cancelled=True)
    run.call("UI.manualSSID.waitSSIDKey", "UI.renderListAndLoop")
    _machine_ok(run)


def _ip_case(image, symbols, overlay, keys, mode, maximum, expected, initial=b""):
    actual = _new(image, symbols, overlay)
    reference = _new(image, symbols, overlay)
    address = symbols["UI.sip_buf"]
    actual.m.set_memory_block(address, initial + b"\0")
    actual.put("UI.sti_len", len(initial))
    actual.put("UI.sti_line", 8)
    actual.put("UI.sti_mode", mode)
    queue = _keyboard(actual, keys)
    calls = _count_big_calls(actual, symbols)
    actual.m.hl, actual.m.b = address, maximum
    actual.call("UI.ipTextInput")
    assert not queue and not actual.m.f & 1
    assert bytes(actual.m.memory[address : address + len(expected) + 1]) == expected + b"\0"
    _full_reference(reference, symbols, 8, expected, len(expected))
    assert _screen(actual) == _screen(reference), (keys, mode, maximum)
    assert actual.m.iff1
    _machine_ok(actual, returned=True)
    return len(calls)


def _ip_checks(image, symbols, overlay):
    # IP mode accepts digits/dots; signed modes accept digits/signs and reject dots.
    assert _ip_case(image, symbols, overlay, b"1.2x3\r", 0, 15, b"1.23") == 11
    assert _ip_case(image, symbols, overlay, b"-2.\r", 2, 3, b"-2") == 7
    assert _ip_case(image, symbols, overlay, b"+3\r", 1, 3, b"+3") == 7
    assert _ip_case(image, symbols, overlay, bytes((ord("1"), ord("2"), BS, ord("3"), 13)), 0, 15, b"13") == 11
    assert _ip_case(image, symbols, overlay, b"1234\r", 0, 3, b"123") == 9
    assert _ip_case(image, symbols, overlay, b"\r", 0, 15, b"123", initial=b"123") == 6

    run = _new(image, symbols, overlay)
    address = symbols["UI.sip_buf"]
    run.m.memory[address] = 0
    run.put("UI.sti_len", 0)
    run.put("UI.sti_line", 8)
    run.put("UI.sti_mode", 0)
    _keyboard(run, (), cancelled=True)
    run.m.hl, run.m.b = address, 15
    run.call("UI.ipTextInput")
    assert run.m.f & 1 and run.m.iff1
    _machine_ok(run, returned=True)


def check(image, symbols, target, overlay=None):
    del target
    _password_checks(image, symbols, overlay)
    _ssid_checks(image, symbols, overlay)
    _ip_checks(image, symbols, overlay)
