#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
WORKSPACE_ROOT=$(readlink -f "$SCRIPT_DIR/..")

DEFAULT_BRANCH="main"
IMAGE_NAMESPACE="${IMAGE_NAMESPACE:-ghcr.io/oss-test-group}"
LEGACY_REPOSITORY="${LEGACY_REPOSITORY:-ghcr.io/oss-test-group/autoware-partition}"
RELEASE_TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
SNAPSHOT_TAG="${SNAPSHOT_TAG:?SNAPSHOT_TAG is required}"

# shellcheck source=tagging.sh
source "$SCRIPT_DIR/tagging.sh"

cd "$WORKSPACE_ROOT"

current_branch="${GITHUB_REF_NAME:-$(git symbolic-ref --quiet --short HEAD || true)}"
if [ "$current_branch" != "$DEFAULT_BRANCH" ]; then
    echo "Publish must run from $DEFAULT_BRANCH, not ${current_branch:-detached HEAD}." >&2
    exit 1
fi

source_sha=$(git rev-parse HEAD)
source_short_sha=$(git rev-parse --short=7 HEAD)
release_validate_snapshot_tag "$SNAPSHOT_TAG" "$DEFAULT_BRANCH" "$source_short_sha"
release_validate_semver_tag "$RELEASE_TAG"

git fetch --force --tags origin
if [ "$(git cat-file -t "refs/tags/${RELEASE_TAG}")" != "tag" ]; then
    echo "$RELEASE_TAG must be an annotated Git tag." >&2
    exit 1
fi

tag_sha=$(git rev-parse "${RELEASE_TAG}^{commit}")
if [ "$tag_sha" != "$source_sha" ]; then
    echo "$RELEASE_TAG resolves to $tag_sha, but the release source is $source_sha." >&2
    exit 1
fi

components=(adsw-perception adsw-decision adsw-control)
declare -A amd64_digests
declare -A arm64_digests
declare -A snapshot_present
declare -A snapshot_digests

inspect_image_manifest_digest() {
    docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' | jq -er '.digest'
}

inspect_platform_digest() {
    local manifest_json="$1"
    local architecture="$2"
    jq -er --arg architecture "$architecture" \
        '.manifests[] | select(.platform.os == "linux" and .platform.architecture == $architecture) | .digest' \
        <<<"$manifest_json"
}

validate_native_image() {
    local reference="$1"
    local expected_arch="$2"
    local image_json
    local manifest_json
    local actual

    image_json=$(docker buildx imagetools inspect "$reference" --format '{{json .Image}}')
    manifest_json=$(docker buildx imagetools inspect "$reference" --format '{{json .Manifest}}')

    actual=$(jq -er '.architecture' <<<"$image_json")
    [ "$actual" = "$expected_arch" ] || {
        echo "$reference architecture is $actual, expected $expected_arch." >&2
        return 1
    }

    actual=$(jq -er '.os' <<<"$image_json")
    [ "$actual" = "linux" ] || {
        echo "$reference OS is $actual, expected linux." >&2
        return 1
    }

    actual=$(jq -er '.config.Labels["org.opencontainers.image.revision"]' <<<"$image_json")
    [ "$actual" = "$source_sha" ] || {
        echo "$reference revision label is $actual, expected $source_sha." >&2
        return 1
    }

    actual=$(jq -er '.config.Labels["org.opencontainers.image.ref.name"]' <<<"$image_json")
    [ "$actual" = "$DEFAULT_BRANCH" ] || {
        echo "$reference ref label is $actual, expected $DEFAULT_BRANCH." >&2
        return 1
    }

    actual=$(jq -er '.config.Labels["org.opencontainers.image.version"]' <<<"$image_json")
    [ "$actual" = "$SNAPSHOT_TAG" ] || {
        echo "$reference version label is $actual, expected $SNAPSHOT_TAG." >&2
        return 1
    }

    actual=$(jq -er '.config.Labels["org.opencontainers.image.source"]' <<<"$image_json")
    [ "$actual" = "https://github.com/OSS-TEST-GROUP/katech-autoware" ] || {
        echo "$reference source label is unexpected: $actual." >&2
        return 1
    }

    jq -er '.config.Labels["org.opencontainers.image.created"] | length > 0' \
        <<<"$image_json" >/dev/null
    jq -er '.digest' <<<"$manifest_json"
}

