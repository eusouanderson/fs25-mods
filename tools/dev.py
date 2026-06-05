#!/usr/bin/env python3
"""
FS25 Mod Development Helper — B.O.B's Dev Tools

Usage:
    python tools/dev.py log              Show errors/warnings from last session
    python tools/dev.py watch            Tail game log in real-time (Ctrl+C to stop)
    python tools/dev.py check <mod>      Validate modDesc.xml for common issues
    python tools/dev.py info <mod>       Show mod info from modDesc.xml
    python tools/dev.py deploy <mod>     Copy mod from repo to FS25 mods folder
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
REPO = "eusouanderson/fs25-mods"

GAME_USER_DIR = Path("/mnt/g/Users/Administrador/Documents/My Games/FarmingSimulator2025")
MODS_DIR = GAME_USER_DIR / "mods"
LOG_FILE = GAME_USER_DIR / "log.txt"
GAME_XML = GAME_USER_DIR / "game.xml"


def color(text: str, code: str) -> str:
    codes = {"red": "31", "green": "32", "yellow": "33", "cyan": "36", "bold": "1"}
    c = codes.get(code, "0")
    return f"\033[{c}m{text}\033[0m" if sys.stdout.isatty() else text


def find_mod_dir(query: str) -> Path | None:
    if not MODS_DIR.exists():
        return None
    query_lower = query.lower()
    matches = []
    for d in MODS_DIR.iterdir():
        if d.is_dir() and query_lower in d.name.lower():
            matches.append(d)
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        print(f"  ℹ  Multiple mods match '{query}':")
        for m in matches:
            print(f"     {m.name}")
        return None
    for base in (BASE_DIR / "fs25", BASE_DIR / "fs22"):
        for cat_dir in base.iterdir() if base.exists() else []:
            if cat_dir.is_dir():
                for mod_dir in cat_dir.iterdir():
                    if mod_dir.is_dir() and query_lower in mod_dir.name.lower():
                        matches.append(mod_dir)
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            print(f"  ℹ  Multiple mods match '{query}' in repo:")
            for m in matches:
                print(f"     {m.name}")
            return None
    return None


def cmd_log(args):
    if not LOG_FILE.exists():
        print(f"  ✖  Log not found: {LOG_FILE}")
        sys.exit(1)

    content = LOG_FILE.read_text(encoding="utf-8", errors="replace")
    lines = content.splitlines()

    errors = [(i + 1, l.strip()) for i, l in enumerate(lines) if "Error" in l or "error" in l]
    warnings = [(i + 1, l.strip()) for i, l in enumerate(lines) if "Warning" in l or "warning" in l]
    mod_loads = [(i + 1, l.strip()) for i, l in enumerate(lines) if "mod" in l.lower() and ("load" in l.lower() or "register" in l.lower())]

    print(f"  📋  Log: {LOG_FILE.name} ({len(lines)} lines)")
    print(f"  {'Errors:':12} {color(str(len(errors)), 'red')}")
    print(f"  {'Warnings:':12} {color(str(len(warnings)), 'yellow')}")
    print(f"  {'Mods loaded:':12} {len(mod_loads)}")
    print()

    if errors:
        print(color("── Errors ──", "red"))
        for lineno, line in errors[-20:]:
            print(f"  L{lineno} {color('✖', 'red')} {line[:200]}")
        print()

    if warnings:
        print(color("── Warnings ──", "yellow"))
        for lineno, line in warnings[-15:]:
            if not args.verbose and any(s in line for s in ["Warning: Scheduled", "Warning: Terrain", "Warning: LOD"]):
                continue
            print(f"  L{lineno} {color('⚠', 'yellow')} {line[:200]}")
        print()

    if not errors and not warnings:
        print(color("  ✅  No errors or warnings found!", "green"))


def cmd_watch(args):
    if not LOG_FILE.exists():
        print(f"  ✖  Log not found: {LOG_FILE}")
        print("  Start the game first!")
        sys.exit(1)

    print(f"  👀  Watching {LOG_FILE}... (Ctrl+C to stop)")
    print()
    try:
        with open(LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
            f.seek(0, 2)
            while True:
                line = f.readline()
                if line:
                    line = line.rstrip("\n\r")
                    if "Error" in line or "error" in line:
                        print(f"  {color('✖', 'red')} {line[:300]}")
                    elif "Warning" in line or "warning" in line:
                        print(f"  {color('⚠', 'yellow')} {line[:300]}")
                    else:
                        print(f"  {line[:300]}")
                else:
                    time.sleep(0.5)
    except KeyboardInterrupt:
        print()
        print("  👋  Stopped.")


def cmd_check(args):
    mod_dir = find_mod_dir(args.mod)
    if not mod_dir:
        print(f"  ✖  Mod not found: {args.mod}")
        print(f"     Looked in: {MODS_DIR}")
        print(f"     And in repo: fs25/ and fs22/")
        sys.exit(1)

    moddesc = mod_dir / "modDesc.xml"
    if not moddesc.exists():
        print(f"  ✖  No modDesc.xml in {mod_dir}")
        sys.exit(1)

    content = moddesc.read_text(encoding="utf-8")
    issues = []

    m = re.search(r"<version>([^<]+)</version>", content)
    if m:
        ver = m.group(1).strip()
        if not re.match(r"^\d+(\.\d+){0,3}$", ver):
            issues.append(("error", f"Invalid version format: '{ver}' (expected e.g. 1.0.0.0)"))
        parts = ver.split(".")
        if len(parts) > 4:
            issues.append(("warning", f"Version has {len(parts)} parts, FS25 expects ≤4 (e.g. 1.0.0.0)"))
    else:
        issues.append(("error", "Missing <version> tag"))

    m = re.search(r'<modDesc\s+descVersion="(\d+)"', content)
    if m:
        dv = int(m.group(1))
        if dv < 101:
            issues.append(("warning", f"descVersion={dv} — FS25 typically uses descVersion=101 or higher"))
    else:
        issues.append(("warning", "Missing descVersion attribute on <modDesc>"))

    if 'storeItems' in content and not re.search(r'storeItems\s+xmlFilename=', content):
        issues.append(("info", "No <storeItem> found inside <storeItems>"))

    for tag in ["title", "description", "author"]:
        if not re.search(rf"<{tag}[>\s]", content):
            issues.append(("warning", f"Missing <{tag}> tag"))

    fs22_patterns = [
        (r"specialization.*fillUnit", "fillUnit specialization — FS25 uses fillUnit directly"),
        (r"specialization.*attachable", "attachable specialization — check if FS25 compatible"),
    ]
    for pattern, desc in fs22_patterns:
        if re.search(pattern, content):
            issues.append(("info", f"Found: {desc}"))

    print(f"  📁  {mod_dir.name}")
    print(f"  🔍  modDesc.xml: {len(issues)} check(s)")
    print()

    if not issues:
        print(color("  ✅  No issues found!", "green"))
        return

    for severity, msg in issues:
        if severity == "error":
            print(f"  {color('✖', 'red')} {msg}")
        elif severity == "warning":
            print(f"  {color('⚠', 'yellow')} {msg}")
        else:
            print(f"  {color('ℹ', 'cyan')}  {msg}")

    print()


def cmd_info(args):
    mod_dir = find_mod_dir(args.mod)
    if not mod_dir:
        print(f"  ✖  Mod not found: {args.mod}")
        sys.exit(1)

    moddesc = mod_dir / "modDesc.xml"
    if not moddesc.exists():
        print(f"  ✖  No modDesc.xml in {mod_dir}")
        sys.exit(1)

    content = moddesc.read_text(encoding="utf-8")

    def get_tag(tag: str) -> str:
        m = re.search(rf"<{tag}[^>]*>([^<]+)</{tag}>", content)
        return m.group(1).strip() if m else "—"

    def get_l10n(tag: str, lang: str = "en") -> str:
        m = re.search(rf"<{tag}[^>]*>\s*<{lang}[^>]*>(.*?)</{lang}>", content, re.DOTALL)
        if m:
            return m.group(1).strip()[:80]
        m = re.search(rf"<{tag}[^>]*>\s*<en[^>]*>(.*?)</en>", content, re.DOTALL)
        return m.group(1).strip()[:80] if m else "—"

    size_mb = sum(f.stat().st_size for f in mod_dir.rglob("*") if f.is_file()) / (1024 * 1024)

    print(f"  ┌─ {color(mod_dir.name, 'bold')} ─────────────────────────────")
    print(f"  │  📂  Path:    {mod_dir}")
    print(f"  │  📏  Size:    {size_mb:.1f} MB")
    print(f"  │  🏷️   Version: {get_tag('version')}")
    print(f"  │  ✍️   Author:  {get_tag('author')}")
    print(f"  │  📝  Title:   {get_l10n('title', 'en')}")
    print(f"  │  📝  Title:   {get_l10n('title', 'pt') or get_l10n('title', 'br')}")
    print(f"  │  📄  Desc:    {get_l10n('description', 'en')}")
    print(f"  └────────────────────────────────────")

    files = sorted(mod_dir.rglob("*"))
    dirs = len([f for f in files if f.is_dir()])
    file_count = len([f for f in files if f.is_file()])
    print(f"  📄  {file_count} files, {dirs} subdirectories")
    print()


def cmd_deploy(args):
    source = Path(args.source).resolve()
    dest = args.dest

    if not source.exists() or not source.is_dir():
        print(f"  ✖  Source not found: {source}")
        sys.exit(1)

    target_name = source.name

    if dest == "game":
        target_dir = MODS_DIR / target_name
        print(f"  📦  Deploying {target_name} → game mods folder")
    elif dest == "repo":
        found = None
        for base_dir in [BASE_DIR / "fs25", BASE_DIR / "fs22"]:
            if not base_dir.exists():
                continue
            for cat_dir in base_dir.iterdir():
                if cat_dir.is_dir():
                    for existing in cat_dir.iterdir():
                        if existing.name.lower() == target_name.lower().replace(" ", "-"):
                            found = existing
                            break
        if found:
            target_dir = found
        else:
            category = (input(f"  Category? (trucks/tractors/trailers/maps/cars/other) [other]: ").strip() or "other")
            target_dir = BASE_DIR / "fs25" / category / target_name.lower().replace(" ", "-")
        print(f"  📦  Deploying {target_name} → repo ({target_dir.relative_to(BASE_DIR)})")
    else:
        print(f"  ✖  Invalid destination.")
        sys.exit(1)

    if target_dir.exists():
        if not args.force:
            print(f"  ⚠   Target exists: {target_dir}")
            confirm = input(f"  Overwrite? [y/N]: ").strip().lower()
            if confirm != "y":
                print("  ✖  Cancelled.")
                sys.exit(1)
        shutil.rmtree(target_dir)

    print(f"  📋  Copying: {source} → {target_dir}")
    shutil.copytree(source, target_dir, ignore=shutil.ignoring_patterns("__pycache__", "*.pyc", ".git"))
    size = sum(f.stat().st_size for f in target_dir.rglob("*") if f.is_file()) / (1024 * 1024)
    print(f"  ✅  Done! Copied {target_name} ({size:.1f} MB)")


def main():
    parser = argparse.ArgumentParser(
        description="FS25 Mod Development Helper",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python tools/dev.py log                 # Show last errors\n"
            "  python tools/dev.py log -v              # Show all warnings too\n"
            "  python tools/dev.py watch               # Live log tail\n"
            "  python tools/dev.py check kamaz         # Validate mod\n"
            "  python tools/dev.py info kamaz          # Show mod info\n"
            "  python tools/dev.py deploy kamaz game   # Copy from repo → FS25\n"
        ),
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_log = subparsers.add_parser("log", help="Show errors/warnings from last session")
    p_log.add_argument("-v", "--verbose", action="store_true", help="Include verbose warnings")

    subparsers.add_parser("watch", help="Tail game log in real-time")

    p_check = subparsers.add_parser("check", help="Validate modDesc.xml")
    p_check.add_argument("mod", help="Mod name (partial match)")

    p_info = subparsers.add_parser("info", help="Show mod info")
    p_info.add_argument("mod", help="Mod name (partial match)")

    p_deploy = subparsers.add_parser("deploy", help="Copy mod between repo and game")
    p_deploy.add_argument("source", help="Mod folder name or path")
    p_deploy.add_argument("dest", choices=["game", "repo"], help="Destination")
    p_deploy.add_argument("-f", "--force", action="store_true", help="Overwrite without confirmation")

    args = parser.parse_args()

    commands = {
        "log": cmd_log,
        "watch": cmd_watch,
        "check": cmd_check,
        "info": cmd_info,
        "deploy": cmd_deploy,
    }

    commands[args.command](args)


if __name__ == "__main__":
    main()
