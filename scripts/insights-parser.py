#!/usr/bin/env python3
"""insights-parser.py — parse ~/.claude/usage-data/report.html and emit
structured triage lines for /wrap Phase 1b.

Output line types:
  [TRIAGE CLAUDE.md] <markdown text> — why: <rationale>
  [TRIAGE MEMORY]    friction: <title> — examples: <ex1>; <ex2>
  [TRIAGE SETTINGS]  <hook description> — why: <rationale>
  [TRIAGE SKILL]     <skill name>: <description> — why: <rationale>
  [SUGGEST PROMPT]   <title>: <prompt text>
  [SUGGEST SPEC]     <title>: <starter prompt>

No external deps. Python 3.9+.
"""

import os
import sys
from datetime import date, datetime, timezone
from html.parser import HTMLParser
from pathlib import Path

REPORT_PATH = Path.home() / '.claude/usage-data/report.html'
STALE_DAYS = 14


# ---------------------------------------------------------------------------
# Minimal DOM-like collector using html.parser
# ---------------------------------------------------------------------------

class Node:
    def __init__(self, tag, attrs):
        self.tag = tag
        self.attrs = dict(attrs)
        self.children = []
        self.text_parts = []

    def text(self):
        parts = list(self.text_parts)
        for c in self.children:
            parts.append(c.text())
        return ' '.join(p.strip() for p in parts if p.strip())

    def has_class(self, cls):
        return cls in self.attrs.get('class', '').split()

    def find_all(self, cls):
        results = []
        for c in self.children:
            if c.has_class(cls):
                results.append(c)
            results.extend(c.find_all(cls))
        return results

    def find(self, cls):
        r = self.find_all(cls)
        return r[0] if r else None


class TreeBuilder(HTMLParser):
    VOID = {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}

    def __init__(self):
        super().__init__()
        self.root = Node('root', [])
        self.stack = [self.root]

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in self.VOID:
            self.stack.append(node)

    def handle_endtag(self, tag):
        if len(self.stack) > 1 and self.stack[-1].tag == tag:
            self.stack.pop()

    def handle_data(self, data):
        if self.stack:
            self.stack[-1].text_parts.append(data)


def parse_html(path: Path) -> Node:
    builder = TreeBuilder()
    builder.feed(path.read_text(encoding='utf-8', errors='replace'))
    return builder.root


# ---------------------------------------------------------------------------
# Extractors
# ---------------------------------------------------------------------------

def extract_claude_md(root: Node) -> list[tuple[str, str]]:
    """Returns list of (markdown_text, why)."""
    results = []
    for inp in root.find_all('cmd-checkbox'):
        data_text = inp.attrs.get('data-text', '').strip().replace('\\n', '\n')
        if not data_text:
            continue
        # why lives in the next sibling's .cmd-why — walk parent's children
        why = ''
        parent = _find_parent(root, inp)
        if parent:
            found_inp = False
            for sib in parent.children:
                if sib is inp:
                    found_inp = True
                elif found_inp and sib.has_class('cmd-why'):
                    why = sib.text().strip()
                    break
        results.append((data_text, why))
    return results


def extract_friction(root: Node) -> list[tuple[str, list[str]]]:
    """Returns list of (title, [example1, example2])."""
    results = []
    for card in root.find_all('friction-category'):
        title_node = card.find('friction-title')
        title = title_node.text().strip() if title_node else ''
        if not title:
            continue
        examples = []
        for li in card.find_all('friction-examples'):
            for child in li.children:
                if child.tag == 'li':
                    t = child.text().strip()
                    if t:
                        examples.append(t)
        results.append((title, examples[:2]))
    return results


def extract_features(root: Node) -> tuple[list, list, list]:
    """Returns (hooks, skills, prompts) each as list of (title, code, why)."""
    hooks, skills, prompts = [], [], []
    for card in root.find_all('feature-card'):
        title_node = card.find('feature-title')
        title = title_node.text().strip() if title_node else ''
        why_node = card.find('feature-why')
        why = why_node.text().strip() if why_node else ''
        # strip "Why for you:" prefix
        why = why.replace('Why for you:', '').strip()
        codes = [n.text().strip() for n in card.find_all('example-code') if n.text().strip()]
        code = codes[0] if codes else ''
        tl = title.lower()
        if 'hook' in tl:
            hooks.append((title, code, why))
        elif 'skill' in tl:
            skills.append((title, code, why))
        elif 'agent' in tl or 'task' in tl:
            prompts.append((title, code, why))
    return hooks, skills, prompts


def extract_patterns(root: Node) -> list[tuple[str, str]]:
    """Returns list of (title, prompt_text)."""
    results = []
    for card in root.find_all('pattern-card'):
        title_node = card.find('pattern-title')
        title = title_node.text().strip() if title_node else ''
        prompt_node = card.find('copyable-prompt')
        prompt = prompt_node.text().strip() if prompt_node else ''
        if title and prompt:
            results.append((title, prompt))
    return results