for component in "${components[@]}"; do
    repository="${IMAGE_NAMESPACE}/${component}"
    amd64_ref="${repository}:${SNAPSHOT_TAG}-amd64"
    arm64_ref="${repository}:${SNAPSHOT_TAG}-arm64"
    snapshot_ref="${repository}:${SNAPSHOT_TAG}"

    amd64_digests["$component"]=$(validate_native_image "$amd64_ref" amd64)
    arm64_digests["$component"]=$(validate_native_image "$arm64_ref" arm64)

    if existing_json=$(docker buildx imagetools inspect "$snapshot_ref" \
        --format '{{json .Manifest}}' 2>/dev/null); then
        existing_amd64=$(inspect_platform_digest "$existing_json" amd64)
        existing_arm64=$(inspect_platform_digest "$existing_json" arm64)
        if [ "$existing_amd64" != "${amd64_digests[$component]}" ] ||
            [ "$existing_arm64" != "${arm64_digests[$component]}" ]; then
            echo "Refusing to overwrite immutable snapshot $snapshot_ref." >&2
            exit 1
        fi
        snapshot_present["$component"]=true
    else
        snapshot_present["$component"]=false
    fi
done

# All six native images are valid. Only now create any missing public snapshots.
for component in "${components[@]}"; do
    repository="${IMAGE_NAMESPACE}/${component}"
    snapshot_ref="${repository}:${SNAPSHOT_TAG}"

    if [ "${snapshot_present[$component]}" = "false" ]; then
        docker buildx imagetools create \
            --tag "$snapshot_ref" \
            "${repository}@${amd64_digests[$component]}" \
            "${repository}@${arm64_digests[$component]}"
    fi

    existing_json=$(docker buildx imagetools inspect "$snapshot_ref" \
        --format '{{json .Manifest}}')
    platform_count=$(jq -er \
        '[.manifests[] | select(.platform.os == "linux" and (.platform.architecture == "amd64" or .platform.architecture == "arm64"))] | length' \
        <<<"$existing_json")
    [ "$platform_count" -eq 2 ] || {
        echo "$snapshot_ref must contain exactly one amd64 and one arm64 image." >&2
        exit 1
    }

    snapshot_digests["$component"]=$(jq -er '.digest' <<<"$existing_json")
done

# Release tags are immutable. Validate every component before moving any pointer.
for component in "${components[@]}"; do
    repository="${IMAGE_NAMESPACE}/${component}"
    release_ref="${repository}:${RELEASE_TAG}"
    if release_digest=$(inspect_image_manifest_digest "$release_ref" 2>/dev/null); then
        if [ "$release_digest" != "${snapshot_digests[$component]}" ]; then
            echo "Refusing to overwrite immutable release tag $release_ref." >&2
            exit 1
        fi
    fi
done

for component in "${components[@]}"; do
    repository="${IMAGE_NAMESPACE}/${component}"
    snapshot_digest="${snapshot_digests[$component]}"

    docker buildx imagetools create \
        --tag "${repository}:latest" \
        --tag "${repository}:${RELEASE_TAG}" \
        "${repository}@${snapshot_digest}"

    # Compatibility pointer. Deprecated at v1.0.0.
    docker buildx imagetools create \
        --tag "${LEGACY_REPOSITORY}:${component}" \
        "${repository}@${snapshot_digest}"

    published_digest=$(inspect_image_manifest_digest "${repository}:${RELEASE_TAG}")
    [ "$published_digest" = "$snapshot_digest" ] || {
        echo "Post-publish digest verification failed for ${repository}:${RELEASE_TAG}." >&2
        exit 1
    }
done

summary_file="${GITHUB_STEP_SUMMARY:-/dev/null}"
{
    echo "## Published release"
    echo
    echo "- Source: \`${source_sha}\`"
    echo "- Git tag: \`${RELEASE_TAG}\`"
    echo "- Snapshot: \`${SNAPSHOT_TAG}\`"
    echo
    echo "| Image | Digest |"
    echo "| --- | --- |"
    for component in "${components[@]}"; do
        echo "| \`${IMAGE_NAMESPACE}/${component}:${RELEASE_TAG}\` | \`${snapshot_digests[$component]}\` |"
    done
} >>"$summary_file"
