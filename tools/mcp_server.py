#!/usr/bin/env python3
"""
FS25 Mod Search MCP Server
==========================
MCP (Model Context Protocol) server for searching FS25 mod conversions.
Exposes tools for opencode to query the mod database.

Usage:
    python mcp_server.py
"""

import json
import subprocess
import sys
import traceback
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
DB_PATH = TOOLS_DIR / "fs25-mods-db.json"
REPO = "eusouanderson/fs25-mods"


# ── Database helpers ──────────────────────────────────────────────────────────

def load_db() -> dict:
    if not DB_PATH.exists():
        return {"mods": []}
    return json.loads(DB_PATH.read_text(encoding="utf-8"))


def save_db(db: dict):
    DB_PATH.write_text(
        json.dumps(db, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _base_slug(tag: str) -> str:
    slug = tag
    while "-v" in slug:
        parts = slug.rsplit("-v", 1)
        if parts[1] and parts[1][0].isdigit():
            slug = parts[0]
        else:
            break
    return slug


# ── Search logic ──────────────────────────────────────────────────────────────

def search_local(db: dict, query: str) -> list[dict]:
    q = query.lower()
    results = []
    for mod in db.get("mods", []):
        terms = [
            mod.get("name", "").lower(),
            mod.get("manufacturer", "").lower(),
            mod.get("slug", "").lower(),
            mod.get("description", "").lower(),
        ]
        terms.extend(t.lower() for t in mod.get("search_terms", []))
        combined = " ".join(terms)
        if q in combined:
            results.append(mod)
        else:
            for word in q.split():
                if word in combined and mod not in results:
                    results.append(mod)
    return results


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


def search_github(releases: list[dict], query: str) -> list[dict]:
    q = query.lower()
    results = []
    for r in releases:
        tag = r["tagName"].lower()
        if q in tag:
            results.append(r)
        elif any(word in tag for word in q.split()):
            results.append(r)
    return results


# ── Tool implementations ──────────────────────────────────────────────────────

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
        local_results = [
            m for m in local_results
            if m.get("manufacturer", "").lower() == mq
        ]

    result = {
        "local": local_results,
        "github": [],
        "total_local": len(local_results),
    }

    if not db_only:
        releases = fetch_github_releases()
        if releases:
            known_base = {_base_slug(m["slug"]) for m in db["mods"]}
            github_results = search_github(releases, query)
            new = [
                r for r in github_results
                if _base_slug(r["tagName"]) not in known_base
            ]
            result["github"] = new

    return result


def tool_list_mods(params: dict) -> dict:
    manufacturer = params.get("manufacturer")
    db = load_db()
    mods = db["mods"]

    if manufacturer:
        mq = manufacturer.lower()
        mods = [m for m in mods if m.get("manufacturer", "").lower() == mq]

    return {
        "mods": mods,
        "total": len(mods),
    }


def tool_list_categories(params: dict) -> dict:
    db = load_db()
    cats = {}
    for m in db["mods"]:
        cat = m.get("category", "other")
        cats[cat] = cats.get(cat, 0) + 1
    return {"categories": cats}


def tool_sync_mods(params: dict) -> dict:
    releases = fetch_github_releases()
    if not releases:
        return {"error": "Could not fetch GitHub releases. Is `gh` CLI installed and authenticated?"}

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

    return {"added": added}


TOOLS = {
    "search_mods": {
        "name": "search_mods",
        "description": "Search FS25 mod conversions by name, manufacturer, or keywords. Queries local database and optionally GitHub releases.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search term (mod name, manufacturer, keyword)"},
                "manufacturer": {"type": "string", "description": "Filter by manufacturer (optional)"},
                "db_only": {"type": "boolean", "description": "Only search local database, skip GitHub (optional)"},
            },
            "required": ["query"],
        },
        "handler": tool_search_mods,
    },
    "list_mods": {
        "name": "list_mods",
        "description": "List all known FS25 mod conversions in the database, optionally filtered by manufacturer.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "manufacturer": {"type": "string", "description": "Filter by manufacturer (optional)"},
            },
        },
        "handler": tool_list_mods,
    },
    "list_categories": {
        "name": "list_categories",
        "description": "List all available mod categories with counts.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
        "handler": tool_list_categories,
    },
    "sync_mods": {
        "name": "sync_mods",
        "description": "Synchronize the local mod database with GitHub releases. Adds any new releases as mod entries.",
        "inputSchema": {
            "type": "object",
            "properties": {},
        },
        "handler": tool_sync_mods,
    },
}


# ── MCP Protocol (JSON-RPC 2.0 over stdio) ───────────────────────────────────

def send_message(msg: dict):
    line = json.dumps(msg, ensure_ascii=False)
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def handle_request(msg: dict) -> dict | None:
    method = msg.get("method", "")
    msg_id = msg.get("id")
    params = msg.get("params", {})

    if method == "initialize":
        return {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {},
            },
            "serverInfo": {
                "name": "fs25-mods-search",
                "version": "1.0.0",
            },
        }

    if method == "notifications/initialized":
        return None

    if method == "tools/list":
        tool_defs = [
            {k: v for k, v in t.items() if k != "handler"}
            for t in TOOLS.values()
        ]
        return {"tools": tool_defs}

    if method == "tools/call":
        tool_name = params.get("name", "")
        arguments = params.get("arguments", {})

        tool = TOOLS.get(tool_name)
        if not tool:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Unknown tool: {tool_name}",
                    }
                ],
            }

        try:
            result = tool["handler"](arguments)
            if "error" in result:
                return {
                    "isError": True,
                    "content": [{"type": "text", "text": result["error"]}],
                }
            return {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(result, indent=2, ensure_ascii=False),
                    }
                ],
            }
        except Exception as e:
            return {
                "isError": True,
                "content": [
                    {
                        "type": "text",
                        "text": f"Error: {e}\n{traceback.format_exc()}",
                    }
                ],
            }

    return {
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            send_message({
                "jsonrpc": "2.0",
                "error": {"code": -32700, "message": f"Parse error: {e}"},
            })
            continue

        msg_id = msg.get("id")
        result = handle_request(msg)

        if result is not None:
            resp = {"jsonrpc": "2.0", "id": msg_id}
            if "error" in result:
                resp["error"] = result["error"]
            else:
                resp["result"] = result
            send_message(resp)


if __name__ == "__main__":
    main()
