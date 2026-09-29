#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(readlink -f "$(dirname "$0")")
WORKSPACE_ROOT=$(readlink -f "$SCRIPT_DIR/..")

REPO="${PARTITION_IMAGE_REPO:-ghcr.io/oss-test-group/autoware-partition}"
IMAGE_NAMESPACE="${PARTITION_IMAGE_NAMESPACE:-ghcr.io/oss-test-group}"
IMAGE_TAG="${PARTITION_IMAGE_TAG:-}"
MAP_PATH="$HOME/autoware_map/sample-map-planning"
ROS_DOMAIN="${ROS_DOMAIN_ID:-42}"
START_DELAY=10
HOST_SOURCE_DIR="${HOST_SOURCE_DIR:-$HOME/source}"
LOG_DIR="$WORKSPACE_ROOT/log"
HEADLESS=false
NETWORK_INTERFACE=""
SIMULATOR_MODE="dummy"
CARLA_HOST="127.0.0.1"
CARLA_PORT="2000"
CARLA_MAP="Town01"
CARLA_TIMEOUT="20"
CARLA_SPAWN_POINT="None"
MAP_PATH_EXPLICIT=false

print_help() {
    cat <<'EOF'
Usage: partition/run_partitions.sh [OPTIONS]

Options:
  --repo <repo>          Docker image repo (default: ghcr.io/oss-test-group/autoware-partition)
  --image-namespace <ns> Component image namespace (default: ghcr.io/oss-test-group)
  --image-tag <tag>      Shared snapshot or release tag for all three component images
  --map-path <path>      Host map path (default: ~/autoware_map/sample-map-planning)
  --domain-id <id>       ROS_DOMAIN_ID (default: 42)
  --delay <sec>          Delay between partitions (default: 10)
  --headless             Disable RViz on the Autoware host
  --network-interface <if> Cyclone DDS network interface (e.g., eth0)
  --simulator-mode <mode> Simulator profile: dummy or carla (default: dummy)
  --carla-host <host>    CARLA server hostname/IP (default: 127.0.0.1)
  --carla-port <port>    CARLA RPC port (default: 2000)
  --carla-map <name>     CARLA map name (default: Town01)
  --carla-timeout <sec>  CARLA connection timeout (default: 20)
  --carla-spawn-point <value> Ego spawn point or None (default: None)
  --help, -h             Show this help

Logs are written under /workspace/log inside each container.
On the host this is the repo log/ directory.
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
    --repo)
        REPO="$2"
        shift
        ;;
    --image-namespace)
        IMAGE_NAMESPACE="$2"
        shift
        ;;
    --image-tag)
        IMAGE_TAG="$2"
        shift
        ;;
    --map-path)
        MAP_PATH="$2"
        MAP_PATH_EXPLICIT=true
        shift
        ;;
    --domain-id)
        ROS_DOMAIN="$2"
        shift
        ;;
    --delay)
        START_DELAY="$2"
        shift
        ;;
    --headless)
        HEADLESS=true
        ;;
    --network-interface)
        NETWORK_INTERFACE="$2"
        shift
        ;;
    --simulator-mode)
        SIMULATOR_MODE="$2"
        shift
        ;;
    --carla-host)
        CARLA_HOST="$2"
        shift
        ;;
    --carla-port)
        CARLA_PORT="$2"
        shift
        ;;
    --carla-map)
        CARLA_MAP="$2"
        shift
        ;;
    --carla-timeout)
        CARLA_TIMEOUT="$2"
        shift
        ;;
    --carla-spawn-point)
        CARLA_SPAWN_POINT="$2"
        shift
        ;;
    --help | -h)
        print_help
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        print_help
        exit 1
        ;;
    esac
    shift
done

case "$SIMULATOR_MODE" in
dummy | carla)
    ;;
*)
    echo "Unsupported simulator mode: $SIMULATOR_MODE (expected dummy or carla)" >&2
    exit 1
    ;;
esac

if ! [[ "$CARLA_PORT" =~ ^[0-9]+$ ]] || [ "$CARLA_PORT" -lt 1 ] || [ "$CARLA_PORT" -gt 65535 ]; then
    echo "Invalid CARLA port: $CARLA_PORT" >&2
    exit 1
fi

