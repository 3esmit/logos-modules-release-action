#!/usr/bin/env python3
"""Build a logos-modules index.json by aggregating per-module-version releases.

Walks every release in the given GitHub repository and turns it into one
element of `packages[].versions[]`. The sidecar JSON attached to each
release (produced by release.yml) is the source of truth — we read it
verbatim rather than re-deriving from the .lgx, so the index stays cheap
to rebuild and identical across runs.

Output schema (matches plan):

    {
      "schemaVersion": 2,
      "repositoryName": "<from logos-repo.json>",
      "generatedAt":    "<ISO-8601 UTC>",
      "packages": [
        { "name": "<pkg>",
          "versions": [
            { "releasedAt": "...", "publisherRef": "...",
              "url": "...", "size": <int>, "sha256": "...", "rootHash": "...",
              "manifest": {...},
              "signature": {...}?   # optional
            },
            ...
          ]
        },
        ...
      ]
    }
"""

import argparse
import datetime as _dt
import json
import os
import re
import sys
import urllib.parse
import urllib.request


def gh_api(url: str, token: str) -> dict | list:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "logos-modules-release-action",
        },
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def iter_releases(owner: str, repo: str, token: str):
    """Yield every non-draft release for the repo, paginated."""
    page = 1
    while True:
        url = (
            f"https://api.github.com/repos/{owner}/{repo}/releases"
            f"?per_page=100&page={page}"
        )
        items = gh_api(url, token)
        if not items:
            return
        for r in items:
            if r.get("draft"):
                continue
            yield r
        if len(items) < 100:
            return
        page += 1


def fetch_asset(url: str, token: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/octet-stream",
            "Authorization": f"Bearer {token}",
            "User-Agent": "logos-modules-release-action",
        },
    )
    with urllib.request.urlopen(req) as r:
        return r.read()


# Per the action's release.yml, the per-release sidecar JSON has the
# structure ready to drop into `packages[].versions[]`. The release tag
# itself is `<module>-v<version>` (with the `index` release name reserved
# for the rolling catalog).
TAG_RE = re.compile(r"^(?P<name>[a-z][a-z0-9_-]*)-v(?P<ver>.+)$")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("error: GITHUB_TOKEN is required", file=sys.stderr)
        return 1

    # Read repo metadata from logos-repo.json at the default branch root.
    # This is best-effort — the field only feeds into the index's
    # `repositoryName`, so a fetch failure degrades to the repo's
    # GitHub name, which is fine for boot-strapping a brand-new repo.
    repo_name = args.repo
    try:
        meta_url = (
            f"https://raw.githubusercontent.com/{args.owner}/{args.repo}"
            f"/HEAD/logos-repo.json"
        )
        with urllib.request.urlopen(meta_url) as r:
            meta = json.loads(r.read())
            if isinstance(meta, dict) and isinstance(meta.get("name"), str):
                repo_name = meta["name"]
    except Exception as exc:  # noqa: BLE001
        print(
            f"warning: could not fetch logos-repo.json ({exc!r}); "
            f"falling back to repo name '{args.repo}'",
            file=sys.stderr,
        )

    # name -> list[versionEntry]
    packages: dict[str, list[dict]] = {}

    for rel in iter_releases(args.owner, args.repo, token):
        tag = rel.get("tag_name") or ""
        if tag == "index":
            continue  # the rolling index itself; skip
        m = TAG_RE.match(tag)
        if not m:
            print(f"skip: unrecognised tag '{tag}'", file=sys.stderr)
            continue
        pkg_name = m.group("name")
        assets = {a.get("name"): a for a in rel.get("assets") or []}
        sidecar_asset = assets.get("sidecar.json")
        if not sidecar_asset:
            print(
                f"skip: release '{tag}' has no sidecar.json asset",
                file=sys.stderr,
            )
            continue

        try:
            sidecar_bytes = fetch_asset(sidecar_asset["url"], token)
            entry = json.loads(sidecar_bytes)
        except Exception as exc:  # noqa: BLE001
            print(f"skip: cannot read sidecar for '{tag}': {exc!r}", file=sys.stderr)
            continue

        # The sidecar deliberately omits the `url` field — we backfill it
        # here from the release's `.lgx` asset, where the canonical
        # download URL lives.
        lgx_asset = next(
            (a for a in rel.get("assets") or [] if a.get("name", "").endswith(".lgx")),
            None,
        )
        if not lgx_asset:
            print(f"skip: release '{tag}' has no .lgx asset", file=sys.stderr)
            continue
        entry["url"] = lgx_asset.get("browser_download_url", "")

        packages.setdefault(pkg_name, []).append(entry)

    # Sort each package's versions newest-first by releasedAt.
    for vs in packages.values():
        vs.sort(key=lambda v: v.get("releasedAt", ""), reverse=True)

    out = {
        "schemaVersion": 2,
        "repositoryName": repo_name,
        "generatedAt": _dt.datetime.now(_dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "packages": [
            {"name": name, "versions": vs}
            for name, vs in sorted(packages.items())
        ],
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
        f.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
