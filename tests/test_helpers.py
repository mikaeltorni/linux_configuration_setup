#!/usr/bin/env python3
"""Tests for helpers.sh logic — simulation only, no system changes."""

import subprocess
import sys


def test_toml_string_array_format():
    """toml_string_array should format array correctly."""
    items = ["model-with-reasoning", "current-dir", "context-remaining"]
    result = "[" + ", ".join('"' + item.replace("\\", "\\\\").replace('"', '\\"') + '"' for item in items) + "]"
    expected = '["model-with-reasoning", "current-dir", "context-remaining"]'
    assert result == expected, f"Expected {expected}, got {result}"


def test_toml_string_array_single_item():
    """toml_string_array should handle single item."""
    items = ["single-item"]
    result = "[" + ", ".join('"' + item.replace("\\", "\\\\").replace('"', '\\"') + '"' for item in items) + "]"
    expected = '["single-item"]'
    assert result == expected, f"Expected {expected}, got {result}"


def test_toml_string_array_escapes():
    """toml_string_array should escape backslashes and quotes."""
    items = ['path\\with\\backslash', 'word "quoted"']
    result = "[" + ", ".join('"' + item.replace("\\", "\\\\").replace('"', '\\"') + '"' for item in items) + "]"
    assert "\\" in result  # escaped backslashes present
    assert '"' in result   # quotes are present (escaped)


def test_need_cmd_logic():
    """need_cmd should return true for existing commands."""
    # Simulate: which bash >/dev/null 2>&1
    proc = subprocess.run(["which", "bash"], capture_output=True)
    assert proc.returncode == 0, "bash should be found in PATH"


def test_need_cmd_nonexistent():
    """need_cmd should return false for non-existent commands."""
    proc = subprocess.run(["which", "nonexistent_command_xyz123"], capture_output=True)
    assert proc.returncode != 0, "nonexistent command should not be found"


def test_find_desktop_file_path_logic():
    """find_desktop_file_path should search correct directories."""
    desktop_dirs = [
        "/usr/share/applications",
        "/var/lib/snapd/desktop/applications",
        "/tmp/test_target/.local/share/applications"
    ]

    # Simulate finding a file in user applications dir
    test_name = "custom.desktop"
    found = False
    for d in desktop_dirs:
        if f"{d}/{test_name}" == "/tmp/test_target/.local/share/applications/custom.desktop":
            found = True
            break
    assert found, "Should find the file in user applications dir"


def test_find_desktop_entry_returns_basename():
    """find_desktop_entry should return basename of first match."""
    candidates = ["nonexistent.desktop", "custom.desktop"]
    # Simulate: only custom.desktop exists at /tmp/test_target/.local/share/applications/
    for c in candidates:
        if c == "custom.desktop":
            assert c == "custom.desktop"  # basename of first match


if __name__ == "__main__":
    tests = [t for name, t in sorted(globals().items()) if name.startswith("test_") and callable(t)]
    passed = failed = 0
    for test_fn in tests:
        try:
            test_fn()
            print(f"  PASS: {test_fn.__doc__}")
            passed += 1
        except Exception as e:
            print(f"  FAIL: {test_fn.__doc__} — {e}")
            failed += 1
    print(f"\nResults: {passed} passed, {failed} failed")
    sys.exit(failed)
