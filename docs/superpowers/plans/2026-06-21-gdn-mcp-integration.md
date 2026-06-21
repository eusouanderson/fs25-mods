# GDN Documentation MCP Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 3 MCP tools (`gdn_search`, `gdn_get_class`, `gdn_fetch_url`) to the fs25-mods MCP server that connect to the GDN FS25 scripting documentation.

**Architecture:** Append ~250 lines of Python to the existing MCP server (`tools/mcp_server.py`). Follow existing patterns: tool_* handlers + TOOLS dict registration. Index built by crawling GDN sidebar HTML and persisted as JSON.

**Tech Stack:** Python 3 stdlib only — `urllib`, `html.parser`, `json`, `time`, `re`

## Global Constraints

- Zero new dependencies (stdlib only)
- Follow existing MCP server patterns (fetch(), load_db()/save_db(), TOOLS dict)
- Index JSON stored at `tools/fs25-gdn-index.json` alongside `fs25-mods-db.json`
- Auto-update index if >24h old
- All tools handle errors gracefully, return structured JSON

---

### Task 1: GDN Index Builder

**Files:**
- Modify: `tools/mcp_server.py` (append after line 44, before `# ── Helpers`)

**Interfaces:**
- Produces: `GDN_BASE_URL = "https://gdn.giants-software.com/documentation_scripting_fs25.php"`
- Produces: `GDN_INDEX_PATH = TOOLS_DIR / "fs25-gdn-index.json"`
- Produces: `_parse_gdn_sidebar(html) -> list[dict]` — extracts category list from main page
- Produces: `_parse_category_classes(html) -> list[dict]` — extracts class list from a category page
- Produces: `_build_gdn_index() -> dict` — builds full index by crawling all categories
- Produces: `_load_gdn_index() -> dict` — loads from JSON
- Produces: `_save_gdn_index(index)` — saves to JSON
- Produces: `_ensure_gdn_index() -> dict` — loads or builds if missing/stale

- [ ] **Step 1: Add constants and index helpers**

Append after line 44:
```python
# ── GDN Documentation ─────────────────────────────────────────────────────────

GDN_BASE_URL = "https://gdn.giants-software.com/documentation_scripting_fs25.php"
GDN_INDEX_PATH = TOOLS_DIR / "fs25-gdn-index.json"
GDN_INDEX_MAX_AGE = 86400  # 24 hours in seconds
```

- [ ] **Step 2: Add `_parse_gdn_sidebar()` helper**

```python
def _parse_gdn_sidebar(html: str) -> list[dict]:
    """Parse the GDN main page sidebar to extract category + first class entries."""
    categories = []
    # Pattern: <a href="?version=script&amp;category=X&amp;class=Y">CategoryName</a>
    for m in re.finditer(
        r'href="[^"]*\?version=script&amp;category=(\d+)&amp;class=(\d+)[^"]*"[^>]*>([^<]*)</a>',
        html
    ):
        name = m.group(3).strip()
        if not name:
            continue
        categories.append({
            "name": name,
            "category_id": int(m.group(1)),
            "class_id": int(m.group(2)),
        })
    return categories
```

- [ ] **Step 3: Add `_parse_category_classes()` helper**

```python
def _parse_category_classes(html: str) -> list[dict]:
    """Parse class list from a category page sidebar."""
    classes = []
    seen_ids = set()
    for m in re.finditer(
        r'href="[^"]*\?version=script&amp;category=(\d+)&amp;class=(\d+)[^"]*"[^>]*>([^<]+)</a>',
        html
    ):
        name = m.group(3).strip()
        class_id = int(m.group(2))
        if not name or class_id in seen_ids:
            continue
        seen_ids.add(class_id)
        classes.append({"name": name, "class_id": class_id})
    return classes
```

- [ ] **Step 4: Add `_build_gdn_index()`**

