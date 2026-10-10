#!/usr/bin/env python3
"""Reject server credential identifiers in a built iOS executable."""
import argparse
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def server_identifiers():
    names = {"SERVICE_ROLE", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"}
    for path in (ROOT / "supabase/functions").rglob("*.ts"):
        for name in re.findall(r'Deno\.env\.get\("([A-Z0-9_]+)"', path.read_text()):
            if "SERVICE_ROLE" in name or name.endswith("_API_KEY"):
                names.add(name)
    return sorted(names)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="Built Staging or Release .app directory")
    args = parser.parse_args()
    with (args.app / "Info.plist").open("rb") as handle:
        metadata = plistlib.load(handle)
    binary = (args.app / metadata["CFBundleExecutable"]).read_bytes()
    identifiers = server_identifiers()
    found = [name for name in identifiers if name.encode() in binary]
    if found:
        print("FAIL: server credential identifiers in app executable: " + ", ".join(found))
        return 1
    notices = args.app / "ThirdPartyNotices.txt"
    if not notices.is_file() or not notices.read_text().strip():
        print("FAIL: bundled third-party license notices are missing.")
        return 1
    print(f"Checked {len(identifiers)} server credential identifiers: absent. License notices are bundled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
