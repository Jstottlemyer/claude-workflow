#!/usr/bin/env python3
"""
gen-social-image.py — generate the MonsterFlow social card via Gemini.

Generates a "coding monster in a harness" illustration using Gemini's
image-gen API and saves it to docs/social-image.png.

Setup (one-time):
    1. Create a key at https://aistudio.google.com/apikey
    2. Add to ~/.zshenv.local:
         export GEMINI_API_KEY=...
    3. New shell, or `source ~/.zshenv.local`

Run:
    python3 scripts/gen-social-image.py             # default prompt
    python3 scripts/gen-social-image.py --variant logo   # tight monster portrait
    python3 scripts/gen-social-image.py --prompt "..."   # custom prompt

Models tried in order:
    1. gemini-2.5-flash-image-preview  (Gemini multimodal image-out)
    2. imagen-3.0-generate-002         (Imagen 3 — fallback)
"""

import argparse
import os
import sys
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_DIR / "docs"

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


def gen_with_gemini(prompt: str, out_path: Path) -> bool:
    """Try gemini-2.5-flash-image-preview (multimodal image-out)."""
    try:
        from google import genai
        from google.genai import types
    except ImportError:
        print("✗ google-genai not installed. pip install google-genai")
        return False

    api_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not api_key:
        print("✗ GEMINI_API_KEY (or GOOGLE_API_KEY) not set.")
        print("  Get one: https://aistudio.google.com/apikey")
        print("  Add to ~/.zshenv.local: export GEMINI_API_KEY=...")
        return False

    client = genai.Client(api_key=api_key)

    print("→ trying gemini-2.5-flash-image-preview …")
    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash-image-preview",
            contents=[prompt],
            config=types.GenerateContentConfig(response_modalities=["TEXT", "IMAGE"]),
        )
        for part in response.candidates[0].content.parts:
            if getattr(part, "inline_data", None) and part.inline_data.data:
                out_path.write_bytes(part.inline_data.data)
                print(f"✓ wrote {out_path} ({out_path.stat().st_size} bytes)")
                return True
        print("  (no image part returned)")
    except Exception as e:
        print(f"  failed: {e}")

    print("→ trying imagen-3.0-generate-002 …")
    try:
        result = client.models.generate_images(
            model="imagen-3.0-generate-002",
            prompt=prompt,
            config=types.GenerateImagesConfig(
                number_of_images=1,
                aspect_ratio="16:9",
            ),
        )
        if result.generated_images:
            img = result.generated_images[0].image
            out_path.write_bytes(img.image_bytes)
            print(f"✓ wrote {out_path} ({out_path.stat().st_size} bytes)")
            return True
        print("  (no images returned)")
    except Exception as e:
        print(f"  failed: {e}")

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
