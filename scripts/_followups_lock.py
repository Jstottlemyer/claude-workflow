#!/usr/bin/env python3
"""_followups_lock.py — fcntl.flock concurrency helper for followups.jsonl writes.

Spec: docs/specs/pipeline-gate-permissiveness/spec.md (Edge Case 14, Atomicity)
Plan: docs/specs/pipeline-gate-permissiveness/plan.md (Cross-cutting decision #3,
"Lock primitive" pinned).

Why this exists
---------------
`docs/specs/<feature>/followups.jsonl` is regenerated from active findings on
every gate Synthesis (read → mutate → atomic .tmp + rename). When two gate
processes run concurrently for the same feature, their writes race. A
file-level POSIX advisory lock (`fcntl.flock` LOCK_EX) serialises them. The
sole writer per feature is whichever Synthesis call holds the lock; concurrent
runs queue rather than collide.

Liveness invariant — KERNEL AUTO-CLEANUP
----------------------------------------
The kernel releases `flock` automatically when the holding process's last
file descriptor referring to the lock file closes — including on SIGKILL,
crash, panic, OOM, or any abnormal exit. We therefore do NOT implement a
PID-liveness probe and we do NOT manually unlink the lock file on release;
both would re-introduce stale-lock races that the kernel already handles.
The on-disk JSON metadata persists between holders for post-incident audit
and is overwritten by the next acquirer. (Plan §Cross-cutting decision #3.)

Filesystem caveat — LOCAL WORKTREE ONLY
---------------------------------------
`fcntl.flock` is reliable on local filesystems (APFS, ext4, xfs). It is
NOT reliable across NFS, SMB, or iCloud Drive (`~/Library/Mobile
Documents/...`). MonsterFlow assumes the worktree lives on a local
filesystem. If a user opens this repo from iCloud Drive, the lock will
appear to acquire on each side independently and the write is no longer
serialised. Out of scope per plan R6.

CLI surface
-----------
    python3 scripts/_followups_lock.py acquire <lock-path> [--timeout=N] [--blocking]
        Acquires the lock and HOLDS IT until the acquirer process is killed.
        With --blocking, waits indefinitely for acquire (ignores --timeout).
        Without --blocking, polls every 50ms until --timeout (default 60s)
        elapses, then exits non-zero with FollowupsLockTimeout's message on
        stderr.

    python3 scripts/_followups_lock.py with-lock <lock-path> -- <command...>
        Reserved for future use; not implemented in W1.5 (subprocess is on
        the AST ban list, so this CLI form is out of scope here). Use the
        Python API instead from another script that needs to wrap a callable.

Module API
----------
    from scripts._followups_lock import followups_lock, FollowupsLockTimeout

    with followups_lock(lock_path, timeout=60) as lock_fd:
        # critical section: read + mutate + atomic-write followups.jsonl
        ...
    # FD closed on context exit → kernel releases lock

Hard constraints (per plan + AST banlist)
-----------------------------------------
- Python 3.9+ stdlib only.
- No `subprocess`, `eval`, `exec`, `compile`, `__import__`, `socket`, or
  banned `os.*` methods. (Banlist mirrors scripts/autorun/_policy_json.py.)
- macOS bash 3.2 callers: invoke via `python3` only — no shell-side flock.
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, Optional


DEFAULT_TIMEOUT_SECONDS = 60
POLL_INTERVAL_SECONDS = 0.05


class FollowupsLockTimeout(Exception):
    """Raised when followups_lock() cannot acquire the lock within timeout."""


def _hostname() -> str:
    """Return short hostname without importing `socket` (AST-banned).

    `os.uname()` is on POSIX (Darwin + Linux) and is not on the autorun
    policy banlist (banned os.* methods are system/popen/putenv/unsetenv/
    fork*/exec*/spawn*). Falls back to env HOST/HOSTNAME if unavailable.
    """
    try:
        return os.uname()[1]
    except (AttributeError, OSError):
        return os.environ.get("HOSTNAME") or os.environ.get("HOST") or "unknown"


def _infer_feature(lock_path: Path) -> str:
    """Best-effort feature slug from a lock path like
    `docs/specs/<feature>/.followups.jsonl.lock`. Returns empty string if
    the layout doesn't match — metadata is audit-only, so a missing slug
    is non-fatal.
    """
    parts = lock_path.resolve().parts
    try:
        idx = parts.index("specs")
    except ValueError:
        return ""
    if idx + 1 < len(parts):
        return parts[idx + 1]
    return ""


def _now_iso_utc() -> str:
    # ISO-8601 UTC, second precision, trailing Z. datetime.utcnow() is
    # deprecated in 3.12+; timezone-aware is the durable form.
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_metadata(fd: int, lock_path: Path) -> None:
    """Write {pid, hostname, started_at, feature} to the locked FD.

    Truncates first so stale metadata from a previous holder is replaced
    cleanly. The kernel lock is what enforces mutual exclusion; this
    payload is purely for post-incident audit.
    """
    payload = {
        "pid": os.getpid(),
        "hostname": _hostname(),
        "started_at": _now_iso_utc(),
        "feature": _infer_feature(lock_path),
    }
    os.lseek(fd, 0, os.SEEK_SET)
    os.ftruncate(fd, 0)
    os.write(fd, (json.dumps(payload) + "\n").encode("utf-8"))
    os.fsync(fd)


def _open_lock_fd(lock_path: Path) -> int:
    """Create parent dirs (mkdir -p) and open the lock file for read+write.

    Uses O_CREAT so the file appears on first acquire. We do NOT use O_EXCL
    — multiple acquirers must be able to open the same path; the flock call
    is what serialises them.
    """
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    return os.open(str(lock_path), os.O_RDWR | os.O_CREAT, 0o644)


@contextlib.contextmanager
def followups_lock(
    lock_path,
    timeout: Optional[float] = DEFAULT_TIMEOUT_SECONDS,
    blocking: bool = False,
) -> Iterator[int]:
    """Acquire an exclusive POSIX advisory lock on `lock_path`.

    Yields the integer file descriptor while the lock is held. The FD is
    closed on context exit (success or exception), which causes the kernel
    to release the lock atomically.

    Parameters
    ----------
    lock_path : str | os.PathLike
        Path to the lock file. Tilde-expanded. Parent dirs auto-created.
    timeout : float, optional
        Seconds to wait for acquire (polling LOCK_NB every 50ms). Ignored
        when `blocking=True`. Default 60s. Set to 0 for a single-shot try.
    blocking : bool
        If True, wait indefinitely (uses LOCK_EX without LOCK_NB).

    Raises
    ------
    FollowupsLockTimeout
        Non-blocking acquire did not succeed within `timeout` seconds.

    Notes
    -----
    Polling-loop is preferred over `signal.alarm` because alarm() is
    process-global, doesn't compose with library callers that have their
    own SIGALRM handlers, and is not thread-safe.
    """
    p = Path(os.fspath(lock_path)).expanduser()
    fd = _open_lock_fd(p)
    try:
        if blocking:
            fcntl.flock(fd, fcntl.LOCK_EX)
        else:
            deadline = time.monotonic() + (timeout if timeout is not None else 0)
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except (BlockingIOError, OSError):
                    if time.monotonic() >= deadline:
                        raise FollowupsLockTimeout(
                            "could not acquire %s within %s seconds"
                            % (p, timeout)
                        )
                    time.sleep(POLL_INTERVAL_SECONDS)
        _write_metadata(fd, p)
        yield fd
    finally:
        # Closing the FD releases the kernel-held flock. We deliberately
        # do NOT unlink the lock file: that would race with concurrent
        # acquirers re-creating it, and the metadata payload is intended
        # to persist for the next acquirer's audit reference.
        try:
            os.close(fd)
        except OSError:
            pass


def _cli_acquire(args: argparse.Namespace) -> int:
    """`acquire` subcommand: hold the lock until the process is killed.

    Used by the roundtrip test fixture. Real callers use the Python API.
    """
    lock_path = Path(args.lock_path).expanduser()
    timeout = None if args.blocking else args.timeout
    try:
        with followups_lock(lock_path, timeout=timeout, blocking=args.blocking):
            sys.stdout.write("acquired %s pid=%d\n" % (lock_path, os.getpid()))
            sys.stdout.flush()
            # Hold until killed. Sleep loop (no busy-wait, no signal handler
            # shenanigans). Test fixture sends SIGTERM/SIGKILL.
            while True:
                time.sleep(3600)
    except FollowupsLockTimeout as e:
        sys.stderr.write("FollowupsLockTimeout: %s\n" % e)
        return 1
    except KeyboardInterrupt:
        return 0
    return 0


def _cli_with_lock(args: argparse.Namespace) -> int:
    """`with-lock` is intentionally not implemented in W1.5.

    Spawning a child requires `subprocess`, which is on the AST ban list
    for this module's lineage. Python callers should use the
    `followups_lock()` context manager directly.
    """
    sys.stderr.write(
        "with-lock CLI form not implemented in this helper; "
        "use the Python API: `from scripts._followups_lock import followups_lock`\n"
    )
    return 2


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="_followups_lock.py",
        description="fcntl.flock helper for serialising followups.jsonl writes.",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    acq = sub.add_parser("acquire", help="acquire and hold the lock")
    acq.add_argument("lock_path", help="path to the lock file")
    acq.add_argument(
        "--timeout",
        type=float,
        default=float(DEFAULT_TIMEOUT_SECONDS),
        help="seconds to wait for acquire (default 60); ignored with --blocking",
    )
    acq.add_argument(
        "--blocking",
        action="store_true",
        help="wait indefinitely for acquire",
    )
    acq.set_defaults(func=_cli_acquire)

    wl = sub.add_parser("with-lock", help="(reserved; not implemented)")
    wl.add_argument("lock_path")
    wl.add_argument("rest", nargs=argparse.REMAINDER)
    wl.set_defaults(func=_cli_with_lock)

    return parser


def main(argv=None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
