#!/usr/bin/env python3
"""
_logging_compat.py — Backward-compatibility shim for the logging module.

This file re-exports all symbols from the new modular logging files so that
existing imports continue to work without changes:

    from scripts._logging_compat import LogLevel, Logger, get_logger, ...

New code should prefer direct imports from the split modules:
    from scripts.logging_core import LogLevel
    from scripts.logger_class import Logger, get_logger, setup_logging
    from scripts.logging_utils import timed, OperationError, GracefulFailure, log
"""

# Core types and formatters
from scripts.logging_core import DevFormatter, JsonFormatter, LogLevel  # noqa: F401

# Logger class and factory functions
from scripts.logger_class import (  # noqa: F401
    Logger,
    get_logger,
    setup_logging,
)

# Utilities: decorators, exceptions, convenience
from scripts.logging_utils import (  # noqa: F401
    GracefulFailure,
    OperationError,
    log,
    timed,
)

__all__ = [
    "LogLevel",
    "JsonFormatter",
    "DevFormatter",
    "Logger",
    "get_logger",
    "setup_logging",
    "timed",
    "OperationError",
    "GracefulFailure",
    "log",
]
