#!/usr/bin/env python3
"""
FS22 Mod Downloader — B.O.B's FS25 Mod Tool
============================================
Downloads mods from fs22.com and organizes them into ../fs22/<mod-name>/

Usage:
    python download_mod.py <mod-url>
    python download_mod.py https://fs22.com/farming-simulator-22-mods/trucks/renault-k480-v1-0/
    python download_mod.py --list-urls urls.txt

The script will:
  1. Fetch the mod page
  2. Find the download link (.attachment-link)
  3. Follow the redirect to the actual .zip file
  4. Save it in ../fs22/<mod-slug>/<filename>.zip
  5. Regenerate ../fs22/README.md with the updated mod list
"""

import argparse
import html.parser
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

# ── Config ──────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent.parent  # repo root
FS22_DIR = BASE_DIR / "fs22"
README_FILE = FS22_DIR / "README.md"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/120.0.0.0 Safari/537.36"
)

SITE_DOMAIN = "fs22.com"


# ── Helpers ─────────────────────────────────────────────────────────────

def fetch(url: str) -> str:
    """GET a URL and return its text body. Raises on HTTP error."""
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
        # Try UTF-8 first, fallback to Latin-1
        try:
            return body.decode("utf-8")
        except UnicodeDecodeError:
            return body.decode("latin-1")


