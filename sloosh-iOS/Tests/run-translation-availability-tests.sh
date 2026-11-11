#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/UI/Shared/TranslationAvailabilityPolicy.swift \
  Tests/TranslationAvailabilityTests.swift \
  -o "$test_dir/translation-availability-tests"
"$test_dir/translation-availability-tests"
