#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(readlink -f "$(dirname "$0")")
WORKSPACE_ROOT=$(readlink -f "$TEST_DIR/..")

# shellcheck source=../release/tagging.sh
source "$WORKSPACE_ROOT/release/tagging.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

expect_success() {
    "$@" >/dev/null 2>&1 || fail "expected success: $*"
}

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        fail "expected failure: $*"
    fi
}

expect_success release_platform_arch linux/amd64
expect_success release_platform_arch linux/arm64
expect_failure release_platform_arch linux/ppc64le

expect_success release_validate_snapshot_tag main-20260731-abcdef0 main abcdef0
expect_failure release_validate_snapshot_tag develop-20260731-abcdef0 main abcdef0
expect_failure release_validate_snapshot_tag main-20260230-abcdef0 main abcdef0
expect_failure release_validate_snapshot_tag main-20260731-1234567 main abcdef0

expect_success release_validate_semver_tag v0.1.0
expect_success release_validate_semver_tag v1.2.0-rc1
expect_failure release_validate_semver_tag 0.1.0
expect_failure release_validate_semver_tag v01.2.3
expect_failure release_validate_semver_tag v1.2

expect_success release_validate_lock_manifest "$WORKSPACE_ROOT/release/autoware-release.repos"

echo "release tagging tests: PASS"
