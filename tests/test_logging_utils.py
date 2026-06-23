#!/usr/bin/env python3
"""Tests for centralized Python logging helpers."""

from __future__ import annotations

import logging
import sys
import tempfile
import unittest
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT_DIR / "scripts"))

from logging_utils import get_logger, log_call  # noqa: E402


class LoggingUtilsTests(unittest.TestCase):
    """Verify sink setup, handler idempotence, and call tracing."""

    def test_get_logger_writes_under_log_dir_once(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            logger = get_logger(
                "test-idempotent", "test.log", repo_root=Path(temp_dir)
            )
            same_logger = get_logger(
                "test-idempotent", "test.log", repo_root=Path(temp_dir)
            )

            self.assertIs(logger, same_logger)
            self.assertEqual(1, len(logger.handlers))
            logger.info("hello")
            for handler in logger.handlers:
                handler.flush()

            log_path = Path(temp_dir) / ".log" / "test.log"
            self.assertIn("hello", log_path.read_text(encoding="utf-8"))

    def test_log_call_records_arguments_and_return_value(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            logger = get_logger("test-trace", "trace.log", repo_root=Path(temp_dir))

            @log_call(logger, logging.INFO)
            def add(left: int, right: int = 1) -> int:
                return left + right

            self.assertEqual(5, add(2, right=3))
            for handler in logger.handlers:
                handler.flush()

            text = (Path(temp_dir) / ".log" / "trace.log").read_text(
                encoding="utf-8"
            )
            self.assertIn("ENTER test_logging_utils.py", text)
            self.assertIn("left=2", text)
            self.assertIn("right=3", text)
            self.assertIn("EXIT test_logging_utils.py", text)
            self.assertIn("-> 5", text)


if __name__ == "__main__":
    unittest.main()
