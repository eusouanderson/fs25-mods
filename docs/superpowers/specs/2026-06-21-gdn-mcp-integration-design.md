# GDN Documentation MCP Integration

## Purpose

Add 3 MCP tools to the FS25 Mods MCP server that connect to the GIANTS Developer Network
(GDN) documentation for Farming Simulator 25 scripting API.

## Tools

### `gdn_search(query)`

Search the local GDN index by class name, function name, or category.

- **Query**: string — partial or full name
- **Returns**: list of matches with class name, category, URL, and matched function names
- **Index**: auto-updated if >24h old

### `gdn_get_class(name)`

Fetch a specific class page from GDN and return formatted Markdown.

- **Name**: class name (e.g., "BuyVehicleData", "VehicleLoadingData")
- **Returns**: class description, all functions with signatures, parameters, and code examples
- **Source**: live fetch from `?category=X&class=Y&version=script`

### `gdn_fetch_url(url)`

Generic fetch of any GDN URL, returns content as formatted Markdown.

- **URL**: full or relative GDN URL
- **Returns**: page content converted to Markdown

## Index Format

Stored in `tools/fs25-gdn-index.json`:

```json
{
  "version": "1.15.0.0",
  "last_updated": "2026-06-21T12:00:00",
  "categories": {
    "Shop": { "id": 74, "classes": {
      "BuyVehicleData": { "id": 614 },
      "StoreManager": { "id": 615 }
    }},
    "Vehicles": { "id": 90, "classes": {
      "Vehicle": { "id": 886 },
      "VehicleLoadingData": { "id": 891 }
    }}
  }
}
```

## Architecture

```
gdn_search(query)
  → check index age, auto-rebuild if >24h
  → linear scan over category→class names + function names
  → return matches

gdn_get_class(name)
  → lookup category/class IDs from index
  → HTTP GET: document_scripting_fs25.php?category=X&class=Y&version=script
  → parse HTML: extract heading, description, function list, code blocks
  → return Markdown

gdn_fetch_url(url)
  → HTTP GET url
  → convert HTML→Markdown (strip nav, keep content)
  → return formatted text
```

## Implementation

- **File**: `tools/mcp_server.py` (append new tools to existing server)
- **Parser**: Python `html.parser.HTMLParser` for sidebar extraction, regex for code blocks
- **Dependencies**: none new — `urllib` + `html.parser` are stdlib
- **Index build**: 1 HTTP request for sidebar + N requests for function extraction (lazy/deferred)

## Build Strategy

1. First request to main page extracts sidebar → all categories + class names + IDs
2. Function name extraction is done lazily: when `gdn_get_class(name)` is called, the
   response also caches the function names in the index for future `gdn_search()`
3. This avoids N*M HTTP requests during initial build while still providing full-text search
   after classes have been visited
