#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  sloosh/Sources/Data/Repositories/LocalMediaPathPolicy.swift \
  Tests/LocalMediaPathPolicyTests.swift \
  -o "$test_dir/local-media-path-tests"
"$test_dir/local-media-path-tests"
