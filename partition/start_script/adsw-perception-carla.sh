#!/usr/bin/env bash

set -euo pipefail

CARLA_HOST="${CARLA_HOST:-127.0.0.1}"
CARLA_PORT="${CARLA_PORT:-2000}"
CARLA_MAP="${CARLA_MAP:-Town01}"
CARLA_TIMEOUT="${CARLA_TIMEOUT:-20}"
CARLA_SPAWN_POINT="${CARLA_SPAWN_POINT:-None}"
AUTOWARE_RVIZ="${AUTOWARE_RVIZ:-true}"
AUTOWARE_VEHICLE_MODEL="${AUTOWARE_VEHICLE_MODEL:-sample_vehicle}"
AUTOWARE_SENSOR_MODEL="${AUTOWARE_SENSOR_MODEL:-awsim_sensor_kit}"

python3 -c 'import carla; assert hasattr(carla, "Client")' || {
    echo "CARLA 0.9.15 Python API is not available in the Perception image." >&2
    exit 1
}

if [ ! -e /dev/nvidiactl ]; then
    echo "NVIDIA devices are not available; start the container with --gpus all." >&2
    exit 1
fi

child_pids=()
cleanup_done=false

cleanup() {
    if [ "$cleanup_done" = "true" ]; then
        return
    fi
    cleanup_done=true

    for pid in "${child_pids[@]}"; do
        if kill -0 "$pid" >/dev/null 2>&1; then
            kill -TERM "$pid" >/dev/null 2>&1 || true
        fi
    done

    for pid in "${child_pids[@]}"; do
        wait "$pid" >/dev/null 2>&1 || true
    done
}

trap cleanup EXIT
trap 'exit 130' INT TERM

bridge_args=(
    "host:=$CARLA_HOST"
    "port:=$CARLA_PORT"
    "timeout:=$CARLA_TIMEOUT"
    "carla_map:=$CARLA_MAP"
    "spawn_point:=$CARLA_SPAWN_POINT"
)

perception_args=(
    "map_path:=/autoware_map"
    "vehicle_model:=$AUTOWARE_VEHICLE_MODEL"
    "sensor_model:=$AUTOWARE_SENSOR_MODEL"
    "use_sim_time:=true"
    "launch_sensing_driver:=false"
    "launch_system_monitor:=false"
    "launch_dummy_diag_publisher:=true"
    "is_simulation:=true"
    "rviz:=$AUTOWARE_RVIZ"
    "pointcloud_container_name:=pointcloud_container_perception"
    "glog_name:=glog_component_perception"
)

ros2 launch autoware_carla_interface autoware_carla_interface.launch.xml \
    "${bridge_args[@]}" &
child_pids+=("$!")

ros2 launch obigo_launch adsw_perception.launch.xml \
    "${perception_args[@]}" &
child_pids+=("$!")

set +e
wait -n "${child_pids[@]}"
status=$?
set -e

exit "$status"