```python
def _build_gdn_index() -> dict:
    """Build complete GDN index by crawling main page + all category pages."""
    main_html = fetch(GDN_BASE_URL + "?version=script")
    categories = _parse_gdn_sidebar(main_html)
    if not categories:
        return {"version": "unknown", "last_updated": 0, "categories": {}}

    index = {"version": "unknown", "last_updated": time.time(), "categories": {}}
    for cat in categories:
        cat_id = cat["category_id"]
        cat_entry = {"id": cat_id, "classes": {}}
        cat_entry["classes"][cat["name"]] = {"id": cat["class_id"]}

        # Fetch the category's first class page to get full class list
        try:
            url = f"{GDN_BASE_URL}?version=script&category={cat_id}&class={cat['class_id']}"
            cat_html = fetch(url)
            class_list = _parse_category_classes(cat_html)
            for cls in class_list:
                if cls["name"] != cat["name"]:
                    cat_entry["classes"][cls["name"]] = {"id": cls["class_id"]}
        except Exception:
            pass  # Use at least the first class

        index["categories"][cat["name"]] = cat_entry

    return index
```

- [ ] **Step 5: Add `_load_gdn_index()` and `_save_gdn_index()`**

```python
def _load_gdn_index() -> dict:
    if not GDN_INDEX_PATH.exists():
        return None
    try:
        return json.loads(GDN_INDEX_PATH.read_text(encoding="utf-8"))
    except Exception:
        return None

def _save_gdn_index(index: dict):
    GDN_INDEX_PATH.write_text(
        json.dumps(index, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
```

- [ ] **Step 6: Add `_ensure_gdn_index()`**

```python
def _ensure_gdn_index() -> dict:
    index = _load_gdn_index()
    now = time.time()
    if index is None or (now - index.get("last_updated", 0)) > GDN_INDEX_MAX_AGE:
        try:
            index = _build_gdn_index()
            _save_gdn_index(index)
        except Exception as e:
            if index is None:
                return {"version": "unknown", "last_updated": 0, "categories": {}}
    return index
```

- [ ] **Step 7: Verify helpers work standalone**

Run: `python3 -c "exec(open('tools/mcp_server.py').read()); print('ok')"`
Expected: no errors from syntax or missing imports. (Helpers are functions, not executed at import time.)

---

### Task 2: `gdn_search` tool

**Files:**
- Modify: `tools/mcp_server.py` (add handler after existing tools, add TOOLS entry)

**Interfaces:**
- Consumes: `_ensure_gdn_index()` from Task 1
- Produces: `tool_gdn_search(params) -> dict`

- [ ] **Step 1: Add handler function**

```python
def tool_gdn_search(params: dict) -> dict:
    query = params.get("query", "")
    if not query:
        return {"error": "query parameter is required"}

    index = _ensure_gdn_index()
    q = query.lower()
    results = []

    for cat_name, cat_data in index.get("categories", {}).items():
        for cls_name, cls_data in cat_data.get("classes", {}).items():
            if q in cls_name.lower() or q in cat_name.lower():
                url = f"{GDN_BASE_URL}?version=script&category={cat_data['id']}&class={cls_data['id']}"
                results.append({
                    "class": cls_name,
                    "category": cat_name,
                    "category_id": cat_data["id"],
                    "class_id": cls_data["id"],
                    "url": url,
                })

    results.sort(key=lambda r: (0 if r["class"].lower().startswith(q) else 1, r["class"]))
    return {
        "query": query,
        "total": len(results),
        "results": results[:20],  # Limit results
    }
```

- [ ] **Step 2: Register in TOOLS**

```python
    "gdn_search": {
        "name": "gdn_search",
        "description": "Search the GDN FS25 scripting documentation for classes by name or category.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Class name or category to search for"},
            },
            "required": ["query"],
        },
        "handler": tool_gdn_search,
    },
```

- [ ] **Step 3: Verify registration**

