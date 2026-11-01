#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  Tests/PosterQualityTests.swift \
  -o "$test_dir/poster-quality-tests"
"$test_dir/poster-quality-tests"
