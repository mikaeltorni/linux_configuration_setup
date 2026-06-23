#!/usr/bin/env python3
"""Centralized Python logging for linux_configuration_setup.

All Python helpers import ``get_logger`` and ``log_call`` from this module.
Logging is best-effort, writes under repository ``.log/`` by default, and never
changes the helper scripts' stdout contracts.
"""

from __future__ import annotations

import functools
import inspect
import logging
from pathlib import Path
from typing import Any, Callable, TypeVar


LOG_FORMAT = "%(asctime)s %(levelname)s [%(name)s] %(message)s"
F = TypeVar("F", bound=Callable[..., Any])


def _repo_root() -> Path:
    """Return the repository root relative to this module."""
    return Path(__file__).resolve().parents[1]


def get_logger(
    name: str, log_file: str, repo_root: Path | None = None
) -> logging.Logger:
    """Return an idempotent logger writing under repository ``.log/``.

    Args:
        name: Logger name shown in each record.
        log_file: File name inside the repository ``.log/`` directory.
        repo_root: Optional root override used by tests.

    Returns:
        A configured logger. If the sink cannot be created, the logger uses a
        null handler so logging cannot abort the caller.
    """
    logger = logging.getLogger(name)
    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    if logger.handlers:
        return logger
    try:
        log_dir = (repo_root or _repo_root()) / ".log"
        log_dir.mkdir(parents=True, exist_ok=True)
        handler: logging.Handler = logging.FileHandler(
            log_dir / log_file, encoding="utf-8"
        )
        handler.setFormatter(logging.Formatter(LOG_FORMAT))
    except OSError:
        handler = logging.NullHandler()
    logger.addHandler(handler)
    return logger


def log_call(logger: logging.Logger, level: int = logging.DEBUG) -> Callable[[F], F]:
    """Trace a function by logging every argument on entry and return on exit.

    Args:
        logger: Centralized logger obtained from ``get_logger``.
        level: Logging level used for the enter and exit records.

    Returns:
        A decorator that wraps the target callable.
    """

    def decorator(func: F) -> F:
        location = f"{Path(func.__code__.co_filename).name}:{func.__qualname__}"
        signature = inspect.signature(func)

        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            bound = signature.bind(*args, **kwargs)
            bound.apply_defaults()
            rendered = ", ".join(
                f"{name}={value!r}" for name, value in bound.arguments.items()
            )
            logger.log(level, "ENTER %s(%s)", location, rendered)
            result = func(*args, **kwargs)
            logger.log(level, "EXIT %s -> %r", location, result)
            return result

        return wrapper  # type: ignore[return-value]

    return decorator
