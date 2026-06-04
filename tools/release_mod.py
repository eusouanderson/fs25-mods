#!/usr/bin/env python3
"""
FS22/FS25 Mod Release Tool — B.O.B's FS25 Mod Tool
====================================================
Zips a mod directory, creates a GitHub Release, uploads the zip,
and updates the mod's README.

The mod directory can be inside the repo (fs25/<category>/<mod>/)
or an external path (e.g. your FS25 mods folder on Windows).

Usage:
    python release_mod.py <mod-dir> [--version X.Y.Z] [--category trucks]
    python release_mod.py fs25/trucks/kamaz-65116 --version 1.0.0
    python release_mod.py /path/to/FS25Kamaz65116 --name kamaz-65116 --category trucks
    python release_mod.py fs25/trucks/kamaz-65116 --dry-run
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
REPO = "eusouanderson/fs25-mods"
CATEGORIES = ("trucks", "tractors", "trailers", "maps", "cars", "other")

EXCLUDE_PATTERNS = (
    ".git", "__pycache__", "*.pyc", ".DS_Store",
    "*.bak", "Thumbs.db", "desktop.ini",
)


def run_gh(args: list[str], capture: bool = True) -> str:
    cmd = ["gh", "-R", REPO] + args
    print(f"  $ gh {' '.join(args)}")
    try:
        r = subprocess.run(cmd, capture_output=capture, text=True, check=True, timeout=60)
        return r.stdout.strip() if capture else ""
    except subprocess.CalledProcessError as e:
        print(f"  ✖  gh command failed: {' '.join(args)}")
        print(f"     stderr: {e.stderr.strip() if e.stderr else '(none)'}")
        sys.exit(1)
    except FileNotFoundError:
        print("  ✖  `gh` CLI not found. Install it from https://cli.github.com/")
        sys.exit(1)


def slug_from_path(path: Path) -> str:
    name = path.name
    name = re.sub(r'[^a-zA-Z0-9\-]', '-', name)
    name = re.sub(r'-+', '-', name).strip('-').lower()
    return name


def mod_display_name(path: Path) -> str:
    name = path.name
    name = re.sub(r'[-_]', ' ', name)
    name = name.title().strip()
    name = re.sub(r'\bFs(\d+)\b', r'FS\1', name)
    name = re.sub(r'\bV(\d+)', r'v\1', name)
    return name


def estimate_dir_size(path: Path) -> int:
    total = 0
    for f in path.rglob("*"):
        if f.is_file() and not any(f.match(p) for p in EXCLUDE_PATTERNS):
            total += f.stat().st_size
    return total


def create_zip(source_dir: Path, output_path: Path) -> Path:
    print(f"  📦  Zipping: {source_dir.name}")
    total = estimate_dir_size(source_dir)
    print(f"  ℹ   Estimated size: {total / 1024 / 1024:.1f} MB")

    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for file_path in source_dir.rglob("*"):
            if file_path.is_dir():
                continue
            rel = file_path.relative_to(source_dir)
            if any(file_path.match(p) for p in EXCLUDE_PATTERNS):
                continue
            if ".git" in rel.parts:
                continue
            zf.write(file_path, arcname=rel)

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"  ✅  Created: {output_path.name} ({size_mb:.1f} MB)")
    return output_path


def read_version_from_moddesc(mod_dir: Path) -> str | None:
    """Read the <version> tag from modDesc.xml inside the mod folder."""
    moddesc = mod_dir / "modDesc.xml"
    if not moddesc.exists():
        return None
    try:
        content = moddesc.read_text(encoding="utf-8")
        m = re.search(r'<version>([^<]+)</version>', content)
        if m:
            ver = m.group(1).strip()
            ver = re.sub(r'\.0$', '', ver)
            return ver
    except Exception:
        pass
    return None


def get_next_version(slug: str) -> str:
    try:
        result = subprocess.run(
            ["gh", "-R", REPO, "release", "list", "--limit", "20", "--json", "tagName"],
            capture_output=True, text=True, check=True, timeout=15
        )
        releases = json.loads(result.stdout)
        prefix = f"{slug}-v"
        versions = []
        for r in releases:
            tag = r["tagName"]
            if tag.startswith(prefix):
                ver = tag[len(prefix):]
                try:
                    parts = [int(x) for x in ver.split(".")]
                    versions.append(parts)
                except ValueError:
                    pass
        if versions:
            versions.sort()
            latest = versions[-1]
            latest[-1] += 1
            return ".".join(str(x) for x in latest)
    except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
        pass
    return "1.0.0"


def release_exists(tag: str) -> bool:
    try:
        subprocess.run(
            ["gh", "-R", REPO, "release", "view", tag],
            capture_output=True, check=True, timeout=15
        )
        return True
    except subprocess.CalledProcessError:
        return False


def category_emoji(cat: str) -> str:
    emojis = {
        "trucks": "🚚", "tractors": "🚜", "trailers": "🚛",
        "maps": "🗺️", "cars": "🚗",
    }
    return emojis.get(cat, "📦")


def update_readme_with_link(readme_path: Path, mod_name: str, version: str, tag: str, dry_run: bool = False) -> str:
    download_url = f"https://github.com/{REPO}/releases/tag/{tag}"
    if not readme_path.exists():
        print(f"  ℹ   No README at {readme_path}, skipping update")
        return download_url

    content = readme_path.read_text(encoding="utf-8")
    download_section = (
        f"## 📥 Download\n"
        f"\n"
        f"**{mod_name} v{version}**\n"
        f"\n"
        f"[⬇ Baixar / Download]({download_url})\n"
        f"\n"
        f"---\n"
    )

    if re.search(r'^## 📥 Download', content, re.MULTILINE):
        content = re.sub(
            r'^## 📥 Download\n.*?\n(?:---\n)?',
            download_section,
            content,
            count=1,
            flags=re.DOTALL | re.MULTILINE
        )
        print(f"  🔄  Updated download link in {readme_path.name}")
    else:
        if "\n---\n" in content:
            content = content.replace("\n---\n", f"\n{download_section}\n", 1)
        else:
            content += f"\n{download_section}\n"
        print(f"  ➕  Added download section to {readme_path.name}")

    if dry_run:
        print(f"  ℹ   [DRY RUN] Would write {readme_path.relative_to(BASE_DIR)}")
    else:
        readme_path.write_text(content, encoding="utf-8")
        print(f"  ✅  Updated {readme_path.relative_to(BASE_DIR)}")
    return download_url


def commit_and_push_readme(readme_rel: str, mod_name: str, version: str, dry_run: bool = False):
    if dry_run:
        print(f"  ℹ   [DRY RUN] Would commit and push README update")
        return
    try:
        subprocess.run(["git", "-C", str(BASE_DIR), "add", readme_rel], check=True, capture_output=True, timeout=15)
        subprocess.run(
            ["git", "-C", str(BASE_DIR), "commit", "-m", f"Update {mod_name} README with v{version} download link"],
            check=True, capture_output=True, timeout=15
        )
        subprocess.run(["git", "-C", str(BASE_DIR), "push"], check=True, capture_output=True, timeout=30)
        print(f"  ✅  Committed and pushed README update")
    except subprocess.CalledProcessError as e:
        print(f"  ⚠   Git warning: {e.stderr.decode() if e.stderr else ''}")


def find_readme_in_repo(mod_slug: str, category: str | None) -> Path | None:
    """Search for the mod's README within the repo."""
    if category:
        candidate = BASE_DIR / "fs25" / category / mod_slug / "README.md"
        if candidate.exists():
            return candidate
        candidate = BASE_DIR / "fs22" / category / mod_slug / "README.md"
        if candidate.exists():
            return candidate
    for cat in CATEGORIES:
        for base in ("fs25", "fs22"):
            candidate = BASE_DIR / base / cat / mod_slug / "README.md"
            if candidate.exists():
                return candidate
    return None


