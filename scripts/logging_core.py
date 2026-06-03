#!/usr/bin/env python3
"""
logging_core.py - Core logging types, enums, and formatters.

Components:
  - LogLevel enum: verbose, debug, info, warn, error with from_string() conversion
  - JsonFormatter: Structured JSON log output for production use
  - DevFormatter: Human-readable log format for development use

Usage:
    from scripts.logging_core import LogLevel, JsonFormatter, DevFormatter
    
    level = LogLevel.from_string("debug")
    formatter = DevFormatter()
"""

import json
import logging
from datetime import datetime, timezone
from enum import Enum


class LogLevel(Enum):
    """Supported log levels in priority order.

    Attributes:
        VERBOSE: Lowest priority (0) - for extremely detailed tracing.
        DEBUG: Debug-level messages (10).
        INFO: Informational progress messages (20).
        WARN: Warning-level non-critical issues (30).
        ERROR: Error-level failure messages (40).
    """

    VERBOSE = 0
    DEBUG = 10
    INFO = 20
    WARN = 30
    ERROR = 40

    @classmethod
    def from_string(cls, level_str: str) -> "LogLevel":
        """Convert a string to the corresponding LogLevel.

        Args:
            level_str: Case-insensitive log level name (e.g., 'debug', 'INFO').

        Returns:
            The matching LogLevel enum value. Defaults to INFO if unrecognized.
        """
        mapping = {
            "verbose": cls.VERBOSE,
            "debug": cls.DEBUG,
            "info": cls.INFO,
            "warn": cls.WARN,
            "warning": cls.WARN,
            "error": cls.ERROR,
        }
        return mapping.get(level_str.lower(), cls.INFO)


# -- Structured JSON formatter ------------------------------------------------

class JsonFormatter(logging.Formatter):
    """Format log records as structured JSON for production use.

    Output format:
        {"timestamp": "...", "level": "...", "logger": "...", "message": "..."}

    Usage:
        handler = logging.StreamHandler()
        handler.setFormatter(JsonFormatter())
    """

    def format(self, record: logging.LogRecord) -> str:
        """Format a log record as a JSON string.

        Args:
            record: The log record to format.

        Returns:
            A JSON-encoded string with timestamp, level, logger name, message,
            and optional exception info.
        """
        entry = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info and record.exc_info[0] is not None:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry)


# -- Human-readable formatter (development) -----------------------------------

class DevFormatter(logging.Formatter):
    """Human-readable log format for development use.

    Format: [YYYY-MM-DD HH:MM:SS] [LEVEL] [module:line] message

    Usage:
        handler = logging.StreamHandler()
        handler.setFormatter(DevFormatter())
    """

    def __init__(self) -> None:
        super().__init__(
            fmt="[%(asctime)s] [%(levelname)-5s] [%(name)s:%(lineno)d] %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )
