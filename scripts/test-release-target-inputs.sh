#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
parser="$root/scripts/release-target-inputs.sh"
workflow="$root/.github/workflows/release.yml"

assert_json() {
    local metadata_path="$1"
    local build_attr="$2"
    local expected="$3"
    local actual
    actual="$("$parser" "$metadata_path" "$build_attr")"
    if [[ "$(jq -cS . <<<"$actual")" != "$(jq -cS . <<<"$expected")" ]]; then
        printf 'unexpected target for metadata=%s attr=%s\nexpected: %s\nactual: %s\n' \
            "$metadata_path" "$build_attr" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_rejected() {
    if "$parser" "$1" "$2" >/dev/null 2>&1; then
        printf 'invalid target unexpectedly succeeded: metadata=%s attr=%s\n' "$1" "$2" >&2
        exit 1
    fi
}

assert_json \
    'metadata.json' \
    'lgx-portable' \
    '{"metadata_path":"metadata.json","build_attr":"lgx-portable"}'

assert_json \
    'core/metadata.json' \
    'core-lgx-portable' \
    '{"metadata_path":"core/metadata.json","build_attr":"core-lgx-portable"}'

assert_rejected '' 'lgx-portable'
assert_rejected '/metadata.json' 'lgx-portable'
assert_rejected '../metadata.json' 'lgx-portable'
assert_rejected 'core/../metadata.json' 'lgx-portable'
assert_rejected 'core/metadata.json' ''
assert_rejected 'core/metadata.json' 'core-lgx-portable;whoami'

grep -Fq 'metadata_path:' "$workflow"
grep -Fq 'build_attr:' "$workflow"
grep -Fq 'nix build ".#${BUILD_ATTR}" --print-out-paths --no-link' "$workflow"