def get_mod_info(mod_path: Path, name: str | None, category: str | None) -> tuple:
    """Extract mod name, slug, and category from path and arguments."""
    mod_name = mod_display_name(mod_path)
    mod_slug = name or slug_from_path(mod_path)

    # Detect category from path if inside repo
    detected_cat = category
    if not detected_cat:
        try:
            rel = mod_path.relative_to(BASE_DIR)
            parts = rel.parts
            if len(parts) >= 2 and parts[0] in ("fs25", "fs22") and parts[1] in CATEGORIES:
                detected_cat = parts[1]
        except ValueError:
            pass

    return mod_name, mod_slug, detected_cat


def main():
    parser = argparse.ArgumentParser(
        description="Zip a mod and publish it as a GitHub Release.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python release_mod.py fs25/trucks/kamaz-65116\n"
            "  python release_mod.py fs25/trucks/kamaz-65116 --version 1.0.0\n"
            "  python release_mod.py /path/to/FS25Kamaz65116 --name kamaz-65116 --category trucks\n"
            "  python release_mod.py fs25/trucks/kamaz-65116 --dry-run\n"
        ),
    )
    parser.add_argument("mod_dir", help="Path to the mod directory (in repo or external)")
    parser.add_argument("--name", help="Mod slug/name (auto-detected from folder)")
    parser.add_argument("--category", choices=CATEGORIES, help="Mod category (auto-detected if path is inside repo)")
    parser.add_argument("--version", "-v", help="Version tag (auto: from modDesc.xml or next patch)")
    parser.add_argument("--dry-run", "-n", action="store_true", help="Preview only")
    parser.add_argument("--no-readme", action="store_true", help="Skip README update")
    parser.add_argument("--overwrite", action="store_true", help="Delete existing release and recreate")

    args = parser.parse_args()

    mod_path = Path(args.mod_dir).resolve()
    if not mod_path.exists() or not mod_path.is_dir():
        print(f"  ✖  Mod directory not found: {mod_path}")
        sys.exit(1)

    mod_name, mod_slug, category = get_mod_info(mod_path, args.name, args.category)

    # Version detection priority: --version flag > modDesc.xml > auto from previous releases
    if args.version:
        version = args.version
    else:
        moddesc_ver = read_version_from_moddesc(mod_path)
        if moddesc_ver:
            version = moddesc_ver
            print(f"  ℹ   Version from modDesc.xml: {version}")
        else:
            version = get_next_version(mod_slug)
            print(f"  ℹ   Auto-detected version: {version}")

    tag = f"{mod_slug}-v{version}"

    zip_basename = mod_path.name

    print(f"\n{'='*60}")
    emoji = category_emoji(category or "other")
    print(f"  {emoji}  Publishing: {mod_name}")
    print(f"  🏷   Tag:        {tag}")
    print(f"  📦  Zip:        {zip_basename}.zip")
    print(f"  📂  Category:   {category or 'auto-detect'}")
    print(f"  📁  Source:      {mod_path}")
    print(f"{'='*60}")

    release_already_exists = not args.dry_run and release_exists(tag)
    if release_already_exists:
        if args.overwrite:
            print(f"  ⚠   Release '{tag}' exists. Deleting and recreating...")
            run_gh(["release", "delete", tag])
        else:
            print(f"  ✖  Release '{tag}' already exists!")
            print(f"     Tips:")
            print(f"       • Update the version in modDesc.xml and run again")
            print(f"       • Use --overwrite to replace this release")
            print(f"       • Use --version X.Y.Z to override")
            sys.exit(1)

    estimated_mb = estimate_dir_size(mod_path) / (1024 * 1024)
    if estimated_mb > 1900:
        print(f"  ✖  {estimated_mb:.0f} MB exceeds GitHub Release 2 GB limit!")
        sys.exit(1)
    if estimated_mb > 100:
        print(f"  ⚠   Large mod: {estimated_mb:.0f} MB (GitHub Release limit is 2 GB, this is fine)")

    with tempfile.TemporaryDirectory(prefix="bob-release-") as tmp_dir:
        zip_path = Path(tmp_dir) / f"{zip_basename}.zip"
        create_zip(mod_path, zip_path)

        if args.dry_run:
            print(f"\n  ℹ   [DRY RUN] Would create Release:")
            print(f"       Tag:    {tag}")
            print(f"       Title:  {mod_slug} v{version}")
            print(f"       Asset:  {zip_path.name} ({zip_path.stat().st_size / 1024 / 1024:.1f} MB)")
            print(f"  ℹ   FS25 ready: zip name matches original folder ({zip_basename}.zip)")
            sys.exit(0)

        release_notes = (
            f"## {mod_name} v{version}\n\n"
            f"Categoria: {category or 'other'}\n\n"
            f"### Instalação / Installation\n\n"
            f"1. Baixe o arquivo `{zip_basename}.zip` abaixo\n"
            f"2. Extraia para `~Documents/My Games/FarmingSimulator2025/mods/`\n"
            f"3. Pronto!\n"
        )

        result = run_gh([
            "release", "create", tag,
            str(zip_path),
            "--title", f"{mod_slug} v{version}",
            "--notes", release_notes,
        ])
        print(f"  ✅  Release: https://github.com/{REPO}/releases/tag/{tag}")

        if not args.no_readme:
            readme_path = find_readme_in_repo(mod_slug, category)
            if readme_path:
                dl_url = update_readme_with_link(readme_path, mod_name, version, tag)
                try:
                    rel = readme_path.relative_to(BASE_DIR)
                    commit_and_push_readme(str(rel), mod_name, version)
                except ValueError:
                    pass
            else:
                print(f"  ℹ   No README found for this mod in the repo")

    print(f"\n  ✅  Done! {mod_name} v{version} published.")


if __name__ == "__main__":
    main()
