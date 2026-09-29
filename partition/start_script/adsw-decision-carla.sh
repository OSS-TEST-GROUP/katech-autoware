#!/usr/bin/env bash

set -euo pipefail

AUTOWARE_VEHICLE_MODEL="${AUTOWARE_VEHICLE_MODEL:-sample_vehicle}"
AUTOWARE_SENSOR_MODEL="${AUTOWARE_SENSOR_MODEL:-carla_sensor_kit}"

args=(
    "map_path:=/autoware_map"
    "vehicle_model:=$AUTOWARE_VEHICLE_MODEL"
    "sensor_model:=$AUTOWARE_SENSOR_MODEL"
    "use_sim_time:=true"
    "system_run_mode:=planning_simulation"
    "launch_system_monitor:=false"
    "launch_dummy_diag_publisher:=true"
    "enable_all_modules_auto_mode:=true"
    "is_simulation:=true"
    "rviz:=false"
    "pointcloud_container_name:=pointcloud_container_decision"
    "glog_name:=glog_component_decision"
)

exec ros2 launch obigo_launch adsw_decision.launch.xml "${args[@]}"
