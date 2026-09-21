#!/usr/bin/env bash

set -euo pipefail

TEST_DIR=$(readlink -f "$(dirname "$0")")
WORKSPACE_ROOT=$(readlink -f "$TEST_DIR/..")
FIXTURE_ROOT=$(mktemp -d)
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "$FIXTURE_ROOT/work/release" "$FIXTURE_ROOT/state"
cp "$WORKSPACE_ROOT/release/tagging.sh" "$FIXTURE_ROOT/work/release/"
cp "$WORKSPACE_ROOT/release/publish-ghcr.sh" "$FIXTURE_ROOT/work/release/"

git -C "$FIXTURE_ROOT/work" init -q -b main
git -C "$FIXTURE_ROOT/work" config user.name "Release Test"
git -C "$FIXTURE_ROOT/work" config user.email "release-test@example.com"
git -C "$FIXTURE_ROOT/work" add release
git -C "$FIXTURE_ROOT/work" commit -qm "release fixture"
git clone -q --bare "$FIXTURE_ROOT/work" "$FIXTURE_ROOT/origin.git"
git -C "$FIXTURE_ROOT/work" remote add origin "$FIXTURE_ROOT/origin.git"

source_sha=$(git -C "$FIXTURE_ROOT/work" rev-parse HEAD)
short_sha=$(git -C "$FIXTURE_ROOT/work" rev-parse --short=7 HEAD)
snapshot_tag="main-20260731-${short_sha}"
git -C "$FIXTURE_ROOT/work" tag -a v0.1.0 -m "v0.1.0"
git -C "$FIXTURE_ROOT/work" push -q origin v0.1.0

test_path="$WORKSPACE_ROOT/tests/helpers:$PATH"
common_env=(
    "PATH=$test_path"
    "MOCK_REGISTRY_STATE=$FIXTURE_ROOT/state"
    "MOCK_SNAPSHOT_TAG=$snapshot_tag"
    "MOCK_SOURCE_SHA=$source_sha"
    "SNAPSHOT_TAG=$snapshot_tag"
    "RELEASE_TAG=v0.1.0"
)

mkdir -p "$FIXTURE_ROOT/bad-state"
if env "${common_env[@]}" \
    "MOCK_REGISTRY_STATE=$FIXTURE_ROOT/bad-state" \
    "MOCK_BAD_NATIVE=adsw-control-arm64" \
    "$FIXTURE_ROOT/work/release/publish-ghcr.sh" >/dev/null 2>&1; then
    echo "FAIL: mismatched native revision was not rejected" >&2
    exit 1
fi
if find "$FIXTURE_ROOT/bad-state" -type f -print -quit | grep -q .; then
    echo "FAIL: a snapshot was published before all native images passed validation" >&2
    exit 1
fi

env "${common_env[@]}" "$FIXTURE_ROOT/work/release/publish-ghcr.sh"
env "${common_env[@]}" "$FIXTURE_ROOT/work/release/publish-ghcr.sh"

if env "${common_env[@]}" "MOCK_BAD_RELEASE=adsw-perception" \
    "$FIXTURE_ROOT/work/release/publish-ghcr.sh" >/dev/null 2>&1; then
    echo "FAIL: immutable release tag mismatch was not rejected" >&2
    exit 1
fi

echo "publish GHCR tests: PASS"
