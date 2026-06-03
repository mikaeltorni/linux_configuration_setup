#!/usr/bin/env python3
"""Tests for _logging_compat.py — simulation only, no system changes."""

import json
import os
import sys
import unittest
from io import StringIO
from pathlib import Path

# Add project root to path so we can import scripts._logging_compat
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


class TestLogLevel(unittest.TestCase):
    """Test LogLevel enum and from_string conversion."""

    def test_enum_values(self):
        from scripts._logging_compat import LogLevel
        self.assertEqual(LogLevel.VERBOSE.value, 0)
        self.assertEqual(LogLevel.DEBUG.value, 10)
        self.assertEqual(LogLevel.INFO.value, 20)
        self.assertEqual(LogLevel.WARN.value, 30)
        self.assertEqual(LogLevel.ERROR.value, 40)

    def test_from_string_case_insensitive(self):
        from scripts._logging_compat import LogLevel
        self.assertEqual(LogLevel.from_string("verbose"), LogLevel.VERBOSE)
        self.assertEqual(LogLevel.from_string("VERBOSE"), LogLevel.VERBOSE)
        self.assertEqual(LogLevel.from_string("debug"), LogLevel.DEBUG)
        self.assertEqual(LogLevel.from_string("info"), LogLevel.INFO)
        self.assertEqual(LogLevel.from_string("warn"), LogLevel.WARN)
        self.assertEqual(LogLevel.from_string("warning"), LogLevel.WARN)
        self.assertEqual(LogLevel.from_string("error"), LogLevel.ERROR)

    def test_from_string_unknown_defaults_to_info(self):
        from scripts._logging_compat import LogLevel
        self.assertEqual(LogLevel.from_string("unknown"), LogLevel.INFO)


class TestLogger(unittest.TestCase):
    """Test Logger class methods and output."""

    def setUp(self):
        # Capture stderr to verify log output
        self.stderr_capture = StringIO()
        sys.stderr = self.stderr_capture

    def tearDown(self):
        sys.stderr = sys.__stderr__

    def test_info_logs_message(self):
        from scripts._logging_compat import Logger, LogLevel
        logger = Logger("test.info", level=LogLevel.INFO)
        logger.info("test message")
        output = self.stderr_capture.getvalue()
        self.assertIn("INFO", output)
        self.assertIn("test message", output)

    def test_debug_filtered_at_info_level(self):
        from scripts._logging_compat import Logger, LogLevel
        logger = Logger("test.debug_filter", level=LogLevel.INFO)
        logger.debug("should not appear")
        output = self.stderr_capture.getvalue()
        self.assertNotIn("should not appear", output)

    def test_debug_visible_at_debug_level(self):
        from scripts._logging_compat import Logger, LogLevel
        self.stderr_capture.truncate(0)
        self.stderr_capture.seek(0)
        logger = Logger("test.debug_visible", level=LogLevel.DEBUG)
        logger.debug("should appear")
        output = self.stderr_capture.getvalue()
        self.assertIn("DEBUG", output)
        self.assertIn("should appear", output)

    def test_warn_logs_message(self):
        from scripts._logging_compat import Logger, LogLevel
        self.stderr_capture.truncate(0)
        self.stderr_capture.seek(0)
        logger = Logger("test.warn", level=LogLevel.WARN)
        logger.warn("warning message")
        output = self.stderr_capture.getvalue()
        self.assertIn("WARN", output)
        self.assertIn("warning message", output)

    def test_error_logs_message(self):
        from scripts._logging_compat import Logger, LogLevel
        self.stderr_capture.truncate(0)
        self.stderr_capture.seek(0)
        logger = Logger("test.error", level=LogLevel.ERROR)
        logger.error("error message")
        output = self.stderr_capture.getvalue()
        self.assertIn("ERROR", output)
        self.assertIn("error message", output)

    def test_production_json_output(self):
        from scripts._logging_compat import Logger, LogLevel
        os.environ["INSTALLER_PRODUCTION"] = "1"
        try:
            self.stderr_capture.truncate(0)
            self.stderr_capture.seek(0)
            logger = Logger("test.json", level=LogLevel.INFO)
            logger.info("json test")
            output = self.stderr_capture.getvalue().strip()
            parsed = json.loads(output)
            self.assertEqual(parsed["level"], "INFO")
            self.assertEqual(parsed["message"], "json test")
            self.assertIn("timestamp", parsed)
        finally:
            del os.environ["INSTALLER_PRODUCTION"]


