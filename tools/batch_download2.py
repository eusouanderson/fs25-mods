#!/usr/bin/env python3
import sys, time, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from download_fs25 import extract_download_urls, resolve_download_url, download_zip, FS25_DIR, DELAY

URLS = [
    "https://fs25.net/iveco-eurocargo-v1-0/",
    "https://fs25.net/volvo-fh12-v1-0/",
    "https://fs25.net/volvo-fh16-v1-0-3/",
    "https://fs25.net/volvo-fmx-v1-0/",
    "https://fs25.net/volvo-fmx-v1-0-2/",
    "https://fs25.net/volvo-fh500-v1-0/",
    "https://fs25.net/volvo-fh3-540-v1-0/",
    "https://fs25.net/volvo-fh16-south-america-v1-0/",
]

DB_PATH = Path(__file__).resolve().parent / "fs25-mods-db.json"

def load_db():
    if not DB_PATH.exists(): return {"mods": []}
    return json.loads(DB_PATH.read_text(encoding="utf-8"))

def add_to_db(name, slug, manufacturer, version, dl_url):
    db = load_db()
    existing = {m["slug"] for m in db["mods"]}
    if slug in existing:
        print(f"  ℹ  Already in DB: {slug}")
        return
    db["mods"].append({
        "name": name, "slug": slug, "category": "trucks", "manufacturer": manufacturer,
        "converted": True, "converted_by": "?", "version": version or "?",
        "release_url": dl_url, "original_author": "?", "original_game": "FS22",
        "type": "truck", "description": f"{manufacturer} {name} — FS25",
        "search_terms": name.lower().split() + manufacturer.lower().split(),
        "added": time.strftime("%Y-%m-%d"),
    })
    DB_PATH.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"  ✅  DB: {name}")

for i, url in enumerate(URLS, 1):
    print(f"\n{'='*60}")
    print(f"  [{i}/{len(URLS)}] {url}")
    slug = url.rstrip("/").split("/")[-1]
    try:
        dl_pages = extract_download_urls(url)
        if not dl_pages:
            print(f"  ⚠  No download link")
            continue
        for dl_page in dl_pages:
            zip_url, zip_name = resolve_download_url(dl_page)
            if not zip_url: continue
            dest = FS25_DIR / slug / zip_name
            downloaded = download_zip(zip_url, dest)
            if downloaded:
                parts = slug.replace("-", " ").title().split()
                manu = parts[0] if parts else "?"
                name = slug.replace("-", " ").title()
                add_to_db(name, slug, manu, "?", zip_url)
        time.sleep(DELAY)
    except Exception as e:
        print(f"  ⚠  Error: {e}")

print(f"\n  ✅  Batch 2 complete!")
