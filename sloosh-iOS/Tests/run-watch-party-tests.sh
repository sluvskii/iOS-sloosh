#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  sloosh/Sources/Data/Models/WatchPartyModels.swift \
  sloosh/Sources/Data/Models/MessengerModels.swift \
  Tests/WatchPartySyncTests.swift \
  -o "$test_dir/watch-party-tests"
"$test_dir/watch-party-tests"
