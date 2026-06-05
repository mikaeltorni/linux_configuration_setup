#!/usr/bin/env python3
"""Extract a Windows CUR image as RGBA PNG for xcursorgen.

Usage:
    extract_cursor.py INPUT.cur OUTPUT.png [SIZE]

The command prints the output hotspot as ``X Y`` on stdout.
"""

from __future__ import annotations

import argparse
import struct
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


@dataclass(frozen=True)
class CursorEntry:
    """Metadata for one image in a Windows CUR file."""

    width: int
    height: int
    hotspot_x: int
    hotspot_y: int


def read_largest_cursor_entry(cursor_path: Path) -> CursorEntry:
    """Return metadata for the largest image in a Windows CUR file."""
    data = cursor_path.read_bytes()
    if len(data) < 6:
        raise ValueError("cursor file is too small")

    reserved, cursor_type, entry_count = struct.unpack_from("<HHH", data)
    if reserved != 0 or cursor_type != 2:
        raise ValueError("input is not a Windows CUR file")
    if entry_count < 1 or len(data) < 6 + entry_count * 16:
        raise ValueError("cursor file has no complete image entries")

    entries = []
    for index in range(entry_count):
        offset = 6 + index * 16
        width_byte, height_byte = struct.unpack_from("<BB", data, offset)
        hotspot_x, hotspot_y = struct.unpack_from("<HH", data, offset + 4)
        entries.append(
            CursorEntry(
                width=width_byte or 256,
                height=height_byte or 256,
                hotspot_x=hotspot_x,
                hotspot_y=hotspot_y,
            )
        )

    return max(entries, key=lambda entry: (entry.width * entry.height, entry.width))


def extract_cursor(cursor_path: Path, output_path: Path, size: int | None) -> tuple[int, int]:
    """Extract the largest CUR image and return its output hotspot."""
    entry = read_largest_cursor_entry(cursor_path)

    with Image.open(cursor_path) as source:
        if source.format != "CUR":
            raise ValueError("Pillow did not recognize the input as a CUR file")
        image = source.convert("RGBA")

    output_size = size or image.width
    if output_size <= 0:
        raise ValueError("output size must be positive")

    scale_x = output_size / entry.width
    scale_y = output_size / entry.height
    hotspot_x = round(entry.hotspot_x * scale_x)
    hotspot_y = round(entry.hotspot_y * scale_y)

    if image.size != (output_size, output_size):
        image = image.resize((output_size, output_size), Image.Resampling.LANCZOS)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.save(output_path, "PNG")
    return hotspot_x, hotspot_y


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Windows CUR file")
    parser.add_argument("output", type=Path, help="RGBA PNG output path")
    parser.add_argument("size", nargs="?", type=int, help="square output size")
    return parser.parse_args()


def main() -> None:
    """Run cursor extraction and print the output hotspot."""
    args = parse_args()
    hotspot_x, hotspot_y = extract_cursor(args.input, args.output, args.size)
    print(f"{hotspot_x} {hotspot_y}")


if __name__ == "__main__":
    main()
