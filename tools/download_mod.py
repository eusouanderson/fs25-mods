#!/usr/bin/env python3
"""
FS22 Mod Downloader — B.O.B's FS25 Mod Tool
============================================
Downloads mods from fs22.com and organizes them into fs22/<category>/<mod>/

Usage:
    python download_mod.py <mod-url>                   # Single mod
    python download_mod.py --category trucks           # ALL trucks
    python download_mod.py --category-url <url>        # Any category listing
    python download_mod.py --category trucks --limit 5 # First 5 only

Examples:
    python download_mod.py --category trucks
    python download_mod.py --category trucks --limit 10 --dry-run
    python download_mod.py https://fs22.com/.../renault-k480-v1-0/
    python download_mod.py --list-urls urls.txt
"""

import argparse
import html.parser
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

BASE_DIR = Path(__file__).resolve().parent.parent
FS22_DIR = BASE_DIR / "fs22"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)
SITE = "https://fs22.com"
CATEGORY_PATHS = {
    "trucks":   "category/farming-simulator-22-mods/trucks/",
    "tractors": "category/farming-simulator-22-mods/tractors/",
    "trailers": "category/farming-simulator-22-mods/trailers/",
    "maps":     "category/farming-simulator-22-mods/maps/",
    "cars":     "category/farming-simulator-22-mods/cars/",
}
DELAY_BETWEEN_DOWNLOADS = 2  # seconds, to be polite


# ── HTTP ────────────────────────────────────────────────────────────────

def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
        try:
            return body.decode("utf-8")
        except UnicodeDecodeError:
            return body.decode("latin-1")


# ── Category scraping ───────────────────────────────────────────────────

def extract_mod_links(html: str) -> list[str]:
    """Extract all mod page URLs from a listing page."""
    urls = []
    for m in re.finditer(r'<a[^>]*href="([^"]+)"[^>]*rel="bookmark"', html):
        url = m.group(1)
        if url not in urls:
            urls.append(url)
    return urls


def get_total_pages(html: str) -> int:
    """Find the last page number in pagination."""
    pages = []
    for m in re.finditer(r'/page/(\d+)/"[^>]*>(\d+)</a>', html):
        pages.append(int(m.group(1)))
    return max(pages) if pages else 1


def category_from_url(url: str) -> str:
    """Extract category name from a category listing URL."""
    parsed = urlparse(url)
    path = parsed.path.rstrip("/")
    # Direct match: /category/.../trucks/
    for cat in CATEGORY_PATHS:
        if f"/{cat}/" in path or path.endswith(f"/{cat}"):
            return cat
    # Fallback: grab last meaningful segment before /page/N/
    segments = [s for s in path.split("/") if s and not s.startswith("page")]
    if segments:
        return segments[-1]
    return "other"


def scrape_category_urls(category_url: str, limit: int = 0, dry_run: bool = False) -> list[str]:
    """
    Scrape all mod page URLs from a category listing (multi-page).
    Returns a list of mod page URLs.
    """
    cat = category_from_url(category_url)
    print(f"  ℹ  Category: {cat}")
    print(f"  ℹ  Scraping: {category_url}")

    html = fetch(category_url)
    total_pages = get_total_pages(html)
    print(f"  ℹ  Total pages: {total_pages}")

    all_urls = extract_mod_links(html)
    print(f"  ℹ  Page 1: {len(extract_mod_links(html))} mod(s)")

    if not all_urls:
        print("  ✖  No mod links found on this page. Check the URL.")
        sys.exit(1)

    for page in range(2, total_pages + 1):
        if limit and len(all_urls) >= limit:
            break
        page_url = f"{category_url.rstrip('/')}/page/{page}/"
        print(f"  ℹ  Page {page}/{total_pages}...")
        try:
            page_html = fetch(page_url)
            links = extract_mod_links(page_html)
            if not links:
                print(f"  ℹ  No more mods found at page {page}, stopping.")
                break
            all_urls.extend(links)
            if limit and len(all_urls) >= limit:
                all_urls = all_urls[:limit]
                break
        except Exception as e:
            print(f"  ⚠  Error on page {page}: {e}")
            continue
        time.sleep(0.5)  # polite delay between pages

    if limit:
        all_urls = all_urls[:limit]

    print(f"  ✅  Found {len(all_urls)} mod(s) total across {total_pages} page(s)")
    return all_urls


def category_slug_from_mod_url(url: str) -> str:
    """Extract category from a mod page URL like /trucks/mod-name/"""
    parsed = urlparse(url)
    path = parsed.path.rstrip("/")
    # URL format: /farming-simulator-22-mods/{category}/{mod-slug}/
    parts = [p for p in path.split("/") if p]
    try:
        idx = [i for i, p in enumerate(parts) if p == "mods"][0]
        if idx + 1 < len(parts):
            return parts[idx + 1]
    except IndexError:
        pass
    # Fallback: check against known categories
    for cat in CATEGORY_PATHS:
        if f"/{cat}/" in path:
            return cat
    return "other"


# ── Download resolution ─────────────────────────────────────────────────

