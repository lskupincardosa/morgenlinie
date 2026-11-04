# Morgenlinie

Daily news digest data for RSS readers and a future iOS app.

- `editions/YYYY-MM-DD.json`: one file per edition
- `feed.xml`: RSS feed for the last 14 days
- `latest.json`: newest edition for app use
- `scripts/build_feed.py`: validates editions and rebuilds the feed

Feed address: https://lskupincardosa.github.io/morgenlinie/feed.xml

After adding an edition, run `python3 scripts/build_feed.py`.
