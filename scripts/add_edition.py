#!/usr/bin/env python3
"""Add one Morgenlinie page to the archive.

Usage: python3 scripts/add_edition.py path/to/page.html

Copies the page byte-for-byte to editions/YYYY-MM-DD.html (the date comes from
the header's sign-meta span), then rebuilds editions.json and index.html from
every file in editions/. Standard library only, no network access. Rerunning
with the same input changes nothing.
"""
import hashlib
import html
import json
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EDITIONS = ROOT / "editions"
MANIFEST = ROOT / "editions.json"
INDEX = ROOT / "index.html"
SCHEMA_VERSION = 1

MONTHS = {m: i for i, m in enumerate(
    ["january", "february", "march", "april", "may", "june", "july",
     "august", "september", "october", "november", "december"], start=1)}
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday",
            "saturday", "sunday"]

SIGN_META = re.compile(
    r'<div[^>]*class="[^"]*\bsign-meta\b[^"]*"[^>]*>\s*<span[^>]*>(.*?)</span>',
    re.S | re.I)
HEADER_DATE = re.compile(
    r"^(?:(?P<wd>[a-z]+),?\s+)?(?P<d>\d{1,2})\.?\s+(?P<m>[a-z]+)\s+(?P<y>\d{4})$",
    re.I)
TOPIC = re.compile(r"<h2[^>]*>\s*Topic of the day:\s*(.*?)</h2>", re.S | re.I)
TAG = re.compile(r"<[^>]+>")


def text(fragment):
    return " ".join(html.unescape(TAG.sub("", fragment)).split())


def parse_date(page):
    m = SIGN_META.search(page)
    if not m:
        raise ValueError("no <div class=\"sign-meta\"><span>…</span> header found")
    raw = text(m.group(1))
    p = HEADER_DATE.match(raw)
    if not p or p["m"].lower() not in MONTHS:
        raise ValueError(f"cannot parse header date {raw!r}")
    d = date(int(p["y"]), MONTHS[p["m"].lower()], int(p["d"]))
    if p["wd"] and p["wd"].lower() in WEEKDAYS and WEEKDAYS[d.weekday()] != p["wd"].lower():
        print(f"warning: header says {p['wd']}, but {d} is a "
              f"{WEEKDAYS[d.weekday()].title()}; using the date", file=sys.stderr)
    return d


def parse_topic(page):
    m = TOPIC.search(page)
    return (text(m.group(1)) or None) if m else None


def scan():
    editions = []
    for f in sorted(EDITIONS.glob("????-??-??.html"), reverse=True):
        try:
            date.fromisoformat(f.stem)
        except ValueError:
            continue
        data = f.read_bytes()
        editions.append({
            "date": f.stem,
            "path": f"editions/{f.name}",
            "topic": parse_topic(data.decode("utf-8", "replace")),
            "sha256": hashlib.sha256(data).hexdigest(),
            "bytes": len(data),
        })
    return editions


def write_manifest(editions):
    # Keep the old timestamp when nothing changed, so reruns are no-ops.
    try:
        old = json.loads(MANIFEST.read_text("utf-8"))
    except (OSError, ValueError):
        old = {}
    if old.get("editions") == editions and old.get("updatedAt"):
        updated = old["updatedAt"]
    else:
        updated = datetime.now(timezone.utc).replace(microsecond=0) \
            .isoformat().replace("+00:00", "Z")
    manifest = {"schemaVersion": SCHEMA_VERSION, "updatedAt": updated,
                "editions": editions}
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", "utf-8")


def write_index(editions):
    rows = []
    for e in editions:
        d = date.fromisoformat(e["date"])
        label = f"{WEEKDAYS[d.weekday()].title()} {d.day} {list(MONTHS)[d.month - 1].title()} {d.year}"
        topic = f' <span class="topic">{html.escape(e["topic"])}</span>' if e["topic"] else ""
        rows.append(f'<li><a href="{e["path"]}">{label}</a>{topic}</li>')
    INDEX.write_text(f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Morgenlinie archive</title>
<style>
:root {{ color-scheme: light dark; --ink: #15252c; --muted: #52646c; --ground: #edf1f2 }}
@media (prefers-color-scheme: dark) {{ :root {{ --ink: #e8eff1; --muted: #a2b2b9; --ground: #101a1f }} }}
body {{ margin: 0 auto; max-width: 640px; padding: 24px 16px; background: var(--ground); color: var(--ink); font: 17px/1.5 Georgia, serif }}
h1 {{ font-family: "Courier New", monospace; letter-spacing: .02em }}
ol {{ list-style: none; padding: 0 }}
li {{ padding: 6px 0; border-bottom: 1px solid color-mix(in srgb, var(--muted) 30%, transparent) }}
a {{ color: inherit }}
.topic {{ color: var(--muted) }}
.topic::before {{ content: "· " }}
</style>
</head>
<body>
<h1>MORGENLINIE</h1>
<p>Every archived edition, newest first.</p>
<ol>
{chr(10).join(rows)}
</ol>
</body>
</html>
""", "utf-8")


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    src = Path(argv[1])
    data = src.read_bytes()
    try:
        page = data.decode("utf-8")
        d = parse_date(page)
    except (UnicodeDecodeError, ValueError) as err:
        print(f"error: {src}: {err}", file=sys.stderr)
        return 1
    EDITIONS.mkdir(exist_ok=True)
    dest = EDITIONS / f"{d.isoformat()}.html"
    dest.write_bytes(data)
    editions = scan()
    write_manifest(editions)
    write_index(editions)
    print(f"added {dest.relative_to(ROOT)} (topic: {parse_topic(page)}); "
          f"{len(editions)} edition(s) in editions.json")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
