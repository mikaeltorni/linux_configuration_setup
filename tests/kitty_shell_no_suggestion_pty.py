#!/usr/bin/env python3
"""Check that typing cd does not show a previous command suggestion."""
import os
import pty
import select
import signal
import sys
import time

home = os.path.abspath(sys.argv[1])
with open(os.path.join(home, '.kitty-highlighting-test-history'), 'w', encoding='utf-8') as history:
    history.write('cd /tmp/history-suggestion-regression-marker\n')
os.mkdir(os.path.join(home, 'tab-completion-check'))
pid, terminal = pty.fork()
if pid == 0:
    os.environ.update(HOME=home, HISTFILE=os.path.join(home, '.kitty-highlighting-test-history'), TERM='xterm-256color', KITTY_WINDOW_ID='123')
    os.execlp('bash', 'bash', '--rcfile', os.path.join(home, '.bashrc'), '-i')
output = b''
try:
    start = time.monotonic()
    sent = False
    while time.monotonic() - start < 5:
        if select.select([terminal], [], [], 0.1)[0]:
            output += os.read(terminal, 65536)
        if not sent and time.monotonic() - start > 2:
            os.write(terminal, b'cd')
            sent = True
    assert b'history-suggestion-regression-marker' not in output, 'An old command appeared as an inline suggestion'
    assert b'38;5;81' in output and b'cd' in output, 'The command color was not displayed'
    os.write(terminal, b'\x15cd ' + os.fsencode(home) + b'/tab-comple\t')
    tab_output = b''
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if select.select([terminal], [], [], 0.1)[0]:
            tab_output += os.read(terminal, 65536)
    assert b'tion-check' in tab_output, 'Tab completion did not complete the directory'
finally:
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    os.close(terminal)
print('No inline history suggestion; command color remains active')
