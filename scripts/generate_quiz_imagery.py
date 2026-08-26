#!/usr/bin/env python3
# =============================================================================
# scripts/generate_quiz_imagery.py — produce the §6.9 comparison frames.
# =============================================================================
# Generates every frame of the paired-image preference quiz against OpenAI's
# `gpt-image-2`, called directly with Astra's own key. No reseller — see
# `docs/16-quiz-imagery-bakeoff.md`.
#
# THE ONE IDEA THIS SCRIPT EXISTS FOR: EVERY FRAME IS THE SAME FIGURE.
#
# The quiz asks someone to choose between two photographs. Every difference
# between them that is NOT the axis under test is a reason they might pick one,
# and the quiz records it as a style preference — an answer that is wrong in a
# form nothing downstream can detect.
#
# So this script does not generate frames. It generates ONE canonical figure —
# a headless person in a plain grey base layer — and then dresses them, passing
# that figure to `/v1/images/edits` for every single frame. The person, their
# build, their skin tone, the backdrop, the lighting and the framing are all
# held by the reference. The prompt varies the garments and nothing else.
#
# ---------------------------------------------------------------------------
# USAGE
#
#     export OPENAI_API_KEY=...            # never committed; see supabase/README.md
#     # Men's graph (default):
#     python3 scripts/generate_quiz_imagery.py --reference
#     python3 scripts/generate_quiz_imagery.py --all
#     # Women's graph (ADR 0019):
#     python3 scripts/generate_quiz_imagery.py --graph womenswear --reference
#     python3 scripts/generate_quiz_imagery.py --graph womenswear --all
#
# Writes full-resolution PNGs to `brand/quiz-imagery/` (menswear) or
# `brand/quiz-imagery/womenswear/` (womenswear). It does NOT write the shipped
# tiles — `scripts/build_quiz_imagery.py` does that.
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

