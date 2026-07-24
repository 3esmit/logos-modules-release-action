#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$root/.github/workflows/release.yml"
cleanup_block="$(sed -n \
    '/name: Reclaim Linux runner disk/,/DeterminateSystems.*installer/p' \
    "$workflow")"

grep -Fq 'reclaim_linux_disk_space:' "$workflow"
input_block="$(sed -n \
    '/^      reclaim_linux_disk_space:/,/^      signing_mode:/p' \
    "$workflow")"
grep -Fqx '        type: boolean' <<<"$input_block"
grep -Fqx '        default: false' <<<"$input_block"
grep -Fq \
    "if: inputs.reclaim_linux_disk_space && matrix.variant == 'linux-amd64'" \
    "$workflow"
# These are intentional literal workflow-source assertions.
# shellcheck disable=SC2016
grep -Fq 'minimum_available_kib=$((20 * 1024 * 1024))' "$workflow"
# shellcheck disable=SC2016
grep -Fq 'before_kib="$(df -Pk /' "$workflow"
# shellcheck disable=SC2016
grep -Fq 'after_kib="$(df -Pk /' "$workflow"
grep -Fq 'sudo apt-get clean' "$workflow"
grep -Fq 'if ((after_kib < minimum_available_kib)); then' "$workflow"

# Intentional literal workflow-source assertion.
# shellcheck disable=SC2016
if [[ "$(grep -Fc 'sudo rm -rf -- "$path"' <<<"$cleanup_block")" -ne 1 ||
      "$(grep -Ec 'sudo rm -rf' <<<"$cleanup_block")" -ne 1 ]]; then
    printf 'cleanup must contain exactly one path-scoped recursive removal\n' >&2
    exit 1
fi
if ! awk '
    /for path in "\$\{cleanup_paths\[@\]\}"; do/ {
        in_loop = 1
    }
    in_loop && /sudo rm -rf -- "\$path"/ {
        found = 1
    }
    in_loop && /^          done$/ {
        in_loop = 0
    }
    END {
        exit !found
    }
' <<<"$cleanup_block"; then
    printf 'recursive removal must remain inside the allowlist loop\n' >&2
    exit 1
fi

for path in \
    /usr/local/lib/android \
    /usr/share/dotnet \
    /opt/ghc \
    /usr/local/.ghcup; do
    if [[ "$(grep -Fc "            $path" "$workflow")" -ne 1 ]]; then
        printf 'cleanup path must occur exactly once: %s\n' "$path" >&2
        exit 1
    fi
done

cleanup_line="$(grep -nF 'name: Reclaim Linux runner disk' "$workflow" | cut -d: -f1)"
nix_line="$(grep -m1 -nF \
    'uses: DeterminateSystems/nix-installer-action@' \
    "$workflow" |
    cut -d: -f1)"
if ((cleanup_line >= nix_line)); then
    printf 'Linux disk cleanup must run before Nix installation\n' >&2
    exit 1
fi
