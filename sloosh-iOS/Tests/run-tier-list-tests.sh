#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/Data/Models/TierListModels.swift \
  sloosh/Sources/Data/Repositories/TierListsRepository.swift \
  Tests/TierListRepositoryTestSupport.swift \
  Tests/TierListPolicyTests.swift \
  -o "$test_dir/tier-list-tests"
"$test_dir/tier-list-tests"
