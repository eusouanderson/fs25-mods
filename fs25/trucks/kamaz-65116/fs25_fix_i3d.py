#!/usr/bin/env python3
"""FS22 -> FS25 I3D Converter Fix Script.

Fixes two GE10 conversion issues:
  1. Restores '$data/' prefix on shared resource paths (GE10 strips the '$')
  2. Converts collisionMask (decimal, FS22) to collisionFilterGroup/Mask (hex, FS25)

Usage:
  python fs25_fix_i3d.py kamaz65116.i3d          # in-place fix with .bak backup
  python fs25_fix_i3d.py kamaz65116.i3d --dry-run # preview only
"""

import re
import os
import sys
import shutil

COLLISION_MAP = {
    # (FS22 decimal) -> (FS25 collisionFilterGroup, collisionFilterMask)
    10494210: ("0x10004", "0xfe3ffb83"),     # main body compound
    1056768:  ("0x20000000", "0x100000"),     # AI collision trigger
    8194:     ("0x10004", "0xfe3ffb83"),      # compound child of main body
    1048576:  ("0x20000000", "0x100000"),     # action trigger
    2105410:  ("0x202042", "0xfe3ffb83"),     # wheel axle compound
}


def fix_dollar_data_paths(content):
    """Restore '$data/' prefix stripped by GE10 on shared resource paths."""
    before = len(re.findall(r'filename="data/', content))
    if before == 0:
        return content, 0
    new_content = re.sub(r'filename="(?!\$)(data/)', 'filename="$\\1', content)
    after = len(re.findall(r'filename="data/', new_content))
    return new_content, before - after


def fix_collision_masks(content):
    """Convert FS22 decimal collisionMask to FS25 hex collisionFilterGroup/Mask."""
    fixed = 0
    changes = []

    def replace_fn(m):
        nonlocal fixed
        dec = int(m.group(1))
        if dec in COLLISION_MAP:
            group, mask = COLLISION_MAP[dec]
            fixed += 1
            changes.append(f"       {dec:>10} -> group={group}  mask={mask}")
            return f'collisionFilterGroup="{group}" collisionFilterMask="{mask}"'
        return m.group(0)

    new_content = re.sub(r'collisionMask="(\d+)"', replace_fn, content)
    if fixed:
        print(f"\n  Fix 2: Converted {fixed} collision mask(s) from FS22 -> FS25 format")
        for c in changes:
            print(c)
    return new_content, fixed


def fix_encoding(content):
    """Update legacy encoding to utf-8."""
    if 'encoding="iso-8859-1"' in content:
        content = content.replace('encoding="iso-8859-1"', 'encoding="utf-8"')
        print("\n  Fix encoding: iso-8859-1 -> utf-8")
    return content


def process_file(filepath, dry_run=False):
    """Apply all fixes to a single I3D file. Returns True if changes were needed."""
    if not os.path.exists(filepath):
        print(f"\n  File not found: {filepath}")
        return False

    print(f"\n{'='*60}")
    print(f"  File: {filepath}")
    print(f"{'='*60}")

    with open(filepath, 'rb') as f:
        raw = f.read()
    try:
        content = raw.decode('utf-8')
    except UnicodeDecodeError:
        content = raw.decode('iso-8859-1')

    original = content
    content, _ = fix_dollar_data_paths(content)
    content, _ = fix_collision_masks(content)
    content = fix_encoding(content)

    needs_changes = content != original

    if dry_run:
        if needs_changes:
            print(f"\n  DRY RUN - changes detected but NOT applied")
        else:
            print(f"\n  No changes needed")
        return needs_changes

    if not needs_changes:
        print(f"\n  No changes needed")
        return False

    bak = filepath + ".bak"
    if not os.path.exists(bak):
        shutil.copy2(filepath, bak)
        print(f"\n  Backup: {bak}")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"\n  Fixed file written: {filepath}")
    return True


def main():
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    files = [a for a in args if not a.startswith("--")]

    if not files:
        print(__doc__)
        print("\nUsage:")
        print("  python fs25_fix_i3d.py kamaz65116.i3d")
        print("  python fs25_fix_i3d.py kamaz65116.i3d --dry-run")
        return

    any_changed = any(process_file(fp, dry_run) for fp in files)

    print(f"\n{'='*60}")
    if dry_run:
        print("  DRY RUN complete. Re-run without --dry-run to apply.")
    elif any_changed:
        print("  ALL FIXES APPLIED. Now open the I3D in GE10 and File -> Save to rebuild .shapes.")
    else:
        print("  No fixes needed on these files.")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
