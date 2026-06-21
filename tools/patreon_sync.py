#!/usr/bin/env python3
"""
Patreon Sync — post-release hook for B.O.B's FS25 Mod Tool
=============================================================
After a GitHub Release is published, mirror it as a Patreon post
(title + changelog + download link) using the Patreon API v2.

Credentials come ONLY from environment variables — never hardcode them:
    PATREON_ACCESS_TOKEN  - creator's API access token (required to enable the hook)
    PATREON_CAMPAIGN_ID   - campaign id, attached as a relationship (optional)
    PATREON_API_BASE      - override the API base (default: https://www.patreon.com/api/oauth2/v2)
    PATREON_SYNC_ENABLED  - set to "0"/"false" to force-disable the hook

If PATREON_ACCESS_TOKEN is not set, the hook is a no-op so the release
pipeline behaves exactly as before.

Idempotency: before posting, the GitHub release notes for the tag are
checked for a "<!-- patreon-post: <url> -->" marker. If present, the
existing post URL is reused and nothing is sent to Patreon. After a
successful post, the marker is appended to the release notes.

NOTE: As of this writing, Patreon's officially documented public API v2
does not expose a documented endpoint for *creating* posts (the /posts
endpoints in docs.patreon.com are read-only, gated by the
`campaigns.posts` scope). This module implements the endpoint and
payload shape requested by the project, isolated in _build_payload()
and POSTS_ENDPOINT so they're easy to adjust if Patreon's response
indicates a different schema (e.g. "unpermitted attribute" errors).

Usage as a library (called from release_mod.py / build_release.py):
    from patreon_sync import create_patreon_post
    post_url = create_patreon_post({
        "tag": "kamaz-65116-v1.0.0",
        "title": "kamaz-65116 v1.0.0",
        "notes": "...changelog markdown...",
        "asset_url": "https://github.com/<repo>/releases/download/<tag>/FS25_Kamaz65116.zip",
        "release_url": "https://github.com/<repo>/releases/tag/<tag>",
    })

Usage standalone (e.g. a GitHub Action triggered on `release: published`):
    python3 tools/patreon_sync.py \\
        --tag "$RELEASE_TAG" --title "$RELEASE_TITLE" \\
        --notes "$RELEASE_NOTES" --asset-url "$ASSET_URL" \\
        --release-url "$RELEASE_URL"
"""

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

API_BASE = os.environ.get("PATREON_API_BASE", "https://www.patreon.com/api/oauth2/v2")
POSTS_ENDPOINT = f"{API_BASE}/posts"
DEFAULT_REPO = os.environ.get("GITHUB_REPOSITORY", "eusouanderson/fs25-mods")
MARKER_RE = re.compile(r"<!-- patreon-post: (\S+) -->")


def _is_enabled() -> bool:
    if os.environ.get("PATREON_SYNC_ENABLED", "").strip().lower() in ("0", "false", "no"):
        return False
    return bool(os.environ.get("PATREON_ACCESS_TOKEN"))


def _gh_release_body(tag: str, repo: str) -> str | None:
    try:
        r = subprocess.run(
            ["gh", "-R", repo, "release", "view", tag, "--json", "body"],
            capture_output=True, text=True, check=True, timeout=15,
        )
        return json.loads(r.stdout).get("body", "")
    except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError, OSError):
        return None


def _existing_post_url(tag: str, repo: str) -> str | None:
    """Return the Patreon post URL already linked in the release notes, if any."""
    if not tag:
        return None
    body = _gh_release_body(tag, repo)
    if not body:
        return None
    m = MARKER_RE.search(body)
    return m.group(1) if m else None


def _append_marker_to_release(tag: str, repo: str, post_url: str) -> None:
    body = _gh_release_body(tag, repo)
    if body is None:
        print("  ⚠   patreon_sync: couldn't read release notes to record the Patreon link")
        return
    if MARKER_RE.search(body):
        return
    new_body = body.rstrip("\n") + f"\n\n<!-- patreon-post: {post_url} -->\n"
    try:
        subprocess.run(
            ["gh", "-R", repo, "release", "edit", tag, "--notes", new_body],
            check=True, capture_output=True, timeout=15,
        )
    except (subprocess.CalledProcessError, FileNotFoundError, OSError) as e:
        stderr = e.stderr.decode().strip() if getattr(e, "stderr", None) else str(e)
        print(f"  ⚠   patreon_sync: couldn't update release notes with Patreon link: {stderr}")


def _build_content(release_data: dict) -> str:
    parts = [release_data.get("notes", "").strip()]
    asset_url = release_data.get("asset_url")
    if asset_url:
        parts.append(f"⬇️ Download: {asset_url}")
    release_url = release_data.get("release_url")
    if release_url:
        parts.append(f"🔗 Release notes: {release_url}")
    return "\n\n".join(p for p in parts if p)


def _build_payload(title: str, content: str) -> dict:
    attributes = {
        "title": title,
        "content": content,
        "published": True,
    }
    payload = {"data": {"type": "post", "attributes": attributes}}
    campaign_id = os.environ.get("PATREON_CAMPAIGN_ID")
    if campaign_id:
        payload["data"]["relationships"] = {
            "campaign": {"data": {"type": "campaign", "id": campaign_id}}
        }
    return payload


def _post_to_patreon(payload: dict) -> dict:
    token = os.environ["PATREON_ACCESS_TOKEN"]
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        POSTS_ENDPOINT,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "fs25-mods-patreon-sync/1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _extract_post_url(result: dict) -> str:
    data = result.get("data", {}) if isinstance(result, dict) else {}
    attrs = data.get("attributes", {}) if isinstance(data, dict) else {}
    url = attrs.get("url")
    if url:
        return url
    post_id = data.get("id")
    if post_id:
        return f"https://www.patreon.com/posts/{post_id}"
    return "https://www.patreon.com/posts/unknown"


