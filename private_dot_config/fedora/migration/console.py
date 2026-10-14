#!/usr/bin/env python3
"""Give the installer guard its own hidden-input VT without util-linux setsid."""
import fcntl
import os
import sys
import termios

VT_ACTIVATE = 0x5606
VT_WAITACTIVE = 0x5607


def main():
    if os.geteuid() != 0 or len(sys.argv) < 2:
        raise SystemExit("Installer console requires root and a Python script")
    pid = os.fork()
    if pid == 0:
        os.setsid()
        fd = os.open("/dev/tty9", os.O_RDWR)
        fcntl.ioctl(fd, termios.TIOCSCTTY, 0)
        for destination in (0, 1, 2):
            os.dup2(fd, destination)
        if fd > 2:
            os.close(fd)
        fcntl.ioctl(0, VT_ACTIVATE, 9)
        fcntl.ioctl(0, VT_WAITACTIVE, 9)
        os.write(1, b"\x1b[2J\x1b[HRivest Fedora installation and recovery\n\n")
        os.execv(sys.executable, [sys.executable, "-u", *sys.argv[1:]])
    _, status = os.waitpid(pid, 0)
    # Leave errors visible on the guard's VT until acknowledged; Anaconda also
    # receives the nonzero result and cannot proceed to partitioning.
    if os.waitstatus_to_exitcode(status) == 0:
        with open("/dev/tty1", "rb", buffering=0) as console:
            fcntl.ioctl(console, VT_ACTIVATE, 1)
    raise SystemExit(os.waitstatus_to_exitcode(status))


if __name__ == "__main__":
    main()
