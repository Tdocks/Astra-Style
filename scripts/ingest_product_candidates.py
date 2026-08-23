#!/usr/bin/env python3
# =============================================================================
# scripts/ingest_product_candidates.py — P6-SHOP-08 curated catalog ingest
# =============================================================================
# Service-role upsert into `product_candidates` from a JSON fixture.
# Authenticated clients cannot write this table (RLS select-only).
# Discover Unlocks does not read this table except through evaluations.
#
# Never prints the service-role key.
# =============================================================================

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_FIXTURE = REPO_ROOT / "supabase" / "seed" / "product_candidates.json"

CATEGORIES = {
    "top",
    "bottom",
    "outerwear",
    "shoes",
    "accessory",
    "watch",
    "fragrance",
}


def die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_products(path: Path) -> list[dict[str, Any]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    products = raw.get("products") if isinstance(raw, dict) else raw
    if not isinstance(products, list) or not products:
        die(f"{path} must contain a non-empty 'products' array.")
    return products


def validate_product(row: dict[str, Any], index: int) -> dict[str, Any]:
    url = row.get("canonical_url")
    name = row.get("name")
    category = row.get("category")
    if not isinstance(url, str) or not url.startswith("https://"):
        die(f"products[{index}].canonical_url must be an https URL.")
    if not isinstance(name, str) or not name.strip():
        die(f"products[{index}].name is required.")
    if category not in CATEGORIES:
        die(f"products[{index}].category must be a clothing_category (got {category!r}).")
    currency = row.get("currency", "USD")
    if not isinstance(currency, str) or len(currency) != 3:
        die(f"products[{index}].currency must be a 3-letter code.")
    price = row.get("price")
    if price is not None and (not isinstance(price, (int, float)) or price < 0):
        die(f"products[{index}].price must be >= 0.")
    attributes = row.get("attributes") or {}
    if not isinstance(attributes, dict):
        die(f"products[{index}].attributes must be an object.")
    sponsored = bool(row.get("sponsored", False))
    payload: dict[str, Any] = {
        "canonical_url": url,
        "retailer": row.get("retailer"),
        "brand": row.get("brand"),
        "name": name.strip(),
        "category": category,
        "price": price,
        "currency": currency,
        "image_url": row.get("image_url"),
        "affiliate_url": row.get("affiliate_url"),
        "availability": row.get("availability") or {},
        "attributes": attributes,
        "sponsored": sponsored,
        "last_checked_at": "now",
    }
    return payload


def validate_fixture(path: Path) -> list[dict[str, Any]]:
    products = load_products(path)
    return [validate_product(row, i) for i, row in enumerate(products)]


def rest_upsert(supabase_url: str, service_role_key: str, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    endpoint = supabase_url.rstrip("/") + "/rest/v1/product_candidates?on_conflict=canonical_url"
    body = json.dumps(rows).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=representation",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:2000]
        die(f"PostgREST {error.code}: {detail}")


def stamp_last_checked(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    stamped = []
    for row in rows:
        copy = dict(row)
        copy["last_checked_at"] = now
        stamped.append(copy)
    return stamped


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Upsert curated product_candidates with the service role (P6-SHOP-08)."
    )
    parser.add_argument(
        "--fixture",
        type=Path,
        default=DEFAULT_FIXTURE,
        help="JSON file with a products array (default: supabase/seed/product_candidates.json)",
    )
    parser.add_argument(
        "--supabase-url",
        default="",
        help="Project URL, e.g. https://<ref>.supabase.co (or SUPABASE_URL)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print names/URLs; do not write.",
    )
    args = parser.parse_args()

    rows = stamp_last_checked(validate_fixture(args.fixture))
    if args.dry_run:
        for row in rows:
            flag = " sponsored" if row["sponsored"] else ""
            print(f"{row['category']:10} {row['name']}{flag}")
            print(f"           {row['canonical_url']}")
        print(f"{len(rows)} product(s) valid.", file=sys.stderr)
        return 0

    import os

    url = args.supabase_url or os.environ.get("SUPABASE_URL", "")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        die(
            "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (service role never printed). "
            "Or pass --dry-run to validate the fixture only."
        )
    written = rest_upsert(url, key, rows)
    print(f"upserted {len(written)} product_candidates row(s).")
    for row in written:
        print(f"  {row.get('id')}  {row.get('name')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
