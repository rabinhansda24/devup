#!/usr/bin/env python3
"""Type keys at an interactive shell running in a pty.

Used by test_ff_keys.sh to prove that a key really does reach the widget it is
bound to, which is the one thing `bindkey`/`bind -X` output cannot tell you.

  keydrive.py '<shell command>' EXPECT:<text> SEND:<escaped text> WAIT:<seconds> ...

EXPECT waits for text to appear rather than guessing how long a shell takes to
become ready, and exits 1 if it never does. Everything the terminal produced is
written to stdout either way, so a failure can be read rather than guessed at.
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

def expect(text, timeout=20.0):
    """Pump until text shows up in the output, or give up."""
    end = time.time() + timeout
    needle = text.encode()
    while time.time() < end:
        if needle in bytes(out):
            return True
        if not pump(0.1):
            break
    return needle in bytes(out)


status = 0
pump(0.5)
for step in steps:
    kind, _, val = step.partition(":")
    if kind == "SEND":
        os.write(fd, val.encode().decode("unicode_escape").encode())
    elif kind == "WAIT":
        pump(float(val))
    elif kind == "EXPECT":
        if not expect(val):
            sys.stderr.write("keydrive: timed out waiting for %r\n" % val)
            status = 1
            break
pump(0.3)
try:
    os.kill(pid, signal.SIGKILL)
except ProcessLookupError:
    pass
os.waitpid(pid, 0)
sys.stdout.buffer.write(bytes(out))
sys.exit(status)
