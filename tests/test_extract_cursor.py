#!/usr/bin/env python3
"""Tests for the Windows cursor extraction helper."""

import subprocess
import tempfile
import unittest
import json
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT_DIR / "scripts" / "extract_cursor.py"
CURSOR_ASSET = ROOT_DIR / "configs" / "cursors" / "purple_cross.cur"
PYTHON_BIN = "/usr/bin/python3"

if subprocess.run(
    [PYTHON_BIN, "-c", "from PIL import Image"],
    check=False,
    capture_output=True,
).returncode != 0:
    PYTHON_BIN = "python3"

subprocess.run([PYTHON_BIN, "-c", "from PIL import Image"], check=True)


class ExtractCursorTests(unittest.TestCase):
    """Verify extraction against the repository's real cursor asset."""

    def test_extracts_expected_pixels_and_hotspot(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "purple-cross.png"
            result = subprocess.run(
                [
                    PYTHON_BIN,
                    str(EXTRACTOR),
                    str(CURSOR_ASSET),
                    str(output_path),
                    "32",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            image_probe = subprocess.run(
                [
                    PYTHON_BIN,
                    "-c",
                    (
                        "import json, sys; from PIL import Image; "
                        "image = Image.open(sys.argv[1]).convert('RGBA'); "
                        "visible = [p for p in image.getdata() if p[3] != 0]; "
                        "print(json.dumps({"
                        "'size': image.size, 'bbox': image.getbbox(), "
                        "'visible_count': len(visible), "
                        "'visible_colors': sorted(set(visible))"
                        "}))"
                    ),
                    str(output_path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            image = json.loads(image_probe.stdout)

            self.assertEqual([32, 32], image["size"])
            self.assertEqual([0, 0, 19, 19], image["bbox"])
            self.assertEqual(105, image["visible_count"])
            self.assertEqual([[172, 37, 253, 255]], image["visible_colors"])
            self.assertEqual("9 9", result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