Run: `python3 -c "exec(open('tools/mcp_server.py').read()); print('gdn_search' in TOOLS, 'gdn_get_class' in TOOLS)"
Expected: `True False` (only gdn_search registered so far)

---

### Task 3: `gdn_get_class` tool

**Files:**
- Modify: `tools/mcp_server.py`

**Interfaces:**
- Consumes: `_ensure_gdn_index()` from Task 1
- Produces: `_parse_class_page(html, class_name) -> dict`
- Produces: `tool_gdn_get_class(params) -> dict`

- [ ] **Step 1: Add `_parse_class_page()` helper**

```python
def _parse_class_page(html: str, class_name: str) -> dict:
    """Parse a GDN class page into structured documentation."""
    result = {
        "name": class_name,
        "description": "",
        "functions": [],
    }

    # Extract description (first text block after class heading)
    desc_match = re.search(
        r'<div[^>]*class="[^"]*content[^"]*"[^>]*>.*?<h[12][^>]*>(?:' + re.escape(class_name) + r')</h[12]>\s*<p[^>]*>(.*?)</p>',
        html, re.DOTALL | re.IGNORECASE
    )
    if desc_match:
        result["description"] = re.sub(r'<[^>]+>', '', desc_match.group(1)).strip()

    # Extract function blocks: ### functionName + Description + Code
    # Pattern: heading followed by description and optional code block
    func_pattern = re.compile(
        r'<h3[^>]*>(?:<a[^>]*>)?([^<]+)(?:</a>)?</h3>'
        r'(.*??)(?=<h3[^>]*>|<h[12][^>]*>|$)',
        re.DOTALL
    )
    for m in func_pattern.finditer(html):
        func_name = m.group(1).strip()
        func_html = m.group(2).strip()
        if not func_name:
            continue
        func = {"name": func_name, "description": "", "code": ""}
        # Description
        desc_m = re.search(r'<p[^>]*>(.*?)</p>', func_html, re.DOTALL)
        if desc_m:
            func["description"] = re.sub(r'<[^>]+>', '', desc_m.group(1)).strip()
        # Code block
        code_m = re.search(r'<pre[^>]*>(.*?)</pre>', func_html, re.DOTALL)
        if code_m:
            func["code"] = code_m.group(1).strip()
        result["functions"].append(func)

    return result
```

- [ ] **Step 2: Add handler**

```python
def tool_gdn_get_class(params: dict) -> dict:
    name = params.get("name", "")
    if not name:
        return {"error": "name parameter is required"}

    index = _ensure_gdn_index()
    # Find class in index
    class_info = None
    for cat_name, cat_data in index.get("categories", {}).items():
        for cls_name, cls_data in cat_data.get("classes", {}).items():
            if cls_name.lower() == name.lower():
                class_info = cls_data
                class_info["category"] = cat_name
                class_info["category_id"] = cat_data["id"]
                break
        if class_info:
            break

    if not class_info:
        return {"error": f"Class '{name}' not found in GDN index"}

    url = f"{GDN_BASE_URL}?version=script&category={class_info['category_id']}&class={class_info['id']}"
    try:
        html = fetch(url)
    except Exception as e:
        return {"error": f"Failed to fetch GDN page: {e}"}

    parsed = _parse_class_page(html, name)
    parsed["url"] = url

    # Format as readable markdown
    lines = [f"# {parsed['name']}", ""]
    if parsed["description"]:
        lines.append(parsed["description"])
        lines.append("")

    for func in parsed["functions"]:
        lines.append(f"## {func['name']}")
        lines.append("")
        if func["description"]:
            lines.append(func["description"])
            lines.append("")
        if func["code"]:
            lines.append("```lua")
            lines.append(func["code"])
            lines.append("```")
            lines.append("")

    return {
        "class": name,
        "category": class_info["category"],
        "url": url,
        "documentation": "\n".join(lines),
        "functions": [f["name"] for f in parsed["functions"]],
    }
```

- [ ] **Step 3: Register in TOOLS**

```python
    "gdn_get_class": {
        "name": "gdn_get_class",
        "description": "Fetch the full documentation page for a specific GDN FS25 class, including all functions, signatures, and code examples.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "name": {"type": "string", "description": "Class name (e.g., 'BuyVehicleData', 'VehicleLoadingData')"},
            },
            "required": ["name"],
        },
        "handler": tool_gdn_get_class,
    },
```

- [ ] **Step 4: Verify**

Run: `python3 -c "
exec(open('tools/mcp_server.py').read())
print('gdn_search' in TOOLS, 'gdn_get_class' in TOOLS)
"` Expected: `True True`

---

### Task 4: `gdn_fetch_url` tool

**Files:**
- Modify: `tools/mcp_server.py`

**Interfaces:**
- Produces: `_html_to_text(html) -> str`
- Produces: `tool_gdn_fetch_url(params) -> dict`

- [ ] **Step 1: Add `_html_to_text()` helper**

