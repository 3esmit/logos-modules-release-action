# logos-modules-release-action

Versioned, reusable GitHub Actions for publishing Logos modules.

A consumer repo (e.g. `logos-co/logos-modules-v2` or any third-party fork)
holds the module submodules and calls these workflows. The mechanism itself
is version-pinned (`@v1`, `@v2`, ...) so consumers upgrade on their own
cadence.

## What this gives you

For each module in your repo, the `release.yml` workflow:

1. Reads `metadata.json` to pick up `name` and `version`.
2. Builds the module's `.lgx` on a per-variant matrix (Linux + macOS by
   default).
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
      signing_mode: inline                   # or "external" / "none"
    secrets:
      signing_key: ${{ secrets.LOGOS_SIGNING_KEY }}
```

Repeat per module. Bumping the submodule pointer (and thereby its
`metadata.json` `version`) is what triggers a new release.

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
