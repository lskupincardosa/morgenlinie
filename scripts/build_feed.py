#!/usr/bin/env python3
"""Build feed.xml and latest.json from the files in editions/."""
import hashlib
import json
from datetime import date, datetime, timedelta, timezone
from email.utils import format_datetime
from html import escape
from pathlib import Path
from urllib.parse import urlparse
from xml.sax.saxutils import escape as xml_escape

ROOT = Path(__file__).resolve().parent.parent
SITE = "https://lskupincardosa.github.io/morgenlinie/"
FEED_DAYS = 14
BLOCKED_DOMAINS = {
    "abc.es", "b-z.de", "bild.de", "businessinsider.com", "businessinsider.de",
    "bz-berlin.de", "eldebate.com", "elmundo.es", "faz.net", "foxnews.com",
    "jungefreiheit.de", "larazon.es", "libertaddigital.com", "nius.de",
    "okdiario.com", "politico.com", "politico.eu", "telegraph.co.uk",
    "tichyseinblick.de", "welt.de",
}


def is_blocked(url):
    host = (urlparse(url).hostname or "").lower()
    return any(host == d or host.endswith("." + d) for d in BLOCKED_DOMAINS)


def validate(edition, path):
    date.fromisoformat(edition["date"])
    if path.stem != edition["date"]:
        raise ValueError(f"{path.name} does not match date {edition['date']}")
    for section in edition["sections"]:
        for story in section["stories"]:
            if not story.get("links"):
                raise ValueError(f"No link for story: {story['title']}")
            for link in story["links"]:
                if urlparse(link["url"]).scheme != "https":
                    raise ValueError(f"Link is not HTTPS: {link['url']}")
                if is_blocked(link["url"]):
                    raise ValueError(f"Blocked source: {link['url']}")


def load_editions():
    editions = []
    for path in sorted((ROOT / "editions").glob("*.json"), reverse=True):
        edition = json.loads(path.read_text(encoding="utf-8"))
        validate(edition, path)
        editions.append(edition)
    if not editions:
        raise ValueError("No editions found")
    return editions


def item_xml(edition, section, story, published):
    key = f"{edition['date']}|{section['id']}|{story['title']}"
    guid = hashlib.sha256(key.encode("utf-8")).hexdigest()[:24]
    links = " · ".join(
        f'<a href="{escape(link["url"])}">{escape(link["label"])}</a>'
        for link in story["links"]
    )
    body = (
        f"<p><em>{escape(section['title'])}. {escape(story.get('label', ''))}</em></p>"
        f"<p>{escape(story['summary'])}</p><p>{links}</p>"
    )
    return (
        "<item>"
        f"<title>{xml_escape(story['title'])}</title>"
        f"<link>{xml_escape(story['links'][0]['url'])}</link>"
        f'<guid isPermaLink="false">morgenlinie-{guid}</guid>'
        f"<pubDate>{format_datetime(published)}</pubDate>"
        f"<category>{xml_escape(section['title'])}</category>"
        f"<description>{xml_escape(body)}</description>"
        "</item>"
    )


def build_feed(editions):
    newest = date.fromisoformat(editions[0]["date"])
    cutoff = newest - timedelta(days=FEED_DAYS - 1)
    items = []
    for edition in editions:
        day = date.fromisoformat(edition["date"])
        if day < cutoff:
            continue
        published = datetime(day.year, day.month, day.day, 6, 40, tzinfo=timezone.utc)
        order = 0
        for section in edition["sections"]:
            for story in section["stories"]:
                # Keep the digest's order in readers that sort by newest first.
                stamp = published - timedelta(seconds=order)
                items.append(item_xml(edition, section, story, stamp))
                order += 1
    built = datetime(newest.year, newest.month, newest.day, 6, 40, tzinfo=timezone.utc)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>'
        "<title>Morgenlinie</title>"
        f"<link>{SITE}</link>"
        "<description>Lucas's morning news digest, summarised by Claude.</description>"
        "<language>en</language>"
        f"<lastBuildDate>{format_datetime(built)}</lastBuildDate>"
        f'<atom:link href="{SITE}feed.xml" rel="self" type="application/rss+xml"/>'
        + "".join(items)
        + "</channel></rss>\n"
    )


def main():
    editions = load_editions()
    (ROOT / "feed.xml").write_text(build_feed(editions), encoding="utf-8")
    (ROOT / "latest.json").write_text(
        json.dumps(editions[0], ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Built feed from {len(editions)} edition(s), newest {editions[0]['date']}")


if __name__ == "__main__":
    main()
