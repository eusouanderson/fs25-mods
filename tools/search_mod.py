#!/usr/bin/env python3
"""
FS25 Mod Search Tool — B.O.B's FS25 Mod Tool
==============================================
Search for FS25 mod conversions in the local database and GitHub releases.

Usage:
    python search_mod.py <query>
    python search_mod.py renault
    python search_mod.py kamaz
    python search_mod.py --manufacturer mercedes
    python search_mod.py --list-categories
    python search_mod.py --list-all
    python search_mod.py --sync          # Fetch all releases from GitHub
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
DB_PATH = TOOLS_DIR / "fs25-mods-db.json"
REPO = "eusouanderson/fs25-mods"

CATEGORY_EMOJI = {
    "trucks": "\U0001F69A",
    "tractors": "\U0001F69C",
    "trailers": "\U0001F69B",
    "maps": "\U0001F5FA\uFE0F",
    "cars": "\U0001F697",
}


def load_db() -> dict:
    if not DB_PATH.exists():
        return {"mods": []}
    return json.loads(DB_PATH.read_text(encoding="utf-8"))


def save_db(db: dict):
    DB_PATH.write_text(
        json.dumps(db, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


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
    except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
        return []


def search_local(db: dict, query: str) -> list[dict]:
    q = query.lower()
    results = []
    for mod in db.get("mods", []):
        terms = [mod.get("name", "").lower(), mod.get("manufacturer", "").lower(),
                 mod.get("slug", "").lower(), mod.get("description", "").lower()]
        terms.extend(t.lower() for t in mod.get("search_terms", []))
        if q in " ".join(terms):
            results.append(mod)
        elif any(q in t for t in terms):
            results.append(mod)
        # Check individual words
        for word in q.split():
            if word in " ".join(terms):
                if mod not in results:
                    results.append(mod)
    return results


def search_github(releases: list[dict], query: str) -> list[dict]:
    q = query.lower()
    results = []
    for r in releases:
        tag = r["tagName"].lower()
        name = r.get("name", "").lower()
        if q in tag or q in name:
            results.append(r)
        elif any(word in tag for word in q.split()):
            results.append(r)
    return results


def print_mod_table(mods: list[dict]):
    if not mods:
        return
    name_w = max(len(m["name"]) for m in mods) + 2
    manu_w = max(len(m.get("manufacturer", "")) for m in mods) + 2
    ver_w = 10
    print()
    header = f"  {'Mod':<{name_w}} {'Marca':<{manu_w}} {'Versão':<{ver_w}} Download"
    print(f"  {'=' * len(header)}")
    print(header)
    print(f"  {'=' * len(header)}")
    for m in sorted(mods, key=lambda x: x["name"].lower()):
        emoji = CATEGORY_EMOJI.get(m.get("category", ""), "\U0001F4E6")
        url = m.get("release_url", "")
        print(f"  {emoji} {m['name']:<{name_w-2}} {m.get('manufacturer', '-'):<{manu_w}} "
              f"v{m.get('version', '?'):<{ver_w-1}} {url}")
    print()


def print_github_table(releases: list[dict]):
    if not releases:
        return
    print()
    print(f"  {'='*60}")
    print(f"  Encontrados no GitHub (não cadastrados no DB):")
    print(f"  {'='*60}")
    for r in sorted(releases, key=lambda x: x["tagName"]):
        print(f"  \U0001F4E6 {r['tagName']}")
        print(f"      {r.get('url', '')}")
    print()


def cmd_search(query: str, manufacturer: str | None, db_only: bool):
    db = load_db()

    if not query and not manufacturer:
        print("  \u2716  Forneça um termo de busca. Use --help para ajuda.")
        sys.exit(1)

    # Search local
    if query:
        local_results = search_local(db, query)
    else:
        local_results = db["mods"]

    # Filter by manufacturer
    if manufacturer:
        mq = manufacturer.lower()
        local_results = [m for m in local_results if m.get("manufacturer", "").lower() == mq]

    if local_results:
        print_mod_table(local_results)
    else:
        print(f"  \u2139  Nenhum mod encontrado no banco local para: {query or manufacturer}")

    # Search GitHub
    if not db_only:
        releases = fetch_github_releases()
        if releases and query:
            known_base = {_base_slug(m["slug"]) for m in db["mods"]}
            github_results = search_github(releases, query)
            new = [r for r in github_results if
                   _base_slug(r["tagName"]) not in known_base]
            if new:
                print_github_table(new)
            elif not local_results:
                print(f"  \u2139  Também não encontrado no GitHub.")
    elif not local_results:
        print(f"  \u2139  Nada encontrado.")


def _base_slug(tag: str) -> str:
    slug = tag
    while "-v" in slug:
        parts = slug.rsplit("-v", 1)
        if parts[1] and parts[1][0].isdigit():
            slug = parts[0]
        else:
            break
    return slug


def cmd_sync():
    print("  \U0001F504  Sincronizando com GitHub releases...")
    releases = fetch_github_releases()
    if not releases:
        print("  \u2716  Não foi possível buscar releases do GitHub. `gh` CLI instalado?")
        sys.exit(1)

    db = load_db()
    known_base = {_base_slug(m["slug"]) for m in db["mods"]}

    added = 0
    seen = set()
    for r in releases:
        tag = r["tagName"]
        base = _base_slug(tag)
        if base in known_base or base in seen:
            continue
        seen.add(base)
        version = "?"
        if "-v" in tag:
            version = tag.rsplit("-v", 1)[1]
        name = base.replace("-", " ").title()
        name = name.replace("Fs25", "FS25").replace("Fs", "FS")
        db["mods"].append({
            "name": name,
            "slug": base,
            "category": "other",
            "manufacturer": "?",
            "converted": True,
            "converted_by": "?",
            "version": version,
            "release_url": f"https://github.com/{REPO}/releases/tag/{tag}",
            "original_author": "?",
            "original_game": "FS22",
            "search_terms": base.split("-"),
            "added": r.get("createdAt", "?")[:10],
        })
        added += 1

    if added:
        save_db(db)
        print(f"  \u2705  {added} novo(s) mod(s) adicionado(s) ao banco.")
    else:
        print(f"  \u2139  Banco já está atualizado.")


def cmd_list_all(manufacturer: str | None):
    db = load_db()
    mods = db["mods"]
    if manufacturer:
        mq = manufacturer.lower()
        mods = [m for m in mods if m.get("manufacturer", "").lower() == mq]

    if not mods:
        print(f"  \u2139  Nenhum mod encontrado.")
        return

    print(f"\n  Total: {len(mods)} mods convertidos\n")
    print_mod_table(mods)


def cmd_list_categories():
    db = load_db()
    cats = {}
    for m in db["mods"]:
        cat = m.get("category", "other")
        cats.setdefault(cat, 0)
        cats[cat] += 1
    print(f"\n  Categorias disponíveis:")
    for cat, count in sorted(cats.items()):
        emoji = CATEGORY_EMOJI.get(cat, "\U0001F4E6")
        print(f"    {emoji} {cat}: {count} mod(s)")
    print()


def main():
    parser = argparse.ArgumentParser(
        description="Busca mods convertidos para FS25 no banco local e GitHub.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Exemplos:\n"
            "  python search_mod.py renault\n"
            "  python search_mod.py kamaz\n"
            "  python search_mod.py mercedes --manufacturer\n"
            "  python search_mod.py --list-all\n"
            "  python search_mod.py --sync\n"
        ),
    )
    parser.add_argument("query", nargs="?", help="Termo de busca (nome, marca, palavra-chave)")
    parser.add_argument("--manufacturer", "-m", help="Filtrar por fabricante")
    parser.add_argument("--db-only", action="store_true", help="Buscar apenas no banco local (sem GitHub)")
    parser.add_argument("--sync", action="store_true", help="Sincronizar banco com GitHub releases")
    parser.add_argument("--list-all", action="store_true", help="Listar todos os mods no banco")
    parser.add_argument("--list-categories", action="store_true", help="Listar categorias disponíveis")

    args = parser.parse_args()

    if args.sync:
        cmd_sync()
    elif args.list_all:
        cmd_list_all(args.manufacturer)
    elif args.list_categories:
        cmd_list_categories()
    elif args.query:
        cmd_search(args.query, args.manufacturer, args.db_only)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
