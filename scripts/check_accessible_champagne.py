#!/usr/bin/env python3
"""Reject decorative champagne in semantic text, tint, or outline modifiers."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODIFIER = re.compile(r"\.(foregroundStyle|foregroundColor|tint|stroke|strokeBorder)\s*\(")
RAW = re.compile(r"\bAstraColor\.(?:accentChampagne|accentChampagnePressed)\b")


def violations(source):
    failures = []
    for match in MODIFIER.finditer(source):
        depth, index = 1, match.end()
        while index < len(source) and depth:
            depth += (source[index] == '(') - (source[index] == ')')
            index += 1
        if RAW.search(source[match.end():index]):
            failures.append(source.count('\n', 0, match.start()) + 1)
    return failures


def main():
    assert violations('Text("x").foregroundStyle(AstraColor.accentChampagne)') == [1]
    assert violations('Circle().stroke(selected ? AstraColor.accentChampagne : .clear)') == [1]
    assert violations('Text("x").foregroundStyle(AstraColor.accentChampagnePressed)') == [1]
    assert not violations('Circle().fill(AstraColor.accentChampagne)')
    assert not violations('Text("x").foregroundStyle(AstraColor.accentChampagneAccessible)')
    errors = []
    for path in sorted((ROOT / 'ios/AstraStyle').rglob('*.swift')):
        if 'Tests' in path.parts:
            continue
        for line in violations(path.read_text()):
            errors.append(f'{path.relative_to(ROOT)}:{line}: use accentChampagneAccessible for text/tint/strokes')
    if errors:
        print('\n'.join(errors))
        return 1
    print('Champagne meaning uses the accessible token; decorative fills remain separate.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
