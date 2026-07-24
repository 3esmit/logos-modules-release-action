#!/usr/bin/env bash
set -euo pipefail

module_name="${1-}"
require_all="${2-}"
requested_json="${3-}"
shift 3 || true

if [[ -z "$module_name" ]]; then
    printf 'module name must be non-empty\n' >&2
    exit 2
fi

case "$require_all" in
    true|false) ;;
    *)
        printf 'require_all_variants must be true or false: %s\n' "$require_all" >&2
        exit 2
        ;;
esac

if ! jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' \
    <<<"$requested_json" >/dev/null; then
    printf 'requested variants must be a non-empty JSON string array\n' >&2
    exit 2
fi

requested_sorted="$(jq -cS 'sort' <<<"$requested_json")"
built=()
prefix="${module_name}-"

for artifact in "$@"; do
    filename="$(basename "$artifact")"
    if [[ "$filename" != "$prefix"* || "$filename" != *.lgx ]]; then
        printf 'artifact does not match module package name: %s\n' "$filename" >&2
        exit 2
    fi
    variant="${filename#"$prefix"}"
    built+=("${variant%.lgx}")
done

built_json="$(printf '%s\n' "${built[@]:-}" | jq -Rsc 'split("\n") | map(select(length > 0)) | sort')"
missing_json="$(jq -cn --argjson requested "$requested_sorted" --argjson built "$built_json" '$requested - $built')"

if [[ "$require_all" == "true" && "$built_json" != "$requested_sorted" ]]; then
    printf 'strict release requires every requested variant; requested=%s built=%s\n' \
        "$requested_sorted" "$built_json" >&2
    exit 1
fi

jq -cn --argjson built "$built_json" --argjson missing "$missing_json" \
    '{built: $built, missing: $missing}'
