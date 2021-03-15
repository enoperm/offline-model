#!/usr/bin/env sh
set -e

cd "$(dirname "$(readlink -f "${0}")")"

jq -r < dub.json \
    '.configurations | map(select(.name != "default")) | .[].name' | \
    xargs -I{} -n1 dub build -c '{}'
