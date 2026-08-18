#!/usr/bin/env python3
"""Turn the captured W4 pages into sanitized parser fixtures.

Real people appear in these captures (the signed-in student, staff and students with
birthdays). Fixtures are committed, so every identifier and name is replaced with an
invented placeholder before anything is written. Structure is preserved byte-for-byte
apart from those substitutions so the parsers are still exercised against real markup.
"""
import pathlib
import re
import sys

SRC = pathlib.Path("/Users/johannes/Projects/betterw4/references/pages")
DST = pathlib.Path("/Users/johannes/Projects/betterw4/ios/BetterW4Tests/Fixtures/W4")

# Real UWC id -> placeholder. Placeholders keep the nc + 2-digit year + letters shape
# so the identity regex is still meaningfully tested.
IDS = {
    "nc26jban": "nc26abcd",   # the signed-in student
    "nc16jmac": "nc16efgh",   # staff, birthday today
    "nc19ndem": "nc19ijkl",   # staff, birthday today
    "nc25wnas": "nc25mnop",   # student, birthday today
    "nc25eros": "nc25qrst",   # student, birthday tomorrow
}

NAMES = {
    "Jonathan Bangert": "Alex Andersen",
}

PAGES = {
    "UWCRCN W4.html": "home.html",
    "Academics.html": "academics-menu.html",
    "Extra Academics.html": "extraacademics-menu.html",
    "School info @ UWCRCN.html": "school-menu.html",
    "Documents.html": "documents.html",
    # "Current applicants at UWCRCN.html" is deliberately NOT used: applicant rows are PII
    # and no parser needs that page.
}


def sanitize(html: str) -> str:
    for real, fake in NAMES.items():
        html = html.replace(real, fake)
    for real, fake in IDS.items():
        html = re.sub(real, fake, html, flags=re.IGNORECASE)
    # Any UWC id we did not explicitly map is redacted rather than leaked.
    html = re.sub(r"\bnc(\d{2})(?!abcd|efgh|ijkl|mnop|qrst)[a-z]{3,}\b", r"nc\1zzzz", html)
    # Session-bearing or personal URLs must never sit in a fixture.
    html = re.sub(r"token=[A-Za-z0-9._-]+", "token=REDACTED", html)
    html = re.sub(r"PHPSESSID=[A-Za-z0-9]+", "PHPSESSID=REDACTED", html)
    return html


def main() -> int:
    DST.mkdir(parents=True, exist_ok=True)
    written = []
    for src_name, dst_name in PAGES.items():
        src = SRC / src_name
        if not src.exists():
            print(f"missing: {src}", file=sys.stderr)
            continue
        html = sanitize(src.read_text(encoding="utf-8", errors="replace"))
        (DST / dst_name).write_text(html, encoding="utf-8")
        written.append((dst_name, len(html)))

    leaked = []
    for name, _ in written:
        text = (DST / name).read_text(encoding="utf-8")
        for real in list(IDS) + list(NAMES):
            if real.lower() in text.lower():
                leaked.append((name, real))
    if leaked:
        print("SANITIZER FAILED, leaked:", leaked, file=sys.stderr)
        return 1

    for name, size in written:
        print(f"{name}: {size} bytes")
    print("no real identifiers remain")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