def resolve_download_url(mod_page_url: str) -> tuple[str, str]:
    """
    Given a mod page URL on fs22.com, return (download_page_url, zip_filename).

    1. Fetches the mod page
    2. Finds the <a class="attachment-link" href="...">Download Name</a>
    3. Follows the download-page redirect to discover final .zip URL
    4. Extracts filename from Content-Disposition or URL path
    """
    print(f"  ℹ  Fetching mod page: {mod_page_url}")
    html = fetch(mod_page_url)

    # --- Find the attachment link ---
    parser = _AttachmentLinkParser()
    parser.feed(html)
    if not parser.download_url:
        print("  ✖  No attachment-link found on this page.")
        print("     Expected a <a class=\"attachment-link\" href=\"...\"> element.")
        sys.exit(1)

    dl_page_url = parser.download_url if parser.download_url.startswith("http") else f"https://{SITE_DOMAIN}{parser.download_url}"
    display_name = parser.link_text or os.path.basename(dl_page_url.rstrip("/"))

    print(f"  ℹ  Found download link: {dl_page_url}")
    print(f"  ℹ  Mod name: {display_name}")

    # --- Follow redirect to get actual .zip ---
    # We do a HEAD (or GET without body) to see the Location header
    req = urllib.request.Request(dl_page_url, method="HEAD", headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            zip_url = resp.geturl()  # Might already be the final URL after redirect
            # Check for content-disposition to get filename
            cd = resp.headers.get("Content-Disposition", "")
    except urllib.error.HTTPError as e:
        # Some servers don't support HEAD; fall back to GET with range=0-0
        req = urllib.request.Request(dl_page_url, headers={"User-Agent": USER_AGENT, "Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            zip_url = resp.geturl()
            cd = resp.headers.get("Content-Disposition", "")

    # If HEAD didn't follow redirect (302), do a GET
    if "/download-mod/" in zip_url:
        req = urllib.request.Request(dl_page_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=60) as resp:
            zip_url = resp.geturl()
            cd = resp.headers.get("Content-Disposition", "")

    print(f"  ℹ  Final .zip URL: {zip_url}")

    # Determine filename
    if cd and "filename=" in cd:
        # Content-Disposition: attachment; filename="FS22_RenaultK480_6x4.zip"
        match = re.search(r'filename=["\']?([^"\';\n]+)', cd)
        zip_filename = match.group(1).strip() if match else os.path.basename(urlparse(zip_url).path)
    else:
        zip_filename = os.path.basename(urlparse(zip_url).path)

    if not zip_filename or not zip_filename.endswith(".zip"):
        zip_filename = f"{display_name}.zip"

    # Clean filename
    zip_filename = re.sub(r'[^\w\.\-\(\) ]', '_', zip_filename)

    return zip_url, zip_filename, display_name


def download_file(url: str, dest: Path) -> None:
    """Download a file from url to dest path. Shows progress."""
    print(f"  ⬇  Downloading to: {dest}")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        total = int(resp.headers.get("Content-Length", 0))
        downloaded = 0
        chunk_size = 8192
        dest.parent.mkdir(parents=True, exist_ok=True)
        with open(dest, "wb") as f:
            while chunk := resp.read(chunk_size):
                f.write(chunk)
                downloaded += len(chunk)
                if total:
                    pct = downloaded * 100 / total
                    print(f"\r  ⬇  Progress: {downloaded / 1024:.0f} KB / {total / 1024:.0f} KB ({pct:.0f}%)", end="")
                else:
                    print(f"\r  ⬇  Downloaded: {downloaded / 1024:.0f} KB", end="")
                sys.stdout.flush()
        print()
    size_mb = dest.stat().st_size / (1024 * 1024)
    print(f"  ✅  Saved: {dest.name} ({size_mb:.1f} MB)")


def slug_from_url(url: str) -> str:
    """Extract a directory-friendly slug from the mod page URL."""
    path = urlparse(url).path.rstrip("/")
    # Take the last path segment
    last = path.split("/")[-1]
    if not last:
        last = path.split("/")[-2]
    # Remove common suffixes
    last = re.sub(r'-[vV]\d+[\d\.]*$', '', last)
    return last


def mod_title_from_html(html_content: str) -> str:
    """Extract the <title> tag content."""
    m = re.search(r'<title>([^<]+)</title>', html_content)
    if m:
        title = m.group(1).replace("&#8211;", "–").strip()
        title = html.unescape(title)
        return title
    return ""


def update_fs22_readme(mods: list[dict]) -> None:
    """Regenerate fs22/README.md with the current list of downloaded mods."""
    lines = [
        "# FS22 Original Mods\n",
        "\n",
        "Mods originais do **Farming Simulator 22** baixados como base para conversão ao FS25.\n",
        "\n",
        "---\n",
        "\n",
        "## 📦 Mods Disponíveis\n",
        "\n",
        "| Mod | Arquivo | Tamanho |\n",
        "|---|--------|--------|\n",
    ]
    for m in sorted(mods, key=lambda x: x["name"].lower()):
        zippath = Path(m["filepath"])
        rel = zippath.relative_to(FS22_DIR) if zippath.is_absolute() else zippath
        size = zippath.stat().st_size if zippath.exists() else 0
        size_str = f"{size / 1024 / 1024:.1f} MB" if size > 0 else "?"
        lines.append(f"| {m['name']} | `{rel}` | {size_str} |\n")

    lines.extend([
        "\n",
        "---\n",
        "\n",
        "*Gerado automaticamente por `tools/download_mod.py`.*\n",
    ])

    README_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(README_FILE, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"  ✅  Updated {README_FILE.relative_to(BASE_DIR)}")


def scan_existing_mods() -> list[dict]:
    """Scan fs22/ subdirectories for .zip files and return a mod list."""
    mods = []
    if not FS22_DIR.exists():
        return mods
    for entry in sorted(FS22_DIR.iterdir()):
        if entry.is_dir():
            for zipf in entry.glob("*.zip"):
                mods.append({
                    "name": entry.name,
                    "filepath": str(zipf),
                    "size": zipf.stat().st_size,
                })
        elif entry.suffix == ".zip":
            mods.append({
                "name": entry.stem,
                "filepath": str(entry),
                "size": entry.stat().st_size,
            })
    return mods


# ── HTML Parser ─────────────────────────────────────────────────────────

class _AttachmentLinkParser(html.parser.HTMLParser):
    """Minimal parser that finds the first <a class="attachment-link" ...>."""
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
            # We'll get the text in handle_data

    def handle_data(self, data):
        if self.download_url is not None and self.link_text is None:
            txt = data.strip()
            if txt:
                self.link_text = txt


# ── CLI ─────────────────────────────────────────────────────────────────

def download_single_mod(url: str) -> dict:
    """Download a single mod from its page URL."""
    print(f"\n{'='*60}")
    print(f"  MOD: {url}")
    print(f"{'='*60}")

    # Resolve download URL
    zip_url, zip_filename, display_name = resolve_download_url(url)

    # Determine output subfolder
    subfolder = slug_from_url(url)
    dest_dir = FS22_DIR / subfolder
    dest_path = dest_dir / zip_filename

    # Check if already downloaded
    if dest_path.exists():
        print(f"  ℹ  Already exists: {dest_path.relative_to(BASE_DIR)} ({dest_path.stat().st_size / 1024 / 1024:.1f} MB)")
    else:
        download_file(zip_url, dest_path)

    mod_info = {
        "name": display_name,
        "slug": subfolder,
        "filepath": str(dest_path),
        "url": url,
    }
    return mod_info


def download_from_urls_file(path: str) -> list[dict]:
    """Read URLs (one per line) from a file and download each."""
    with open(path, "r", encoding="utf-8") as f:
        urls = [line.strip() for line in f if line.strip() and not line.startswith("#")]
    print(f"  ℹ  Loaded {len(urls)} URL(s) from {path}")
    results = []
    for url in urls:
        info = download_single_mod(url)
        results.append(info)
    return results


def main():
    parser = argparse.ArgumentParser(
        description="Download FS22 mods from fs22.com into the fs22/ directory.",
        epilog="Examples:\n"
               "  python download_mod.py https://fs22.com/.../renault-k480-v1-0/\n"
               "  python download_mod.py --list-urls urls.txt\n"
               "  python download_mod.py --rescan\n",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("url", nargs="?", help="URL of an FS22 mod page on fs22.com")
    parser.add_argument("--list-urls", metavar="FILE",
                        help="File with one mod page URL per line")
    parser.add_argument("--rescan", action="store_true",
                        help="Re-scan fs22/ dir and regenerate README only (no download)")
    parser.add_argument("--repo-root", metavar="PATH",
                        help="Override repo root (default: parent of tools/)")

    args = parser.parse_args()

    # Allow overriding repo root (useful when script is called from elsewhere)
    global BASE_DIR, FS22_DIR, README_FILE
    if args.repo_root:
        BASE_DIR = Path(args.repo_root).resolve()
        FS22_DIR = BASE_DIR / "fs22"
        README_FILE = FS22_DIR / "README.md"

    if args.rescan:
        print("  ℹ  Re-scanning fs22/ directory...")
        mods = scan_existing_mods()
        update_fs22_readme(mods)
        print(f"  ✅  Found {len(mods)} mod(s) in fs22/")
        return

    urls = []
    if args.list_urls:
        urls = _read_urls_from_file(args.list_urls)
    elif args.url:
        urls = [args.url]
    else:
        parser.print_help()
        print("\nError: Provide a mod URL, --list-urls, or --rescan")
        sys.exit(1)

    all_mods = []
    for url in urls:
        info = download_single_mod(url)
        all_mods.append(info)

    # Regenerate README
    existing = scan_existing_mods()
    # Merge: keep existing + newly downloaded (avoid duplicates by filepath)
    existing_paths = {m["filepath"] for m in existing}
    for info in all_mods:
        if info["filepath"] not in existing_paths:
            existing.append(info)
            existing_paths.add(info["filepath"])
    update_fs22_readme(existing)

    print(f"\n  ✅  Done! {len(all_mods)} mod(s) downloaded.")
    print(f"  📁  fs22/  ← mod files")
    print(f"  📄  fs22/README.md  ← auto-generated listing")


def _read_urls_from_file(path: str) -> list[str]:
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]


if __name__ == "__main__":
    main()
