#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  sloosh/Sources/UI/Shared/MessengerSearchQuery.swift \
  Tests/MessengerSearchTests.swift \
  -o "$test_dir/messenger-search-tests"
"$test_dir/messenger-search-tests"
