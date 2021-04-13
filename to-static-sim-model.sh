#!/usr/bin/env sh
exec jq -r '"\(.name):static:\(.bounds | join(","))"'
