#!/usr/bin/env python3
"""Type keys at an interactive shell running in a pty.

Used by test_ff_keys.sh to prove that a key really does reach the widget it is
bound to, which is the one thing `bindkey`/`bind -X` output cannot tell you.

  keydrive.py '<shell command>' SEND:<escaped text> WAIT:<seconds> ...
"""
import os, pty, select, sys, time, fcntl, termios, struct, signal

shell_cmd = sys.argv[1]
steps = sys.argv[2:]   # alternating: SEND:<text> or WAIT:<seconds>

pid, fd = pty.fork()
if pid == 0:
    os.execvp("/bin/sh", ["/bin/sh", "-c", shell_cmd])

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
out = bytearray()

def pump(seconds):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return False
            if not chunk:
                return False
            out.extend(chunk)
    return True

pump(1.0)
for step in steps:
    kind, _, val = step.partition(":")
    if kind == "SEND":
        os.write(fd, val.encode().decode("unicode_escape").encode())
    elif kind == "WAIT":
        pump(float(val))
pump(1.0)
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
os.waitpid(pid, 0)
sys.stdout.buffer.write(bytes(out))