def extract_horizon(root: Node) -> list[tuple[str, str]]:
    """Returns list of (title, starter_prompt)."""
    results = []
    for card in root.find_all('horizon-card'):
        title_node = card.find('horizon-title')
        title = title_node.text().strip() if title_node else ''
        # starter prompt is inside .pattern-prompt > code
        prompt = ''
        pp = card.find('pattern-prompt')
        if pp:
            for child in pp.children:
                if child.tag == 'code':
                    prompt = child.text().strip()
                    break
        if title and prompt:
            results.append((title, prompt))
    return results


def _find_parent(root: Node, target: Node) -> Node | None:
    """Find immediate parent of target node in tree."""
    for node in _all_nodes(root):
        if target in node.children:
            return node
    return None


def _all_nodes(root: Node):
    yield root
    for c in root.children:
        yield from _all_nodes(c)


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def _oneline(s: str, limit: int = 120) -> str:
    s = ' '.join(s.split())
    return s[:limit] + '…' if len(s) > limit else s


def _skill_name_from_code(code: str) -> str:
    """Extract skill name from SKILL.md path comment like '# .claude/skills/preship/SKILL.md'."""
    for line in code.splitlines():
        line = line.strip().lstrip('#').strip()
        if 'skills/' in line and 'SKILL.md' in line:
            parts = line.split('skills/')
            if len(parts) > 1:
                return parts[1].split('/')[0]
    return 'custom-skill'


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if not REPORT_PATH.exists():
        print('No insights report found — run /insights to generate one.')
        sys.exit(0)

    mtime = datetime.fromtimestamp(REPORT_PATH.stat().st_mtime, tz=timezone.utc)
    age_days = (datetime.now(tz=timezone.utc) - mtime).days
    age_str = mtime.strftime('%b %-d') + f' · {age_days}d old'

    if age_days > STALE_DAYS:
        print(f'Insights report is {age_days} days old — run /insights to refresh.')
        sys.exit(0)

    try:
        root = parse_html(REPORT_PATH)
    except Exception as e:
        print(f'insights-parser: failed to parse report — {e}', file=sys.stderr)
        sys.exit(0)

    claude_md = extract_claude_md(root)
    friction   = extract_friction(root)
    hooks, skills, feature_prompts = extract_features(root)
    patterns   = extract_patterns(root)
    horizon    = extract_horizon(root)

    # Summary line
    parts = []
    if claude_md:      parts.append(f'{len(claude_md)} CLAUDE.md')
    if friction:       parts.append(f'{len(friction)} friction')
    if hooks:          parts.append(f'{len(hooks)} hook')
    if skills:         parts.append(f'{len(skills)} skill')
    n_prompts = len(feature_prompts) + len(patterns)
    if n_prompts:      parts.append(f'{n_prompts} prompt')
    if horizon:        parts.append(f'{len(horizon)} spec')
    print(f'Insights: {age_str} · ' + ' · '.join(parts))

    # TRIAGE CLAUDE.md
    for text, why in claude_md:
        # prefer the ## heading from data-text over the placement instruction
        heading = next((l.strip() for l in text.splitlines() if l.strip().startswith('##')),
                       text.splitlines()[0].strip() if text else '(no heading)')
        why_short = _oneline(why, 100)
        print(f'[TRIAGE CLAUDE.md] {heading} — why: {why_short}')

    # TRIAGE MEMORY (friction)
    for title, examples in friction:
        ex_str = '; '.join(_oneline(e, 60) for e in examples)
        print(f'[TRIAGE MEMORY] friction: {_oneline(title, 80)} — examples: {ex_str}')

    # TRIAGE SETTINGS (hooks)
    import re as _re
    for title, code, why in hooks:
        hook_type = next((h for h in ('Stop', 'PreToolUse', 'PostToolUse') if h in code), 'hook')
        cmd_m = _re.search(r'"command":\s*"([^"]+)"', code)
        cmd_label = cmd_m.group(1)[:70] if cmd_m else _oneline(code, 70)
        print(f'[TRIAGE SETTINGS] {hook_type} hook: {cmd_label} — why: {_oneline(why, 80)}')

    # TRIAGE SKILL
    for title, code, why in skills:
        name = _skill_name_from_code(code)
        print(f'[TRIAGE SKILL] {name}: {_oneline(why, 100)}')

    # SUGGEST PROMPT (feature agents + patterns)
    for title, code, why in feature_prompts:
        print(f'[SUGGEST PROMPT] {title}: {_oneline(code, 100)}')
    for title, prompt in patterns:
        print(f'[SUGGEST PROMPT] {title}: {_oneline(prompt, 100)}')

    # SUGGEST SPEC (horizon)
    for title, prompt in horizon:
        print(f'[SUGGEST SPEC] {title}: {_oneline(prompt, 100)}')


if __name__ == '__main__':
    main()
