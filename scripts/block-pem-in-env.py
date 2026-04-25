#!/usr/bin/env python3
"""PreToolUse hook: block Write/Edit of PEM/private-key content into shell-sourced dotfiles.

If zsh sources a file containing "-----BEGIN RSA PRIVATE KEY-----", the key leaks
to stdout on every new shell. See ~/CLAUDE.md "Secrets handling".

Input (stdin): Claude Code tool-use JSON.
Exit 2 + stderr on block. Exit 0 on allow.
"""
import json
import os
import re
import sys

HOME = os.path.expanduser("~")

SENSITIVE_EXACT = {
    f"{HOME}/.secrets",
    f"{HOME}/.zshenv.local",
    f"{HOME}/.zshrc",
    f"{HOME}/.zprofile",
    f"{HOME}/.zshenv",
    f"{HOME}/.bashrc",
    f"{HOME}/.bash_profile",
    f"{HOME}/.profile",
    f"{HOME}/.env",
}

SENSITIVE_PREFIXES = (
    f"{HOME}/.secrets.",
    f"{HOME}/.env.",
    f"{HOME}/.zshrc.",
)

PEM_RE = re.compile(
    r"-----BEGIN (RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY-----"
)


def main() -> int:
    try:
        d = json.load(sys.stdin)
    except Exception:
        return 0  # malformed input — don't block

    if d.get("tool_name") not in ("Write", "Edit"):
        return 0

    ti = d.get("tool_input") or {}
    raw_path = ti.get("file_path") or ""
    content = ti.get("content") or ti.get("new_string") or ""

    path = os.path.expanduser(raw_path)
    is_sensitive = path in SENSITIVE_EXACT or path.startswith(SENSITIVE_PREFIXES)
    if not is_sensitive:
        return 0

    if PEM_RE.search(content):
        sys.stderr.write(
            f"blocked: refusing to write PEM/private-key content to {path}.\n\n"
            "Shell-sourced dotfiles must only contain 'export FOO=bar' lines.\n"
            "Put key material inside the app that uses it (e.g. apps/<app>/github-app-key.pem)\n"
            'or ~/.ssh/ with chmod 600. See ~/CLAUDE.md "Secrets handling".\n'
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
