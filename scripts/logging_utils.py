#!/usr/bin/env python3
"""
logging_utils.py — Logging utilities: decorators, exceptions, and convenience functions.

Components:
  - timed(func): Decorator for performance timing of functions
  - OperationError: Structured exception with operation context
  - GracefulFailure: Context manager for graceful degradation
  - log(level, msg): Module-level convenience function (backwards compatibility)

Usage:
    from scripts.logging_utils import timed, OperationError, GracefulFailure, log
    
    @timed
    def slow_operation():
        ...
    
    try:
        risky_operation()
    except OperationError as e:
        print(f"Operation {e.operation} failed: {e.message}")
    
    with GracefulFailure("optional-step", logger=log):
        optional_step()  # Won't crash the whole process if it fails
    
    log("info", "quick message")  # Deprecated; prefer get_logger()
"""

import functools
from datetime import datetime, timezone
from typing import Optional

from scripts.logger_class import Logger, get_logger


# -- Performance timing decorator ---------------------------------------------

def timed(func):
    """Decorator that logs the execution time of a function.

    Usage:
        @timed
        def install_packages():
            ...

    Logs:
        [INFO] <function_name> completed in X.XXs
        [WARN] <function_name> raised an exception after X.XXs
    """

    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        """Wrapper that times the decorated function execution.

        Args:
            *args: Positional arguments passed to the decorated function.
            **kwargs: Keyword arguments passed to the decorated function.

        Returns:
            The return value of the decorated function.

        Raises:
            Any exception raised by the decorated function (after logging).
        """
        log = get_logger(f"{func.__module__}.timing")
        start = datetime.now(timezone.utc)
        try:
            result = func(*args, **kwargs)
            elapsed = (datetime.now(timezone.utc) - start).total_seconds()
            log.info(f"{func.__name__} completed in {elapsed:.2f}s")
            return result
        except Exception as exc:
            elapsed = (datetime.now(timezone.utc) - start).total_seconds()
            log.warn(f"{func.__name__} raised exception after {elapsed:.2f}s: {exc}")
            raise

    return wrapper


# -- Error handling context manager -------------------------------------------

class OperationError(Exception):
    """Base error for installation operations.

    Attributes:
        operation: Name of the failed operation.
        message: Human-readable error description.
        details: Optional technical details.
    """

    def __init__(self, operation: str, message: str, details: Optional[str] = None) -> None:
        """Initialize an OperationError with context.

        Args:
            operation: Name of the failed operation (e.g., "apt-install").
            message: Human-readable error description.
            details: Optional technical details for debugging.
        """
        super().__init__(f"[{operation}] {message}")
        self.operation = operation
        self.message = message
        self.details = details


class GracefulFailure:
    """Context manager for graceful degradation of non-critical operations.

    Usage:
        with GracefulFailure("extension-install", log):
            install_extension()  # If this fails, logs warning and continues

    Args:
        operation: Name of the operation being attempted.
        logger: Logger instance to use for error messages.
        critical: If True, re-raises exceptions instead of catching them.
    """

    def __init__(self, operation: str, logger: Optional[Logger] = None, critical: bool = False) -> None:
        """Initialize a GracefulFailure context manager.

        Args:
            operation: Name of the operation being attempted (for logging).
            logger: Logger instance to use for error messages. Defaults to get_logger().
            critical: If True, re-raises exceptions instead of catching them.
        """
        self.operation = operation
        self.logger = logger or get_logger()
        self.critical = critical

    def __enter__(self):
        """Enter the context manager.

        Returns:
            The GracefulFailure instance itself.
        """
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Exit the context manager, suppressing non-critical exceptions.

        Args:
            exc_type: Exception type if an exception was raised, else None.
            exc_val: Exception value if one was raised, else None.
            exc_tb: Traceback object if one was raised, else None.

        Returns:
            True to suppress the exception (non-critical mode),
            False to re-raise it (critical mode).
        """
        if exc_type is None:
            return False
        if self.critical:
            return False  # Re-raise
        msg = f"{self.operation} failed: {exc_val}"
        self.logger.error(msg)
        return True  # Suppress the exception


# -- Module-level convenience (backwards compatibility) -----------------------

def log(level: str, msg: str) -> None:
    """Convenience function for scripts that still use the old simple log().

    This is deprecated; prefer using get_logger() instead.

    Args:
        level: Log level string.
        msg: Message text.
    """
    logger = get_logger()
    level_upper = level.upper()
    if level_upper in ("VERBOSE", "DEBUG"):
        logger.debug(msg)
    elif level_upper == "INFO":
        logger.info(msg)
    elif level_upper in ("WARN", "WARNING"):
        logger.warn(msg)
    elif level_upper == "ERROR":
        logger.error(msg)
