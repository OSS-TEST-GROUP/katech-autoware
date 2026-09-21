#!/usr/bin/env bash

set -euo pipefail

# Function to print help message
print_help() {
    echo "Usage: build.sh [OPTIONS]"
    echo "Options:"
    echo "  --help          Display this help message"
    echo "  -h              Display this help message"
    echo "  --repo          Docker image repository (default: ghcr.io/oss-test-group/autoware-partition)"
    echo "  --no-cuda       Disable CUDA support"
    echo "  --platform      Specify the platform (default: current platform)"
    echo "  --devel-only    Build devel image only"
    echo "  --push          Reserved for --native-staging (direct legacy push is blocked)"
    echo "  --native-staging Build and push one native release architecture"
    echo "  --snapshot-tag  Shared immutable tag: main-YYYYMMDD-<shortsha>"
    echo "  --namespace     Release image namespace (default: ghcr.io/oss-test-group)"
    echo ""
    echo "Note: The --platform option should be one of 'linux/amd64' or 'linux/arm64'."
}

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
WORKSPACE_ROOT="$SCRIPT_DIR/.."
RELEASE_DIR="$WORKSPACE_ROOT/release"
RELEASE_MANIFEST="$RELEASE_DIR/autoware-release.repos"
DEFAULT_BRANCH="main"
partitions=()

# targets=()
# stages=(
#     "core-devel"
#     "universe-common-devel"
#     "universe-common-devel-cuda"
#     "universe-perception-devel"
#     "universe-sensing-devel"
#     "universe-perception-devel-cuda"
#     "universe-sensing-devel-cuda"
#     "universe-localization-devel"
#     "universe-mapping-devel"
#     "universe-planning-devel"
#     "universe-control-devel"
#     "universe-vehicle-devel"
#     "universe-system-devel"
#     "universe-devel-cuda"
#     "universe-cuda"
#     "adsw-perception"
#     "adsw-perception-cuda"
#     "adsw-decision"
#     "adsw-control"
# )

repo="${PARTITION_IMAGE_REPO:-ghcr.io/oss-test-group/autoware-partition}"
image_namespace="${PARTITION_IMAGE_NAMESPACE:-ghcr.io/oss-test-group}"
output_type="--load"
option_no_cuda=false
option_platform=""
option_devel_only=false
native_staging=false
push_requested=false
snapshot_tag=""
setup_args=""
ssh_allow_option=()
ssh_set_option=()

# shellcheck source=../release/tagging.sh
source "$RELEASE_DIR/tagging.sh"

# Parse arguments
parse_arguments() {
    while [ "${1:-}" != "" ]; do
        case "$1" in
        --help | -h)
            print_help
            exit 0
            ;;
        --no-cuda)
            option_no_cuda=true
            ;;
        --platform)
            option_platform="$2"
            shift
            ;;
        --repo)
            repo="$2"
            shift
            ;;
        --devel-only)
            option_devel_only=true
            ;;
        --push)
            push_requested=true
            output_type="--push"
            ;;
        --native-staging)
            native_staging=true
            output_type="--push"
            ;;
        --snapshot-tag)
            snapshot_tag="$2"
            shift
            ;;
        --namespace)
            image_namespace="$2"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            print_help
            exit 1
            ;;
        esac
        shift
    done

}

# Set CUDA options
set_cuda_options() {
    if [ "$option_no_cuda" = "true" ]; then
        setup_args="--no-nvidia"
        image_name_suffix=""
    else
        image_name_suffix="-cuda"
    fi
}

# Set build options
# set_build_options() {
#     if [ "$option_devel_only" = "true" ]; then
#         targets=("universe-devel")
#     #else
#     #    targets=("$target")
#     fi
# }

# Set platform
set_platform() {
    if [ -n "$option_platform" ]; then
        platform="$option_platform"
    else
        platform="linux/amd64"
        if [ "$(uname -m)" = "aarch64" ]; then
            platform="linux/arm64"
        fi
    fi
}

