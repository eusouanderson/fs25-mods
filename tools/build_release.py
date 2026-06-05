#!/usr/bin/env python3
"""
FS25 Mod Build & Release Pipeline — B.O.B's Mod Tool
=======================================================
Pipeline: run tests → zip mod → (optional) GitHub release.

Usage:
    python tools/build_release.py <mod-dir> [--out-dir ./releases]
    python tools/build_release.py <mod-dir> --publish
    python tools/build_release.py <mod-dir> --publish --dry-run
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_mod import (
    BASE_DIR,
    create_zip,
    estimate_dir_size,
    get_mod_info,
    mod_display_name,
    read_version_from_moddesc,
    release_exists,
    run_gh,
    slug_from_path,
    update_readme_with_link,
    commit_and_push_readme,
    find_readme_in_repo,
    REPO,
)


MODS_DIR = Path("/mnt/g/Users/Administrador/Documents/My Games/FarmingSimulator2025/mods")


def run_tests(mod_dir: Path, verbose: bool = False) -> bool:
    validator_dir = mod_dir / "validator"
    passed = True

    test_xml = validator_dir / "test_xml.py"
    if test_xml.exists():
        print(f"  🧪  Running: {test_xml.name}")
        result = subprocess.run(
            [sys.executable, str(test_xml)],
            capture_output=True, text=True, timeout=120,
            cwd=str(validator_dir),
        )
        for line in result.stdout.strip().splitlines():
            print(f"       {line}")
        if result.stderr.strip():
            print(f"       {result.stderr.strip()}")
        if result.returncode != 0:
            print(f"  ✖  {test_xml.name} FAILED (exit code {result.returncode})")
            passed = False
        else:
            print(f"  ✅  {test_xml.name} passed")
    else:
        print(f"  ℹ   Skipping test_xml.py (not found)")

    pytest_ini = validator_dir / "pytest.ini"
    pyproject = validator_dir / "pyproject.toml"
    tests_dir = validator_dir / "tests"
    if pytest_ini.exists() or pyproject.exists() or tests_dir.exists():
        print(f"  🧪  Running: pytest")
        cmd = [sys.executable, "-m", "pytest"]
        if not verbose:
            cmd.extend(["-q", "--no-header"])
        cmd.extend(["--tb=short", "-W", "ignore::DeprecationWarning"])
        result = subprocess.run(
            cmd,
            capture_output=True, text=True, timeout=120,
            cwd=str(validator_dir),
        )
        for line in result.stdout.strip().splitlines():
            print(f"       {line}")
        if result.stderr.strip():
            for line in result.stderr.strip().splitlines():
                print(f"       {line}")
        if result.returncode != 0:
            print(f"  ✖  pytest FAILED (exit code {result.returncode})")
            passed = False
        else:
            print(f"  ✅  pytest passed")
    else:
        print(f"  ℹ   Skipping pytest (not configured)")

    return passed


def build_zip(mod_dir: Path) -> Path | None:
    zip_name = f"{mod_dir.name}.zip"
    zip_path = Path(zip_name)

    print(f"  📦  Creating: {zip_path.name}")
    total = estimate_dir_size(mod_dir)
    print(f"  ℹ   Estimated size: {total / 1024 / 1024:.1f} MB")

    if total > 2 * 1024 * 1024 * 1024:
        print(f"  ✖  Mod too large for GitHub Releases (limit: 2 GB)")
        return None

    try:
        created = create_zip(mod_dir, zip_path)
        size_mb = created.stat().st_size / (1024 * 1024)
        print(f"  ✅  Created: {created.name} ({size_mb:.1f} MB)")
        return created
    except Exception as e:
        print(f"  ✖  Failed to create zip: {e}")
        return None


def publish_release(mod_dir: Path, zip_path: Path, version: str, tag: str,
                    mod_name: str, mod_slug: str, category: str | None,
                    dry_run: bool = False):
    if not dry_run:
        print(f"  🚀  Creating GitHub Release: {tag}")
        if release_exists(tag):
            print(f"  ⚠   Release {tag} already exists")
            print(f"       Use --overwrite to replace it")
            return

        notes = (
            f"## {mod_name} v{version}\n\n"
            f"Categoria: {category or 'auto-detect'}\n\n"
            f"### Instalação / Installation\n\n"
            f"1. Baixe o arquivo `{zip_path.name}` abaixo\n"
            f"2. Extraia para `~Documents/My Games/FarmingSimulator2025/mods/`\n"
            f"3. Pronto!\n"
        )

        run_gh([
            "release", "create", tag,
            str(zip_path),
            "--title", f"{mod_slug} v{version}",
            "--notes", notes,
        ])
        print(f"  ✅  Release: https://github.com/{REPO}/releases/tag/{tag}")

        readme = find_readme_in_repo(mod_slug, category)
        if readme:
            update_readme_with_link(readme, mod_name, version, tag)
            commit_and_push_readme(
                str(readme.relative_to(BASE_DIR)), mod_name, version
            )
    else:
        print(f"\n  ℹ   [DRY RUN] Would create Release:")
        print(f"       Tag:    {tag}")
        print(f"       Title:  {mod_slug} v{version}")
        print(f"       Asset:  {zip_path.name} ({zip_path.stat().st_size / 1024 / 1024:.1f} MB)")
        if zip_path.name.startswith("FS25_"):
            print(f"  ℹ   FS25 ready: zip name matches original folder ({zip_path.name})")


def main():
    parser = argparse.ArgumentParser(
        description="Build & release pipeline for FS25 mods",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("mod_dir", help="Path to the mod directory")
    parser.add_argument("--out-dir", "-o", default="./releases",
                        help="Directory to save the zip (default: ./releases)")
    parser.add_argument("--version", "-v", help="Version (auto: from modDesc.xml)")
    parser.add_argument("--publish", action="store_true",
                        help="Publish to GitHub Releases after building")
    parser.add_argument("--dry-run", "-n", action="store_true",
                        help="Preview without publishing")
    parser.add_argument("--skip-tests", action="store_true",
                        help="Skip test suite")
    parser.add_argument("--verbose", "-V", action="store_true",
                        help="Verbose test output")
    parser.add_argument("--name", help="Mod slug (auto-detected)")
    parser.add_argument("--category", choices=["trucks","tractors","trailers","maps","cars","other"],
                        help="Mod category (auto-detected if path is inside repo)")

    args = parser.parse_args()

    mod_dir = Path(args.mod_dir).resolve()
    if not mod_dir.exists() or not mod_dir.is_dir():
        print(f"  ✖  Mod directory not found: {mod_dir}")
        sys.exit(1)

    mod_name, mod_slug, category = get_mod_info(mod_dir, args.name, args.category)
    version = args.version or read_version_from_moddesc(mod_dir) or "0.0.0"

    print()
    print(f"  ╔══ B.O.B's FS25 Build Pipeline ═══════════════════")
    print(f"  ║  Mod:     {mod_name}")
    print(f"  ║  Version:  {version}")
    print(f"  ║  Source:   {mod_dir}")
    if args.publish:
        tag = f"{mod_slug}-v{version}"
        print(f"  ║  Tag:      {tag}")
    print(f"  ╚══════════════════════════════════════════════════")
    print()

    if not args.skip_tests:
        print(f"  ── Step 1/3: Running tests ──")
        if not run_tests(mod_dir, verbose=args.verbose):
            print(f"\n  ✖  Tests failed! Aborting.")
            sys.exit(1)
        print()
    else:
        print(f"  ℹ   Tests skipped (--skip-tests)")
        print()

    print(f"  ── Step 2/3: Building ZIP ──")
    zip_path = build_zip(mod_dir)
    if not zip_path:
        sys.exit(1)

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    final_path = out_dir / zip_path.name
    shutil.move(str(zip_path), str(final_path))
    print(f"  📂  Moved to: {final_path}")
    print()

    step_label = "3/3" if args.publish else "(skipped)"
    print(f"  ── Step {step_label}: GitHub Release ──")
    if args.publish:
        tag = f"{mod_slug}-v{version}"
        publish_release(mod_dir, final_path, version, tag,
                        mod_name, mod_slug, category,
                        dry_run=args.dry_run)
    else:
        print(f"  ℹ   Skipped (use --publish to release to GitHub)")
    print()

    print(f"  ✅  Done! {mod_name} v{version}")
    print(f"     📦  {final_path}")
    if args.publish and not args.dry_run:
        print(f"     🚀  https://github.com/{REPO}/releases/tag/{mod_slug}-v{version}")
    print()


if __name__ == "__main__":
    main()
