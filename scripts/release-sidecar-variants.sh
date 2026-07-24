#!/usr/bin/env bash
set -euo pipefail

built_csv="${1-}"
missing_csv="${2-}"

jq -cn \
    --arg built "$built_csv" \
    --arg missing "$missing_csv" \
    '{
        built: ($built | split(",") | map(select(length > 0))),
        missing: ($missing | split(",") | map(select(length > 0)))
    }'
