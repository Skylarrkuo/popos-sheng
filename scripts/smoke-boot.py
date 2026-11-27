#!/usr/bin/env python3
"""Boot the built kernel and Pop user space on a generic ARM64 QEMU machine."""

import argparse
import os
from pathlib import Path
import select
import subprocess
import sys
import time


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("kernel", type=Path)
    parser.add_argument("release")
    parser.add_argument("--timeout", type=int, default=150)
    parser.add_argument("--public", action="store_true", help="Check that no tablet-specific calibration is embedded")
    args = parser.parse_args()
    command = [
        "qemu-system-aarch64", "-machine", "virt,gic-version=3", "-cpu", "max",
        "-smp", "2", "-m", "2048", "-display", "none", "-serial", "stdio",
        "-monitor", "none", "-nodefaults", "-no-reboot", "-snapshot",
        "-drive", f"file={args.image},format=raw,if=virtio", "-kernel", str(args.kernel),
        "-append", "console=ttyAMA0 root=/dev/vda ro rootwait init=/bin/sh",
    ]
    guest = (
        b". /etc/os-release; "
        b"test -x /usr/bin/start-cosmic && test -x /usr/bin/cosmic-comp && "
        b"test -f /usr/share/wayland-sessions/cosmic.desktop && "
        b"test -x /usr/bin/fcitx5 && test -x /usr/bin/sheng-screen-rotation && "
        b"test -x /usr/libexec/sheng-rotation-indicator && "
        b"test -x /usr/libexec/sheng-reboot-android && "
        b"grep -Fxq DefaultIM=pinyin /etc/skel/.config/fcitx5/profile && "
    )
    if args.public:
        guest += (
            b"test ! -e /usr/local/sbin/qbootctl-sheng && "
            b"test ! -e /etc/qbootctl-sheng/boot.sha256 && "
        )
    guest += b"printf 'POP_SHENG_BOOT_OK %s %s\\n' \"$(uname -r)\" \"$VERSION_ID\"\n"
    expected = f"POP_SHENG_BOOT_OK {args.release} 26.04".encode()
    seen = b""
    sent = False
    end = time.monotonic() + args.timeout
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        while time.monotonic() < end:
            readable, _, _ = select.select([process.stdout], [], [], 1)
            if not readable:
                if process.poll() is not None:
                    break
                continue
            data = os.read(process.stdout.fileno(), 65536)
            if not data:
                break
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
            seen = (seen + data)[-65536:]
            if expected in seen:
                return
            if not sent and b"Run /bin/sh as init process" in seen:
                process.stdin.write(guest)
                process.stdin.flush()
                sent = True
        raise SystemExit("The generic ARM64 boot did not return the expected Pop!_OS marker")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


if __name__ == "__main__":
    main()
