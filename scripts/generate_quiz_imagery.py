#!/usr/bin/env python3
# =============================================================================
# scripts/generate_quiz_imagery.py — produce the §6.9 comparison frames.
# =============================================================================
# Generates every frame of the paired-image preference quiz against OpenAI's
# `gpt-image-2`, called directly with Astra's own key. No reseller — see
# `docs/16-quiz-imagery-bakeoff.md`.
#
# THE ONE IDEA THIS SCRIPT EXISTS FOR: EVERY FRAME IS THE SAME MAN.
#
# The quiz asks a man to choose between two photographs. Every difference
# between them that is NOT the axis under test is a reason he might pick one,
# and the quiz records it as a style preference — an answer that is wrong in a
# form nothing downstream can detect.
#
# The first batch was generated text-to-image, one prompt per frame, and the
# generator returned a different person each time: skin tone visibly changed
# between the two halves of three candidate pairs out of ten. That is a worse
# confound than backdrop drift, because the user may be answering the model
# rather than the clothes. It sank seven of ten pairs.
#
# So this script does not generate frames. It generates ONE canonical figure —
# a headless man in a plain grey base layer — and then dresses him, passing that
# figure to `/v1/images/edits` for every single frame. The man, his build, his
# skin tone, the backdrop, the lighting and the framing are all held by the
# reference. The prompt varies the garments and nothing else.
#
# That is not a marginal improvement over prompt wording. It changes what the
# instrument measures: with one man throughout, the person is removed as a
# variable from the whole quiz rather than merely balanced within each pair.
#
# ---------------------------------------------------------------------------
# USAGE
#
#     export OPENAI_API_KEY=...            # never committed; see supabase/README.md
#     python3 scripts/generate_quiz_imagery.py --reference     # once, if missing
#     python3 scripts/generate_quiz_imagery.py --all           # all 16 pairs
#     python3 scripts/generate_quiz_imagery.py --pair texture-1 --pair logo-2
#
# Writes full-resolution PNGs to `brand/quiz-imagery/`. It does NOT write the
# shipped tiles — `scripts/build_quiz_imagery.py` does that (normalise backdrop,
# crop the top 7%, resize to 720px). Two scripts because generation costs money
# and post-processing does not: you re-run the cheap one freely.
#
# ---------------------------------------------------------------------------
# WHAT THIS SCRIPT CANNOT CHECK, AND YOU MUST
#
#   • Hands, at FULL resolution. Generated fashion imagery's classic tell.
#   • That the pair varies ONLY on its axis. The prompts below are written to,
#     but a generator can still drag tone or volume along with a fabric change —
#     that failure defeated three attempts at a texture pair on the old vendor.
#   • That the garments read as the axis intends to a human being.
#
# Absent is honest; a confounded reading is not. Reject a pair rather than ship
# it — a quiz with fewer questions is worth more than one with a wrong answer
# baked into it.
# =============================================================================

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

MODEL = "gpt-image-2"
SIZE = "1024x1536"          # portrait; the quiz tile is 3:4
QUALITY = "medium"          # medium tested indistinguishable from high — docs/16 §3.4
OUT = Path("brand/quiz-imagery")
REFERENCE = OUT / "_reference-figure.png"

# The reference figure. Deliberately the plainest possible outfit in a single
# flat mid-grey: anything with character here would bleed into every frame
# generated from it.
REFERENCE_PROMPT = (
    "Editorial menswear outfit photograph on a seamless warm mid-grey studio backdrop, even soft "
    "directional lighting from upper left. Full body framed from the shoulders down to the shoes, "
    "no face visible, model centered and standing straight, arms relaxed at sides. Wearing a plain "
    "mid-grey crew-neck t-shirt and plain mid-grey trousers and plain white sneakers. Well-made "
    "garments in excellent condition, pressed and clean. Neutral catalog styling, no props, no text, "
    "no logos. Shot on 85mm, f8, full-length studio fashion photography."
)

