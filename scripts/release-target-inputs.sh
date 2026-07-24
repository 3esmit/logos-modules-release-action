#!/usr/bin/env bash
set -euo pipefail

metadata_path="${1-}"
build_attr="${2-}"

if [[ -z "$metadata_path" || "$metadata_path" == /* ]]; then
    printf 'metadata path must be a non-empty relative path: %s\n' "$metadata_path" >&2
    exit 2
fi

case "/$metadata_path/" in
    *'/../'*|*'//')
        printf 'metadata path must not contain traversal or empty segments: %s\n' "$metadata_path" >&2
        exit 2
        ;;
esac

if [[ ! "$metadata_path" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
    printf 'metadata path contains unsupported characters: %s\n' "$metadata_path" >&2
    exit 2
fi

if [[ ! "$metadata_path" =~ \.json$ ]]; then
    printf 'metadata path must name a JSON file: %s\n' "$metadata_path" >&2
    exit 2
fi

if [[ ! "$build_attr" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    printf 'build attribute must be a non-empty safe flake attribute: %s\n' "$build_attr" >&2
    exit 2
fi

jq -cn \
    --arg metadata_path "$metadata_path" \
    --arg build_attr "$build_attr" \
    '{metadata_path: $metadata_path, build_attr: $build_attr}'
