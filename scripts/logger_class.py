#!/usr/bin/env python3
"""
logger_class.py — Core Logger class and factory functions.

Components:
  - Logger class: Thread-safe logger with timestamped, structured output
  - get_logger(name): Factory function to create named loggers
  - setup_logging(level, production, json_output): Global configuration helper

Usage:
    from scripts.logger_class import Logger, get_logger, setup_logging
    
    # Direct usage
    log = Logger(__name__)
    log.info("Starting installation")
    
    # Via factory
    log = get_logger(__name__, level=LogLevel.DEBUG)
    
    # Global config (affects all subsequently-created loggers)
    setup_logging("debug", production=False)
"""

import logging
import os
import sys
import threading
from typing import Optional

from scripts.logging_core import DevFormatter, JsonFormatter, LogLevel


class Logger:
    """Centralized logger with multiple levels, timestamps, and context.

    Attributes:
        name: The logger's name (typically __name__ of the calling module).
        level: Current log level threshold.
        is_production: Whether production mode is active (JSON output).
        _lock: Thread safety lock.
    """

    def __init__(self, name: str, level: LogLevel = LogLevel.INFO) -> None:
        """Initialize a named logger.

        Args:
            name: Logger name, typically the module's __name__.
            level: Minimum log level to output.
        """
        self.name = name
        self.level = level
        self._lock = threading.Lock()
        self.is_production = os.environ.get("INSTALLER_PRODUCTION", "0") == "1"

        # Create the underlying Python logger
        self._logger = logging.getLogger(name)
        self._logger.setLevel(logging.DEBUG)  # Always capture; filter at output
        self._logger.handlers.clear()

        handler = logging.StreamHandler(sys.stderr)
        if self.is_production:
            handler.setFormatter(JsonFormatter())
        else:
            handler.setFormatter(DevFormatter())
        self._logger.addHandler(handler)

    def _should_log(self, level_num: int) -> bool:
        """Check if the given level meets the threshold.

        Args:
            level_num: Numeric log level value.

        Returns:
            True if this message should be logged.
        """
        return level_num >= self.level.value

    def verbose(self, msg: str) -> None:
        """Log a VERBOSE-level message (lowest priority).

        Args:
            msg: Message text.
        """
        with self._lock:
            if self._should_log(LogLevel.VERBOSE.value):
                self._logger.log(5, msg)

    def debug(self, msg: str) -> None:
        """Log a DEBUG-level message for detailed troubleshooting.

        Args:
            msg: Message text.
        """
        with self._lock:
            if self._should_log(LogLevel.DEBUG.value):
                self._logger.debug(msg)

    def info(self, msg: str) -> None:
        """Log an INFO-level message for general progress.

        Args:
            msg: Message text.
        """
        with self._lock:
            if self._should_log(LogLevel.INFO.value):
                self._logger.info(msg)

    def warn(self, msg: str) -> None:
        """Log a WARNING-level message for non-critical issues.

        Args:
            msg: Message text.
        """
        with self._lock:
            if self._should_log(LogLevel.WARN.value):
                self._logger.warning(msg)

    def error(self, msg: str) -> None:
        """Log an ERROR-level message for failures.

        Args:
            msg: Message text.
        """
        with self._lock:
            if self._should_log(LogLevel.ERROR.value):
                self._logger.error(msg)

    def exception(self, msg: str) -> None:
        """Log an ERROR-level message with the current exception context.

        Args:
            msg: Message text describing what went wrong.
        """
        with self._lock:
            if self._should_log(LogLevel.ERROR.value):
                self._logger.exception(msg)


# -- Factory function ---------------------------------------------------------

def get_logger(name: Optional[str] = None, level: Optional[LogLevel] = None) -> Logger:
    """Create or retrieve a named logger.

    Args:
        name: Logger name. Defaults to the calling module's __name__.
        level: Override log level. Defaults to INSTALLER_LOG_LEVEL env var or INFO.

    Returns:
        A configured Logger instance.
    """
    if level is None:
        env_level = os.environ.get("INSTALLER_LOG_LEVEL", "info").lower()
        level = LogLevel.from_string(env_level)
    return Logger(name or __name__, level)


# -- Global setup helper ------------------------------------------------------

def setup_logging(
    level: str = "info",
    production: Optional[bool] = None,
    json_output: bool = False,
) -> LogLevel:
    """Configure global logging behavior.

    This sets the INSTALLER_LOG_LEVEL and INSTALLER_PRODUCTION environment variables
    so that all subsequently-created loggers use the same settings.

    Args:
        level: Log level string (verbose, debug, info, warn, error).
        production: Force production mode. If None, uses INSTALLER_PRODUCTION env var.
        json_output: Force JSON output format. Overrides production setting.

    Returns:
        The resolved LogLevel enum value.
    """
    log_level = LogLevel.from_string(level)
    os.environ["INSTALLER_LOG_LEVEL"] = level.upper()
    if production is not None:
        os.environ["INSTALLER_PRODUCTION"] = "1" if production else "0"
    return log_level
