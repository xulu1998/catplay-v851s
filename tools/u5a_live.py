#!/usr/bin/env python3
"""Run shell commands on the live E20 board over the ACM port.

usage: u5a_live.py <tty> <timeout_s> <cmd> [<cmd> ...]   (output also appended to artifacts/logs/live.log)
"""
import os
import select
import sys
import termios
import time

dev, tmo, cmds = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
log = open(os.path.join(os.path.dirname(__file__), "..", "artifacts", "logs", "live.log"), "ab")
fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd)
a[0] = a[1] = a[3] = 0
a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
termios.tcsetattr(fd, termios.TCSANOW, a)
for n, cmd in enumerate(cmds):
    tag = b"__LIVE_%d__" % (n + 5000)
    os.write(fd, ("%s; echo __LIVE_$((%d+5000))__\n" % (cmd, n)).encode())
    buf, end = bytearray(), time.time() + tmo
    while time.time() < end and tag not in buf:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try:
                buf += os.read(fd, 65536)
            except OSError:
                print("DEVICE_LOST")
                sys.exit(3)
    log.write(b"\n### " + cmd.encode() + b"\n" + bytes(buf))
    sys.stdout.write(buf.decode("utf-8", "replace"))
    if tag not in buf:
        print("\n[TIMEOUT]")
