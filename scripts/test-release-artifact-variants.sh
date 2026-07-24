#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
parser="$root/scripts/release-artifact-variants.sh"
sidecar_parser="$root/scripts/release-sidecar-variants.sh"
workflow="$root/.github/workflows/release.yml"
tmpdir="$(mktemp -d)"

linux="$tmpdir/lez_core-linux-amd64.lgx"
darwin="$tmpdir/lez_core-darwin-arm64.lgx"
trap 'rm -- "$linux" "$darwin"; rmdir "$tmpdir"' EXIT
touch "$linux" "$darwin"

assert_json() {
    local strict="$1"
    local expected="$2"
    shift 2
    local actual
    actual="$("$parser" lez_core "$strict" '["linux-amd64","darwin-arm64"]' "$@")"
    if [[ "$(jq -cS . <<<"$actual")" != "$(jq -cS . <<<"$expected")" ]]; then
        printf 'unexpected artifact selection\nexpected: %s\nactual: %s\n' \
            "$expected" "$actual" >&2
        exit 1
    fi
}

assert_rejected() {
    if "$parser" lez_core "$@" >/dev/null 2>&1; then
        printf 'invalid artifact selection unexpectedly succeeded\n' >&2
        exit 1
    fi
}

assert_json \
    false \
    '{"built":["linux-amd64"],"missing":["darwin-arm64"]}' \
    "$linux"
assert_json \
    true \
    '{"built":["darwin-arm64","linux-amd64"],"missing":[]}' \
    "$linux" "$darwin"
assert_rejected true '["linux-amd64","darwin-arm64"]' "$linux"
assert_rejected maybe '["linux-amd64","darwin-arm64"]' "$linux"

sidecar_variants="$("$sidecar_parser" 'darwin-arm64,linux-amd64' '')"
if [[ "$(jq -cS . <<<"$sidecar_variants")" != \
      '{"built":["darwin-arm64","linux-amd64"],"missing":[]}' ]]; then
    printf 'empty missing-variant CSV did not produce a JSON array: %s\n' \
        "$sidecar_variants" >&2
    exit 1
fi

sidecar_variants="$("$sidecar_parser" 'linux-amd64' 'darwin-arm64')"
if [[ "$(jq -cS . <<<"$sidecar_variants")" != \
      '{"built":["linux-amd64"],"missing":["darwin-arm64"]}' ]]; then
    printf 'non-empty sidecar variant CSV was not preserved: %s\n' \
        "$sidecar_variants" >&2
    exit 1
fi

grep -Fq 'job.workflow_repository' "$workflow"
grep -Fq 'job.workflow_sha' "$workflow"
grep -Fq 'require_all_variants:' "$workflow"
grep -Fq 'dispatch_rebuild_index:' "$workflow"
grep -Fq 'prerelease:' "$workflow"
grep -Fq "needs.build.result == 'success'" "$workflow"
