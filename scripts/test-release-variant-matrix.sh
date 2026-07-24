#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
parser="$root/scripts/release-variant-matrix.sh"
workflow="$root/.github/workflows/release.yml"

assert_json() {
    local input="$1"
    local expected="$2"
    local actual
    actual="$("$parser" "$input")"
    if [[ "$(jq -cS . <<<"$actual")" != "$(jq -cS . <<<"$expected")" ]]; then
        printf 'unexpected matrix for %s\nexpected: %s\nactual: %s\n' \
            "$input" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_json \
    'linux-amd64,darwin-arm64' \
    '{"variants":["linux-amd64","darwin-arm64"],"matrix":[{"variant":"linux-amd64","runner":"ubuntu-latest"},{"variant":"darwin-arm64","runner":"macos-latest"}]}'

assert_json \
    'darwin-arm64,linux-amd64,linux-arm64' \
    '{"variants":["darwin-arm64","linux-amd64","linux-arm64"],"matrix":[{"variant":"darwin-arm64","runner":"macos-latest"},{"variant":"linux-amd64","runner":"ubuntu-latest"},{"variant":"linux-arm64","runner":"ubuntu-24.04-arm"}]}'

if "$parser" 'linux-amd64,unknown' >/dev/null 2>&1; then
    printf 'unknown variant unexpectedly succeeded\n' >&2
    exit 1
fi

if "$parser" 'linux-amd64,linux-amd64' >/dev/null 2>&1; then
    printf 'duplicate variant unexpectedly succeeded\n' >&2
    exit 1
fi

grep -Fq 'include: ${{ fromJson(needs.setup.outputs.build_matrix) }}' "$workflow"
grep -Fq 'runs-on: ${{ matrix.runner }}' "$workflow"
grep -Fq 'install_macos_metal_toolchain:' "$workflow"
grep -Fq "if: inputs.install_macos_metal_toolchain && matrix.variant == 'darwin-arm64'" "$workflow"
grep -Fq 'sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer' "$workflow"
grep -Fq 'xcodebuild -downloadComponent metalToolchain' "$workflow"
grep -Fq 'env -u DEVELOPER_DIR -u SDKROOT xcrun --sdk macosx --find metal' "$workflow"
grep -Fq 'env -u DEVELOPER_DIR -u SDKROOT xcrun --sdk macosx --find metallib' "$workflow"
grep -Fq 'nix_args+=(--option sandbox false)' "$workflow"
if grep -Fq 'matrix.runs-on' "$workflow"; then
    printf 'workflow still uses a static runner include mapping\n' >&2
    exit 1
fi
