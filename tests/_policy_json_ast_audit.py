#!/usr/bin/env python3
"""AST audit for scripts/autorun/_policy_json.py.

Enforces the D34 ban list per docs/specs/autorun-overnight-policy/API_FREEZE.md
section (b) "AST-audited ban list". Exits 0 (clean) or 1 (any banned pattern
detected). Used by tests/test-policy-json.sh::test_policy_json_no_shell_out.

Banned imports (any form: top-level, from-import, aliased):
  subprocess, multiprocessing, socket, urllib, http, ctypes, importlib, runpy

Banned builtin calls: eval, exec, compile, __import__

Banned os.* attribute calls: system, popen, putenv, unsetenv, fork*, exec*,
spawn*

Banned os.environ.* mutators: update, setdefault, pop, clear

Banned subscript-assign: os.environ['X'] = ...
"""

import ast
import sys

PATH = sys.argv[1]

BANNED_TOP_LEVEL_MODULES = {
    "subprocess", "multiprocessing", "socket", "urllib", "http",
    "ctypes", "importlib", "runpy",
}


def _is_banned_module(name):
    if name in BANNED_TOP_LEVEL_MODULES:
        return True
    for top in BANNED_TOP_LEVEL_MODULES:
        if name == top or name.startswith(top + "."):
            return True
    return False


BANNED_BUILTIN_NAMES = {"eval", "exec", "compile", "__import__"}

BANNED_OS_METHODS = {
    "system", "popen", "putenv", "unsetenv",
    "fork", "forkpty",
    "execv", "execve", "execvp", "execvpe", "execl", "execle", "execlp", "execlpe",
    "spawnv", "spawnve", "spawnvp", "spawnvpe", "spawnl", "spawnle", "spawnlp", "spawnlpe",
}
BANNED_OS_ENVIRON_METHODS = {"update", "setdefault", "pop", "clear"}

errors = []

with open(PATH, "r", encoding="utf-8") as f:
    src = f.read()
tree = ast.parse(src)

banned_aliases = set()  # local-name → original-banned

# Pass 1: import audit
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            if _is_banned_module(alias.name):
                errors.append("banned import (line %d): %s" % (node.lineno, alias.name))
    elif isinstance(node, ast.ImportFrom):
        mod = node.module or ""
        if _is_banned_module(mod):
            errors.append(
                "banned from-import (line %d): from %s import ..." % (node.lineno, mod))
        if mod == "os":
            for alias in node.names:
                if alias.name in BANNED_OS_METHODS:
                    errors.append(
                        "banned aliased import (line %d): from os import %s" % (
                            node.lineno, alias.name))
                    banned_aliases.add(alias.asname or alias.name)

# Pass 2: call audit
for node in ast.walk(tree):
    if isinstance(node, ast.Call):
        f = node.func
        if isinstance(f, ast.Name):
            if f.id in BANNED_BUILTIN_NAMES:
                errors.append("banned builtin call (line %d): %s()" % (node.lineno, f.id))
            if f.id in banned_aliases:
                errors.append("banned aliased call (line %d): %s()" % (node.lineno, f.id))
        elif isinstance(f, ast.Attribute):
            chain = []
            cur = f
            while isinstance(cur, ast.Attribute):
                chain.append(cur.attr)
                cur = cur.value
            if isinstance(cur, ast.Name):
                root = cur.id
                full = ".".join([root] + list(reversed(chain)))
                if root == "os" and len(chain) == 1 and chain[0] in BANNED_OS_METHODS:
                    errors.append("banned os call (line %d): %s" % (node.lineno, full))
                if (root == "os" and len(chain) == 2
                        and chain[1] == "environ"
                        and chain[0] in BANNED_OS_ENVIRON_METHODS):
                    errors.append(
                        "banned os.environ mutator (line %d): %s" % (node.lineno, full))


# Pass 3: subscript-assign on os.environ
class AssignVisitor(ast.NodeVisitor):
    def visit_Assign(self, node):
        for tgt in node.targets:
            self._check_target(tgt, node.lineno)
        self.generic_visit(node)

    def visit_AugAssign(self, node):
        self._check_target(node.target, node.lineno)
        self.generic_visit(node)

    def _check_target(self, tgt, lineno):
        if isinstance(tgt, ast.Subscript):
            v = tgt.value
            if isinstance(v, ast.Attribute) and v.attr == "environ":
                if isinstance(v.value, ast.Name) and v.value.id == "os":
                    errors.append(
                        "banned os.environ subscript-assign (line %d)" % lineno)


AssignVisitor().visit(tree)

if errors:
    sys.stderr.write("AST AUDIT FAILED:\n")
    for e in errors:
        sys.stderr.write("  " + e + "\n")
    sys.exit(1)
print("AST AUDIT OK")
sys.exit(0)
