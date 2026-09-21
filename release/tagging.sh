#!/usr/bin/env bash

# Shared validation helpers for native release builds.
# This file is sourced by partition/partition_build.sh and the release tests.

release_die() {
    echo "ERROR: $*" >&2
    return 1
}

release_platform_arch() {
    case "$1" in
    linux/amd64)
        printf '%s\n' "amd64"
        ;;
    linux/arm64)
        printf '%s\n' "arm64"
        ;;
    *)
        release_die "unsupported release platform '$1' (expected linux/amd64 or linux/arm64)"
        ;;
    esac
}

release_validate_snapshot_tag() {
    local snapshot_tag="$1"
    local default_branch="$2"
    local source_short_sha="$3"
    local expected_pattern="^${default_branch}-[0-9]{8}-${source_short_sha}$"

    if [[ ! "$snapshot_tag" =~ $expected_pattern ]]; then
        release_die "snapshot tag '$snapshot_tag' must match ${default_branch}-YYYYMMDD-${source_short_sha}"
        return 1
    fi

    local snapshot_date="${snapshot_tag#${default_branch}-}"
    snapshot_date="${snapshot_date%-${source_short_sha}}"
    if ! date -u -d "${snapshot_date:0:4}-${snapshot_date:4:2}-${snapshot_date:6:2}" +%Y%m%d \
        2>/dev/null | grep -Fxq "$snapshot_date"; then
        release_die "snapshot tag '$snapshot_tag' contains an invalid UTC date"
        return 1
    fi
}

release_validate_semver_tag() {
    local release_tag="$1"
    if [[ ! "$release_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(rc|beta)[1-9][0-9]*)?$ ]]; then
        release_die "release tag '$release_tag' is not an allowed vMAJOR.MINOR.PATCH tag"
        return 1
    fi
}

release_lock_entries() {
    local manifest="$1"
    awk '
        /^  [A-Za-z0-9_.\/-]+:$/ {
            path = $1
            sub(/:$/, "", path)
        }
        /^    version: / {
            print path "\t" $2
        }
    ' "$manifest"
}

release_validate_lock_manifest() {
    local manifest="$1"
    local total_versions
    local valid_versions

    if [ ! -f "$manifest" ]; then
        release_die "release dependency lock not found: $manifest"
        return 1
    fi

    total_versions=$(awk '/^    version: / { count++ } END { print count + 0 }' "$manifest")
    valid_versions=$(release_lock_entries "$manifest" |
        awk '$2 ~ /^[0-9a-f]{40}$/ { count++ } END { print count + 0 }')

    if [ "$total_versions" -eq 0 ] || [ "$total_versions" -ne "$valid_versions" ]; then
        release_die "every version in $manifest must be a full 40-character Git commit SHA"
        return 1
    fi
}

release_validate_dependency_checkouts() {
    local workspace_root="$1"
    local manifest="$2"
    local path
    local expected_sha
    local actual_sha
    local dependency_count=0

    while IFS=$'\t' read -r path expected_sha; do
        dependency_count=$((dependency_count + 1))
        if [ ! -d "$workspace_root/src/$path/.git" ]; then
            release_die "locked dependency checkout is missing: src/$path"
            return 1
        fi

        actual_sha=$(git -C "$workspace_root/src/$path" rev-parse HEAD)
        if [ "$actual_sha" != "$expected_sha" ]; then
            release_die "src/$path is at $actual_sha, expected $expected_sha"
            return 1
        fi

        if [ -n "$(git -C "$workspace_root/src/$path" status --porcelain)" ]; then
            release_die "locked dependency checkout is dirty: src/$path"
            return 1
        fi
    done < <(release_lock_entries "$manifest")

    if [ "$dependency_count" -eq 0 ]; then
        release_die "release dependency lock contains no repositories"
        return 1
    fi
}

release_validate_source() {
    local workspace_root="$1"
    local manifest="$2"
    local snapshot_tag="$3"
    local platform="$4"
    local default_branch="$5"
    local current_branch
    local source_sha
    local source_short_sha

    current_branch=$(git -C "$workspace_root" symbolic-ref --quiet --short HEAD || true)
    if [ "$current_branch" != "$default_branch" ]; then
        release_die "native staging push is allowed only from '$default_branch' (current: '${current_branch:-detached HEAD}')"
        return 1
    fi

    if [ -n "$(git -C "$workspace_root" status --porcelain)" ]; then
        release_die "top-level checkout is dirty; commit, remove, or ignore local files before a release build"
        return 1
    fi

    source_sha=$(git -C "$workspace_root" rev-parse HEAD)
    source_short_sha=$(git -C "$workspace_root" rev-parse --short=7 HEAD)

    release_platform_arch "$platform" >/dev/null
    release_validate_snapshot_tag "$snapshot_tag" "$default_branch" "$source_short_sha"
    release_validate_lock_manifest "$manifest"
    release_validate_dependency_checkouts "$workspace_root" "$manifest"

    printf 'Release source validated: branch=%s revision=%s snapshot=%s platform=%s\n' \
        "$current_branch" "$source_sha" "$snapshot_tag" "$platform"
}
