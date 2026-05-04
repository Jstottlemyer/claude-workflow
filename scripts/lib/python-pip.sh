#!/bin/bash
# python_pip — pick the right pip binary for this machine.
#
# Source it:  . "$(dirname "$0")/lib/python-pip.sh"
# Use it:     "$(python_pip)" install --user some-package
#             python_pip install --user some-package      # also works
#
# Resolution order:
#   1. pip3 (preferred — see global CLAUDE.md note about pip-vs-pip3 ambiguity)
#   2. pip
#   3. python3 -m pip
#   4. error → "neither pip3 nor pip found — brew install python"
#
# Honours the same has_cmd PATH-augmentation install.sh uses, so brew binaries
# at /opt/homebrew/bin or /usr/local/bin resolve even when the script is run
# from a non-login shell that didn't source ~/.zshrc.

_python_pip_has_cmd() {
    command -v "$1" >/dev/null 2>&1 \
        || [ -x "/opt/homebrew/bin/$1" ] \
        || [ -x "/usr/local/bin/$1" ]
}

python_pip() {
    if _python_pip_has_cmd pip3; then
        if [ "${1-}" = "--which" ]; then command -v pip3 || echo "/opt/homebrew/bin/pip3"; return 0; fi
        pip3 "$@"
        return $?
    fi
    if _python_pip_has_cmd pip; then
        if [ "${1-}" = "--which" ]; then command -v pip || echo "/usr/local/bin/pip"; return 0; fi
        pip "$@"
        return $?
    fi
    if _python_pip_has_cmd python3; then
        if [ "${1-}" = "--which" ]; then echo "python3 -m pip"; return 0; fi
        python3 -m pip "$@"
        return $?
    fi
    echo "python_pip: no pip3, pip, or python3 found in PATH" >&2
    echo "python_pip: install with 'brew install python' (or run install.sh which can do it for you)" >&2
    return 127
}
