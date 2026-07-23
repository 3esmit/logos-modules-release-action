#!/usr/bin/env bash
set -euo pipefail

input="${1-}"
IFS=',' read -r -a raw_variants <<<"$input" || true

variants=()
entries=()
for raw_variant in "${raw_variants[@]:-}"; do
    variant="${raw_variant//[[:space:]]/}"
    [[ -n "$variant" ]] || continue

    case "$variant" in
        darwin-arm64)
            runner="macos-latest"
            ;;
        linux-amd64)
            runner="ubuntu-latest"
            ;;
        linux-arm64)
            runner="ubuntu-24.04-arm"
            ;;
        *)
            printf 'unsupported release variant: %s\n' "$variant" >&2
            exit 2
            ;;
    esac

    if [[ " ${variants[*]:-} " == *" $variant "* ]]; then
        printf 'duplicate release variant: %s\n' "$variant" >&2
        exit 2
    fi

    variants+=("$variant")
    entries+=(
        "$(jq -cn --arg variant "$variant" --arg runner "$runner" \
            '{variant: $variant, runner: $runner}')"
    )
done

if (( ${#variants[@]} == 0 )); then
    printf 'release variants input parsed to an empty list: %s\n' "$input" >&2
    exit 2
fi

variants_json="$(printf '%s\n' "${variants[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
matrix_json="$(printf '%s\n' "${entries[@]}" | jq -sc '.')"
jq -cn --argjson variants "$variants_json" --argjson matrix "$matrix_json" \
    '{variants: $variants, matrix: $matrix}'
