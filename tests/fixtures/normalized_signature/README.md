# normalized_signature fixture

**Purpose:** AC #2 — verify the `normalized_signature` canonicalization function (NFC → lowercase → collapse whitespace → strip → sort → join \n → sha256 hex) is deterministic against a known input.

## Files

- `input.txt` — three raw persona-output substrings, one per line (intentional surrounding whitespace in line 1; mixed case in all three).
- `expected.hex` — the precomputed SHA-256 hex digest of the canonicalized form (full 64-char hex).

## Canonicalization procedure (mandated by `commands/_prompts/findings-emit.md`)

1. NFC normalize each input line: `unicodedata.normalize('NFC', s)`
2. Lowercase: `s.lower()` (Unicode-codepoint-wise)
3. Collapse all `\s+` (including newlines, tabs) to single ASCII space: `re.sub(r'\s+', ' ', s)`
4. Strip leading/trailing whitespace: `s.strip()`
5. Sort lines lexicographically (codepoint order, post-normalization)
6. Join with `\n`
7. UTF-8 encode
8. `hashlib.sha256(...).hexdigest()`

## Doctor check

`scripts/doctor.sh` runs this fixture: feeds `input.txt` through canonicalization, asserts the digest matches `expected.hex`. Any mismatch indicates the canonicalization implementation in `findings-emit.md` has drifted.

## How to regenerate

If `input.txt` is intentionally edited, regenerate `expected.hex`:

```bash
python3 -c "
import unicodedata, hashlib, re
with open('tests/fixtures/normalized_signature/input.txt') as f:
    lines = [l for l in f.read().split('\\n') if l.strip()]
canon = sorted(re.sub(r'\\s+', ' ', unicodedata.normalize('NFC', l).lower()).strip() for l in lines)
print(hashlib.sha256('\\n'.join(canon).encode('utf-8')).hexdigest())
" > tests/fixtures/normalized_signature/expected.hex
```
