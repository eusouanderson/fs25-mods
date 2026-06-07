#!/usr/bin/env python3
"""
FS22→FS25 Mod Conversion MCP Server
=====================================
Unified MCP server wrapping all FS25 mod tools for opencode.
Handles: search, download, validate, convert, release.

Usage:
    python mcp_server.py        # Start MCP server (stdin/stdout JSON-RPC)
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from urllib.parse import urlparse, quote

# Lazy imports: numpy and PIL are only needed for resize_icon tool
# Imported inside the icon functions to avoid crashing if not installed

# ── Paths ─────────────────────────────────────────────────────────────────────

TOOLS_DIR = Path(__file__).resolve().parent
BASE_DIR = TOOLS_DIR.parent
DB_PATH = TOOLS_DIR / "fs25-mods-db.json"
FS25_DIR = BASE_DIR / "fs25" / "trucks"
REPO = "eusouanderson/fs25-mods"
CATEGORIES = ("trucks", "tractors", "trailers", "maps", "cars", "other")

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
SEARCH_URL = "https://www.fs25.net/?s={query}"

EXCLUDE_PATTERNS = (".git", "__pycache__", "*.pyc", ".DS_Store", "*.bak", "Thumbs.db", "desktop.ini")
EXCLUDE_DIRS = {"backups", "validator", ".sisyphus"}


# ── Helpers ───────────────────────────────────────────────────────────────────

def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read()
        try:
            return body.decode("utf-8")
        except UnicodeDecodeError:
            return body.decode("latin-1")


def load_db() -> dict:
    if not DB_PATH.exists():
        return {"mods": []}
    return json.loads(DB_PATH.read_text(encoding="utf-8"))


def save_db(db: dict):
    DB_PATH.write_text(json.dumps(db, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def _base_slug(tag: str) -> str:
    slug = tag
    while "-v" in slug:
        parts = slug.rsplit("-v", 1)
        if parts[1] and parts[1][0].isdigit():
            slug = parts[0]
        else:
            break
    return slug


def run_gh(args: list[str]) -> str:
    cmd = ["gh", "-R", REPO] + args
    r = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)
    return r.stdout.strip()


def fetch_github_releases() -> list[dict]:
    try:
        result = subprocess.run(
            ["gh", "-R", REPO, "release", "list", "--limit", "50",
             "--json", "tagName,createdAt"],
            capture_output=True, text=True, check=True, timeout=30,
        )
        releases = json.loads(result.stdout)
        for r in releases:
            r["url"] = f"https://github.com/{REPO}/releases/tag/{r['tagName']}"
        return releases
    except Exception:
        return []


# ── Search / DB ───────────────────────────────────────────────────────────────

def search_local(db: dict, query: str) -> list[dict]:
    q = query.lower()
    results = []
    for mod in db.get("mods", []):
        terms = [mod.get("name", "").lower(), mod.get("manufacturer", "").lower(),
                 mod.get("slug", "").lower(), mod.get("description", "").lower()]
        terms.extend(t.lower() for t in mod.get("search_terms", []))
        combined = " ".join(terms)
        if q in combined or any(word in combined for word in q.split()):
            if mod not in results:
                results.append(mod)
    return results


# ── fs25.net Search/Download ─────────────────────────────────────────────────

def search_fs25net(query: str) -> list[dict]:
    url = SEARCH_URL.format(query=quote(query))
    try:
        html = fetch(url)
    except Exception:
        return []
    results = []
    for m in re.finditer(r'href="([^"]+)"\s*rel="bookmark"', html):
        results.append({"url": m.group(1), "query": query})
    titles = re.findall(r'<a[^>]*href="([^"]+)"[^>]*rel="bookmark"[^>]*>([^<]+)</a>', html)
    title_map = {t[0]: t[1].strip() for t in titles}
    for r in results:
        r["title"] = title_map.get(r["url"], "")
    return results


def extract_download_urls(mod_page_url: str) -> list[str]:
    html = fetch(mod_page_url)
    urls = []
    for m in re.finditer(r'href="([^"]*download-mod/[^"]+)"[^>]*class="[^"]*attachment-link', html):
        u = m.group(1)
        if u not in urls:
            urls.append(u)
    for m in re.finditer(r'class="[^"]*attachment-link[^"]*"[^>]*href="([^"]+)"', html):
        u = m.group(1)
        if u not in urls:
            urls.append(u)
    for m in re.finditer(r'href="([^"]+\.zip)"', html):
        u = m.group(1)
        if u not in urls:
            urls.append(u)
    return urls


def resolve_download_url(dl_page_url: str) -> tuple[str, str]:
    if not dl_page_url.startswith("http"):
        dl_page_url = f"https://fs25.net{dl_page_url}"
    req = urllib.request.Request(dl_page_url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        zip_url = resp.geturl()
        cd = resp.headers.get("Content-Disposition", "")
    zip_filename = ""
    if cd and "filename=" in cd:
        m = re.search(r'filename=["\']?([^"\';\n]+)', cd)
        if m:
            zip_filename = m.group(1).strip()
    if not zip_filename:
        zip_filename = os.path.basename(urlparse(zip_url).path)
    if not zip_filename or not zip_filename.endswith(".zip"):
        zip_filename = f"{urlparse(dl_page_url).path.rstrip('/').split('/')[-1]}.zip"
    zip_filename = re.sub(r'[^\w\.\-\(\) ]', '_', zip_filename)
    return zip_url, zip_filename


def download_zip(url: str, dest: Path) -> bool:
    if dest.exists():
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        with open(dest, "wb") as f:
            while chunk := resp.read(8192):
                f.write(chunk)
    return True


# ── Mod Info / Validation ─────────────────────────────────────────────────────

def read_moddesc(mod_dir: Path) -> str | None:
    md = mod_dir / "modDesc.xml"
    return md.read_text(encoding="utf-8") if md.exists() else None


def get_tag(content: str, tag: str) -> str:
    m = re.search(rf"<{tag}[^>]*>([^<]+)</{tag}>", content)
    return m.group(1).strip() if m else ""


def get_l10n(content: str, tag: str, lang: str = "en") -> str:
    m = re.search(rf"<{tag}[^>]*>\s*<{lang}[^>]*>(.*?)</{lang}>", content, re.DOTALL)
    if m:
        return m.group(1).strip()[:100]
    m = re.search(rf"<{tag}[^>]*>(.*?)</{tag}>", content, re.DOTALL)
    return m.group(1).strip()[:100] if m else ""


# ── Icon Conversion ───────────────────────────────────────────────────────────

def _ensure_img_libs():
    global np, Image
    if 'np' not in globals() or 'Image' not in globals():
        import numpy as _np
        from PIL import _Image
        globals()['np'] = _np
        globals()['Image'] = _Image


def _to_int(v):
    _ensure_img_libs()
    return int(v) if not isinstance(v, (int, np.integer)) else int(v)


def rgb_to_565(r, g, b):
    r, g, b = _to_int(r), _to_int(g), _to_int(b)
    return ((r * 31 + 127) // 255 << 11) | ((g * 63 + 127) // 255 << 5) | ((b * 31 + 127) // 255)


def color_dist_565(c1, c2):
    dr = (((c1 >> 11) & 0x1F) - ((c2 >> 11) & 0x1F)) * 255 // 31
    dg = (((c1 >> 5) & 0x3F) - ((c2 >> 5) & 0x3F)) * 255 // 63
    db = ((c1 & 0x1F) - (c2 & 0x1F)) * 255 // 31
    return dr * dr + dg * dg + db * db


def lerp_color(c0, c1, t):
    r0, g0, b0 = (c0 >> 11) & 0x1F, (c0 >> 5) & 0x3F, c0 & 0x1F
    r1, g1, b1 = (c1 >> 11) & 0x1F, (c1 >> 5) & 0x3F, c1 & 0x1F
    return ((r0 + (r1 - r0) * t // 3) << 11) | ((g0 + (g1 - g0) * t // 3) << 5) | (b0 + (b1 - b0) * t // 3)


def pack_block_dxt5(pixels):
    _ensure_img_libs()
    pixels = np.asarray(pixels, dtype=np.uint8)
    flat = pixels.reshape(-1, 4)
    a_ch = flat[:, 3].astype(np.int32)
    min_a, max_a = int(a_ch.min()), int(a_ch.max())
    if max_a == min_a:
        a1, a2 = min_a, max_a
        a_vals = [min_a] * 8
        alpha_endpoints = struct.pack("<BB", a1, a2)
    elif min_a < max_a:
        a1, a2 = max_a, min_a
        alpha_endpoints = struct.pack("<BB", a1, a2)
        a_vals = [a1, a2] + [(6 * a1 + 1 * a2 + 3) // 7, (5 * a1 + 2 * a2 + 3) // 7,
                             (4 * a1 + 3 * a2 + 3) // 7, (3 * a1 + 4 * a2 + 3) // 7,
                             (2 * a1 + 5 * a2 + 3) // 7, (1 * a1 + 6 * a2 + 3) // 7]
    else:
        a1, a2 = max_a, min_a
        alpha_endpoints = struct.pack("<BB", a1, a2)
        a_vals = [a1, a2, (4 * a1 + 1 * a2 + 2) // 5, (3 * a1 + 2 * a2 + 2) // 5,
                  (2 * a1 + 3 * a2 + 2) // 5, (1 * a1 + 4 * a2 + 2) // 5, 0, 255]
    alpha_bits = 0
    for i in range(16):
        alpha_bits = (alpha_bits << 3) | min(range(8), key=lambda j: abs(int(flat[i, 3]) - a_vals[j]))
    alpha_bytes = alpha_endpoints + struct.pack("<Q", alpha_bits)[:6]
    c_vals = [rgb_to_565(int(flat[i, 0]), int(flat[i, 1]), int(flat[i, 2])) for i in range(16)]
    c0, c1 = min(c_vals), max(c_vals)
    if c0 == c1:
        c0, c1 = 0, 0xFFFF
    is_3c = c0 <= c1
    palette = [c0, c1, lerp_color(c0, c1, 1), lerp_color(c0, c1, 2)] if is_3c else [c1, c0, lerp_color(c1, c0, 2), lerp_color(c1, c0, 1)]
    color_bits = 0
    for i in range(16):
        best = min(range(4), key=lambda j: color_dist_565(c_vals[i], palette[j]))
        color_bits = (color_bits << 2) | (best if not (is_3c and best == 3) else 1)
    return alpha_bytes + struct.pack("<HH", c0, c1) + struct.pack("<I", color_bits)


def compress_dxt5(img_array):
    _ensure_img_libs()
    h, w = img_array.shape[:2]
    if w % 4 or h % 4:
        pil = Image.fromarray(img_array)
        img_array = np.asarray(pil.resize(((w + 3) & ~3, (h + 3) & ~3), Image.LANCZOS))
        w, h = img_array.shape[1], img_array.shape[0]
    data = b"".join(pack_block_dxt5(img_array[by:by + 4, bx:bx + 4]) for by in range(0, h, 4) for bx in range(0, w, 4))
    return data, w, h, ((w + 3) // 4) * ((h + 3) // 4) * 16


def write_dds(filepath, img_array):
    _ensure_img_libs()
    import struct
    if img_array.shape[2] == 3:
        img_array = np.concatenate([img_array, np.full((img_array.shape[0], img_array.shape[1], 1), 255, dtype=np.uint8)], axis=2)
    data, w, h, pitch = compress_dxt5(img_array)
    header = struct.pack("<4sIIIIIIIIIIII11IIII4sIIIIIIIIIII",
                         b"DDS ", 124, 0x00021007, h, w, pitch, 0, 0,
                         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                         32, 0x00000004, b"DXT5", 0, 0, 0, 0, 0,
                         0x00001000, 0, 0, 0, 0)
    with open(filepath, "wb") as f:
        f.write(header)
        f.write(data)


# ── ZIP / Release ─────────────────────────────────────────────────────────────

def estimate_dir_size(path: Path) -> int:
    total = 0
    for f in path.rglob("*"):
        if not f.is_file() or any(f.match(p) for p in EXCLUDE_PATTERNS):
            continue
        if EXCLUDE_DIRS & set(f.relative_to(path).parts):
            continue
        total += f.stat().st_size
    return total


def create_zip(source_dir: Path, output_path: Path):
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for file_path in source_dir.rglob("*"):
            if file_path.is_dir():
                continue
            rel = file_path.relative_to(source_dir)
            if any(file_path.match(p) for p in EXCLUDE_PATTERNS):
                continue
            if ".git" in rel.parts or EXCLUDE_DIRS & set(rel.parts):
                continue
            zf.write(file_path, arcname=rel)
    return output_path


def release_exists(tag: str) -> bool:
    try:
        subprocess.run(["gh", "-R", REPO, "release", "view", tag], capture_output=True, check=True, timeout=15)
        return True
    except subprocess.CalledProcessError:
        return False


# ── fs22.com Download ──────────────────────────────────────────────────────────

SITE_22 = "https://fs22.com"
CATEGORY_PATHS_22 = {
    "trucks":   "category/farming-simulator-22-mods/trucks/",
    "tractors": "category/farming-simulator-22-mods/tractors/",
    "trailers": "category/farming-simulator-22-mods/trailers/",
    "maps":     "category/farming-simulator-22-mods/maps/",
    "cars":     "category/farming-simulator-22-mods/cars/",
}
FS22_DIR = BASE_DIR / "fs22"


def extract_mod_links_22(html: str) -> list[str]:
    urls = []
    for m in re.finditer(r'<a[^>]*href="([^"]+)"[^>]*rel="bookmark"', html):
        url = m.group(1)
        if url not in urls:
            urls.append(url)
    return urls


def get_total_pages_22(html: str) -> int:
    pages = []
    for m in re.finditer(r'/page/(\d+)/"[^>]*>(\d+)</a>', html):
        pages.append(int(m.group(1)))
    return max(pages) if pages else 1


def scrape_category_urls_22(category_url: str, limit: int = 0) -> list[str]:
    html = fetch(category_url)
    total_pages = get_total_pages_22(html)
    all_urls = extract_mod_links_22(html)
    for page in range(2, total_pages + 1):
        if limit and len(all_urls) >= limit:
            break
        try:
            page_html = fetch(f"{category_url.rstrip('/')}/page/{page}/")
            links = extract_mod_links_22(page_html)
            if not links:
                break
            all_urls.extend(links)
            if limit:
                all_urls = all_urls[:limit]
        except Exception:
            continue
    if limit:
        all_urls = all_urls[:limit]
    return all_urls


def resolve_download_url_22(mod_page_url: str) -> tuple[str, str]:
    html = fetch(mod_page_url)
    dl_page_url = ""
    for m in re.finditer(r'href="([^"]*)"[^>]*class="[^"]*attachment-link[^"]*"', html):
        dl_page_url = m.group(1)
        break
    if not dl_page_url:
        for m in re.finditer(r'class="[^"]*attachment-link[^"]*"[^>]*href="([^"]+)"', html):
            dl_page_url = m.group(1)
            break
    if not dl_page_url:
        return "", ""
    dl_page_url = dl_page_url if dl_page_url.startswith("http") else f"{SITE_22}{dl_page_url}"
    req = urllib.request.Request(dl_page_url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            zip_url = resp.geturl()
            cd = resp.headers.get("Content-Disposition", "")
    except urllib.error.HTTPError:
        req = urllib.request.Request(dl_page_url, headers={"User-Agent": USER_AGENT, "Range": "bytes=0-0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            zip_url = resp.geturl()
            cd = resp.headers.get("Content-Disposition", "")
    zip_filename = ""
    if cd and "filename=" in cd:
        m = re.search(r'filename=["\']?([^"\';\n]+)', cd)
        if m:
            zip_filename = m.group(1).strip()
    if not zip_filename:
        zip_filename = os.path.basename(urlparse(zip_url).path)
    if not zip_filename or not zip_filename.endswith(".zip"):
        zip_filename = f"{urlparse(dl_page_url).path.rstrip('/').split('/')[-1]}.zip"
    zip_filename = re.sub(r'[^\w\.\-\(\) ]', '_', zip_filename)
    return zip_url, zip_filename


def slug_from_url_22(url: str) -> str:
    path = urlparse(url).path.rstrip("/")
    segments = [s for s in path.split("/") if s]
    return segments[-1].lower() if segments else "mod"


def category_from_url_22(url: str) -> str:
    path = urlparse(url).path.rstrip("/")
    for cat in CATEGORY_PATHS_22:
        if f"/{cat}/" in path:
            return cat
    return "other"


def scan_fs22_mods_22() -> dict[str, list[dict]]:
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
                        "name": entry.name, "folder": entry.name,
                        "filepath": str(zipf.relative_to(FS22_DIR)),
                        "size_mb": round(zipf.stat().st_size / (1024*1024), 1),
                    })
                    break
        if mods:
            categories[cat_dir.name] = mods
    return categories


def generate_fs22_readme_22() -> str:
    categories = scan_fs22_mods_22()
    lines = ["# FS22 Original Mods\n\nMods originais do **Farming Simulator 22** baixados como base para conversão ao FS25.\n\n---\n\n"]
    for cat in sorted(categories.keys()):
        lines.append(f"## {cat.capitalize()}\n\n| Mod | Arquivo | Tamanho |\n|---|---|---|\n")
        for m in sorted(categories[cat], key=lambda x: x["name"].lower()):
            lines.append(f"| [{m['name']}]({cat}/{m['folder']}/) | `{m['filepath']}` | {m['size_mb']} MB |\n")
        lines.append("\n")
    lines.append("---\n*Gerado automaticamente.*\n")
    (FS22_DIR / "README.md").write_text("".join(lines), encoding="utf-8")
    return "".join(lines)


# ── Deploy helpers ─────────────────────────────────────────────────────────────

GAME_MODS_DIR = Path("/mnt/g/Users/Administrador/Documents/My Games/FarmingSimulator2025/mods")


def find_mod_in_repo(query: str) -> Path | None:
    query_l = query.lower()
    for base in (BASE_DIR / "fs25", BASE_DIR / "fs22"):
        if not base.exists():
            continue
        for cat_dir in base.iterdir():
            if not cat_dir.is_dir():
                continue
            for mod_dir in cat_dir.iterdir():
                if mod_dir.is_dir() and query_l in mod_dir.name.lower():
                    return mod_dir
    return None


# ── fs25.net predefined trucks ─────────────────────────────────────────────────

ALL_TRUCKS_25 = [
    "Chevrolet Brasil 3100", "Chevrolet C-60", "Chevrolet D-60", "Chevrolet C-65",
    "Ford F-600", "Ford F-700", "Ford F-11000", "Ford F-4000", "Ford Cargo",
    "Mercedes L-312", "Mercedes L-1111", "Mercedes L-1113", "Mercedes L-1519",
    "Mercedes L-2013", "Mercedes L-1513",
    "Scania L75", "Scania L110", "Scania 111", "Scania 112", "Scania 113",
    "Volvo N10", "Volvo N12", "Volvo F10", "Volvo F12",
    "Mercedes 1113", "Mercedes 1313", "Mercedes 1513", "Mercedes 1519",
    "Mercedes 1935", "Mercedes 2213", "Mercedes 1620",
    "VW 7-110", "VW 8-150", "VW 9-150", "VW 13-130", "VW 18-310",
    "VW Constellation 24-250",
    "Iveco Eurocargo", "Iveco Stralis", "Iveco Cursor",
    "Scania 124", "Scania 114", "Scania P", "Scania G", "Scania R",
    "Volvo FH12", "Volvo FH16", "Volvo FM12", "Volvo VM",
    "VW Constellation 17-190", "VW Constellation 24-280", "VW Meteor 28-460",
    "VW e-Delivery",
    "Mercedes Actros", "Mercedes Atego", "Mercedes Arocs", "Mercedes Accelo",
    "Volvo FH", "Volvo FMX", "Volvo FM", "Volvo VNL",
    "DAF XF", "DAF CF", "DAF LF",
    "Iveco S-Way", "Iveco Hi-Way", "Iveco Daily",
]


def slug_from_name_25(name: str) -> str:
    return re.sub(r'[^a-z0-9\-]', '', name.lower().replace(" ", "-"))


def add_to_db_25(name: str, slug: str, manufacturer: str, dl_url: str):
    db = load_db()
    if slug in {m["slug"] for m in db["mods"]}:
        return
    db["mods"].append({
        "name": name, "slug": slug, "category": "trucks", "manufacturer": manufacturer,
        "converted": True, "converted_by": "?", "version": "?",
        "release_url": dl_url, "original_author": "?", "original_game": "FS22",
        "type": "truck", "description": f"{manufacturer} {name} — FS25",
        "search_terms": name.lower().split() + manufacturer.lower().split(),
        "added": time.strftime("%Y-%m-%d"),
    })
    save_db(db)


# ── New Tool handlers ──────────────────────────────────────────────────────────

def tool_download_fs22_mod(params: dict) -> dict:
    url = params.get("url", "")
    if not url:
        return {"error": "url parameter is required"}
    zip_url, zip_filename = resolve_download_url_22(url)
    if not zip_url:
        return {"error": "No download link found on page"}
    cat = category_from_url_22(url)
    slug = slug_from_url_22(url)
    dest_dir = FS22_DIR / cat / slug
    dest_path = dest_dir / zip_filename
    if dest_path.exists():
        return {"message": "Already exists", "filepath": str(dest_path.relative_to(BASE_DIR)), "size_mb": round(dest_path.stat().st_size / (1024*1024), 1)}
    dest_dir.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(zip_url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        with open(dest_path, "wb") as f:
            while chunk := resp.read(8192):
                f.write(chunk)
    generate_fs22_readme_22()
    return {
        "filepath": str(dest_path.relative_to(BASE_DIR)),
        "size_mb": round(dest_path.stat().st_size / (1024*1024), 1),
        "category": cat,
        "slug": slug,
    }


def tool_download_fs22_category(params: dict) -> dict:
    category = params.get("category", "")
    limit = params.get("limit", 0)
    if not category or category not in CATEGORY_PATHS_22:
        return {"error": f"Invalid category '{category}'. Available: {', '.join(CATEGORY_PATHS_22.keys())}"}
    cat_url = f"{SITE_22}/{CATEGORY_PATHS_22[category]}"
    urls = scrape_category_urls_22(cat_url, limit=limit)
    if not urls:
        return {"error": f"No mods found for category '{category}'"}
    results = []
    for i, url in enumerate(urls):
        try:
            zip_url, zip_filename = resolve_download_url_22(url)
            if not zip_url:
                continue
            slug = slug_from_url_22(url)
            dest_dir = FS22_DIR / category / slug
            dest_path = dest_dir / zip_filename
            if dest_path.exists():
                results.append({"url": url, "slug": slug, "status": "exists"})
                continue
            dest_dir.mkdir(parents=True, exist_ok=True)
            req = urllib.request.Request(zip_url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=120) as resp:
                with open(dest_path, "wb") as f:
                    while chunk := resp.read(8192):
                        f.write(chunk)
            results.append({"url": url, "slug": slug, "status": "downloaded", "size_mb": round(dest_path.stat().st_size / (1024*1024), 1)})
        except Exception as e:
            results.append({"url": url, "status": "error", "error": str(e)})
    generate_fs22_readme_22()
    return {"category": category, "total": len(urls), "downloaded": len([r for r in results if r["status"] == "downloaded"]), "results": results}


def tool_scan_fs22_mods(params: dict) -> dict:
    readme = generate_fs22_readme_22()
    categories = scan_fs22_mods_22()
    return {
        "categories": {k: len(v) for k, v in categories.items()},
        "total_mods": sum(len(v) for v in categories.values()),
        "message": "fs22/README.md regenerated",
    }


def tool_search_download_fs25(params: dict) -> dict:
    query = params.get("query", "")
    if not query:
        return {"error": "query parameter is required"}
    results = search_fs25net(query)
    if not results:
        return {"error": f"No results found for: {query}"}
    downloaded = []
    for r in results:
        try:
            dl_pages = extract_download_urls(r["url"])
            if not dl_pages:
                continue
            slug = r["url"].rstrip("/").split("/")[-1]
            title = r.get("title", "") or slug
            for dl_page in dl_pages:
                zip_url, zip_name = resolve_download_url(dl_page)
                if not zip_url:
                    continue
                dest = FS25_DIR / slug / zip_name
                if download_zip(zip_url, dest):
                    manufacturer = query.split()[0] if query.split() else "?"
                    add_to_db_25(title, slug, manufacturer, zip_url)
                    downloaded.append({"title": title, "slug": slug, "file": zip_name, "size_mb": round(dest.stat().st_size / (1024*1024), 1)})
        except Exception:
            continue
    return {"query": query, "total_found": len(results), "downloaded": downloaded}


def tool_list_missing_fs25(params: dict) -> dict:
    db = load_db()
    db_slugs = {m["slug"] for m in db["mods"]}
    missing = []
    for truck in ALL_TRUCKS_25:
        slug = slug_from_name_25(truck)
        if slug not in db_slugs:
            missing.append({"name": truck, "slug": slug})
    return {"total_missing": len(missing), "total_all": len(ALL_TRUCKS_25), "missing": missing}


def tool_deploy_mod(params: dict) -> dict:
    source = params.get("source", "")
    destination = params.get("destination", "game")
    if not source:
        return {"error": "source parameter is required"}
    if destination not in ("game", "repo"):
        return {"error": "destination must be 'game' or 'repo'"}
    source_path = Path(source).resolve()
    if not source_path.exists():
        source_path = find_mod_in_repo(source)
        if not source_path:
            return {"error": f"Source not found: {source}"}
    if destination == "game":
        target = GAME_MODS_DIR / source_path.name
    else:
        target = find_mod_in_repo(source_path.name)
        if not target:
            return {"error": f"Could not find matching mod in repo for '{source_path.name}'"}
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(source_path, target, ignore=shutil.ignoring_patterns("__pycache__", "*.pyc", ".git"))
    size = sum(f.stat().st_size for f in target.rglob("*") if f.is_file()) / (1024 * 1024)
    return {
        "source": str(source_path),
        "target": str(target),
        "size_mb": round(size, 1),
        "message": f"Copied {source_path.name} to {'game mods' if destination == 'game' else 'repo'}",
    }

def tool_search_mods(params: dict) -> dict:
    query = params.get("query", "")
    manufacturer = params.get("manufacturer")
    db_only = params.get("db_only", False)
    if not query:
        return {"error": "query parameter is required"}
    db = load_db()
    local_results = search_local(db, query)
    if manufacturer:
        mq = manufacturer.lower()
        local_results = [m for m in local_results if m.get("manufacturer", "").lower() == mq]
    result = {"local": local_results, "github": [], "total_local": len(local_results)}
    if not db_only:
        releases = fetch_github_releases()
        if releases:
            known = {_base_slug(m["slug"]) for m in db["mods"]}
            result["github"] = [r for r in search_github(releases, query) if _base_slug(r["tagName"]) not in known]
    return result


def search_github(releases: list[dict], query: str) -> list[dict]:
    q = query.lower()
    return [r for r in releases if q in r["tagName"].lower() or q in r.get("name", "").lower() or any(w in r["tagName"].lower() for w in q.split())]


def tool_list_mods(params: dict) -> dict:
    manufacturer = params.get("manufacturer")
    db = load_db()
    mods = db["mods"]
    if manufacturer:
        mods = [m for m in mods if m.get("manufacturer", "").lower() == manufacturer.lower()]
    return {"mods": mods, "total": len(mods)}


def tool_list_categories(params: dict) -> dict:
    db = load_db()
    cats = {}
    for m in db["mods"]:
        cats[m.get("category", "other")] = cats.get(m.get("category", "other"), 0) + 1
    return {"categories": cats}


def tool_sync_mods(params: dict) -> dict:
    releases = fetch_github_releases()
    if not releases:
        return {"error": "Could not fetch GitHub releases. Is `gh` CLI installed?"}
    db = load_db()
    known = {_base_slug(m["slug"]) for m in db["mods"]}
    added, seen = 0, set()
    for r in releases:
        tag = r["tagName"]
        base = _base_slug(tag)
        if base in known or base in seen:
            continue
        seen.add(base)
        version = tag.rsplit("-v", 1)[1] if "-v" in tag else "?"
        db["mods"].append({
            "name": base.replace("-", " ").title().replace("Fs25", "FS25"),
            "slug": base, "category": "other", "manufacturer": "?",
            "converted": True, "converted_by": "?", "version": version,
            "release_url": f"https://github.com/{REPO}/releases/tag/{tag}",
            "original_author": "?", "original_game": "FS22",
            "search_terms": base.split("-"), "added": r.get("createdAt", "?")[:10],
        })
        added += 1
    if added:
        save_db(db)
    return {"added": added}


def tool_search_fs25_net(params: dict) -> dict:
    query = params.get("query", "")
    if not query:
        return {"error": "query parameter is required"}
    results = search_fs25net(query)
    return {"results": results, "total": len(results)}


def tool_download_mod(params: dict) -> dict:
    url = params.get("url", "")
    if not url:
        return {"error": "url parameter is required"}

    slug = url.rstrip("/").split("/")[-1]
    dl_pages = extract_download_urls(url)
    if not dl_pages:
        return {"error": "No download link found on page"}

    downloaded = []
    for dl_page in dl_pages:
        try:
            zip_url, zip_name = resolve_download_url(dl_page)
            dest = FS25_DIR / slug / zip_name
            if download_zip(zip_url, dest):
                downloaded.append({"file": zip_name, "size_mb": round(dest.stat().st_size / (1024*1024), 1)})
        except Exception as e:
            continue

    if not downloaded:
        return {"error": "Failed to download"}

    db = load_db()
    existing = {m["slug"] for m in db["mods"]}
    if slug not in existing:
        title = slug.replace("-", " ").title()
        manufacturer = slug.split("-")[0].title() if slug else "?"
        db["mods"].append({
            "name": title, "slug": slug, "category": "trucks", "manufacturer": manufacturer,
            "converted": True, "converted_by": "?", "version": "?",
            "release_url": url, "original_author": "?", "original_game": "FS22",
            "type": "truck", "description": f"{manufacturer} {title} — FS25",
            "search_terms": title.lower().split() + manufacturer.lower().split(),
            "added": time.strftime("%Y-%m-%d"),
        })
        save_db(db)

    return {"downloaded": downloaded}


def tool_get_mod_info(params: dict) -> dict:
    path = params.get("path", "")
    if not path:
        return {"error": "path parameter is required"}
    mod_dir = Path(path).resolve()
    if not mod_dir.exists() or not mod_dir.is_dir():
        return {"error": f"Directory not found: {mod_dir}"}

    content = read_moddesc(mod_dir)
    if not content:
        return {"error": "modDesc.xml not found in directory"}

    size = sum(f.stat().st_size for f in mod_dir.rglob("*") if f.is_file()) / (1024 * 1024)
    files = len([f for f in mod_dir.rglob("*") if f.is_file()])

    return {
        "name": mod_dir.name,
        "title": get_l10n(content, "title", "en"),
        "title_pt": get_l10n(content, "title", "pt") or get_l10n(content, "title", "br"),
        "description": get_l10n(content, "description", "en"),
        "author": get_tag(content, "author"),
        "version": get_tag(content, "version"),
        "descVersion": int(m.group(1)) if (m := re.search(r'<modDesc\s+descVersion="(\d+)"', content)) else None,
        "storeItems": bool(re.search(r'storeItems\s+xmlFilename=', content)),
        "size_mb": round(size, 1),
        "file_count": files,
    }


def tool_validate_mod(params: dict) -> dict:
    path = params.get("path", "")
    if not path:
        return {"error": "path parameter is required"}
    mod_dir = Path(path).resolve()
    if not mod_dir.exists() or not mod_dir.is_dir():
        return {"error": f"Directory not found: {mod_dir}"}

    content = read_moddesc(mod_dir)
    if not content:
        return {"error": "modDesc.xml not found"}

    issues = []
    m = re.search(r"<version>([^<]+)</version>", content)
    if m:
        ver = m.group(1).strip()
        if not re.match(r"^\d+(\.\d+){0,3}$", ver):
            issues.append({"severity": "error", "message": f"Invalid version: '{ver}'"})
        if ver.count(".") > 3:
            issues.append({"warning": True, "message": f"Version has {ver.count('.')+1} parts"})
    else:
        issues.append({"severity": "error", "message": "Missing <version> tag"})

    m = re.search(r'<modDesc\s+descVersion="(\d+)"', content)
    if m and int(m.group(1)) < 101:
        issues.append({"severity": "warning", "message": f"descVersion={m.group(1)} should be 101+"})
    if not m:
        issues.append({"severity": "warning", "message": "Missing descVersion attribute"})

    for tag in ["title", "description", "author"]:
        if not re.search(rf"<{tag}[>\s]", content):
            issues.append({"severity": "warning", "message": f"Missing <{tag}> tag"})

    fs22_patterns = [
        (r"specialization.*fillUnit", "fillUnit specialization — FS25 uses fillUnit directly"),
        (r"specialization.*attachable", "attachable specialization — check if FS25 compatible"),
        (r"specialization.*baleWrapper", "baleWrapper specialization — verify FS25 compatibility"),
        (r"specialization.*concreteMixer", "concreteMixer specialization — verify FS25 compatibility"),
        (r"specialization.*logistics", "logistics specialization — may need FS25 update"),
    ]
    for pattern, desc in fs22_patterns:
        if re.search(pattern, content):
            issues.append({"severity": "info", "message": f"FS22 pattern found: {desc}"})

    i3d_matches = list(mod_dir.rglob("*.i3d"))
    if i3d_matches:
        issues.append({"severity": "info", "message": f"Found {len(i3d_matches)} .i3d file(s)"})

    shapes = list(mod_dir.rglob("*.i3d.shapes"))
    if not shapes:
        issues.append({"severity": "warning", "message": "No .i3d.shapes files found (may cause collision issues)"})

    return {
        "mod_name": mod_dir.name,
        "issues": issues,
        "issue_count": len(issues),
        "errors": len([i for i in issues if i.get("severity") == "error"]),
        "warnings": len([i for i in issues if i.get("severity") == "warning"]),
    }


def tool_resize_icon(params: dict) -> dict:
    _ensure_img_libs()
    input_path = params.get("input", "")
    output_path = params.get("output", "")
    icon_type = params.get("type", "icon")

    if not input_path or not output_path:
        return {"error": "input and output parameters are required"}

    sizes = {"icon": (512, 512), "brand": (512, 256), "store": (512, 512)}
    target = sizes.get(icon_type, (512, 512))

    inp = Path(input_path)
    if not inp.exists():
        return {"error": f"Input file not found: {input_path}"}

    out = Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(inp).convert("RGBA").resize(target, Image.LANCZOS)
    img_array = np.asarray(img, dtype=np.uint8)
    write_dds(str(out), img_array)

    return {
        "input": str(inp),
        "output": str(out),
        "original_size": f"{Image.open(inp).size[0]}x{Image.open(inp).size[1]}",
        "target_size": f"{target[0]}x{target[1]}",
        "format": "DDS DXT5",
        "size_kb": round(out.stat().st_size / 1024, 0),
    }


def tool_create_release(params: dict) -> dict:
    mod_dir = params.get("mod_dir", "")
    version = params.get("version", "")
    dry_run = params.get("dry_run", False)
    publish = params.get("publish", False)

    if not mod_dir:
        return {"error": "mod_dir parameter is required"}

    mp = Path(mod_dir).resolve()
    if not mp.exists() or not mp.is_dir():
        return {"error": f"Directory not found: {mod_dir}"}

    mod_name = mp.name.replace("-", " ").replace("_", " ").title()
    mod_name = re.sub(r'\bFs(\d+)\b', r'FS\1', mod_name)
    mod_slug = re.sub(r'[^a-zA-Z0-9\-]', '-', mp.name).strip('-').lower()

    if not version:
        content = read_moddesc(mp)
        version = get_tag(content, "version") if content else "1.0.0"

    tag = f"{mod_slug}-v{version}"
    est_mb = estimate_dir_size(mp) / (1024 * 1024)

    if est_mb > 1900:
        return {"error": f"Mod too large: {est_mb:.0f} MB (limit: 2 GB)"}

    if dry_run:
        return {
            "mod_name": mod_name,
            "tag": tag,
            "version": version,
            "estimated_mb": round(est_mb, 1),
            "dry_run": True,
            "message": f"Would create release {tag}",
        }

    if not publish:
        # Just build the ZIP
        with tempfile.TemporaryDirectory() as tmp:
            zip_path = Path(tmp) / f"{mod_slug}.zip"
            create_zip(mp, zip_path)
            output = Path.cwd() / f"{mod_slug}.zip"
            shutil.move(str(zip_path), str(output))
            return {
                "mod_name": mod_name,
                "zip": str(output),
                "size_mb": round(output.stat().st_size / (1024 * 1024), 1),
                "message": "ZIP created locally. Use --publish to create a GitHub Release.",
            }

    # Publish to GitHub
    if not shutil.which("gh"):
        return {"error": "`gh` CLI not found. Install from https://cli.github.com/"}

    if release_exists(tag):
        return {"error": f"Release '{tag}' already exists. Use --overwrite in release_mod.py"}

    with tempfile.TemporaryDirectory(prefix="bob-release-") as tmp:
        zip_path = Path(tmp) / f"{mod_slug}.zip"
        create_zip(mp, zip_path)
        notes = (
            f"## {mod_name} v{version}\n\n"
            f"Categoria: {mod_slug.split('-')[0] if mod_slug else 'auto'}\n\n"
            f"### Instalação\n\n"
            f"1. Baixe o arquivo `{zip_path.name}` abaixo\n"
            f"2. Extraia para `~Documents/My Games/FarmingSimulator2025/mods/`\n"
            f"3. Pronto!\n"
        )
        run_gh(["release", "create", tag, str(zip_path),
                "--title", f"{mod_slug} v{version}", "--notes", notes])
        dl_url = f"https://github.com/{REPO}/releases/tag/{tag}"

    return {
        "mod_name": mod_name,
        "tag": tag,
        "version": version,
        "release_url": dl_url,
        "size_mb": round(zip_path.stat().st_size / (1024 * 1024), 1),
        "message": "Published to GitHub Releases",
    }


# ── Tool registry ─────────────────────────────────────────────────────────────

TOOLS = {
    "search_mods": {
        "name": "search_mods",
        "description": "Search FS25 mod conversions in the local database and GitHub releases.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search term"},
                "manufacturer": {"type": "string", "description": "Filter by manufacturer"},
                "db_only": {"type": "boolean", "description": "Skip GitHub search"},
            },
            "required": ["query"],
        },
        "handler": tool_search_mods,
    },
    "list_mods": {
        "name": "list_mods",
        "description": "List all mods in the local database.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "manufacturer": {"type": "string", "description": "Filter by manufacturer"},
            },
        },
        "handler": tool_list_mods,
    },
    "list_categories": {
        "name": "list_categories",
        "description": "List all mod categories with counts.",
        "inputSchema": {"type": "object", "properties": {}},
        "handler": tool_list_categories,
    },
    "sync_mods": {
        "name": "sync_mods",
        "description": "Sync database with GitHub releases.",
        "inputSchema": {"type": "object", "properties": {}},
        "handler": tool_sync_mods,
    },
    "search_fs25_net": {
        "name": "search_fs25_net",
        "description": "Search fs25.net for FS25 mods by query.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search term"},
            },
            "required": ["query"],
        },
        "handler": tool_search_fs25_net,
    },
    "download_mod": {
        "name": "download_mod",
        "description": "Download an FS25 mod ZIP from fs25.net and add to database.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "Full URL of the mod page on fs25.net"},
            },
            "required": ["url"],
        },
        "handler": tool_download_mod,
    },
    "get_mod_info": {
        "name": "get_mod_info",
        "description": "Read modDesc.xml from a local mod folder and return metadata (version, author, title, etc).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Path to the mod directory"},
            },
            "required": ["path"],
        },
        "handler": tool_get_mod_info,
    },
    "validate_mod": {
        "name": "validate_mod",
        "description": "Check a mod directory's modDesc.xml for common issues (version format, descVersion, missing tags).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Path to the mod directory"},
            },
            "required": ["path"],
        },
        "handler": tool_validate_mod,
    },
    "resize_icon": {
        "name": "resize_icon",
        "description": "Convert an image (PNG/JPG) to DDS DXT5 at the exact size FS25 needs for store icons, brands, or store previews.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "input": {"type": "string", "description": "Input image path"},
                "output": {"type": "string", "description": "Output DDS path"},
                "type": {"type": "string", "enum": ["icon", "brand", "store"], "description": "Image type (icon=512x512, brand=512x256, store=512x512)"},
            },
            "required": ["input", "output"],
        },
        "handler": tool_resize_icon,
    },
    "create_release": {
        "name": "create_release",
        "description": "Build a ZIP and optionally publish a GitHub Release for a mod. Use dry_run=true to preview.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "mod_dir": {"type": "string", "description": "Path to the mod directory"},
                "version": {"type": "string", "description": "Version string (optional, reads from modDesc.xml)"},
                "dry_run": {"type": "boolean", "description": "Preview without building"},
                "publish": {"type": "boolean", "description": "Create GitHub Release after building ZIP"},
            },
            "required": ["mod_dir"],
        },
        "handler": tool_create_release,
    },
    "download_fs22_mod": {
        "name": "download_fs22_mod",
        "description": "Download a single FS22 mod from fs22.com into fs22/<category>/<mod>/.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "Full URL of the mod page on fs22.com"},
            },
            "required": ["url"],
        },
        "handler": tool_download_fs22_mod,
    },
    "download_fs22_category": {
        "name": "download_fs22_category",
        "description": "Download all FS22 mods from a category on fs22.com (trucks, tractors, maps, trailers, cars).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "category": {"type": "string", "enum": ["trucks", "tractors", "trailers", "maps", "cars"], "description": "Category name"},
                "limit": {"type": "integer", "description": "Max mods to download (0 = all)"},
            },
            "required": ["category"],
        },
        "handler": tool_download_fs22_category,
    },
    "scan_fs22_mods": {
        "name": "scan_fs22_mods",
        "description": "Rescan fs22/ directory and regenerate fs22/README.md with current mod inventory.",
        "inputSchema": {"type": "object", "properties": {}},
        "handler": tool_scan_fs22_mods,
    },
    "search_download_fs25": {
        "name": "search_download_fs25",
        "description": "Search fs25.net for a mod query, download all results, and catalog in the database.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search term for fs25.net"},
            },
            "required": ["query"],
        },
        "handler": tool_search_download_fs25,
    },
    "list_missing_fs25": {
        "name": "list_missing_fs25",
        "description": "List trucks from the predefined list that are not yet in the local database.",
        "inputSchema": {"type": "object", "properties": {}},
        "handler": tool_list_missing_fs25,
    },
    "deploy_mod": {
        "name": "deploy_mod",
        "description": "Copy a mod between the repository and the game's mod folder.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "source": {"type": "string", "description": "Mod folder name or path"},
                "destination": {"type": "string", "enum": ["game", "repo"], "description": "Copy to game mods folder or back to repo"},
            },
            "required": ["source", "destination"],
        },
        "handler": tool_deploy_mod,
    },
}


# ── MCP Protocol ──────────────────────────────────────────────────────────────

def send_message(msg: dict):
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def handle_request(msg: dict) -> dict | None:
    method = msg.get("method", "")
    params = msg.get("params", {})

    if method == "initialize":
        return {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "fs25-mods-mcp", "version": "2.0.0"},
        }

    if method == "notifications/initialized":
        return None

    if method == "tools/list":
        return {"tools": [{k: v for k, v in t.items() if k != "handler"} for t in TOOLS.values()]}

    if method == "tools/call":
        tool_name = params.get("name", "")
        arguments = params.get("arguments", {})
        tool = TOOLS.get(tool_name)
        if not tool:
            return {"isError": True, "content": [{"type": "text", "text": f"Unknown tool: {tool_name}"}]}
        try:
            result = tool["handler"](arguments)
            if "error" in result:
                return {"isError": True, "content": [{"type": "text", "text": result["error"]}]}
            return {"content": [{"type": "text", "text": json.dumps(result, indent=2, ensure_ascii=False)}]}
        except Exception as e:
            return {"isError": True, "content": [{"type": "text", "text": f"Error: {e}\n{traceback.format_exc()}"}]}

    return {"error": {"code": -32601, "message": f"Method not found: {method}"}}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            send_message({"jsonrpc": "2.0", "error": {"code": -32700, "message": f"Parse error: {e}"}})
            continue
        result = handle_request(msg)
        if result is not None:
            resp = {"jsonrpc": "2.0", "id": msg.get("id")}
            if "error" in result:
                resp["error"] = result["error"]
            else:
                resp["result"] = result
            send_message(resp)


if __name__ == "__main__":
    main()