```python
def _html_to_text(html: str) -> str:
    """Convert HTML to clean plain text while preserving structure."""
    # Remove scripts and styles
    text = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
    text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL)
    # Replace block elements with newlines
    text = re.sub(r'</?(?:div|p|tr|li|ol|ul|h[1-6]|blockquote|pre|br)[^>]*>', '\n', text, flags=re.DOTALL)
    # Remove remaining tags
    text = re.sub(r'<[^>]+>', '', text)
    # Collapse whitespace
    text = re.sub(r'\n\s*\n', '\n\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    return text.strip()
```

- [ ] **Step 2: Add handler**

```python
def tool_gdn_fetch_url(params: dict) -> dict:
    url = params.get("url", "")
    if not url:
        return {"error": "url parameter is required"}

    # Allow relative URLs
    if url.startswith("?"):
        url = GDN_BASE_URL + url
    elif not url.startswith("http"):
        url = GDN_BASE_URL + "/" + url.lstrip("/")

    try:
        html = fetch(url)
    except Exception as e:
        return {"error": f"Failed to fetch URL: {e}"}

    text = _html_to_text(html)
    # Truncate if too long
    max_chars = 50000
    if len(text) > max_chars:
        text = text[:max_chars] + "\n\n[... truncated ...]"

    return {
        "url": url,
        "content": text,
        "char_count": len(text),
    }
```

- [ ] **Step 3: Register in TOOLS**

```python
    "gdn_fetch_url": {
        "name": "gdn_fetch_url",
        "description": "Fetch any GDN URL and return its content as formatted text. Useful for exploring documentation pages not covered by other tools.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "Full or relative GDN URL (e.g., '?version=script&category=74&class=614')"},
            },
            "required": ["url"],
        },
        "handler": tool_gdn_fetch_url,
    },
```

- [ ] **Step 4: Verify all tools registered**

Run: `python3 -c "
exec(open('tools/mcp_server.py').read())
for t in ['gdn_search', 'gdn_get_class', 'gdn_fetch_url']:
    print(t, t in TOOLS)
"` Expected:
```
gdn_search True
gdn_get_class True
gdn_fetch_url True
```

---

### Task 5: Integration test

**Files:**
- Test: `tools/mcp_server.py` (simulate MCP calls via stdin)

- [ ] **Step 1: Test index build**

```python
python3 -c "
exec(open('tools/mcp_server.py').read())
idx = _build_gdn_index()
cats = len(idx['categories'])
total_classes = sum(len(c['classes']) for c in idx['categories'].values())
print(f'Categories: {cats}, Total classes: {total_classes}')
# Save it
_save_gdn_index(idx)
print(f'Index saved to {GDN_INDEX_PATH}')
"
```
Expected: `Categories: ~50, Total classes: ~200-400`, no errors

- [ ] **Step 2: Test gdn_search via MCP protocol**

```python
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"gdn_search","arguments":{"query":"VehicleLoadingData"}}}' | python3 tools/mcp_server.py
```
Expected: JSON with results containing VehicleLoadingData class info

- [ ] **Step 3: Test gdn_get_class via MCP protocol**

```python
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"gdn_get_class","arguments":{"name":"BuyVehicleData"}}}' | python3 tools/mcp_server.py
```
Expected: JSON with documentation, functions list, code samples

- [ ] **Step 4: Test gdn_fetch_url via MCP protocol**

```python
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"gdn_fetch_url","arguments":{"url":"?version=script&category=74&class=614"}}}' | python3 tools/mcp_server.py
```
Expected: JSON with text content of the page

- [ ] **Step 5: Test error handling**

```python
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"gdn_search","arguments":{"query":""}}}' | python3 tools/mcp_server.py
```
Expected: Error response with "query parameter is required"

```python
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"gdn_get_class","arguments":{"name":"NonExistentClass12345"}}}' | python3 tools/mcp_server.py
```
Expected: Error response with "Class not found"

- [ ] **Step 6: Verify auto-index update works**

```python
python3 -c "
exec(open('tools/mcp_server.py').read())
# Delete existing index to force rebuild
if GDN_INDEX_PATH.exists():
    GDN_INDEX_PATH.unlink()
idx = _ensure_gdn_index()
print('Index built:', idx.get('last_updated', 0) > 0)
print('Categories:', len(idx.get('categories', {})))
# Second call should load from cache
idx2 = _ensure_gdn_index()
print('Loaded from cache:', idx2.get('last_updated') == idx.get('last_updated'))
"
```
Expected: Index built, cached, all working
