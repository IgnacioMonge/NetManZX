"""Reject retired AY formats and execute the supported UNO +3DOS image."""

import re
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

import audit_regression as ar
from test_ui_audit import check_about, check_connection_fields, check_modal_buffers
from test_ui_followup import check_menu_priority
from test_display_followup import check_footer
from test_transport_followup import check_connection_info, check_connection_probe
from test_editor_optimization import check as check_editors
from test_audit_control_flow import check_summary
from test_audit_control_flow import check_quit
from test_audit_entry_path import check as check_entry_path
from test_audit_uart_diag import check as check_uart_diag
from test_audit_wifi_recovery import check as check_wifi_recovery


def check_removed_ay():
    for flags in (("-DAY",), ("-DAY", "-DDOT"), ("-DAY", "-DDOT", "-DTAP"), (), ("-DDOT",)):
        with TemporaryDirectory(prefix="removed-ay-", dir=ar.BUILD) as directory:
            result = subprocess.run(
                ["sjasmplus", "--nologo", "--msg=war", *flags,
                 "-isrc", "-iassets", f"--outprefix={directory}/", "src/main.asm"],
                cwd=ar.ROOT, capture_output=True, text=True,
            )
            assert not any(Path(directory).iterdir()), flags
        assert result.returncode != 0, flags
        assert "AY supports TAP only" in result.stdout + result.stderr, flags
    print("AY +3DOS/DOT: unsupported builds rejected", flush=True)


def check():
    ar.COLD_OVERLAY = None
    target = "UNO"
    stem = ar.BUILD / "audit-uno-dos"
    subprocess.run(
        ["sjasmplus", "--nologo", "--msg=war", "-DUNO",
         "-isrc", "-iassets", f"--outprefix={ar.BUILD}/",
         f"--sym={stem}.sym", "src/main.asm"],
        cwd=ar.ROOT, check=True,
    )
    s = {name: int(value, 16) for name, value in re.findall(
        r"^(\S+): EQU 0x([0-9A-Fa-f]+)$", stem.with_suffix(".sym").read_text(), re.M
    )}
    cod = (ar.BUILD / "netmanzx.cod").read_bytes()
    header, payload = cod[:128], cod[128:]
    assert header[:9] == b"PLUS3DOS\x1a"
    assert sum(header[:127]) & 255 == header[127]
    assert int.from_bytes(header[11:15], "little") == len(cod)
    assert header[15] == 3
    assert int.from_bytes(header[16:18], "little") == len(payload)
    assert int.from_bytes(header[18:20], "little") == 0x8000
    assert len(payload) == s["dos_payload_end"] - 0x8000
    assert payload[0] == 0xC3
    assert int.from_bytes(payload[1:3], "little") == s["start"]
    assert s["program_end"] <= 0xBF00
    assert s["rt_ptr"] <= s["stack_top"] - 64

    r = ar.Run(payload, s)
    r.m.set_memory_block(0x8000, payload)
    r.m.alt_hl = 0x2758
    # Model a BASIC USR caller below the program's #8000 load address.
    def enter():
        r.m.sp = 0x7FE8
        r.m.set_memory_block(r.m.sp, ar.STOP.to_bytes(2, "little"))
        r.m.pc = s["start"]

    r.hook("text", enter)
    assert s["dos_overlay_source"] == s["static_data_end"]
    assert 0x6000 == s["dos_overlay"] < s["dos_overlay_end"] <= 0x8000
    overlay = payload[s["dos_overlay_source"] - 0x8000:]
    assert len(overlay) == s["dos_overlay_end"] - s["dos_overlay"]
    r.m.set_memory_block(0x6000, b"\xa5" * len(overlay))
    r.call("text", "Display.initFontCache")
    assert int.from_bytes(r.m.memory[s["saved_sp"]:s["saved_sp"] + 2], "little") == 0x7FE8
    assert bytes(r.m.memory[0x7FE8:0x7FEA]) == ar.STOP.to_bytes(2, "little")
    assert int.from_bytes(r.m.memory[s["saved_hl_alt"]:s["saved_hl_alt"] + 2], "little") == 0x2758
    assert r.m.sp == s["stack_top"] - 2 and r.m.iy == 0x5C3A
    assert bytes(r.m.memory[0x6000:s["dos_overlay_end"]]) == overlay
    # Execute relocated code whose input includes stale bytes after NUL.
    r.m.set_memory_block(s["UI.diag_buffer"], b"no quote\0stale\0")
    r.m.hl = s["UI.diag_buffer"]
    r.call("UI.doNetworkInfo.findQuote")
    assert r.m.hl == s["UI.diag_buffer"] + 8
    # A second USR entry must not relocate the overwritten staging area.
    end = s["dos_overlay_source"] + len(overlay)
    r.m.set_memory_block(s["buffer"], b"X" * (end - s["buffer"]))
    r.call("text", "Display.initFontCache")
    assert bytes(r.m.memory[0x6000:s["dos_overlay_end"]]) == overlay
    r.m.set_memory_block(s["UI.diag_buffer"], b"no quote\0")
    r.m.hl = s["UI.diag_buffer"]
    r.call("UI.doNetworkInfo.findQuote")
    assert r.m.hl == s["UI.diag_buffer"] + 8
    assert s["Display.font_cache"] == 0xC000
    check_connection_fields(payload, s, target, overlay)
    ar.COLD_OVERLAY = overlay
    check_about(payload, s)
    check_modal_buffers(payload, s)
    check_menu_priority(payload, s, target)
    check_footer(payload, s)
    check_connection_info(payload, s, target)
    check_connection_probe(payload, s, target)
    check_editors(payload, s, target)
    check_summary(payload, s)
    check_quit(payload, s, target)
    check_entry_path(payload, s, target)
    check_uart_diag(payload, s, target)
    check_wifi_recovery(payload, s, target)
    ar.COLD_OVERLAY = None
    (ar.BUILD / "netmanzx.cod").replace(ar.BUILD / "netmanzx-uno.cod")
    print("UNO +3DOS: header, startup and memory checks passed", flush=True)
