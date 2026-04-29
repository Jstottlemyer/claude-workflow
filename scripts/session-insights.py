#!/usr/bin/env python3
"""Session insights — reads ~/.claude/usage-data session-meta + facets for the
current session and prints a compact summary for /wrap Phase 1a.

Output lines:
  Session: Xmin · N in / M out · ~$0.XX
  Commits: N · Files: N · Lines +N/-N
  Outcome: <outcome> · Helpfulness: <rating>
  Friction: <friction_detail>            (if present)
  [TRIAGE] <friction item>               (one per friction_counts entry — feeds Phase 2)

No external deps. Python 3.9+.
"""

import json
import os
import sys
from datetime import date, datetime, timezone
from pathlib import Path

# Pricing per token (in / out) — matches session-cost.py
PRICING = {
    'claude-sonnet-4-6': (3e-6, 15e-6),
    'claude-sonnet-4-5': (3e-6, 15e-6),
    'claude-opus-4-7':   (5e-6, 25e-6),
    'claude-opus-4-6':   (5e-6, 25e-6),
    'claude-haiku-4-5':  (1e-6,  5e-6),
}
DEFAULT_PRICING = (3e-6, 15e-6)  # sonnet fallback


def find_session(meta_dir: Path, cwd: str) -> tuple[dict, str] | None:
    """Find today's most-recent session-meta for this project."""
    today = date.today().isoformat()
    candidates = []
    for f in meta_dir.glob('*.json'):
        try:
            d = json.loads(f.read_text())
            proj = d.get('project_path', '')
            start = d.get('start_time', '')
            # match project by cwd containment or exact path
            if (cwd in proj or proj in cwd) and start.startswith(today):
                candidates.append((start, d, f.stem))
        except Exception:
            continue
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    _, meta, session_id = candidates[0]
    return meta, session_id


def load_facets(facets_dir: Path, session_id: str) -> dict:
    f = facets_dir / f'{session_id}.json'
    if f.exists():
        try:
            return json.loads(f.read_text())
        except Exception:
            pass
    return {}


def estimate_cost(meta: dict) -> float:
    in_tok = meta.get('input_tokens', 0)
    out_tok = meta.get('output_tokens', 0)
    in_rate, out_rate = DEFAULT_PRICING
    return in_tok * in_rate + out_tok * out_rate


def main():
    meta_dir  = Path.home() / '.claude/usage-data/session-meta'
    facets_dir = Path.home() / '.claude/usage-data/facets'
    cwd = os.getcwd()

    if not meta_dir.exists():
        sys.exit(0)

    result = find_session(meta_dir, cwd)
    if result is None:
        print('No session data found for today in this project.')
        sys.exit(0)

    meta, session_id = result
    facets = load_facets(facets_dir, session_id)
    cost = estimate_cost(meta)

    in_tok  = meta.get('input_tokens', 0)
    out_tok = meta.get('output_tokens', 0)
    dur     = meta.get('duration_minutes', '?')
    commits = meta.get('git_commits', 0)
    files   = meta.get('files_modified', 0)
    added   = meta.get('lines_added', 0)
    removed = meta.get('lines_removed', 0)

    print(f"Session: {dur}min · {in_tok:,} in / {out_tok:,} out · ~${cost:.2f}")
    print(f"Commits: {commits} · Files: {files} · Lines +{added}/-{removed}")

    if facets:
        outcome     = facets.get('outcome', 'unknown').replace('_', ' ')
        helpfulness = facets.get('claude_helpfulness', 'unknown').replace('_', ' ')
        print(f"Outcome: {outcome} · Helpfulness: {helpfulness}")

        friction_detail = facets.get('friction_detail', '').strip()
        if friction_detail:
            print(f"Friction: {friction_detail}")

        # Emit triage lines for Phase 2 to pick up
        friction_counts = facets.get('friction_counts', {})
        for ftype, count in friction_counts.items():
            label = ftype.replace('_', ' ')
            print(f"[TRIAGE] {label} (×{count}) — from facets friction signal")


if __name__ == '__main__':
    main()