class TestGetLogger(unittest.TestCase):
    """Test get_logger factory function."""

    def test_get_logger_returns_instance(self):
        from scripts._logging_compat import get_logger, LogLevel
        logger = get_logger("test.factory")
        self.assertIsNotNone(logger)
        self.assertEqual(logger.name, "test.factory")

    def test_get_logger_uses_env_level(self):
        os.environ["INSTALLER_LOG_LEVEL"] = "debug"
        try:
            from scripts._logging_compat import get_logger
            logger = get_logger("test.env_level")
            self.assertEqual(logger.level.value, 10)  # DEBUG
        finally:
            del os.environ["INSTALLER_LOG_LEVEL"]


class TestSetupLogging(unittest.TestCase):
    """Test setup_logging global configuration."""

    def test_setup_logging_sets_env(self):
        from scripts._logging_compat import setup_logging, LogLevel
        result = setup_logging("verbose")
        self.assertEqual(result, LogLevel.VERBOSE)
        self.assertEqual(os.environ.get("INSTALLER_LOG_LEVEL"), "VERBOSE")


class TestTimedDecorator(unittest.TestCase):
    """Test the @timed performance timing decorator."""

    def test_timed_completes_successfully(self):
        from scripts._logging_compat import timed
        call_count = [0]

        @timed
        def simple_func():
            call_count[0] += 1
            return 42

        result = simple_func()
        self.assertEqual(result, 42)
        self.assertEqual(call_count[0], 1)

    def test_timed_raises_exception(self):
        from scripts._logging_compat import timed

        @timed
        def failing_func():
            raise ValueError("test error")

        with self.assertRaises(ValueError):
            failing_func()


class TestOperationError(unittest.TestCase):
    """Test OperationError exception class."""

    def test_operation_error_attributes(self):
        from scripts._logging_compat import OperationError
        err = OperationError("apt-install", "package not found", "exit code 100")
        self.assertEqual(err.operation, "apt-install")
        self.assertEqual(err.message, "package not found")
        self.assertEqual(err.details, "exit code 100")
        self.assertIn("[apt-install]", str(err))

    def test_operation_error_no_details(self):
        from scripts._logging_compat import OperationError
        err = OperationError("test", "simple error")
        self.assertIsNone(err.details)


class TestGracefulFailure(unittest.TestCase):
    """Test GracefulFailure context manager."""

    def test_graceful_failure_suppresses_non_critical(self):
        from scripts._logging_compat import GracefulFailure, Logger
        log = Logger("test.gf")
        with GracefulFailure("test-op", logger=log) as ctx:
            raise ValueError("test exception")
        # If we reach here, the exception was suppressed

    def test_graceful_failure_re_raises_critical(self):
        from scripts._logging_compat import GracefulFailure, Logger
        log = Logger("test.gf2")
        with self.assertRaises(ValueError):
            with GracefulFailure("critical-op", logger=log, critical=True) as ctx:
                raise ValueError("should re-raise")

    def test_graceful_failure_no_exception(self):
        from scripts._logging_compat import GracefulFailure, Logger
        log = Logger("test.gf3")
        result = []
        with GracefulFailure("no-err-op", logger=log) as ctx:
            result.append(1)
        self.assertEqual(result, [1])


class TestLogConvenience(unittest.TestCase):
    """Test the module-level log() convenience function."""

    def setUp(self):
        self.stderr_capture = StringIO()
        sys.stderr = self.stderr_capture

    def tearDown(self):
        sys.stderr = sys.__stderr__

    def test_log_convenience_info(self):
        from scripts._logging_compat import log
        log("info", "convenience test")
        output = self.stderr_capture.getvalue()
        self.assertIn("INFO", output)
        self.assertIn("convenience test", output)


if __name__ == "__main__":
    unittest.main()