def create_patreon_post(release_data: dict) -> str | None:
    """Create (or reuse) a Patreon post for a published GitHub release.

    release_data keys:
        tag          - release tag, used for idempotency (required)
        title        - post title, typically the release name
        notes        - changelog/description text (markdown)
        asset_url    - direct download URL of the .zip asset
        release_url  - URL of the GitHub release page
        repo         - "owner/repo" (defaults to GITHUB_REPOSITORY or the project repo)

    Returns the Patreon post URL, or None if the hook is disabled or the
    API call failed. Never raises -- failures are logged and swallowed so
    the release pipeline keeps going.
    """
    tag = release_data.get("tag", "")
    repo = release_data.get("repo") or DEFAULT_REPO

    if not _is_enabled():
        print("  ℹ   patreon_sync: skipped (PATREON_ACCESS_TOKEN not set or sync disabled)")
        return None

    existing = _existing_post_url(tag, repo)
    if existing:
        print(f"  ℹ   patreon_sync: post already exists for '{tag}', skipping: {existing}")
        return existing

    title = release_data.get("title", tag)
    content = _build_content(release_data)
    payload = _build_payload(title, content)

    print(f"  📣  patreon_sync: creating Patreon post for '{tag}'...")
    try:
        result = _post_to_patreon(payload)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        print(f"  ✖  patreon_sync: Patreon API returned HTTP {e.code}: {detail}")
        return None
    except urllib.error.URLError as e:
        print(f"  ✖  patreon_sync: network error contacting Patreon: {e.reason}")
        return None
    except Exception as e:
        print(f"  ✖  patreon_sync: unexpected error: {e}")
        return None

    post_url = _extract_post_url(result)
    print(f"  ✅  patreon_sync: post created: {post_url}")

    if tag:
        _append_marker_to_release(tag, repo, post_url)

    return post_url


def preview_post(release_data: dict) -> None:
    """Print what create_patreon_post() would do, without any network call."""
    tag = release_data.get("tag", "")
    repo = release_data.get("repo") or DEFAULT_REPO

    existing = _existing_post_url(tag, repo)
    if existing:
        print(f"  ℹ   [DRY RUN] Release '{tag}' already has a Patreon post marker: {existing}")
        print(f"  ℹ   [DRY RUN] Would skip (idempotent) -- no request would be sent")
        return

    title = release_data.get("title", tag)
    content = _build_content(release_data)
    payload = _build_payload(title, content)

    print(f"  ℹ   [DRY RUN] Would POST {POSTS_ENDPOINT}")
    print(f"  ℹ   [DRY RUN] data.attributes.title:   {title}")
    print(f"  ℹ   [DRY RUN] data.attributes.published: {payload['data']['attributes']['published']}")
    print(f"  ℹ   [DRY RUN] data.attributes.content:")
    for line in content.splitlines() or [""]:
        print(f"        {line}")
    if "relationships" in payload["data"]:
        campaign_id = payload["data"]["relationships"]["campaign"]["data"]["id"]
        print(f"  ℹ   [DRY RUN] data.relationships.campaign.id: {campaign_id}")
    else:
        print(f"  ℹ   [DRY RUN] (no PATREON_CAMPAIGN_ID set -- no campaign relationship)")
    print(f"  ℹ   [DRY RUN] No request sent. Auth: "
          f"{'PATREON_ACCESS_TOKEN is set' if os.environ.get('PATREON_ACCESS_TOKEN') else 'PATREON_ACCESS_TOKEN NOT set'}")


def main():
    parser = argparse.ArgumentParser(
        description="Create a Patreon post for a GitHub release (idempotent, best-effort).",
    )
    parser.add_argument("--tag", default=os.environ.get("RELEASE_TAG"),
                        help="GitHub release tag, used for idempotency (env: RELEASE_TAG)")
    parser.add_argument("--title", default=os.environ.get("RELEASE_TITLE"),
                        help="Post title / release name (env: RELEASE_TITLE)")
    parser.add_argument("--notes", default=os.environ.get("RELEASE_NOTES", ""),
                        help="Changelog/description text (env: RELEASE_NOTES)")
    parser.add_argument("--asset-url", default=os.environ.get("ASSET_URL"),
                        help="Direct download URL of the .zip asset (env: ASSET_URL)")
    parser.add_argument("--release-url", default=os.environ.get("RELEASE_URL"),
                        help="URL of the GitHub release page (env: RELEASE_URL)")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"),
                        help="owner/repo (env: GITHUB_REPOSITORY)")
    parser.add_argument("--dry-run", "-n", action="store_true",
                        help="Print what would be sent to Patreon, without calling the API")
    args = parser.parse_args()

    if not args.tag or not args.title:
        parser.error("--tag and --title are required (directly or via RELEASE_TAG/RELEASE_TITLE)")

    release_data = {
        "tag": args.tag,
        "title": args.title,
        "notes": args.notes or "",
        "asset_url": args.asset_url,
        "release_url": args.release_url,
        "repo": args.repo,
    }

    if args.dry_run:
        preview_post(release_data)
        sys.exit(0)

    if not _is_enabled():
        print("  ℹ   patreon_sync: skipped (PATREON_ACCESS_TOKEN not set or sync disabled)")
        sys.exit(0)

    post_url = create_patreon_post(release_data)
    if post_url:
        print(post_url)
        sys.exit(0)
    sys.exit(1)


if __name__ == "__main__":
    main()
