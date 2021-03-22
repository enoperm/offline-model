#!/usr/bin/env bash
set -ex -o pipefail

cd "$(dirname "$(readlink -f "${0}")")"

jq -r < dub.json \
    '.configurations | map(select(.name != "default")) | .[].name' | \
    xargs -I{} -n1 dub test --verror -c '{}'
