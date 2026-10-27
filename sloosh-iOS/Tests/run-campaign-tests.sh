#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  sloosh/Sources/Data/Models/RemoteCampaign.swift \
  sloosh/Sources/Data/Repositories/RemoteCampaignStore.swift \
  Tests/RemoteCampaignTests.swift \
  -o "$test_dir/campaign-tests"
"$test_dir/campaign-tests" ../endpoint.json
