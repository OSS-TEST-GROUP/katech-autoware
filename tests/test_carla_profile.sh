#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
WORKSPACE_ROOT=$(readlink -f "$SCRIPT_DIR/..")
cd "$WORKSPACE_ROOT"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

expect_failure() {
    local expected="$1"
    shift
    local output
    local status

    set +e
    output=$("$@" 2>&1)
    status=$?
    set -e

    [ "$status" -ne 0 ] || fail "command unexpectedly succeeded: $*"
    grep -Fq -- "$expected" <<<"$output" || {
        echo "$output" >&2
        fail "missing expected error: $expected"
    }
}

bash -n \
    partition/partition_build.sh \
    partition/run_partitions.sh \
    partition/start_script/adsw-perception-carla.sh \
    partition/start_script/adsw-decision-carla.sh \
    partition/start_script/adsw-control-carla.sh

jq -e '.carla_packages | index("autoware_carla_interface") != null' \
    partition/partition_config/sample-adsw-perception.json >/dev/null
jq -e '.carla_packages | index("autoware_raw_vehicle_cmd_converter") != null' \
    partition/partition_config/sample-adsw-perception.json >/dev/null

grep -Fq 'adsw-perception-carla-cuda' partition/run_partitions.sh
grep -Fq 'adsw-decision-carla' partition/run_partitions.sh
grep -Fq 'adsw-control-carla' partition/run_partitions.sh
grep -Fq 'install_carla_python_api="true"' partition/partition_build.sh
grep -Fq 'launch_vehicle:=true' partition/start_script/adsw-control-carla.sh
grep -Fq 'launch_vehicle_interface:=false' partition/start_script/adsw-control-carla.sh
grep -Fq 'launch_sensing_driver:=false' partition/start_script/adsw-perception-carla.sh
grep -Fq 'import carla' partition/start_script/adsw-perception-carla.sh
grep -Fq '/dev/nvidiactl' partition/start_script/adsw-perception-carla.sh
grep -Fq 'd8766616df2511a58ac152ccc53e3307a84ccef9e7fb7108006667188d5766f8' \
    partition/Dockerfile.template
grep -Fq 'version: 7d4cf908b2c5113164e9e5a311071ed3c4aeb693' autoware.repos

if rg -q 'sample_adsw_.*_run|dummy_perception|simple_planning_simulator' \
    partition/start_script/*-carla.sh; then
    fail "CARLA start scripts must not launch the dummy simulator profile"
fi

expect_failure \
    'ERROR: --no-cuda and --carla are mutually exclusive.' \
    ./partition/partition_build.sh --carla --no-cuda
expect_failure \
    'ERROR: the CARLA 0.9.15 Python API profile supports linux/amd64 only.' \
    ./partition/partition_build.sh --carla --platform linux/arm64
expect_failure \
    'CARLA mode requires --map-path pointing to the matching CARLA Lanelet2 map.' \
    ./partition/run_partitions.sh --simulator-mode carla
expect_failure \
    'Unsupported simulator mode: invalid' \
    ./partition/run_partitions.sh --simulator-mode invalid

git diff --check

echo "CARLA profile checks passed."
