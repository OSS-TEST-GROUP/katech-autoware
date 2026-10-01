#!/usr/bin/env bash

set -euo pipefail

AUTOWARE_VEHICLE_MODEL="${AUTOWARE_VEHICLE_MODEL:-sample_vehicle}"
AUTOWARE_SENSOR_MODEL="${AUTOWARE_SENSOR_MODEL:-carla_sensor_kit}"

# Use a writable package overlay for the CARLA-tuned obstacle planner config.
# The runtime user cannot modify the package installed under /opt/autoware.
planner_config_rel="config/planning/scenario_planning/lane_driving/motion_planning/obstacle_cruise_planner/obstacle_cruise_planner.param.yaml"
planner_config_src="/exec/src/universe/autoware.universe/obigo_launch/${planner_config_rel}"
obigo_override_prefix="/tmp/obigo_launch_carla_override"
if [[ -f "$planner_config_src" ]]; then
    rm -rf "$obigo_override_prefix"
    mkdir -p "$obigo_override_prefix/share/ament_index/resource_index/packages"
    cp -a /opt/autoware/share/obigo_launch "$obigo_override_prefix/share/obigo_launch"
    cp "$planner_config_src" "$obigo_override_prefix/share/obigo_launch/${planner_config_rel}"
    touch "$obigo_override_prefix/share/ament_index/resource_index/packages/obigo_launch"
    export AMENT_PREFIX_PATH="$obigo_override_prefix:${AMENT_PREFIX_PATH:-}"
fi

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
