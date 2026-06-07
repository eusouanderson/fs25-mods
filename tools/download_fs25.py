#!/usr/bin/env python3
"""
FS25 Mod Bulk Search & Downloader
==================================
Search fs25.net for FS25 mods, download them, and catalog in the database.

Usage:
    python tools/download_fs25.py --search "mercedes 1113"
    python tools/download_fs25.py --file trucks.txt
    python tools/download_fs25.py --file trucks.txt --auto-yes
    python tools/download_fs25.py --list-missing
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse, quote

TOOLS_DIR = Path(__file__).resolve().parent
BASE_DIR = TOOLS_DIR.parent
FS25_DIR = BASE_DIR / "fs25" / "trucks"
DB_PATH = TOOLS_DIR / "fs25-mods-db.json"

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/124.0.0.0 Safari/537.36"
)
SEARCH_URL = "https://www.fs25.net/?s={query}"
DELAY = 1.5

ALL_TRUCKS = [
    # Clássicos BR - Chevrolet/GM
    "Chevrolet Brasil 3100", "Chevrolet C-60", "Chevrolet D-60", "Chevrolet C-65",
    # Clássicos BR - Ford
    "Ford F-600", "Ford F-700", "Ford F-11000", "Ford F-4000", "Ford Cargo",
    # Clássicos BR - Mercedes-Benz antigos
    "Mercedes L-312", "Mercedes L-1111", "Mercedes L-1113", "Mercedes L-1519",
    "Mercedes L-2013", "Mercedes L-1513",
    # Clássicos Europeus - Scania
    "Scania L75", "Scania L110", "Scania 111", "Scania 112", "Scania 113",
    # Clássicos Europeus - Volvo
    "Volvo N10", "Volvo N12", "Volvo F10", "Volvo F12",
    # Mercedes anos 70-90
    "Mercedes 1113", "Mercedes 1313", "Mercedes 1513", "Mercedes 1519",
    "Mercedes 1935", "Mercedes 2213", "Mercedes 1620",
    # VW Caminhões
    "VW 7-110", "VW 8-150", "VW 9-150", "VW 13-130", "VW 18-310",
    "VW Constellation 24-250",
    # Iveco
    "Iveco Eurocargo", "Iveco Stralis", "Iveco Cursor",
    # Scania modernos
    "Scania 124", "Scania 114", "Scania P", "Scania G", "Scania R",
    # Volvo modernos
    "Volvo FH12", "Volvo FH16", "Volvo FM12", "Volvo VM",
    # Atuais VW
    "VW Constellation 17-190", "VW Constellation 24-280", "VW Meteor 28-460",
    "VW e-Delivery",
    # Atuais Mercedes
    "Mercedes Actros", "Mercedes Atego", "Mercedes Arocs", "Mercedes Accelo",
    # Atuais Scania
    "Scania S", "Scania P", "Scania G", "Scania R",
    # Atuais Volvo
    "Volvo FH", "Volvo FMX", "Volvo FM", "Volvo VNL",
    # DAF
    "DAF XF", "DAF CF", "DAF LF",
    # Iveco atuais
    "Iveco S-Way", "Iveco Hi-Way", "Iveco Daily",
]


# ── HTTP helpers ──────────────────────────────────────────────────────────────

def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
        try:
            return body.decode("utf-8")
        except UnicodeDecodeError:
            return body.decode("latin-1")


# ── Search ────────────────────────────────────────────────────────────────────

def search_fs25net(query: str) -> list[dict]:
    url = SEARCH_URL.format(query=quote(query))
    print(f"  🔍  Searching: {query}")
    try:
        html = fetch(url)
    except Exception as e:
        print(f"  ⚠  Fetch error: {e}")
        return []

    results = []
    for m in re.finditer(r'href="([^"]+)"\s*rel="bookmark"', html):
        mod_url = m.group(1)
        results.append({"url": mod_url, "query": query})

    # Also try to get titles
    titles = re.findall(r'<a[^>]*href="([^"]+)"[^>]*rel="bookmark"[^>]*>([^<]+)</a>', html)
    title_map = {url: title.strip() for url, title in titles}

    for r in results:
        r["title"] = title_map.get(r["url"], "")

    return results


def extract_download_urls(mod_page_url: str) -> list[str]:
    """Extract all download URLs from a mod page. Returns list of download-page URLs."""
    html = fetch(mod_page_url)
    urls = []

    # Pattern 1: href="..." ... class="attachment-link" (href can be before or after class)
    for m in re.finditer(r'href="([^"]*download-mod/[^"]+)"[^>]*class="[^"]*attachment-link', html):
        url = m.group(1)
        if url not in urls:
            urls.append(url)

    # Pattern 2: class="attachment-link" ... href="..."
    for m in re.finditer(r'class="[^"]*attachment-link[^"]*"[^>]*href="([^"]+)"', html):
        url = m.group(1)
        if url not in urls:
            urls.append(url)

    # Pattern 3: direct .zip links
    for m in re.finditer(r'href="([^"]+\.zip)"', html):
        url = m.group(1)
        if url not in urls:
            urls.append(url)

    return urls


def resolve_download_url(dl_page_url: str) -> tuple[str, str]:
    """Follow redirect to get the actual ZIP URL and filename."""
    if not dl_page_url.startswith("http"):
        dl_page_url = f"https://fs25.net{dl_page_url}"

    req = urllib.request.Request(
        dl_page_url,
        headers={"User-Agent": USER_AGENT},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            zip_url = resp.geturl()
            cd = resp.headers.get("Content-Disposition", "")
    except urllib.error.HTTPError:
        req = urllib.request.Request(
            dl_page_url,
            headers={"User-Agent": USER_AGENT, "Range": "bytes=0-0"},
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            zip_url = resp.geturl()
            cd = resp.headers.get("Content-Disposition", "")

    zip_filename = ""
    if cd and "filename=" in cd:
        match = re.search(r'filename=["\']?([^"\';\n]+)', cd)
        if match:
            zip_filename = match.group(1).strip()
    if not zip_filename:
        zip_filename = os.path.basename(urlparse(zip_url).path)
    if not zip_filename or not zip_filename.endswith(".zip"):
        zip_filename = f"{urlparse(dl_page_url).path.rstrip('/').split('/')[-1]}.zip"
    zip_filename = re.sub(r'[^\w\.\-\(\) ]', '_', zip_filename)

    return zip_url, zip_filename


def download_zip(url: str, dest: Path) -> bool:
    if dest.exists():
        mb = dest.stat().st_size / 1024 / 1024
        print(f"  ℹ  Already exists: {dest.name} ({mb:.1f} MB)")
        return False

    print(f"  ⬇  Downloading: {dest.name}")
    dest.parent.mkdir(parents=True, exist_ok=True)

    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            with open(dest, "wb") as f:
                while chunk := resp.read(8192):
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total:
                        pct = downloaded * 100 / total
                        print(f"\r  ⬇  {downloaded/1024:.0f}KB / {total/1024:.0f}KB ({pct:.0f}%)", end="")
                    else:
                        print(f"\r  ⬇  {downloaded/1024:.0f}KB", end="")
            print()
        mb = dest.stat().st_size / 1024 / 1024
        print(f"  ✅  Saved ({mb:.1f} MB)")
        return True
    except Exception as e:
        print(f"  ✖  Download failed: {e}")
        return False


def slug_from_name(name: str) -> str:
    slug = name.lower().replace(" ", "-")
    slug = re.sub(r"[^a-z0-9\-]", "", slug)
    return slug


# ── Database ──────────────────────────────────────────────────────────────────

def load_db() -> dict:
    if not DB_PATH.exists():
        return {"mods": []}
    return json.loads(DB_PATH.read_text(encoding="utf-8"))


def save_db(db: dict):
    DB_PATH.write_text(
        json.dumps(db, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def add_to_db(name: str, slug: str, manufacturer: str, version: str,
              dl_url: str, category: str = "trucks"):
    db = load_db()
    existing = {m["slug"] for m in db["mods"]}
    if slug in existing:
        print(f"  ℹ  Already in database: {slug}")
        return

    db["mods"].append({
        "name": name,
        "slug": slug,
        "category": category,
        "manufacturer": manufacturer,
        "converted": True,
        "converted_by": "?",
        "version": version or "?",
        "release_url": dl_url,
        "original_author": "?",
        "original_game": "?",
        "type": "truck",
        "description": f"{manufacturer} {name} — FS25",
        "search_terms": name.lower().split() + manufacturer.lower().split(),
        "added": time.strftime("%Y-%m-%d"),
    })
    save_db(db)
    print(f"  ✅  Added to database: {name}")


# ── Main commands ─────────────────────────────────────────────────────────────

def cmd_search(query: str, auto_yes: bool = False):
    results = search_fs25net(query)
    if not results:
        print(f"  ℹ  No results found for: {query}")
        return

    print(f"\n  {'='*60}")
    print(f"  Found {len(results)} result(s):")
    print(f"  {'='*60}")
    for i, r in enumerate(results, 1):
        title = r.get("title", "") or r["url"].rstrip("/").split("/")[-1]
        print(f"  [{i}] {title}")
        print(f"      {r['url']}")

    if not auto_yes:
        resp = input(f"\n  Download all? [Y/n] ").strip().lower()
        if resp and resp != "y" and resp != "yes":
            print("  Skipped.")
            return

    for r in results:
        print(f"\n  {'─'*50}")
        print(f"  Processing: {r['url']}")
        time.sleep(DELAY)
        try:
            dl_pages = extract_download_urls(r["url"])
            if not dl_pages:
                print("  ⚠  No download link found on page")
                continue

            slug = r["url"].rstrip("/").split("/")[-1]
            title = r.get("title", "") or slug

            for dl_page in dl_pages:
                try:
                    zip_url, zip_name = resolve_download_url(dl_page)
                    if not zip_url:
                        continue

                    dest = FS25_DIR / slug / zip_name
                    downloaded = download_zip(zip_url, dest)

                    if downloaded:
                        manufacturer = query.split()[0] if query.split() else "?"
                        add_to_db(title, slug, manufacturer, "?", zip_url)
                except Exception as e:
                    print(f"  ⚠  Error resolving download: {e}")
                    continue

        except Exception as e:
            print(f"  ⚠  Error processing {r['url']}: {e}")
            continue


def cmd_bulk(file_path: str, auto_yes: bool = False):
    with open(file_path, "r") as f:
        queries = [line.strip() for line in f if line.strip() and not line.startswith("#")]

    print(f"  ℹ  Loaded {len(queries)} truck(s) from {file_path}")
    for q in queries:
        print(f"\n{'#'*60}")
        print(f"  # {q}")
        print(f"{'#'*60}")
        cmd_search(q, auto_yes)
        time.sleep(DELAY)


def cmd_search_all(auto_yes: bool = False):
    print(f"  ℹ  Searching for {len(ALL_TRUCKS)} trucks...")
    for truck in ALL_TRUCKS:
        print(f"\n{'#'*60}")
        print(f"  # {truck}")
        print(f"{'#'*60}")
        cmd_search(truck, auto_yes)
        time.sleep(DELAY)


def cmd_list_missing():
    db = load_db()
    db_slugs = {m["slug"] for m in db["mods"]}

    print(f"\n  {'='*60}")
    print(f"  Trucks not yet in database:")
    print(f"  {'='*60}")
    missing = 0
    for truck in ALL_TRUCKS:
        slug = slug_from_name(truck)
        if slug not in db_slugs:
            print(f"  🔴 {truck}")
            missing += 1

    print(f"\n  Total missing: {missing}/{len(ALL_TRUCKS)}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Search and download FS25 mods from fs25.net",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--search", "-s", help="Search for a single truck")
    parser.add_argument("--file", "-f", help="File with truck names (one per line)")
    parser.add_argument("--search-all", action="store_true", help="Search ALL predefined trucks")
    parser.add_argument("--list-missing", action="store_true", help="List trucks not yet in DB")
    parser.add_argument("--auto-yes", "-y", action="store_true", help="Auto-confirm downloads")

    args = parser.parse_args()

    if args.list_missing:
        cmd_list_missing()
    elif args.search_all:
        cmd_search_all(args.auto_yes)
    elif args.file:
        cmd_bulk(args.file, args.auto_yes)
    elif args.search:
        cmd_search(args.search, args.auto_yes)
    else:
        parser.print_help()
        print("\nError: Provide --search, --file, --search-all, or --list-missing")


if __name__ == "__main__":
    main()
