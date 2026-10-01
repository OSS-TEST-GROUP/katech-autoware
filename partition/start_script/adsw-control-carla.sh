#!/usr/bin/env bash

set -euo pipefail

AUTOWARE_VEHICLE_MODEL="${AUTOWARE_VEHICLE_MODEL:-sample_vehicle}"
AUTOWARE_SENSOR_MODEL="${AUTOWARE_SENSOR_MODEL:-carla_sensor_kit}"

args=(
    "map_path:=/autoware_map"
    "vehicle_model:=$AUTOWARE_VEHICLE_MODEL"
    "sensor_model:=$AUTOWARE_SENSOR_MODEL"
    "use_sim_time:=true"
    "launch_vehicle:=true"
    "launch_vehicle_interface:=false"
    "system_run_mode:=planning_simulation"
    "launch_system_monitor:=false"
    "launch_dummy_diag_publisher:=true"
    "is_simulation:=true"
    "rviz:=false"
    "pointcloud_container_name:=pointcloud_container_control"
    "glog_name:=glog_component_control"
)

# The operation-mode manager publishes its initial state before the trajectory follower is loaded.
# The state publisher is transient-local, but the follower subscription is volatile, so the follower
# can miss that first sample and never produce a control command. Republish the state once all control
# components are present by making a harmless LOCAL -> STOP transition while the vehicle is stopped.
republish_operation_mode_after_controller_start() {
    for _ in $(seq 1 120); do
        if ros2 node list 2>/dev/null | grep -Fxq "/control/trajectory_follower/controller_node_exe" && \
            ros2 service type /system/operation_mode/change_operation_mode >/dev/null 2>&1; then
            sleep 2
            ros2 service call \
                /system/operation_mode/change_operation_mode \
                tier4_system_msgs/srv/ChangeOperationMode \
                "{mode: 3}" >/dev/null 2>&1
            ros2 service call \
                /system/operation_mode/change_operation_mode \
                tier4_system_msgs/srv/ChangeOperationMode \
                "{mode: 1}" >/dev/null 2>&1
            return 0
        fi
        sleep 1
    done
    echo "Timed out waiting to republish the operation-mode state" >&2
}

republish_operation_mode_after_controller_start &

exec ros2 launch obigo_launch adsw_control.launch.xml "${args[@]}"
