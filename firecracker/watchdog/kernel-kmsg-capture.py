#!/usr/bin/env python3
"""
Capture kernel ring-buffer messages directly from /dev/kmsg and persist them
outside journald so logs survive journald failures.
"""

import datetime as dt
import errno
import os
import selectors
import signal
import socket
import sys
import time
from typing import List

DEFAULT_LOG_FILE = "/var/log/firecracker/kernel-kmsg.log"
DEFAULT_FALLBACK_LOG_FILES = [
    "/var/tmp/firecracker-watchdog/kernel-kmsg.log",
    "/tmp/firecracker-watchdog/kernel-kmsg.log",
]
KMSG_PATH = "/dev/kmsg"


def env_int(name: str, default: int) -> int:
    value = os.environ.get(name, "").strip()
    if not value:
        return default
    try:
        return int(value)
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    value = os.environ.get(name, "").strip()
    if not value:
        return default
    try:
        return float(value)
    except ValueError:
        return default


def fallback_log_candidates() -> List[str]:
    env_value = os.environ.get("KMSG_FALLBACK_LOG_FILES", "").strip()
    if not env_value:
        return list(DEFAULT_FALLBACK_LOG_FILES)
    return [item for item in env_value.split(":") if item]


def pick_log_file() -> str:
    primary_log_file = os.environ.get("KMSG_LOG_FILE", DEFAULT_LOG_FILE).strip()
    candidates = [primary_log_file] + fallback_log_candidates()

    for path in candidates:
        if not path:
            continue
        directory = os.path.dirname(path) or "."
        try:
            os.makedirs(directory, exist_ok=True)
            with open(path, "a", encoding="utf-8"):
                pass
            return path
        except OSError:
            continue

    raise RuntimeError("no writable log destination found for kernel kmsg capture")


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def parse_record(record: str) -> str:
    # /dev/kmsg format: "<pri>,<seq>,<ts_usec>,<flags>;message"
    if ";" not in record:
        return f"raw={record}"

    meta, msg = record.split(";", 1)
    parts = meta.split(",", 3)
    if len(parts) != 4:
        return f"raw={record}"

    pri, seq, ts_usec, flags = parts
    try:
        level = int(pri) & 7
    except ValueError:
        level = -1

    return f"seq={seq} level={level} ktime_us={ts_usec} flags={flags} msg={msg}"


def rotate_if_needed(handle, path: str, rotate_bytes: int):
    if rotate_bytes <= 0:
        return handle

    try:
        size = os.path.getsize(path)
    except OSError:
        return handle

    if size < rotate_bytes:
        return handle

    handle.flush()
    os.fsync(handle.fileno())
    handle.close()

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    rotated = f"{path}.{stamp}"
    try:
        os.rename(path, rotated)
    except OSError:
        pass

    return open(path, "a", encoding="utf-8", buffering=1)


def main() -> int:
    if not os.path.exists(KMSG_PATH):
        print(f"kmsg-capture: {KMSG_PATH} not available, skipping", file=sys.stderr)
        return 0

    log_path = pick_log_file()
    rotate_bytes = env_int("KMSG_ROTATE_BYTES", 256 * 1024 * 1024)
    fsync_every = max(1, env_int("KMSG_FSYNC_EVERY_LINES", 1))
    fsync_interval = max(0.1, env_float("KMSG_FSYNC_MAX_SECONDS", 1.0))
    start_mode = os.environ.get("KMSG_START_MODE", "tail").strip().lower()

    stop_requested = False

    def handle_signal(_signum, _frame):
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    log_handle = open(log_path, "a", encoding="utf-8", buffering=1)
    try:
        log_handle.write(
            f"[{utc_now()}] kmsg-capture start host={socket.gethostname()} path={KMSG_PATH} start_mode={start_mode}\n"
        )
        log_handle.flush()
        os.fsync(log_handle.fileno())

        file_descriptor = os.open(KMSG_PATH, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
        try:
            if start_mode == "tail":
                try:
                    os.lseek(file_descriptor, 0, os.SEEK_END)
                except OSError:
                    pass

            selector = selectors.DefaultSelector()
            selector.register(file_descriptor, selectors.EVENT_READ)

            lines_since_fsync = 0
            last_fsync_time = time.monotonic()

            while not stop_requested:
                events = selector.select(timeout=1.0)
                if not events:
                    continue

                for _key, _event in events:
                    while True:
                        try:
                            data = os.read(file_descriptor, 65536)
                            if not data:
                                break
                        except BlockingIOError:
                            break
                        except OSError as exc:
                            if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                                break
                            if exc.errno == errno.EPIPE:
                                log_handle.write(f"[{utc_now()}] kmsg-capture dropped_messages=1\n")
                                lines_since_fsync += 1
                                break
                            raise

                        for raw_record in data.splitlines():
                            text_record = raw_record.decode("utf-8", errors="replace")
                            log_handle.write(f"[{utc_now()}] {parse_record(text_record)}\n")
                            lines_since_fsync += 1

                            if (
                                lines_since_fsync >= fsync_every
                                or (time.monotonic() - last_fsync_time) >= fsync_interval
                            ):
                                log_handle.flush()
                                os.fsync(log_handle.fileno())
                                lines_since_fsync = 0
                                last_fsync_time = time.monotonic()

                            rotated_handle = rotate_if_needed(log_handle, log_path, rotate_bytes)
                            if rotated_handle is not log_handle:
                                log_handle = rotated_handle

        finally:
            os.close(file_descriptor)
    finally:
        try:
            log_handle.flush()
            os.fsync(log_handle.fileno())
        except OSError:
            pass
        log_handle.close()

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover
        print(f"kmsg-capture fatal: {exc}", file=sys.stderr)
        raise
