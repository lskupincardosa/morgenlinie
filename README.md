# Morgenlinie

Archive of the daily Morgenlinie news page, served as static assets by a Cloudflare Worker for the Morgenlinie iOS app.

- `editions/YYYY-MM-DD.html`: one self-contained page per day, stored byte-for-byte as published
- `editions.json`: manifest the app syncs from (date, topic, sha256, size), newest first
- `index.html`: plain archive list for browsers (`noindex`)
- `scripts/add_edition.py`: adds a page and rebuilds `editions.json` and `index.html`
- `ios/`: the iOS app (SwiftUI). Not published (see `.assetsignore`), but the repo is public, so keep secrets out of it.
- `src/worker.js`: push notifications for new editions (only `/push/*` and a 10-minute cron run code; everything else is a static asset)
- `wrangler.jsonc`, `.assetsignore`, `_headers`: Cloudflare config. Workers Builds redeploys on every push to `main`.

Base URL: https://morgenlinie.lskupincardosa.workers.dev/ (`editions.json` is served with `max-age=0` and an ETag, so new editions show up immediately).

## Adding an edition

```sh
python3 scripts/add_edition.py path/to/page.html
git add editions editions.json index.html
git commit -m "Add edition YYYY-MM-DD"
git push origin main
```

The date comes from the page header (`<div class="sign-meta"><span>Wednesday 11 November 2026</span>`), the topic from `<h2>Topic of the day: …</h2>` (`null` on weekends). Rerunning for the same day overwrites that edition; rerunning with the same file changes nothing.

This runs automatically: the "Morning news digest" task (05:10 Atlantic/Canary, 06:10 Berlin) publishes the page to the Morgenlinie artifact, and the "Morgenlinie archive" routine (05:40 Atlantic/Canary, 06:40 Berlin, https://claude.ai/code/routines/trig_01AbDQPC9hrD2E77gfHVEcnm) reads it, runs this script and pushes to `main`.

## Manifest format

```json
{
  "schemaVersion": 1,
  "updatedAt": "2026-11-11T06:47:00Z",
  "editions": [
    { "date": "2026-11-11", "path": "editions/2026-11-11.html",
      "topic": "Open source", "sha256": "…", "bytes": 33005 }
  ]
}
```

Bump `schemaVersion` only for breaking changes; the app ignores manifests with a version it does not know.

## Push notifications

The app registers its APNs device token with `POST /push/register`; tokens live in the `PUSH` KV namespace. Every 10 minutes a cron trigger compares the newest date in `editions.json` with the last one announced and, when it is newer, sends one notification per device ("Die Ausgabe für … ist da", no news content). If today's edition is still missing at 07:30 Berlin time, it sends one warning that day instead (`POST /push/test?kind=missing` to try it). The first run after a deploy only records the current edition.

Secrets (set once with `npx wrangler secret put NAME`): `APNS_KEY` (contents of the `.p8` key), `APNS_KEY_ID`, `ADMIN_TOKEN`. To send the newest edition to all devices right away:

```sh
curl -X POST -H "Authorization: Bearer $ADMIN_TOKEN" https://morgenlinie.lskupincardosa.workers.dev/push/test
```
