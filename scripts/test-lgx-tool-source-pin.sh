#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pinned_flake='github:logos-co/logos-package/8d4236f9453bce8b44dfd2f85a5006af993b7ed2#lgx'

for workflow in \
    "$root/.github/workflows/release.yml" \
    "$root/.github/workflows/rebuild-index.yml"; do
    if grep -Fq 'github:logos-co/logos-package#lgx' "$workflow"; then
        printf 'workflow retains a floating Logos Package reference: %s\n' "$workflow" >&2
        exit 1
    fi
    if [[ "$(grep -Fc "LGX_TOOL_FLAKE: $pinned_flake" "$workflow")" -ne 1 ]]; then
        printf 'workflow must declare the reviewed LGX flake exactly once: %s\n' "$workflow" >&2
        exit 1
    fi
    if ! grep -Fq 'nix build "$LGX_TOOL_FLAKE" --out-link "$RUNNER_TEMP/lgx-tool"' "$workflow"; then
        printf 'workflow does not build LGX through its pinned source: %s\n' "$workflow" >&2
        exit 1
    fi
done