# The instruction wrapped around every garment clause. The first sentence is
# the load-bearing one and the reason the whole set coheres.
EDIT_SKELETON = (
    "Keep this exact same man — identical body proportions, identical skin tone, identical framing "
    "and crop, identical seamless warm mid-grey studio backdrop and lighting. Change only the "
    "clothing. He is now wearing {garments}. Full body from the shoulders down to the shoes, no "
    "face visible, standing straight, arms relaxed at sides. Well-made garments in excellent "
    "condition, pressed and clean. Neutral catalog styling, no props{extra}."
)
NO_MARKS = ", no text, no logos"

# ---------------------------------------------------------------------------
# The pairs. Two per axis, because one comparison yields `.low` confidence
# permanently — see StylePreferenceInference's confidence table.
#
# `a` is the NEGATIVE end of the axis and `b` the POSITIVE end, matching
# StyleDimension's documented sign conventions. Those conventions are
# load-bearing: flipping one silently inverts every profile already stored.
#
# Each pair holds everything constant but its own axis. Where two axes are
# naturally entangled — a chunky fabric genuinely has more volume than a fine
# one — the prompt names the constant explicitly rather than hoping.
# ---------------------------------------------------------------------------
PAIRS: dict[str, dict] = {
    # formality: -1 relaxed / +1 tailored
    "formality-1": {
        "a": "a washed grey sweatshirt, olive cotton trousers, and off-white canvas sneakers",
        "b": "a navy single-breasted two-button blazer with natural shoulders, a white shirt, "
             "straight-leg mid-grey wool trousers, and brown leather cap-toe oxford shoes",
    },
    "formality-2": {
        "a": "a plain white crew-neck t-shirt, mid-blue jeans, and white leather sneakers",
        "b": "a charcoal wool suit with a white shirt and a navy silk tie, and black leather "
             "oxford shoes",
    },
    # colour_tolerance: -1 restrained / +1 saturated
    "colour-1": {
        "a": "a putty crew-neck knit, stone flat-front trousers, and tan suede loafers",
        "b": "a burgundy crew-neck knit, forest-green corduroy trousers, and tan suede loafers",
    },
    "colour-2": {
        "a": "a stone-grey crew-neck knit, oatmeal flat-front trousers, and tan suede loafers",
        "b": "a cobalt-blue crew-neck knit, rust-orange flat-front trousers, and tan suede loafers",
    },
    # silhouette: -1 close to the body / +1 loose and voluminous
    "silhouette-1": {
        "a": "a navy fine-gauge knit cut close through the body and sleeve, slim tapered navy "
             "trousers, and black leather boots",
        "b": "an oversized navy knit with dropped shoulders, wide-leg navy trousers breaking over "
             "the shoe, and black leather boots",
    },
    "silhouette-2": {
        "a": "a charcoal shirt cut close to the body and tucked in, slim charcoal trousers, and "
             "black leather derby shoes",
        # "long-sleeved" is explicit because the first generation returned a
        # short-sleeved shirt, which put sleeve length in the frame alongside
        # volume — two variables in a pair that is supposed to isolate one.
        "b": "a boxy oversized long-sleeved charcoal shirt worn untucked with the sleeves down to "
             "the wrist, loose charcoal trousers, and black leather derby shoes",
    },
    # texture: -1 flat and smooth / +1 pronounced surface
    "texture-1": {
        "a": "a smooth charcoal fine-gauge merino crew-neck, flat charcoal worsted wool trousers, "
             "and black leather derby shoes",
        "b": "a chunky charcoal cable-knit crew-neck with pronounced raised cables, charcoal "
             "corduroy trousers in the same tone and the same straight cut, and black leather "
             "derby shoes",
    },
    "texture-2": {
        "a": "a smooth navy fine-gauge merino crew-neck, flat navy wool trousers, and black "
             "leather derby shoes",
        "b": "a chunky navy wool cable-knit crew-neck with pronounced raised cables, navy "
             "corduroy trousers in the same tone and the same straight cut, and black leather "
             "derby shoes",
    },
    # logo_tolerance: -1 no visible branding / +1 branding welcome
    # The ONLY sanctioned deviation from "no text, no logos": one axis is about
    # logos, so its positive side must be allowed to show one.
    "logo-1": {
        "a": "a plain navy cotton crew-neck sweatshirt with no branding of any kind, mid-grey "
             "flat-front trousers, and white leather sneakers",
        # NO WORDMARKS. Asked for "a large bold lettered wordmark" this returned a
        # real brand's name across the chest — HILFIGER — which is unshippable,
        # and an earlier attempt on the other axis produced a circled G reading
        # as a luxury house's mark. The generator reaches for real brands when
        # asked for letters, so the axis is carried by an abstract graphic
        # instead. Visually distinct from logo-2's concentric rings so the two
        # pairs do not read as the same question asked twice.
        "b": "a navy cotton crew-neck sweatshirt printed across the chest with a large bold "
             "abstract emblem of three stacked white chevrons, containing no letters, no words "
             "and no recognisable real-world brand mark, mid-grey flat-front trousers, and "
             "white leather sneakers",
        "marks_on_b": True,
    },
    "logo-2": {
        "a": "a plain black quarter-zip pullover with no branding of any kind, black flat-front "
             "trousers, and black leather sneakers",
        "b": "a black quarter-zip pullover printed across the chest with a large abstract emblem "
             "of concentric white rings containing no letters and no words, black flat-front "
             "trousers, and black leather sneakers",
        "marks_on_b": True,
    },
    # trend_tolerance: -1 classic and long-lived / +1 current and trend-forward
    "trend-1": {
        "a": "a classic navy single-breasted two-button blazer with natural shoulders, "
             "straight-leg mid-grey wool trousers, and brown leather cap-toe oxford shoes",
        "b": "an unstructured navy double-breasted blazer with wide peak lapels worn open, "
             "pleated cropped mid-grey wool trousers, and chunky lug-soled brown leather loafers",
    },
    "trend-2": {
        "a": "a classic beige cotton gabardine trench coat over a white shirt and navy trousers, "
             "with brown leather derby shoes",
        "b": "a beige technical nylon trench coat with taped seams and a corded drawstring hem "
             "over a white shirt and navy trousers, with brown leather derby shoes",
    },
    # accessory_preference: -1 minimal / +1 accessories as a deliberate layer
    # The bare side is half the comparison. The old vendor put a wristwatch on a
    # man told not to wear one, on BOTH frames, which made this axis unbuildable
    # there — check the wrists before accepting either of these.
    "accessory-1": {
        "a": "a light blue oxford cotton shirt tucked into navy flat-front trousers, and brown "
             "leather loafers, with bare wrists, no belt, no watch and no accessories of any kind",
        "b": "a light blue oxford cotton shirt tucked into navy flat-front trousers, and brown "
             "leather loafers, with a brown leather belt, a steel wristwatch on the left wrist, "
             "and a patterned silk scarf knotted at the neck",
    },
    "accessory-2": {
        "a": "a charcoal crew-neck knit, mid-grey flat-front trousers, and black leather boots, "
             "with bare wrists and no belt, no watch and no accessories of any kind",
        "b": "a charcoal crew-neck knit, mid-grey flat-front trousers, and black leather boots, "
             "with a black leather belt, a leather-strap wristwatch on the left wrist, and a "
             "charcoal wool scarf draped at the neck",
    },
    # contrast_preference: -1 tonal, one narrow value band / +1 high contrast
    # Hue is held constant on both so this does not become a second colour
    # question — only the value relationship changes.
    "contrast-1": {
        "a": "a mid-grey crew-neck knit, mid-grey flat-front trousers, and mid-grey leather "
             "sneakers, every piece within one narrow value band",
        "b": "a near-white crew-neck knit, near-black flat-front trousers, and black leather "
             "sneakers",
    },
    "contrast-2": {
        "a": "a mid-blue chambray shirt, mid-blue flat-front trousers, and mid-blue suede "
             "loafers, every piece within one narrow value band",
        "b": "a pale ice-blue shirt, deep navy flat-front trousers, and deep navy suede loafers",
    },
}


