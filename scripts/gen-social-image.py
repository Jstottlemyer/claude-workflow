#!/usr/bin/env python3
"""
gen-social-image.py — generate the MonsterFlow social card via Gemini.

Generates a "coding monster in a harness" illustration using Gemini's
image-gen API and saves it to docs/social-image.png.

Reads API key from ~/.claude/Gemini.apikey (same pattern CosmicExplorer
uses — keep keys out of env vars and the transcript).

Run:
    python3 scripts/gen-social-image.py                  # default prompt
    python3 scripts/gen-social-image.py --variant logo   # tight monster portrait
    python3 scripts/gen-social-image.py --prompt "..."   # custom prompt

Model: gemini-3.1-flash-image-preview (proven working in CosmicExplorer).
Pipes raw bytes through `sips` for clean PNG output (matching established
CosmicExplorer pattern).
"""

import argparse
import subprocess
import sys
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_DIR / "docs"
API_KEY_PATH = Path.home() / ".claude" / "Gemini.apikey"

# Two prompt variants. The default is a wide LinkedIn-link-preview
# composition; --variant logo gives a tight portrait suitable for an
# avatar / favicon / monogram replacement.
PROMPTS = {
    "wide": (
        "Editorial digital illustration of a friendly coding monster mascot "
        "wearing a leather pilot's harness, sitting at the center of multiple "
        "floating terminal windows. The monster has many small arms — each "
        "typing on a different glowing keyboard or pointing at a different "
        "code-filled screen. Multiple curious, expressive eyes; focused, "
        "happy-builder expression. Cables from the harness connect to each "
        "screen, suggesting orchestrated parallel work. Dark navy background "
        "(#0a0a0f) with subtle teal (#5eead4) and indigo (#7c9cff) gradient "
        "lighting. Stylized polished vector-art aesthetic — mix of vintage "
        "children's book whimsy and modern technical precision. Aspect ratio "
        "16:9, no text in the image, no logos, no UI chrome."
    ),
    "logo": (
        "A small, friendly one-eyed coding monster mascot wearing a leather "
        "climbing harness, holding a glowing terminal cursor in one of its "
        "arms. Stylized vector illustration. Dark background with indigo "
        "(#7c9cff) and teal (#5eead4) accent lighting. Centered portrait "
        "composition, square aspect ratio. No text, no UI chrome — just the "
        "creature."
    ),
}


def load_api_key() -> str:
    if not API_KEY_PATH.exists():
        print(f"✗ API key not found at {API_KEY_PATH}")
        print("  Get one: https://aistudio.google.com/apikey")
        print(f"  Save (one line, no `export`): echo 'YOUR_KEY' > {API_KEY_PATH}")
        print(f"  Then: chmod 600 {API_KEY_PATH}")
        sys.exit(1)
    return API_KEY_PATH.read_text().strip()


def _try_multimodal(client, model: str, prompt: str, out_path: Path) -> bool:
    """Multimodal generate_content path: returns inline_data with image bytes."""
    from google.genai import types
    response = client.models.generate_content(
        model=model,
        contents=prompt,
        config=types.GenerateContentConfig(response_modalities=["IMAGE", "TEXT"]),
    )
    if not response.candidates or not response.candidates[0].content.parts:
        print("  (no candidates returned)")
        return False
    for part in response.candidates[0].content.parts:
        inline = getattr(part, "inline_data", None)
        if inline and inline.mime_type and inline.mime_type.startswith("image/"):
            raw_path = out_path.with_suffix(".raw")
            raw_path.write_bytes(inline.data)
            subprocess.run(
                ["sips", "-s", "format", "png", str(raw_path), "--out", str(out_path)],
                capture_output=True,
            )
            raw_path.unlink(missing_ok=True)
            if out_path.exists():
                print(f"✓ wrote {out_path} ({out_path.stat().st_size} bytes)")
                return True
    print("  (no image part in response)")
    return False


def _try_imagen(client, model: str, prompt: str, out_path: Path) -> bool:
    """Imagen path: dedicated image-gen API."""
    from google.genai import types
    result = client.models.generate_images(
        model=model,
        prompt=prompt,
        config=types.GenerateImagesConfig(number_of_images=1, aspect_ratio="16:9"),
    )
    if result.generated_images:
        img = result.generated_images[0].image
        raw_path = out_path.with_suffix(".raw")
        raw_path.write_bytes(img.image_bytes)
        subprocess.run(
            ["sips", "-s", "format", "png", str(raw_path), "--out", str(out_path)],
            capture_output=True,
        )
        raw_path.unlink(missing_ok=True)
        if out_path.exists():
            print(f"✓ wrote {out_path} ({out_path.stat().st_size} bytes)")
            return True
    print("  (no images returned)")
    return False


def gen_with_gemini(prompt: str, out_path: Path) -> bool:
    """Try multiple Gemini/Imagen models in order until one succeeds.
    503 (overloaded) is the most common transient failure — fall through
    to the next model rather than giving up."""
    try:
        from google import genai  # noqa: F401
    except ImportError:
        print("✗ google-genai not installed. pip install google-genai")
        return False

    from google import genai
    api_key = load_api_key()
    client = genai.Client(api_key=api_key)

    # Try multimodal models first (preferred — better prompt adherence for
    # illustrative work), then Imagen as fallback.
    attempts = [
        ("gemini-3.1-flash-image-preview", _try_multimodal),    # CosmicExplorer's proven pick
        ("gemini-2.5-flash-image-preview", _try_multimodal),    # older multimodal
        ("imagen-4.0-generate-001",         _try_imagen),       # Imagen 4
        ("imagen-3.0-generate-002",         _try_imagen),       # Imagen 3
    ]

    for model, runner in attempts:
        print(f"→ {model} …")
        try:
            if runner(client, model, prompt, out_path):
                return True
        except Exception as e:
            msg = str(e)
            # Truncate noisy provider blobs but keep the actionable bit.
            if len(msg) > 240:
                msg = msg[:240] + " …"
            print(f"  failed: {msg}")
            continue

    print("\n✗ all models failed — Gemini may be having a wide outage.")
    print("  Retry: python3 scripts/gen-social-image.py")
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--variant",
        choices=list(PROMPTS.keys()),
        default="wide",
        help="prompt variant (default: wide / link-preview composition)",
    )
    ap.add_argument(
        "--prompt",
        help="override the variant prompt entirely with custom text",
    )
    ap.add_argument(
        "--out",
        default=None,
        help="output path (default: docs/social-image.png for wide, docs/monster-mascot.png for logo)",
    )
    args = ap.parse_args()

    prompt = args.prompt or PROMPTS[args.variant]
    default_name = "social-image.png" if args.variant == "wide" else "monster-mascot.png"
    out_path = Path(args.out) if args.out else (OUT_DIR / default_name)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"variant: {args.variant}")
    print(f"prompt:  {prompt[:120]}{'…' if len(prompt) > 120 else ''}")
    print(f"out:     {out_path}")
    print()

    ok = gen_with_gemini(prompt, out_path)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
