#!/usr/bin/env python3
"""Check visible command and operator colors in a Kitty-like interactive Bash."""
import os
import pty
import re
import select
import signal
import sys
import time

home = os.path.abspath(sys.argv[1])
pid, terminal = pty.fork()
if pid == 0:
    os.environ.update(HOME=home, TERM="xterm-256color", KITTY_WINDOW_ID="123")
    os.execlp("bash", "bash", "--rcfile", os.path.join(home, ".bashrc"), "-i")
output = b""
try:
    started = time.monotonic()
    sent = False
    while time.monotonic() - started < 8:
        if select.select([terminal], [], [], 0.1)[0]:
            output += os.read(terminal, 65536)
        if not sent and time.monotonic() - started > 2:
            os.write(terminal, b"cd /tmp && sudo ls | cat")
            sent = True
        if sent and b"38;5;214" in output and b"sudo" in output:
            break
    assert re.search(rb"38;5;81m(?:\x1b\[[^m]*m)*cd", output), repr(output)
    assert re.search(rb"38;5;81msudo", output), repr(output)
    assert re.search(rb"38;5;214m&&", output), repr(output)
    assert re.search(rb"38;5;214m\|", output), repr(output)
finally:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    os.close(terminal)
print("Interactive Kitty Bash command and operator colors passed")