class _AttachmentLinkParser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.download_url = None
        self.link_text = None

    def handle_starttag(self, tag, attrs):
        if tag != "a" or self.download_url is not None:
            return
        attrs_dict = dict(attrs)
        cls = attrs_dict.get("class", "")
        if "attachment-link" in cls.split():
            self.download_url = attrs_dict.get("href", "")

    def handle_data(self, data):
        if self.download_url is not None and self.link_text is None:
            txt = data.strip()
            if txt:
                self.link_text = txt


def resolve_download_url(mod_page_url: str) -> tuple[str, str]:
    print(f"  ℹ  Fetching mod page: {mod_page_url}")
    html = fetch(mod_page_url)

    parser = _AttachmentLinkParser()
    parser.feed(html)
    if not parser.download_url:
        print("  ⚠  No attachment-link found, skipping.")
        return "", ""

    dl_page_url = parser.download_url if parser.download_url.startswith("http") else f"{SITE}{parser.download_url}"
    display_name = parser.link_text or os.path.basename(dl_page_url.rstrip("/"))

    # Follow redirect to actual .zip
    req = urllib.request.Request(dl_page_url, method="HEAD", headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            zip_url = resp.geturl()
            cd = resp.headers.get("Content-Disposition", "")
    except urllib.error.HTTPError:
        req = urllib.request.Request(dl_page_url, headers={"User-Agent": USER_AGENT, "Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            zip_url = resp.geturl()
            cd = resp.headers.get("Content-Disposition", "")

    if "/download-mod/" in zip_url:
        req = urllib.request.Request(dl_page_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=60) as resp:
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
        zip_filename = f"{display_name}.zip"
    zip_filename = re.sub(r'[^\w\.\-\(\) ]', '_', zip_filename)

    return zip_url, zip_filename


def slug_from_url(url: str) -> str:
    path = urlparse(url).path.rstrip("/")
    segments = [s for s in path.split("/") if s]
    if segments:
        return segments[-1].lower()
    return "mod"


def download_file(url: str, dest: Path) -> bool:
    if dest.exists():
        print(f"  ℹ  Already exists: {dest.name} ({dest.stat().st_size / 1024 / 1024:.1f} MB)")
        return False
    print(f"  ⬇  Downloading: {dest.name}")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        total = int(resp.headers.get("Content-Length", 0))
        downloaded = 0
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as f:
            while chunk := resp.read(8192):
                f.write(chunk)
                downloaded += len(chunk)
                if total:
                    pct = downloaded * 100 / total
                    print(f"\r  ⬇  {downloaded / 1024:.0f} KB / {total / 1024:.0f} KB ({pct:.0f}%)", end="")
                else:
                    print(f"\r  ⬇  {downloaded / 1024:.0f} KB", end="")
        print()
    print(f"  ✅  Saved ({dest.stat().st_size / 1024 / 1024:.1f} MB)")
    return True


# ── README generation ───────────────────────────────────────────────────

def scan_fs22_mods() -> dict[str, list[dict]]:
    """Scan fs22/ and group mods by category."""
    categories = {}
    if not FS22_DIR.exists():
        return categories
    for cat_dir in FS22_DIR.iterdir():
        if not cat_dir.is_dir() or cat_dir.name.startswith("."):
            continue
        mods = []
        for entry in sorted(cat_dir.iterdir()):
            if entry.is_dir():
                for zipf in entry.glob("*.zip"):
                    mods.append({
                        "name": entry.name,
                        "filepath": str(zipf.relative_to(FS22_DIR)),
                        "size": zipf.stat().st_size,
                        "folder": entry.name,
                    })
                    break
        if mods:
            categories[cat_dir.name] = mods
    return categories


def category_display_name(cat: str) -> str:
    names = {
        "trucks": "🚚 Caminhões / Trucks",
        "tractors": "🚜 Tratores / Tractors",
        "trailers": "🚛 Reboques / Trailers",
        "maps": "🗺️ Mapas / Maps",
        "cars": "🚗 Carros / Cars",
    }
    return names.get(cat, f"📦 {cat.capitalize()}")


def generate_fs22_readme():
    """Regenerate fs22/README.md with mods grouped by category."""
    categories = scan_fs22_mods()
    lines = [
        "# FS22 Original Mods\n",
        "\n",
        "Mods originais do **Farming Simulator 22** baixados como base para conversão ao FS25.\n",
        "\n",
        "---\n",
        "\n",
    ]
    for cat in sorted(categories.keys()):
        mods = categories[cat]
        display = category_display_name(cat)
        lines.append(f"## {display}\n")
        lines.append(f"\n| Mod | Arquivo | Tamanho |\n")
        lines.append(f"|---|--------|--------|\n")
        for m in sorted(mods, key=lambda x: x["name"].lower()):
            size_str = f"{m['size'] / 1024 / 1024:.1f} MB" if m['size'] > 0 else "?"
            mod_rel = f"{cat}/{m['folder']}/"
            lines.append(f"| [{m['name']}]({cat}/{m['folder']}/) | `{m['filepath']}` | {size_str} |\n")
        lines.append("\n")

    lines.append("---\n")
    lines.append("\n*Gerado automaticamente por `tools/download_mod.py`.*\n")

    (FS22_DIR / "README.md").write_text("".join(lines), encoding="utf-8")
    print(f"  ✅  Updated fs22/README.md")


# ── Main ────────────────────────────────────────────────────────────────

def download_single_mod(url: str, dry_run: bool = False) -> dict | None:
    """Download a single mod. Returns info dict or None on failure."""
    zip_url, zip_filename = resolve_download_url(url)
    if not zip_url:
        return None

    cat = category_slug_from_mod_url(url)
    slug = slug_from_url(url)
    dest_dir = FS22_DIR / cat / slug
    dest_path = dest_dir / zip_filename

    if dry_run:
        print(f"  ℹ  [DRY-RUN] Would download: {dest_path.relative_to(BASE_DIR)}")
        return {
            "name": slug,
            "category": cat,
            "url": url,
            "filepath": str(dest_path.relative_to(BASE_DIR)),
        }

    downloaded = download_file(zip_url, dest_path)
    return {
        "name": slug,
        "category": cat,
        "url": url,
        "filepath": str(dest_path.relative_to(BASE_DIR)),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Download FS22 mods from fs22.com into fs22/<category>/<mod>/",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python download_mod.py --category trucks\n"
            "  python download_mod.py --category trucks --limit 5\n"
            "  python download_mod.py --category trucks --dry-run\n"
            "  python download_mod.py https://fs22.com/.../mod-name/\n"
            "  python download_mod.py --category-url https://fs22.com/category/.../trucks/\n"
        ),
    )
    parser.add_argument("url", nargs="?", help="Single mod page URL")
    parser.add_argument("--category", "-c", help="Download all mods from a category (trucks, tractors, maps, trailers, cars)")
    parser.add_argument("--category-url", help="Full URL to a category listing page")
    parser.add_argument("--limit", "-l", type=int, default=0, help="Max mods to download (default: all)")
    parser.add_argument("--dry-run", "-n", action="store_true", help="Preview only, no downloads")
    parser.add_argument("--list-urls", metavar="FILE", help="File with one mod URL per line")
    parser.add_argument("--delay", type=int, default=DELAY_BETWEEN_DOWNLOADS, help=f"Seconds between downloads (default: {DELAY_BETWEEN_DOWNLOADS})")
    parser.add_argument("--rescan", action="store_true", help="Re-scan fs22/ and regenerate README")

    args = parser.parse_args()

    if args.rescan:
        generate_fs22_readme()
        return

    urls = []

    if args.category:
        if args.category not in CATEGORY_PATHS:
            print(f"  ✖  Unknown category '{args.category}'. Available: {', '.join(CATEGORY_PATHS.keys())}")
            sys.exit(1)
        cat_url = f"{SITE}/{CATEGORY_PATHS[args.category]}"
        urls = scrape_category_urls(cat_url, limit=args.limit, dry_run=args.dry_run)
    elif args.category_url:
        urls = scrape_category_urls(args.category_url, limit=args.limit, dry_run=args.dry_run)
    elif args.list_urls:
        with open(args.list_urls, "r") as f:
            urls = [line.strip() for line in f if line.strip() and not line.startswith("#")]
        print(f"  ℹ  Loaded {len(urls)} URL(s) from {args.list_urls}")
    elif args.url:
        urls = [args.url]
    else:
        parser.print_help()
        print("\nError: Provide a mod URL, --category, --category-url, --list-urls, or --rescan")
        sys.exit(1)

    if not urls:
        print("  ℹ  No mods to download.")
        return

    if args.dry_run and not args.category and not args.category_url:
        print(f"\n  ℹ  [DRY-RUN] Would download 1 mod(s):")
        download_single_mod(urls[0], dry_run=True)
        print(f"\n  ✅  Dry-run complete.")
        return

    # Download each mod
    total = len(urls)
    downloaded_count = 0
    skipped_count = 0
    fail_count = 0
    results = []

    for i, url in enumerate(urls, 1):
        print(f"\n{'─'*50}")
        print(f"  [{i}/{total}] {url}")
        print(f"{'─'*50}")
        try:
            info = download_single_mod(url, dry_run=args.dry_run)
            if info:
                results.append(info)
                downloaded_count += 1
                if i < total:
                    time.sleep(args.delay)
        except Exception as e:
            print(f"  ✖  Error: {e}")
            fail_count += 1
            continue

    # Regenerate README
    if not args.dry_run:
        generate_fs22_readme()

    print(f"\n{'='*50}")
    print(f"  ✅  Complete!")
    print(f"     Downloaded: {downloaded_count}")
    if skipped_count:
        print(f"     Skipped (already exists): {skipped_count}")
    if fail_count:
        print(f"     Failed: {fail_count}")
    print(f"  📁  fs22/  ← mod files organized by category")
    print(f"{'='*50}")


if __name__ == "__main__":
    main()
