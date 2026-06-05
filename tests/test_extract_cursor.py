#!/usr/bin/env python3
"""Tests for the Windows cursor extraction helper."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image


ROOT_DIR = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT_DIR / "scripts" / "extract_cursor.py"
CURSOR_ASSET = ROOT_DIR / "configs" / "cursors" / "purple_cross.cur"


class ExtractCursorTests(unittest.TestCase):
    """Verify extraction against the repository's real cursor asset."""

    def test_extracts_expected_pixels_and_hotspot(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "purple-cross.png"
            result = subprocess.run(
                [
                    "python3",
                    str(EXTRACTOR),
                    str(CURSOR_ASSET),
                    str(output_path),
                    "32",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            image = Image.open(output_path).convert("RGBA")
            visible_pixels = [
                pixel for pixel in image.getdata() if pixel[3] != 0
            ]

            self.assertEqual((32, 32), image.size)
            self.assertEqual((0, 0, 19, 19), image.getbbox())
            self.assertEqual(105, len(visible_pixels))
            self.assertEqual({(172, 37, 253, 255)}, set(visible_pixels))
            self.assertEqual("9 9", result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
