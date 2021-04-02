#!/usr/bin/env sh
exec jq '"\(.name):static,\(.bounds | join(","))"'