def api_key() -> str:
    key = os.environ.get("OPENAI_API_KEY", "")
    if not key:
        sys.exit(
            "OPENAI_API_KEY is not set.\n"
            "This is the same credential as IMAGE_PROVIDER_API_KEY on the Supabase project "
            "(spec §25). Export it for this shell only; never commit it."
        )
    return key


def post_json(url: str, payload: dict, key: str) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    return json.load(urllib.request.urlopen(req, timeout=600))


def post_multipart(url: str, fields: dict, files: dict, key: str) -> dict:
    """Minimal multipart/form-data. Written by hand to keep this script
    stdlib-only — the repo's other scripts have no third-party dependencies and
    a generation tool should not be the one that introduces `requests`."""
    boundary = f"----astra{uuid.uuid4().hex}"
    body = bytearray()
    for name, value in fields.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += f"{value}\r\n".encode()
    for name, path in files.items():
        body += f"--{boundary}\r\n".encode()
        body += (
            f'Content-Disposition: form-data; name="{name}"; filename="{Path(path).name}"\r\n'
            f"Content-Type: image/png\r\n\r\n"
        ).encode()
        body += Path(path).read_bytes() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()

    req = urllib.request.Request(
        url,
        data=bytes(body),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    return json.load(urllib.request.urlopen(req, timeout=600))


def write_image(payload: dict, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(base64.b64decode(payload["data"][0]["b64_json"]))


def make_reference(key: str) -> None:
    print(f"Generating the canonical figure -> {REFERENCE}")
    result = post_json(
        "https://api.openai.com/v1/images/generations",
        {"model": MODEL, "prompt": REFERENCE_PROMPT, "size": SIZE, "quality": QUALITY, "n": 1},
        key,
    )
    write_image(result, REFERENCE)
    print("  done. Check his hands at full resolution before generating 30 frames from him —\n"
          "  a flaw in the reference is a flaw in every frame.")


def make_pair(stem: str, key: str) -> bool:
    spec = PAIRS[stem]
    if not REFERENCE.exists():
        sys.exit(f"{REFERENCE} is missing. Run with --reference first.")
    ok = True
    for side in ("a", "b"):
        # Only the logo axis's positive side may show a mark.
        marks = spec.get("marks_on_b") and side == "b"
        prompt = EDIT_SKELETON.format(
            garments=spec[side], extra="" if marks else NO_MARKS
        )
        destination = OUT / f"{stem}-{side}.png"
        try:
            result = post_multipart(
                "https://api.openai.com/v1/images/edits",
                {"model": MODEL, "prompt": prompt, "size": SIZE, "quality": QUALITY},
                {"image[]": str(REFERENCE)},
                key,
            )
            write_image(result, destination)
            print(f"  {destination.name}")
        except urllib.error.HTTPError as error:
            detail = error.read()[:300].decode(errors="ignore")
            print(f"  {destination.name} FAILED: HTTP {error.code} {detail}", file=sys.stderr)
            ok = False
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", action="store_true",
                        help="Generate the canonical figure every frame is dressed from.")
    parser.add_argument("--pair", action="append", dest="pairs", default=[],
                        help=f"Pair stem. Repeatable. One of: {', '.join(sorted(PAIRS))}")
    parser.add_argument("--all", action="store_true", help="Every pair.")
    args = parser.parse_args()

    key = api_key()
    if args.reference:
        make_reference(key)
    stems = sorted(PAIRS) if args.all else args.pairs
    unknown = [s for s in stems if s not in PAIRS]
    if unknown:
        sys.exit(f"Unknown pair(s): {', '.join(unknown)}")

    failed = []
    for stem in stems:
        print(f"{stem}:")
        if not make_pair(stem, key):
            failed.append(stem)

    if stems:
        print(f"\n{len(stems) - len(failed)}/{len(stems)} pairs generated into {OUT}/")
        if failed:
            print(f"FAILED: {', '.join(failed)}", file=sys.stderr)
        print("\nNow: check hands at full resolution, confirm each pair varies ONLY on its axis,\n"
              "then run scripts/build_quiz_imagery.py to produce the shipped tiles.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
