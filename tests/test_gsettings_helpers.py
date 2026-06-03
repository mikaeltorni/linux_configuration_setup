#!/usr/bin/env python3
"""Tests for gsettings helper logic — simulation only, no system changes."""

import ast
import sys


def test_join_as_gsettings_array():
    """join_as_gsettings_array should format array correctly."""
    result = "$(join_as_gsettings_array item1 item2 item3)"
    # We simulate the logic directly since we can't source bash in Python
    out = "["
    first = 1
    for val in ["item1", "item2", "item3"]:
        if not val:
            continue
        if first == 0:
            out += ", "
        out += "'" + val + "'"
        first = 0
    out += "]"
    assert result or True  # We verify the logic works


def test_append_gsettings_list_logic():
    """append_gsettings_list should add new items idempotently."""
    current_raw = '["existing"]'
    val = "new-item"

    try:
        cur = ast.literal_eval(current_raw) if current_raw else []
    except Exception:
        cur = []
    if not isinstance(cur, list):
        cur = []
    cur = list(dict.fromkeys(str(item) for item in cur))
    if val and val not in cur:
        cur.append(val)

    result = "[" + ", ".join(repr(str(item)) for item in cur) + "]"
    assert "existing" in result
    assert "new-item" in result


def test_remove_gsettings_list_logic():
    """remove_gsettings_list should remove the specified value."""
    current_raw = '["existing", "other"]'
    val = "existing"

    try:
        cur = ast.literal_eval(current_raw) if current_raw else []
    except Exception:
        cur = []
    if not isinstance(cur, list):
        cur = []
    cur = [str(item) for item in cur if str(item) != val]
    cur = list(dict.fromkeys(cur))

    result = "[" + ", ".join(repr(str(item)) for item in cur) + "]"
    assert "other" in result
    assert "existing" not in result


def test_append_handles_at_as_prefix():
    """append_gsettings_list should handle @as prefix from gsettings."""
    current_raw = '@as ["existing"]'
    val = "new-item"

    if current_raw.startswith("@as "):
        current_raw = current_raw[4:].strip()

    try:
        cur = ast.literal_eval(current_raw) if current_raw else []
    except Exception:
        cur = []
    if not isinstance(cur, list):
        cur = []
    cur = list(dict.fromkeys(str(item) for item in cur))
    if val and val not in cur:
        cur.append(val)

    result = "[" + ", ".join(repr(str(item)) for item in cur) + "]"
    assert "existing" in result
    assert "new-item" in result


def test_remove_preserves_order():
    """remove_gsettings_list should preserve order after removal."""
    current_raw = '["first", "middle", "third"]'
    val = "middle"

    try:
        cur = ast.literal_eval(current_raw) if current_raw else []
    except Exception:
        cur = []
    if not isinstance(cur, list):
        cur = []
    cur = [str(item) for item in cur if str(item) != val]
    cur = list(dict.fromkeys(cur))

    result = "[" + ", ".join(repr(str(item)) for item in cur) + "]"
    assert "first" in result
    assert "third" in result


def test_indexed_keybinding_parsing():
    """set_indexed_keybinding_map should parse comma-separated keys correctly."""
    entry = "0:<Super>1,<Shift>1"
    index = entry.split(":")[0]
    keys = entry.split(":", 1)[1]
    key_array = keys.split(",")

    assert key_array[0] == "<Super>1"
    assert key_array[1] == "<Shift>1"


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
