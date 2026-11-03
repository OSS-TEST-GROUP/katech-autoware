#!/usr/bin/env bash
# Resolve completely before emitting any apt list. Never mask rosdep failures.
set -euo pipefail
src_path=${1:?source path required}
ros_distro=${2:?ROS distribution required}
shift 2
keys=$(rosdep keys "$@" --ignore-src --from-paths "$src_path")
if [[ -z "$keys" ]]; then
    exit 0
fi
mapfile -t rosdep_keys <<< "$keys"
resolved=$(rosdep resolve --rosdistro "$ros_distro" "${rosdep_keys[@]}")
printf '%s\n' "$resolved" | awk '!/^#/ { for (i=1; i<=NF; i++) print $i }' | sort -u