# ---------------------------------------------------------------------------
# Men's pairs (default graph). `a` is the NEGATIVE end and `b` the POSITIVE
# end of each StyleDimension axis.
# ---------------------------------------------------------------------------
MENSWEAR_PAIRS: dict[str, dict] = {
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
    "colour-1": {
        "a": "a putty crew-neck knit, stone flat-front trousers, and tan suede loafers",
        "b": "a burgundy crew-neck knit, forest-green corduroy trousers, and tan suede loafers",
    },
    "colour-2": {
        "a": "a stone-grey crew-neck knit, oatmeal flat-front trousers, and tan suede loafers",
        "b": "a cobalt-blue crew-neck knit, rust-orange flat-front trousers, and tan suede loafers",
    },
    "silhouette-1": {
        "a": "a navy fine-gauge knit cut close through the body and sleeve, slim tapered navy "
             "trousers, and black leather boots",
        "b": "an oversized navy knit with dropped shoulders, wide-leg navy trousers breaking over "
             "the shoe, and black leather boots",
    },
    "silhouette-2": {
        "a": "a charcoal shirt cut close to the body and tucked in, slim charcoal trousers, and "
             "black leather derby shoes",
        "b": "a boxy oversized long-sleeved charcoal shirt worn untucked with the sleeves down to "
             "the wrist, loose charcoal trousers, and black leather derby shoes",
    },
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
    "logo-1": {
        "a": "a plain navy cotton crew-neck sweatshirt with no branding of any kind, mid-grey "
             "flat-front trousers, and white leather sneakers",
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

# Women's pairs — stem keys match shipped tile names (`w-formality-1`, …) after
# build_quiz_imagery. Garments are women's cuts; axes match StyleDimension signs.
WOMENSWEAR_PAIRS: dict[str, dict] = {
    "w-formality-1": {
        "a": "a washed grey sweatshirt, olive cotton trousers, and off-white canvas sneakers",
        "b": "a navy single-breasted blazer with natural shoulders over a white blouse, "
             "straight-leg mid-grey wool trousers, and brown leather ballet flats",
    },
    "w-formality-2": {
        "a": "a plain white crew-neck t-shirt, mid-blue jeans, and white leather sneakers",
        "b": "a charcoal wool sheath dress with a slim belt, and black leather pumps",
    },
    "w-colour-1": {
        "a": "a putty crew-neck knit, stone flat-front trousers, and tan suede loafers",
        "b": "a burgundy crew-neck knit, forest-green corduroy trousers, and tan suede loafers",
    },
    "w-colour-2": {
        "a": "a stone-grey crew-neck knit, oatmeal flat-front trousers, and tan suede loafers",
        "b": "a cobalt-blue crew-neck knit, rust-orange flat-front trousers, and tan suede loafers",
    },
    "w-silhouette-1": {
        "a": "a navy fine-gauge knit cut close through the body and sleeve, a slim pencil skirt "
             "in navy, and black leather ankle boots",
        "b": "an oversized navy knit with dropped shoulders, a wide A-line navy skirt breaking "
             "over the shoe, and black leather ankle boots",
    },
    "w-silhouette-2": {
        "a": "a charcoal blouse cut close to the body and tucked in, slim charcoal trousers, and "
             "black leather loafers",
        "b": "a boxy oversized long-sleeved charcoal blouse worn untucked with the sleeves down "
             "to the wrist, loose charcoal trousers, and black leather loafers",
    },
    "w-texture-1": {
        "a": "a smooth charcoal fine-gauge merino crew-neck, a flat charcoal worsted wool skirt, "
             "and black leather loafers",
        "b": "a chunky charcoal cable-knit crew-neck with pronounced raised cables, a charcoal "
             "corduroy skirt in the same tone and the same straight cut, and black leather loafers",
    },
    "w-texture-2": {
        "a": "a smooth navy fine-gauge merino crew-neck, a flat navy wool skirt, and black "
             "leather loafers",
        "b": "a chunky navy wool cable-knit crew-neck with pronounced raised cables, a navy "
             "corduroy skirt in the same tone and the same straight cut, and black leather loafers",
    },
    "w-logo-1": {
        "a": "a plain navy cotton crew-neck sweatshirt with no branding of any kind, mid-grey "
             "flat-front trousers, and white leather sneakers",
        "b": "a navy cotton crew-neck sweatshirt printed across the chest with a large bold "
             "abstract emblem of three stacked white chevrons, containing no letters, no words "
             "and no recognisable real-world brand mark, mid-grey flat-front trousers, and "
             "white leather sneakers",
        "marks_on_b": True,
    },
    "w-logo-2": {
        "a": "a plain black quarter-zip pullover with no branding of any kind, black flat-front "
             "trousers, and black leather sneakers",
        "b": "a black quarter-zip pullover printed across the chest with a large abstract emblem "
             "of concentric white rings containing no letters and no words, black flat-front "
             "trousers, and black leather sneakers",
        "marks_on_b": True,
    },
    "w-trend-1": {
        "a": "a classic navy single-breasted blazer with natural shoulders, a straight midi "
             "skirt in mid-grey wool, and brown leather loafers",
        "b": "an unstructured navy double-breasted blazer with wide peak lapels worn open, a "
             "pleated cropped mid-grey wool skirt, and chunky lug-soled brown leather loafers",
    },
    "w-trend-2": {
        "a": "a classic beige cotton gabardine trench coat over a white blouse and navy "
             "trousers, with brown leather loafers",
        "b": "a beige technical nylon trench coat with taped seams and a corded drawstring hem "
             "over a white blouse and navy trousers, with brown leather loafers",
    },
    "w-accessory-1": {
        "a": "a light blue oxford cotton blouse tucked into navy flat-front trousers, and brown "
             "leather loafers, with bare wrists, no belt, no watch and no accessories of any kind",
        "b": "a light blue oxford cotton blouse tucked into navy flat-front trousers, and brown "
             "leather loafers, with a brown leather belt, a steel wristwatch on the left wrist, "
             "and a patterned silk scarf knotted at the neck",
    },
    "w-accessory-2": {
        "a": "a charcoal crew-neck knit, mid-grey flat-front trousers, and black leather boots, "
             "with bare wrists and no belt, no watch and no accessories of any kind",
        "b": "a charcoal crew-neck knit, mid-grey flat-front trousers, and black leather boots, "
             "with a black leather belt, a leather-strap wristwatch on the left wrist, and a "
             "charcoal wool scarf draped at the neck",
    },
    "w-contrast-1": {
        "a": "a mid-grey crew-neck knit, mid-grey flat-front trousers, and mid-grey leather "
             "sneakers, every piece within one narrow value band",
        "b": "a near-white crew-neck knit, near-black flat-front trousers, and black leather "
             "sneakers",
    },
    "w-contrast-2": {
        "a": "a mid-blue chambray blouse, mid-blue flat-front trousers, and mid-blue suede "
             "loafers, every piece within one narrow value band",
        "b": "a pale ice-blue blouse, deep navy flat-front trousers, and deep navy suede loafers",
    },
}

MENSWEAR_REFERENCE_PROMPT = (
    "Editorial menswear outfit photograph on a seamless warm mid-grey studio backdrop, even soft "
    "directional lighting from upper left. Full body framed from the shoulders down to the shoes, "
    "no face visible, model centered and standing straight, arms relaxed at sides. Wearing a plain "
    "mid-grey crew-neck t-shirt and plain mid-grey trousers and plain white sneakers. Well-made "
    "garments in excellent condition, pressed and clean. Neutral catalog styling, no props, no text, "
    "no logos. Shot on 85mm, f8, full-length studio fashion photography."
)

WOMENSWEAR_REFERENCE_PROMPT = (
    "Editorial womenswear outfit photograph on a seamless warm mid-grey studio backdrop, even soft "
    "directional lighting from upper left. Full body framed from the shoulders down to the shoes, "
    "no face visible, adult woman model centered and standing straight, arms relaxed at sides. "
    "Wearing a plain mid-grey crew-neck t-shirt and plain mid-grey trousers and plain white "
    "sneakers. Well-made garments in excellent condition, pressed and clean. Neutral catalog "
    "styling, no props, no text, no logos. Shot on 85mm, f8, full-length studio fashion photography."
)

MENSWEAR_EDIT_SKELETON = (
    "Keep this exact same man — identical body proportions, identical skin tone, identical framing "
    "and crop, identical seamless warm mid-grey studio backdrop and lighting. Change only the "
    "clothing. He is now wearing {garments}. Full body from the shoulders down to the shoes, no "
    "face visible, standing straight, arms relaxed at sides. Well-made garments in excellent "
    "condition, pressed and clean. Neutral catalog styling, no props{extra}."
)

WOMENSWEAR_EDIT_SKELETON = (
    "Keep this exact same woman — identical body proportions, identical skin tone, identical "
    "framing and crop, identical seamless warm mid-grey studio backdrop and lighting. Change only "
    "the clothing. She is now wearing {garments}. Full body from the shoulders down to the shoes, "
    "no face visible, standing straight, arms relaxed at sides. Well-made garments in excellent "
    "condition, pressed and clean. Neutral catalog styling, no props{extra}."
)

NO_MARKS = ", no text, no logos"


def graph_config(graph: str) -> tuple[Path, Path, dict[str, dict], str, str]:
    if graph == "womenswear":
        out = Path("brand/quiz-imagery/womenswear")
        return (
            out,
            out / "_reference-figure-womenswear.png",
            WOMENSWEAR_PAIRS,
            WOMENSWEAR_REFERENCE_PROMPT,
            WOMENSWEAR_EDIT_SKELETON,
        )
    out = Path("brand/quiz-imagery")
    return (
        out,
        out / "_reference-figure.png",
        MENSWEAR_PAIRS,
        MENSWEAR_REFERENCE_PROMPT,
        MENSWEAR_EDIT_SKELETON,
    )


def api_key() -> str:
    key = os.environ.get("OPENAI_API_KEY", "") or os.environ.get("IMAGE_PROVIDER_API_KEY", "")
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
    """Minimal multipart/form-data. Stdlib-only — no third-party deps."""
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


def make_reference(key: str, reference: Path, prompt: str) -> None:
    print(f"Generating the canonical figure -> {reference}")
    result = post_json(
        "https://api.openai.com/v1/images/generations",
        {"model": MODEL, "prompt": prompt, "size": SIZE, "quality": QUALITY, "n": 1},
        key,
    )
    write_image(result, reference)
    print("  done. Check hands at full resolution before generating frames from this figure —\n"
          "  a flaw in the reference is a flaw in every frame.")


def make_pair(
    stem: str,
    key: str,
    pairs: dict[str, dict],
    out: Path,
    reference: Path,
    edit_skeleton: str,
) -> bool:
    spec = pairs[stem]
    if not reference.exists():
        sys.exit(f"{reference} is missing. Run with --reference first.")
    ok = True
    for side in ("a", "b"):
        marks = spec.get("marks_on_b") and side == "b"
        prompt = edit_skeleton.format(
            garments=spec[side], extra="" if marks else NO_MARKS
        )
        destination = out / f"{stem}-{side}.png"
        try:
            result = post_multipart(
                "https://api.openai.com/v1/images/edits",
                {"model": MODEL, "prompt": prompt, "size": SIZE, "quality": QUALITY},
                {"image[]": str(reference)},
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
    parser.add_argument(
        "--graph",
        choices=("menswear", "womenswear"),
        default="menswear",
        help="Product graph (ADR 0019). Default menswear.",
    )
    parser.add_argument("--reference", action="store_true",
                        help="Generate the canonical figure every frame is dressed from.")
    parser.add_argument("--pair", action="append", dest="pairs", default=[],
                        help="Pair stem. Repeatable.")
    parser.add_argument("--all", action="store_true", help="Every pair for this graph.")
    args = parser.parse_args()

    out, reference, pairs, ref_prompt, edit_skeleton = graph_config(args.graph)
    key = api_key()
    if args.reference:
        make_reference(key, reference, ref_prompt)
    stems = sorted(pairs) if args.all else args.pairs
    unknown = [s for s in stems if s not in pairs]
    if unknown:
        sys.exit(f"Unknown pair(s): {', '.join(unknown)}. Known: {', '.join(sorted(pairs))}")

    failed = []
    for stem in stems:
        print(f"{stem}:")
        if not make_pair(stem, key, pairs, out, reference, edit_skeleton):
            failed.append(stem)

    if stems:
        print(f"\n{len(stems) - len(failed)}/{len(stems)} pairs generated into {out}/")
        if failed:
            print(f"FAILED: {', '.join(failed)}", file=sys.stderr)
        print("\nNow: check hands at full resolution, confirm each pair varies ONLY on its axis,\n"
              "then run scripts/build_quiz_imagery.py to produce the shipped tiles.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
