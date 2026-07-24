# logos-modules-release-action

Versioned, reusable GitHub Actions for publishing Logos modules.

A consumer repo (e.g. `logos-co/logos-modules-v2` or any third-party fork)
holds the module submodules and calls these workflows. The mechanism itself
is version-pinned (`@v1`, `@v2`, ...) so consumers upgrade on their own
cadence.

## What this gives you

For each module in your repo, the `release.yml` workflow:

1. Reads selected metadata to pick up `name` and `version`.
2. Builds the module's `.lgx` on a per-variant matrix (Linux + macOS by
   default). Supplying `variants` builds exactly those supported variants;
   unknown or duplicate names fail before a runner is allocated.
3. Merges the per-variant artifacts into a single multi-variant `.lgx`
   (via `lgx merge`).
4. `lgx verify` — fails the run if the package is invalid.
5. **Optional signing** (see [Signing](#signing) below).
6. `lgx manifest --json` to extract the embedded manifest, then build a
   sidecar JSON capturing `releasedAt`, `publisherRef`, `sha256`,
   `rootHash`, the full manifest, and (when signed) the embedded
   `manifest.sig`.
7. Publishes a per-module GitHub release tagged `<module>-v<version>`
   with the `.lgx` and the sidecar attached.
8. Dispatches `rebuild-index`, which:
   - Walks every release in the repo.
   - Reads each sidecar.
   - Aggregates them into a single `index.json`.
   - Uploads it to the rolling `index` release tag.

Clients (the `lgpd` CLI, the Logos `package_downloader` module) fetch
`logos-repo.json` from the repo root and `index.json` from the rolling
`index` release — that's the entire catalog contract.

## Consumer workflow

```yaml
# .github/workflows/release-chat.yml in your repo
on: { workflow_dispatch: {} }
jobs:
  release:
    uses: logos-co/logos-modules-release-action/.github/workflows/release.yml@v1
    with:
      module_path: submodules/logos-chat-module
      variants: linux-amd64,darwin-arm64
      signing_mode: inline                   # or "external" / "none"
    secrets:
      signing_key: ${{ secrets.LOGOS_SIGNING_KEY }}
```

Repeat per module. Bumping the submodule pointer (and thereby its
`metadata.json` `version`) is what triggers a new release.

### Multiple packages from one source tree

The default target is the source root's `metadata.json` and
`lgx-portable` output. A source tree that intentionally exposes multiple
packages can select a nested manifest and a different portable flake output:

```yaml
jobs:
  release-core:
    uses: logos-co/logos-modules-release-action/.github/workflows/release.yml@v1
    with:
      module_path: submodules/logos-inspector
      metadata_path: core/metadata.json
      build_attr: core-lgx-portable
      variants: linux-amd64
      signing_mode: none
```

Both inputs are validated before a build. `metadata_path` must be a relative
JSON path below `module_path`, and `build_attr` must be a non-empty safe flake
attribute. The resulting LGX manifest is still cross-checked against the
selected metadata, so package identity, release tag, and sidecar remain tied
to the built package rather than the source directory.

### Source-owned releases

When the source repository itself owns a package release, call the reusable
workflow from that repository. The workflow reads its helper scripts from the
immutable workflow revision, so the source repository does not need to copy
implementation scripts.

```yaml
# .github/workflows/release-lez-core.yml
name: Publish LEZ Core

on:
  workflow_dispatch:

permissions:
  contents: write

jobs:
  release:
    uses: 3esmit/logos-modules-release-action/.github/workflows/release.yml@v1.0.3
    with:
      module_path: .
      metadata_path: metadata.json
      build_attr: lgx-portable
      variants: linux-amd64,darwin-arm64
      require_all_variants: true
      dispatch_rebuild_index: false
      prerelease: true
      signing_mode: none
```

`require_all_variants` defaults to `false` for compatibility: existing
catalog callers can still publish the variants that build successfully. Set it
to `true` for a source-owned release that must offer every requested platform.
In that mode, failed matrix jobs, missing artifacts, and already-published
partial sidecars are never treated as a completed release; a replacement is
published only after every requested build succeeds. `dispatch_rebuild_index`
defaults to `true`; source repositories should set it to `false` when an
independent catalog indexes their release assets.

`prerelease` defaults to `false`. Set it to `true` when a package is being
introduced through an alpha or beta GitHub Release while preserving the package
version declared by its metadata.

### Idempotent releases (skip if already published)

`release.yml` skips the (expensive) Nix build when a release tagged
`<module>-v<version>` already exists **and** carries both a `.lgx` and
a `sidecar.json` asset — i.e. that version is, or will be on the next
index rebuild, in the catalog. Re-running a workflow for an unchanged
submodule is therefore a fast no-op, and the umbrella "release all"
only rebuilds modules whose version actually moved.

- The release (not `index.json`) is the source of truth — the index is
  derived from releases and eventually consistent, so release-existence
  is the correct, race-free gate.
- A release missing either asset is treated as **not** published, so a
  half-finished prior run self-heals on the next trigger.
- On the skip path the action still nudges `rebuild-index`, so
  "already published" promptly implies "in the index".
- Force a rebuild/republish of the same version with
  `skip_if_published: false`.

### Unpublishing (remove a module or a version)

```yaml
# .github/workflows/unpublish.yml in your repo
on: { workflow_dispatch: { inputs: {
  module:  { required: true, type: string },
  version: { type: string, default: "" },     # blank = ALL versions
  delete_tags: { type: boolean, default: true },
  dry_run: { type: boolean, default: false } } } }
permissions: { contents: write }
jobs:
  unpublish:
    uses: logos-co/logos-modules-release-action/.github/workflows/unpublish.yml@v1
    with:
      module:      ${{ inputs.module }}
      version:     ${{ inputs.version }}
      delete_tags: ${{ inputs.delete_tags }}
      dry_run:     ${{ inputs.dry_run }}
```

Deletes the matching GitHub release(s) (every `<module>-v*` when
`version` is blank, otherwise just `<module>-v<version>`), optionally
their git tags, then rebuilds `index.json` so clients stop offering the
removed package(s). The rolling `index` release is hard-guarded against
deletion. **`dry_run: true` lists what would be removed and stops** —
run that first; deletion is irreversible.

You also need a one-shot workflow that wires up rebuild-index for
automatic triggering, plus a top-level `logos-repo.json` at the repo
root:

```yaml
# .github/workflows/rebuild-index.yml
on: { workflow_dispatch: {}, repository_dispatch: { types: [rebuild-index] } }
jobs:
  rebuild:
    uses: logos-co/logos-modules-release-action/.github/workflows/rebuild-index.yml@v1
```

## Signing

Three mutually exclusive `signing_mode` values:

| Mode       | What runs                            | Where the key lives                                   |
| ---------- | ------------------------------------ | ----------------------------------------------------- |
| `none`     | nothing                              | n/a (unsigned release)                                |
| `inline`   | `lgx sign` inside the workflow       | GitHub Actions `signing_key` secret (JWK string)      |
| `external` | a user-supplied command (`signing_command`) | Anywhere — Jenkins, HSM, hardware token, ... |

For `signing_mode: external`, the workflow runs `signing_command` with
two env vars set:

- `LGX_PATH` — absolute path to the unsigned `.lgx` produced by the build.
- `LGX_SIGNED_OUT` — destination path; if your command writes the signed
  package here, the workflow picks it up. If you modify `LGX_PATH`
  in-place instead, that's fine too.

Optional `signing_command_image` runs the command inside a Docker image,
useful when the signing toolchain isn't on the default runner.

## `logos-repo.json` in your repo

The client identifies your repository by the URL of a `logos-repo.json`
file. Put one at the root of your default branch (or wherever you prefer
— the URL is opaque to the client). Schema:

```json
{
  "schemaVersion": 1,
  "name": "my-logos-modules",
  "displayName": "My Modules",
  "description": "...",
  "homepage": "https://example.com/modules",
  "indexUrl": "https://github.com/<owner>/<repo>/releases/download/index/index.json",
  "trustedSigners": [
    { "did": "did:jwk:...", "name": "..." }
  ]
}
```

## Versioning

This repo follows the standard "moving-major-tag" pattern:

- `@v1` — moving tag pointing at the latest 1.x release.
- `@v1.2.3` — exact pin (recommended for production).
- `main` — bleeding edge; not for consumers.

Bumping `v2` means a breaking change to the workflow's inputs or output
schema. Stay on `@v1` until you've migrated.

## License

MIT.