validate_native_staging_options() {
    if [ "$native_staging" != "true" ]; then
        if [ "$push_requested" = "true" ]; then
            echo "ERROR: direct --push is disabled; use the guarded --native-staging flow." >&2
            exit 1
        fi
        return
    fi

    if [ -z "$snapshot_tag" ]; then
        echo "ERROR: --native-staging requires --snapshot-tag." >&2
        exit 1
    fi

    if [ "$option_no_cuda" != "true" ]; then
        echo "ERROR: the current release scope is No-CUDA; add --no-cuda." >&2
        exit 1
    fi

    if [[ "$image_namespace" != */* ]]; then
        echo "ERROR: --namespace must include a registry host and owner." >&2
        exit 1
    fi
}

# Set arch lib dir
set_arch_lib_dir() {
    if [ "$platform" = "linux/arm64" ]; then
        lib_dir="aarch64"
    elif [ "$platform" = "linux/amd64" ]; then
        lib_dir="x86_64"
    else
        echo "Unsupported platform: $platform"
        exit 1
    fi
}

# Set SSH forwarding options for Docker BuildKit.
set_ssh_options() {
    if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
        ssh_allow_option=("--allow=ssh")
        ssh_set_option=("--set *.ssh=default")
    else
        ssh_allow_option=()
        ssh_set_option=()
        echo "SSH_AUTH_SOCK is not set or not a socket; building without SSH agent forwarding."
    fi
}

# Load env
load_env() {
    source "$WORKSPACE_ROOT/amd64.env"
    if [ "$platform" = "linux/arm64" ]; then
        source "$WORKSPACE_ROOT/arm64.env"
    fi
    if [ "$native_staging" = "true" ]; then
        # shellcheck source=../release/base-images.env
        source "$RELEASE_DIR/base-images.env"
    fi
}

# Clone repositories
# copy_config() {

#     echo "copy_config==================================================="

#     cp -r "$WORKSPACE_ROOT/src/launcher/autoware_launch/autoware_launch/" "$WORKSPACE_ROOT/src/obigo_launch/"

#     target_root="$WORKSPACE_ROOT/src/obigo_launch/config_files"
#     mkdir -p "$target_root"

#     if [ ! -d "$WORKSPACE_ROOT/src" ]; then
#         exit 1
#     fi

#     find "$WORKSPACE_ROOT/src" -type d -name config | while read -r config_dir; do
#         package_xml_path="$(dirname "$config_dir")/package.xml"

#         if [[ -f "$package_xml_path" ]]; then
#             package_name=$(awk -F'[<>]' '/<name>/ {print $3}' "$package_xml_path")

#             if [[ -n "$package_name" ]]; then
#                 target_dir="$target_root/$package_name"
#                 mkdir -p "$target_dir"

#                 cp -r "$config_dir/"* "$target_dir/"
#                 echo "Copied files from $config_dir to $target_dir"
#             else
#                 echo "Warning: <name> tag not found in $package_xml_path"
#             fi
#         else
#             echo "Warning: package.xml not found for config folder $config_dir"
#         fi
#     done
# }

# Clone repositories
clone_repositories() {
    cd "$WORKSPACE_ROOT"
    if [ "$native_staging" = "true" ]; then
        release_validate_lock_manifest "$RELEASE_MANIFEST"
        if [ ! -d "src" ]; then
            mkdir -p src
            vcs import src <"$RELEASE_MANIFEST"
        fi
        release_validate_source \
            "$WORKSPACE_ROOT" \
            "$RELEASE_MANIFEST" \
            "$snapshot_tag" \
            "$platform" \
            "$DEFAULT_BRANCH"
    elif [ ! -d "src" ]; then
        mkdir -p src
        vcs import src <autoware.repos
    else
        echo "Source directory already exists. Updating repositories..."
        vcs import src <autoware.repos
        vcs pull src
    fi
}


get_pkg_path() {

    local PKG_LIST="$1"
    local paths=()

    for pkg in $PKG_LIST; do
        path=$(find src -name package.xml -exec grep -l "<name>$pkg</name>" {} \;)
        if [ -n "$path" ]; then
            echo "$pkg: $(dirname "$path")" >&2
            paths+=($(dirname "$path"))
        else
            echo "$pkg: ❌ not found" >&2
            return 1
        fi
    done

    # return paths
    echo "${paths[@]}"
}


configuration_and_build() {
    local partition_name=""
    local folder_path="$1"

    if [ ! -d "$folder_path" ]; then
        echo "ERROR: '$folder_path' does not exist." >&2
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: 'jq' is not installed."
        echo ""
        echo "Install:"
        echo "  Ubuntu / Debian:"
        echo "    sudo apt update && sudo apt install -y jq"
        exit 1
    fi

    while read file; do
        local copy_list=""
        local bind_list=""

        echo "$file"

        if ! jq empty "$file" >/dev/null; then
            echo "Error: '$file' JSON parsing failed!"
            exit 1
        fi

        partition_name=$(basename $file '.json')
        echo "$partition_name"

        packages=$(jq -r '.packages // [] | .[]' "$file")

        echo "$packages"

        pkg_paths=$(get_pkg_path "${packages}")
        if [ $? -ne 0 ]; then
            echo "Error: Failed to find all packages for $partition_name. Aborting." >&2
            exit 1
        fi

        for path in $pkg_paths; do
            copy_list+="COPY ${path} /autoware/${path}\n"
            bind_list+="--mount=type=bind,from=${partition_name}-depend,source=/autoware/${path},target=/autoware/${path} \\\\\n"
        done

        folders=$(jq -r '.folders  // [] | .[]' "$file")
        for f in ${folders}; do
            copy_list+="COPY ${f} /autoware/${f}\n"
            bind_list+="--mount=type=bind,from=${partition_name}-depend,source=/autoware/${f},target=/autoware/${f} \\\\\n"
        done

        echo "=========copy_list============="
        echo -e "${copy_list}"
        echo "=========bind_list============="
        echo -e "${bind_list}"


        sed -e "s|%PARTITION_NAME%|$partition_name|g" \
            -e "s|%COPY_LIST%|${copy_list}|g" \
            -e "s|%BIND_LIST%|${bind_list}|g" \
            partition/Dockerfile.template >partition/${partition_name}_Dockerfile

        build_images "${partition_name}"

        rm -f partition/${partition_name}_Dockerfile

    done < <(find $folder_path -type f -name '*.json')
}

# Build base images
build_base_images() {
    # https://github.com/docker/buildx/issues/484
    export BUILDKIT_STEP_LOG_MAX_SIZE=10000000

    echo "Building images for platform: $platform"
    echo "ROS distro: $rosdistro"
    echo "Base image: $base_image"
    echo "Setup args: $setup_args"
    echo "Lib dir: $lib_dir"
    echo "Image name suffix: $image_name_suffix"

    base_option=()
    base_option+=("$output_type")
    base_option+=("--progress=plain")
    base_option+=("-f" "$SCRIPT_DIR/docker-bake-base.hcl")
    base_option+=("--set *.context=$WORKSPACE_ROOT")
    base_option+=("${ssh_set_option[@]}")
    if [ "$native_staging" = "true" ]; then
        base_option+=("--provenance=false")
        base_option+=("--set *.platform=$platform")
    elif [ "$output_type" = "--push" ]; then
        base_option+=("--set *.platform=linux/amd64,linux/arm64")
    else
        base_option+=("--set *.platform=$platform")
    fi
    base_option+=("--set *.args.ROS_DISTRO=$rosdistro")
    base_option+=("--set *.args.BASE_IMAGE=$base_image")
    base_option+=("--set *.args.SETUP_ARGS=$setup_args")
    base_option+=("--set *.args.LIB_DIR=$lib_dir")
    if [ "$native_staging" = "true" ]; then
        release_arch=$(release_platform_arch "$platform")
        release_base_repo="${image_namespace}/adsw-build-base"
        release_base_tag="${snapshot_tag}-${release_arch}"
        base_option+=("--set base.tags=${release_base_repo}:${release_base_tag}")
    else
        base_option+=("--set base.tags=$repo:latest")
        base_option+=("--set base-cuda.tags=$repo:cuda-latest")
    fi

    base_targets=("base")
    if [ "$option_no_cuda" != "true" ]; then
        base_targets+=("base-cuda")
    fi

    set -x
    docker buildx bake "${ssh_allow_option[@]}" "${base_option[@]}" "${base_targets[@]}"
    set +x
}

# Build images
build_images() {
    local partition_name="$1"
    local image_tag="${partition_name#sample-}"
    local target_repo="$repo"
    local target_tag="${image_tag}${image_name_suffix}"
    # https://github.com/docker/buildx/issues/484
    export BUILDKIT_STEP_LOG_MAX_SIZE=10000000

    echo "Building images for platform: $platform"
    echo "ROS distro: $rosdistro"
    echo "Base image: $base_image"
    echo "Setup args: $setup_args"
    echo "Lib dir: $lib_dir"
    echo "Image name suffix: $image_name_suffix"
    #echo "Targets: ${targets[*]}"
    echo "Stage: $1"

    if [ "$native_staging" = "true" ]; then
        release_arch=$(release_platform_arch "$platform")
        target_repo="${image_namespace}/${image_tag}"
        target_tag="${snapshot_tag}-${release_arch}"
        autoware_base_image="${image_namespace}/adsw-build-base:${snapshot_tag}-${release_arch}"
        autoware_base_cuda_image="$autoware_base_image"
    else
        autoware_base_image="${repo}:latest"
        autoware_base_cuda_image="${repo}:cuda-latest"
    fi

    echo "Image: ${target_repo}:${target_tag}"
    echo "partition_name: $partition_name"
    echo "autoware_base_image: $autoware_base_image"
    echo "autoware_base_cuda_image: $autoware_base_cuda_image"

    build_option=()
    build_option+=("$output_type")
    #build_option+=("--push")
    build_option+=("--progress=plain")
    build_option+=("-f" "$SCRIPT_DIR/docker-bake.hcl")
    #build_option+=("-f $SCRIPT_DIR/docker-bake-cuda.hcl")
    build_option+=("--set *.context=$WORKSPACE_ROOT")
    build_option+=("${ssh_set_option[@]}")
    #build_option+=("--set *.platform=$platform")
    #build_option+=("--set *.platforms=linux/amd64,linux/arm64")
    build_option+=("--set *.args.ROS_DISTRO=$rosdistro")
    build_option+=("--set *.args.BASE_IMAGE=$base_image")
    build_option+=("--set *.args.AUTOWARE_BASE_IMAGE=$autoware_base_image")
    build_option+=("--set *.args.AUTOWARE_BASE_CUDA_IMAGE=$autoware_base_cuda_image")
    build_option+=("--set *.args.SETUP_ARGS=$setup_args")
    #build_option+=("--set *.args.LIB_DIR=$lib_dir")
    #build_option+=("--set partition.tags=$repo:${partition_name}-${lib_dir}")
    build_option+=("--set partition*.tags=${target_repo}:${target_tag}")
    build_option+=("--set partition*.dockerfile=partition/${partition_name}_Dockerfile")
    build_option+=("--set partition*.target=${partition_name}${image_name_suffix}")
    if [ "$native_staging" = "true" ]; then
        build_option+=("--provenance=false")
        build_option+=("--set *.platform=$platform")
        build_option+=("--set *.args.OCI_REVISION=$(git -C "$WORKSPACE_ROOT" rev-parse HEAD)")
        build_option+=("--set *.args.OCI_REF_NAME=$DEFAULT_BRANCH")
        build_option+=("--set *.args.OCI_CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
        build_option+=("--set *.args.OCI_VERSION=$snapshot_tag")
    fi

    set -x
    if [ "$native_staging" = "true" ]; then
        docker buildx bake "${ssh_allow_option[@]}" "${build_option[@]}" partition
    elif [ "$output_type" = "--push" ]; then
        docker buildx bake "${ssh_allow_option[@]}" "${build_option[@]}" partition-multi-platform
    else
        docker buildx bake "${ssh_allow_option[@]}" "${build_option[@]}" partition
    fi
    set +x
}

# Remove dangling images
remove_dangling_images() {
    docker image prune -f
}

# Main script execution
parse_arguments "$@"
set_cuda_options
#set_build_options
set_platform
validate_native_staging_options
set_arch_lib_dir
set_ssh_options
load_env
#copy_config
clone_repositories

build_base_images
configuration_and_build "partition/partition_config"

if [ "$native_staging" != "true" ]; then
    remove_dangling_images
fi