if ! [[ "$CARLA_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$CARLA_TIMEOUT" -lt 1 ]; then
    echo "Invalid CARLA timeout: $CARLA_TIMEOUT" >&2
    exit 1
fi

if [ "$SIMULATOR_MODE" = "carla" ] && [ "$MAP_PATH_EXPLICIT" != "true" ]; then
    echo "CARLA mode requires --map-path pointing to the matching CARLA Lanelet2 map." >&2
    exit 1
fi

if [ "$SIMULATOR_MODE" = "carla" ] && [ "$(uname -m)" != "x86_64" ]; then
    echo "CARLA mode requires an x86_64 host for the pinned Python API wheel." >&2
    exit 1
fi

if [ ! -d "$MAP_PATH" ]; then
    echo "Map path does not exist: $MAP_PATH" >&2
    exit 1
fi

if [ "$SIMULATOR_MODE" = "carla" ]; then
    for required_map_file in lanelet2_map.osm pointcloud_map.pcd map_projector_info.yaml; do
        if [ ! -f "$MAP_PATH/$required_map_file" ]; then
            echo "CARLA map file is missing: $MAP_PATH/$required_map_file" >&2
            exit 1
        fi
    done
fi

if [ -n "$NETWORK_INTERFACE" ] && ! ip link show "$NETWORK_INTERFACE" >/dev/null 2>&1; then
    echo "Network interface does not exist: $NETWORK_INTERFACE" >&2
    exit 1
fi

mkdir -p "$LOG_DIR" "$HOST_SOURCE_DIR/fastdds" "$HOST_SOURCE_DIR/ros2"
: >"$LOG_DIR/perception_log.txt"
: >"$LOG_DIR/decision_log.txt"
: >"$LOG_DIR/control_log.txt"

X_ARGS=()
if [ "$HEADLESS" = "false" ] && [ -n "${DISPLAY:-}" ]; then
    X_ARGS=(-e "DISPLAY=$DISPLAY" -v /tmp/.X11-unix/:/tmp/.X11-unix)
    if command -v xhost >/dev/null 2>&1; then
        xhost + >/dev/null || true
    fi
fi

DDS_ARGS=(
    -e "RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
    -e "ROS_LOCALHOST_ONLY=0"
)

if [ -n "$NETWORK_INTERFACE" ]; then
    CYCLONEDDS_CONFIG="<CycloneDDS><Domain><General><Interfaces><NetworkInterface name=\"$NETWORK_INTERFACE\" multicast=\"true\"/></Interfaces><AllowMulticast>true</AllowMulticast></General></Domain></CycloneDDS>"
    DDS_ARGS+=(-e "CYCLONEDDS_URI=$CYCLONEDDS_CONFIG")
elif [ -n "${CYCLONEDDS_URI:-}" ]; then
    DDS_ARGS+=(-e "CYCLONEDDS_URI=$CYCLONEDDS_URI")
fi

COMMON_ARGS=(
    --rm
    --net=host
    --pid=host
    --ipc=host
    -e "LOCAL_UID=$(id -u)"
    -e "LOCAL_GID=$(id -g)"
    -e "LOCAL_USER=$(id -un)"
    -e "LOCAL_GROUP=$(id -gn)"
    -e "FASTDDS_BUILTIN_TRANSPORTS=UDPv4"
    -e "ROS_DOMAIN_ID=$ROS_DOMAIN"
    -e "CARLA_HOST=$CARLA_HOST"
    -e "CARLA_PORT=$CARLA_PORT"
    -e "CARLA_MAP=$CARLA_MAP"
    -e "CARLA_TIMEOUT=$CARLA_TIMEOUT"
    -e "CARLA_SPAWN_POINT=$CARLA_SPAWN_POINT"
    "${DDS_ARGS[@]}"
    -e "XAUTHORITY=${XAUTHORITY:-}"
    -e "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
    -v /etc/localtime:/etc/localtime:ro
    -v "$WORKSPACE_ROOT:/workspace"
    -v "$MAP_PATH:/autoware_map:ro"
    -v "$HOME/autoware_data/ml_models:/autoware_data:ro"
    -v "$HOST_SOURCE_DIR/fastdds:/fastdds:rw"
    -v "$WORKSPACE_ROOT:/exec"
    -v "$HOST_SOURCE_DIR/ros2:/ros2"
)

CONTAINERS=(
    "adsw-perception-$ROS_DOMAIN"
    "adsw-decision-$ROS_DOMAIN"
    "adsw-control-$ROS_DOMAIN"
)

cleanup() {
    echo
    echo "Stopping partition containers..."
    docker stop "${CONTAINERS[@]}" >/dev/null 2>&1 || true
}
trap cleanup INT TERM EXIT

remove_stale_container() {
    local name="$1"
    if docker ps -a --format '{{.Names}}' | grep -Fxq "$name"; then
        echo "Removing stale container: $name"
        docker rm -f "$name" >/dev/null
    fi
}

start_partition() {
    local label="$1"
    local name="$2"
    local component="$3"
    local script="$4"
    local log_file="$5"
    local image

    if [ -n "$IMAGE_TAG" ]; then
        image="${IMAGE_NAMESPACE}/${component}:${IMAGE_TAG}"
    else
        image="${REPO}:${component}"
    fi
    local use_gpu="${6:-false}"
    local runtime_args=()

    if [ "$use_gpu" = "true" ]; then
        runtime_args+=(--gpus all)
    fi

    remove_stale_container "$name"

    echo "Starting $label: $image"
    docker run -d \
        --name "$name" \
        "${COMMON_ARGS[@]}" \
        "${X_ARGS[@]}" \
        "${runtime_args[@]}" \
        "$image" \
        bash -lc "mkdir -p /workspace/log && $script > /workspace/log/$log_file 2>&1" >/dev/null
}

if [ -n "$IMAGE_TAG" ]; then
    echo "Images: ${IMAGE_NAMESPACE}/adsw-*:${IMAGE_TAG}"
else
    echo "Images: ${REPO}:adsw-* (deprecated compatibility layout)"
fi
echo "Map: $MAP_PATH"
echo "ROS_DOMAIN_ID: $ROS_DOMAIN"
echo "Delay: ${START_DELAY}s"
echo "Headless: $HEADLESS"
echo "DDS interface: ${NETWORK_INTERFACE:-auto}"
echo "Simulator mode: $SIMULATOR_MODE"
if [ "$SIMULATOR_MODE" = "carla" ]; then
    echo "CARLA server: ${CARLA_HOST}:${CARLA_PORT} (${CARLA_MAP})"
    echo "CUDA: enabled for Perception only"
else
    echo "CUDA: disabled"
fi
echo "Logs: $LOG_DIR"
echo

PERCEPTION_TAG="adsw-perception"
DECISION_TAG="adsw-decision"
CONTROL_TAG="adsw-control"
PERCEPTION_COMMAND="/autoware/start_script/adsw-perception.sh"
DECISION_COMMAND="/autoware/start_script/adsw-decision.sh"
CONTROL_COMMAND="/autoware/start_script/adsw-control.sh"
PERCEPTION_GPU=false

if [ "$SIMULATOR_MODE" = "carla" ]; then
    PERCEPTION_TAG="adsw-perception-carla-cuda"
    DECISION_TAG="adsw-decision-carla"
    CONTROL_TAG="adsw-control-carla"
    PERCEPTION_COMMAND="/exec/partition/start_script/adsw-perception-carla.sh"
    DECISION_COMMAND="/exec/partition/start_script/adsw-decision-carla.sh"
    CONTROL_COMMAND="/exec/partition/start_script/adsw-control-carla.sh"
    PERCEPTION_GPU=true
    if [ "$HEADLESS" = "true" ]; then
        COMMON_ARGS+=(-e "AUTOWARE_RVIZ=false")
    else
        COMMON_ARGS+=(-e "AUTOWARE_RVIZ=true")
    fi
elif [ "$HEADLESS" = "true" ]; then
    PERCEPTION_COMMAND="ros2 launch obigo_launch sample_adsw_perception_run.launch.xml map_path:=/autoware_map vehicle_model:=sample_vehicle sensor_model:=sample_sensor_kit rviz:=false"
fi

start_partition "perception" "${CONTAINERS[0]}" "$PERCEPTION_TAG" "$PERCEPTION_COMMAND" "perception_log.txt" "$PERCEPTION_GPU"
sleep "$START_DELAY"
start_partition "decision" "${CONTAINERS[1]}" "$DECISION_TAG" "$DECISION_COMMAND" "decision_log.txt"
sleep "$START_DELAY"
start_partition "control" "${CONTAINERS[2]}" "$CONTROL_TAG" "$CONTROL_COMMAND" "control_log.txt"

echo
echo "All partitions are running. Press Ctrl-C to stop them."
echo
tail -n +1 -F \
    "$LOG_DIR/perception_log.txt" \
    "$LOG_DIR/decision_log.txt" \
    "$LOG_DIR/control_log.txt"
