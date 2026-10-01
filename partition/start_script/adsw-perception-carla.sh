#!/usr/bin/env bash

set -euo pipefail

CARLA_HOST="${CARLA_HOST:-127.0.0.1}"
CARLA_PORT="${CARLA_PORT:-2000}"
CARLA_MAP="${CARLA_MAP:-Town01}"
CARLA_TIMEOUT="${CARLA_TIMEOUT:-20}"
CARLA_SPAWN_POINT="${CARLA_SPAWN_POINT:-None}"
AUTOWARE_RVIZ="${AUTOWARE_RVIZ:-true}"
AUTOWARE_VEHICLE_MODEL="${AUTOWARE_VEHICLE_MODEL:-sample_vehicle}"
AUTOWARE_SENSOR_MODEL="${AUTOWARE_SENSOR_MODEL:-carla_sensor_kit}"
LIDAR_DETECTION_MODEL="${LIDAR_DETECTION_MODEL:-centerpoint}"
CENTERPOINT_SCORE_THRESHOLD="${CENTERPOINT_SCORE_THRESHOLD:-0.10}"

case "$LIDAR_DETECTION_MODEL" in
centerpoint | centerpoint/centerpoint_tiny | centerpoint/centerpoint | transfusion) ;;
*)
    echo "Unsupported LIDAR_DETECTION_MODEL: $LIDAR_DETECTION_MODEL" >&2
    exit 1
    ;;
esac

if ! [[ "$CENTERPOINT_SCORE_THRESHOLD" =~ ^0(\.[0-9]+)?$|^1(\.0+)?$ ]]; then
    echo "CENTERPOINT_SCORE_THRESHOLD must be a number between 0 and 1." >&2
    exit 1
fi

# Use a writable package overlay for CARLA detector experiments. The detector
# still consumes LiDAR; no CARLA actor/ground-truth objects enter perception.
obigo_override_prefix="/tmp/obigo_launch_carla_override"
obigo_host_root="/exec/src/universe/autoware.universe/obigo_launch"
rm -rf "$obigo_override_prefix"
mkdir -p "$obigo_override_prefix/share/ament_index/resource_index/packages"
cp -a /opt/autoware/share/obigo_launch "$obigo_override_prefix/share/obigo_launch"
cp "$obigo_host_root/launch/adsw_perception.launch.xml" \
    "$obigo_override_prefix/share/obigo_launch/launch/adsw_perception.launch.xml"
cp "$obigo_host_root/config/perception/object_recognition/detection/lidar_model/centerpoint.param.yaml" \
    "$obigo_override_prefix/share/obigo_launch/config/perception/object_recognition/detection/lidar_model/centerpoint.param.yaml"
cp "$obigo_host_root/config/perception/object_recognition/detection/lidar_model/centerpoint_tiny.param.yaml" \
    "$obigo_override_prefix/share/obigo_launch/config/perception/object_recognition/detection/lidar_model/centerpoint_tiny.param.yaml"
cp "$obigo_host_root/config/perception/object_recognition/detection/object_filter/object_lanelet_filter.param.yaml" \
    "$obigo_override_prefix/share/obigo_launch/config/perception/object_recognition/detection/object_filter/object_lanelet_filter.param.yaml"
sed -i -E "s/(score_threshold:)[[:space:]]*[0-9.]+/\\1 ${CENTERPOINT_SCORE_THRESHOLD}/" \
    "$obigo_override_prefix/share/obigo_launch/config/perception/object_recognition/detection/lidar_model/centerpoint.param.yaml" \
    "$obigo_override_prefix/share/obigo_launch/config/perception/object_recognition/detection/lidar_model/centerpoint_tiny.param.yaml"
touch "$obigo_override_prefix/share/ament_index/resource_index/packages/obigo_launch"
export AMENT_PREFIX_PATH="$obigo_override_prefix:${AMENT_PREFIX_PATH:-}"

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
    "data_path:=/autoware_data"
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
    "launch_perception:=true"
    "lidar_detection_model:=$LIDAR_DETECTION_MODEL"
    "localization_pose_source:=carla"
    "localization_twist_source:=carla"
    "localization_gnss_enabled:=false"
    "use_carla_ground_truth_localization:=true"
    "all_traffic_light_camera:=[camera6]"
    "traffic_light_recognition/enable_fine_detection:=false"
    "traffic_light_recognition/enable_image_decompressor:=false"
    "traffic_light_recognition/use_separate_inference_processes:=true"
    "traffic_light_recognition/use_hsv_classifier:=true"
)

ros2 launch autoware_carla_interface autoware_carla_interface.launch.xml \
    input_initial_pose:=/initialpose3d \
    objects_definition_file:=/exec/src/universe/autoware.universe/simulator/autoware_carla_interface/config/objects.json \
    output_imu_topic:=/sensing/imu/imu_data \
    output_camera_image_topic:=/sensing/camera/camera6/image_raw \
    output_camera_info_topic:=/sensing/camera/camera6/camera_info \
    use_traffic_manager:=true \
    "${bridge_args[@]}" &
child_pids+=("$!")

ros2 launch obigo_launch adsw_perception.launch.xml \
    "${perception_args[@]}" &
child_pids+=("$!")

# ColorClassifier loads its HSV parameters during construction, but the current
# implementation initializes the OpenCV ranges only from the dynamic parameter
# callback. Trigger that callback once after the classifier becomes available.
classifier_node="/perception/traffic_light_recognition/camera6/classification/car_traffic_light_classifier"
classifier_initialized=false
for _ in $(seq 1 120); do
    if ros2 param set "$classifier_node" green_min_h 40 >/dev/null 2>&1; then
        echo "Initialized CARLA traffic-light HSV filter."
        classifier_initialized=true
        break
    fi
    sleep 1
done
if [ "$classifier_initialized" != "true" ]; then
    echo "Warning: failed to initialize the CARLA traffic-light HSV filter." >&2
fi

set +e
wait -n "${child_pids[@]}"
status=$?
set -e

exit "$status"
