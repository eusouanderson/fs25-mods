#!/usr/bin/env python3
"""Batch download FS25 mods from a list of URLs using the download_fs25 module."""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from download_fs25 import (
    extract_download_urls,
    resolve_download_url,
    download_zip,
    add_to_db,
    FS25_DIR,
    DELAY,
    fetch,
)

URLS_FILE = Path(__file__).resolve().parent / "found-urls.txt"

if not URLS_FILE.exists():
    print(f"  ✖  {URLS_FILE} not found")
    sys.exit(1)

urls = [line.strip() for line in URLS_FILE.read_text().splitlines()
        if line.strip() and not line.startswith("#")]

print(f"  ℹ  {len(urls)} URLs to process\n")

for i, url in enumerate(urls, 1):
    print(f"\n{'='*60}")
    print(f"  [{i}/{len(urls)}] {url}")
    print(f"{'='*60}")

    slug = url.rstrip("/").split("/")[-1]

    try:
        dl_pages = extract_download_urls(url)
        if not dl_pages:
            print(f"  ⚠  No download link found")
            continue

        for dl_page in dl_pages:
            try:
                zip_url, zip_name = resolve_download_url(dl_page)
                if not zip_url:
                    continue

                dest = FS25_DIR / slug / zip_name
                downloaded = download_zip(zip_url, dest)

                if downloaded:
                    # Extract manufacturer from slug
                    parts = slug.replace("-", " ").title().split()
                    manufacturer = parts[0] if parts else "?"
                    # Clean up FS25 prefix
                    name = slug.replace("-", " ").title()
                    name = name.replace("Fs25", "FS25").replace("V1", "V1.")
                    add_to_db(name, slug, manufacturer, "?", zip_url)
            except Exception as e:
                print(f"  ⚠  Download error: {e}")
                continue

        time.sleep(DELAY)

    except Exception as e:
        print(f"  ⚠  Error: {e}")
        continue

print(f"\n{'='*60}")
print(f"  ✅  Batch complete!")
