ARG BASE_IMAGE=ros:humble-ros-base-jammy
ARG LIB_DIR

# hadolint ignore=DL3006
FROM $BASE_IMAGE AS base
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ROS_DISTRO
ARG LIB_DIR

# Copy files
COPY setup-dev-env.sh ansible-galaxy-requirements.yaml amd64.env arm64.env /autoware/
COPY ansible/ /autoware/ansible/
COPY docker/scripts/cleanup_apt.sh /autoware/cleanup_apt.sh
RUN chmod +x /autoware/cleanup_apt.sh
COPY docker/scripts/cleanup_system.sh /autoware/cleanup_system.sh
RUN chmod +x /autoware/cleanup_system.sh
COPY partition/start_script/ /autoware/start_script/
WORKDIR /autoware

# Install apt packages and add GitHub to known hosts for private repositories
RUN rm -f /etc/apt/apt.conf.d/docker-clean \
  && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
  gosu \
  ssh \
  && /autoware/cleanup_apt.sh \
  && mkdir -p ~/.ssh \
  && ssh-keyscan github.com >> ~/.ssh/known_hosts

# Set up base environment
RUN --mount=type=ssh \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  ./setup-dev-env.sh -y --module base --no-nvidia --no-cuda-drivers --runtime openadkit \
  && pip uninstall -y ansible ansible-core \
  && /autoware/cleanup_apt.sh \
  && echo "source /opt/ros/${ROS_DISTRO}/setup.bash" > /etc/bash.bashrc

# Create entrypoint
COPY docker/etc/ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh
CMD ["/bin/bash"]

FROM base AS base-cuda
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG LIB_DIR

# Set up CUDA runtime environment and artifacts
# hadolint ignore=SC2002
RUN --mount=type=ssh \
  ./setup-dev-env.sh -y --module base --download-artifacts --no-cuda-drivers --runtime openadkit \
  && pip uninstall -y ansible ansible-core \
  && /autoware/cleanup_apt.sh true

ARG BASE_IMAGE
ARG AUTOWARE_BASE_IMAGE
ARG AUTOWARE_BASE_CUDA_IMAGE
#ARG PARTITION_NAME
ARG LIB_DIR





# hadolint ignore=DL3006
FROM $BASE_IMAGE AS rosdep-depend
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ROS_DISTRO
ARG LIB_DIR

COPY setup-dev-env.sh ansible-galaxy-requirements.yaml amd64.env arm64.env /autoware/
COPY ansible/ /autoware/ansible/
COPY docker/scripts/cleanup_apt.sh /autoware/cleanup_apt.sh
RUN chmod +x /autoware/cleanup_apt.sh
COPY docker/scripts/resolve_rosdep_keys.sh /autoware/resolve_rosdep_keys.sh
RUN chmod +x /autoware/resolve_rosdep_keys.sh
WORKDIR /autoware

RUN rm -f /etc/apt/apt.conf.d/docker-clean \
  && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/keep-cache
RUN --mount=type=ssh \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  ./setup-dev-env.sh -y rosdep \
  && pip uninstall -y ansible ansible-core \
  && /autoware/cleanup_apt.sh

COPY --chmod=755 gpu-build/resolve_rosdep_keys.sh /autoware/resolve_rosdep_keys.sh

# Generate install package lists
COPY src/core /autoware/src/core
RUN rosdep update && /autoware/resolve_rosdep_keys.sh /autoware/src ${ROS_DISTRO} \
  > /rosdep-core-depend-packages.txt \
  && cat /rosdep-core-depend-packages.txt

COPY src/universe/external /autoware/src/universe/external
COPY src/universe/autoware.universe/common /autoware/src/universe/autoware.universe/common
COPY src/universe/autoware.universe/sensing/autoware_cuda_utils /autoware/src/universe/autoware.universe/sensing/autoware_cuda_utils
COPY src/universe/autoware.universe/perception/autoware_tensorrt_common /autoware/src/universe/autoware.universe/perception/autoware_tensorrt_common

RUN /autoware/resolve_rosdep_keys.sh /autoware/src ${ROS_DISTRO} \
  > /rosdep-universe-common-depend-packages.txt \
  && cat /rosdep-universe-common-depend-packages.txt


FROM rosdep-depend AS adsw-perception-depend
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ROS_DISTRO
ARG LIB_DIR

#########################################################
COPY src/param /autoware/src/param
COPY src/sensor_component /autoware/src/sensor_component
COPY src/sensor_kit /autoware/src/sensor_kit
COPY src/universe/autoware.universe/evaluator/autoware_perception_online_evaluator /autoware/src/universe/autoware.universe/evaluator/autoware_perception_online_evaluator
COPY src/universe/autoware.universe/launch/perception_simulator_launch /autoware/src/universe/autoware.universe/launch/perception_simulator_launch
COPY src/universe/autoware.universe/launch/tier4_localization_launch /autoware/src/universe/autoware.universe/launch/tier4_localization_launch
COPY src/universe/autoware.universe/launch/tier4_map_launch /autoware/src/universe/autoware.universe/launch/tier4_map_launch
COPY src/universe/autoware.universe/launch/tier4_perception_launch /autoware/src/universe/autoware.universe/launch/tier4_perception_launch
COPY src/universe/autoware.universe/launch/tier4_sensing_launch /autoware/src/universe/autoware.universe/launch/tier4_sensing_launch
COPY src/universe/autoware.universe/localization /autoware/src/universe/autoware.universe/localization
COPY src/universe/autoware.universe/map /autoware/src/universe/autoware.universe/map
COPY src/universe/autoware.universe/obigo_launch /autoware/src/universe/autoware.universe/obigo_launch
COPY src/universe/autoware.universe/perception /autoware/src/universe/autoware.universe/perception
COPY src/universe/autoware.universe/sensing /autoware/src/universe/autoware.universe/sensing
COPY src/universe/autoware.universe/simulator/autoware_dummy_perception_publisher /autoware/src/universe/autoware.universe/simulator/autoware_dummy_perception_publisher
COPY src/universe/autoware.universe/simulator/tier4_dummy_object_rviz_plugin /autoware/src/universe/autoware.universe/simulator/tier4_dummy_object_rviz_plugin
COPY src/universe/autoware.universe/system/autoware_default_adapi_helpers/autoware_automatic_pose_initializer /autoware/src/universe/autoware.universe/system/autoware_default_adapi_helpers/autoware_automatic_pose_initializer
COPY src/universe/autoware.universe/system/autoware_velodyne_monitor /autoware/src/universe/autoware.universe/system/autoware_velodyne_monitor
COPY src/universe/autoware.universe/visualization /autoware/src/universe/autoware.universe/visualization
COPY src/vehicle /autoware/src/vehicle
COPY gpu-build/overrides/korean-package.xml /autoware/src/universe/autoware.universe/perception/autoware_korean_traffic_light_models/package.xml
COPY gpu-build/overrides/simulator-package.xml /autoware/src/universe/autoware.universe/launch/perception_simulator_launch/package.xml
COPY gpu-build/overrides/simulator.launch.xml /autoware/src/universe/autoware.universe/launch/perception_simulator_launch/launch/simulator.launch.xml
#########################################################

RUN /autoware/resolve_rosdep_keys.sh /autoware/src ${ROS_DISTRO} \
    > /rosdep-adsw-perception-depend-packages.txt \
    && cat /rosdep-adsw-perception-depend-packages.txt
RUN /autoware/resolve_rosdep_keys.sh /autoware/src ${ROS_DISTRO} \
    > /rosdep-adsw-perception-exec-depend-packages.txt \
    && cat /rosdep-adsw-perception-exec-depend-packages.txt


# hadolint ignore=DL3006
FROM base AS core-devel
#RUN echo "PARTITION_NAME: $PARTITION_NAME"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ROS_DISTRO
ARG LIB_DIR

ENV CCACHE_DIR="/root/.ccache"
ENV CMAKE_BUILD_PARALLEL_LEVEL=2 COLCON_PARALLEL_WORKERS=2

COPY gpu-build/build_and_clean.sh /autoware/build_and_clean.sh
RUN chmod +x /autoware/build_and_clean.sh

# Set up development environment and tools
RUN --mount=type=ssh \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  ./setup-dev-env.sh -y --module all --no-nvidia --no-cuda-drivers openadkit \
  && ./setup-dev-env.sh -y --module dev-tools openadkit \
  && pip uninstall -y ansible ansible-core \
  && /autoware/cleanup_apt.sh

# Install rosdep dependencies
COPY --from=rosdep-depend /rosdep-core-depend-packages.txt /tmp/rosdep-core-depend-packages.txt
# hadolint ignore=SC2002
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update \
  && cat /tmp/rosdep-core-depend-packages.txt | xargs apt-get install -y --no-install-recommends \
  && /autoware/cleanup_apt.sh

RUN --mount=type=cache,target=${CCACHE_DIR} \
  --mount=type=bind,from=rosdep-depend,source=/autoware/src/core,target=/autoware/src/core \
  source /opt/ros/"$ROS_DISTRO"/setup.bash \
  && MAKEFLAGS="-j2 -l4" /autoware/build_and_clean.sh ${CCACHE_DIR} /opt/autoware

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]

FROM core-devel AS universe-common-devel
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ROS_DISTRO
ARG LIB_DIR

ENV CCACHE_DIR="/root/.ccache"
ENV CMAKE_BUILD_PARALLEL_LEVEL=2 COLCON_PARALLEL_WORKERS=2

# Install rosdep dependencies
COPY --from=rosdep-depend /rosdep-universe-common-depend-packages.txt /tmp/rosdep-universe-common-depend-packages.txt
# hadolint ignore=SC2002
RUN --mount=type=ssh \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update \
  && cat /tmp/rosdep-universe-common-depend-packages.txt | xargs apt-get install -y --no-install-recommends \
  && /autoware/cleanup_apt.sh

# hadolint ignore=SC1091
RUN --mount=type=cache,target=${CCACHE_DIR} \
  --mount=type=bind,from=rosdep-depend,source=/autoware/src/universe/autoware.universe/common,target=/autoware/src/universe/autoware.universe/common \
  --mount=type=bind,from=rosdep-depend,source=/autoware/src/universe/external,target=/autoware/src/universe/external \
  source /opt/ros/"$ROS_DISTRO"/setup.bash \
  && source /opt/autoware/setup.bash \
  && MAKEFLAGS="-j2 -l4" /autoware/build_and_clean.sh ${CCACHE_DIR} /opt/autoware

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]

FROM universe-common-devel AS universe-common-devel-cuda
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG LIB_DIR

# Set up CUDA development environment
# hadolint ignore=SC2002
RUN --mount=type=ssh \
  ./setup-dev-env.sh -y --module all --no-cuda-drivers openadkit \
  && pip uninstall -y ansible ansible-core \
  && /autoware/cleanup_apt.sh true

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]

FROM universe-common-devel AS adsw-perception-devel
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ROS_DISTRO
ARG LIB_DIR

ENV CCACHE_DIR="/root/.ccache"
ENV CMAKE_BUILD_PARALLEL_LEVEL=2 COLCON_PARALLEL_WORKERS=2

# Install rosdep dependencies
COPY --from=adsw-perception-depend /rosdep-adsw-perception-depend-packages.txt /tmp/rosdep-adsw-perception-depend-packages.txt
# hadolint ignore=SC2002
RUN --mount=type=ssh \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update \
  && cat /tmp/rosdep-adsw-perception-depend-packages.txt | xargs apt-get install -y --no-install-recommends \
  && /autoware/cleanup_apt.sh

# hadolint ignore=SC1091
RUN --mount=type=cache,target=${CCACHE_DIR} \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/param,target=/autoware/src/param \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/sensor_component,target=/autoware/src/sensor_component \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/sensor_kit,target=/autoware/src/sensor_kit \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/evaluator/autoware_perception_online_evaluator,target=/autoware/src/universe/autoware.universe/evaluator/autoware_perception_online_evaluator \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/perception_simulator_launch,target=/autoware/src/universe/autoware.universe/launch/perception_simulator_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/tier4_localization_launch,target=/autoware/src/universe/autoware.universe/launch/tier4_localization_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/tier4_map_launch,target=/autoware/src/universe/autoware.universe/launch/tier4_map_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/tier4_perception_launch,target=/autoware/src/universe/autoware.universe/launch/tier4_perception_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/tier4_sensing_launch,target=/autoware/src/universe/autoware.universe/launch/tier4_sensing_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/localization,target=/autoware/src/universe/autoware.universe/localization \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/map,target=/autoware/src/universe/autoware.universe/map \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/obigo_launch,target=/autoware/src/universe/autoware.universe/obigo_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/perception,target=/autoware/src/universe/autoware.universe/perception \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/sensing,target=/autoware/src/universe/autoware.universe/sensing \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/simulator/autoware_dummy_perception_publisher,target=/autoware/src/universe/autoware.universe/simulator/autoware_dummy_perception_publisher \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/simulator/tier4_dummy_object_rviz_plugin,target=/autoware/src/universe/autoware.universe/simulator/tier4_dummy_object_rviz_plugin \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/system/autoware_default_adapi_helpers/autoware_automatic_pose_initializer,target=/autoware/src/universe/autoware.universe/system/autoware_default_adapi_helpers/autoware_automatic_pose_initializer \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/system/autoware_velodyne_monitor,target=/autoware/src/universe/autoware.universe/system/autoware_velodyne_monitor \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/visualization,target=/autoware/src/universe/autoware.universe/visualization \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/vehicle,target=/autoware/src/vehicle \
  source /opt/ros/"$ROS_DISTRO"/setup.bash \
  && source /opt/autoware/setup.bash \
  && MAKEFLAGS="-j2 -l4" /autoware/build_and_clean.sh ${CCACHE_DIR} /opt/autoware

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]


FROM universe-common-devel-cuda AS adsw-perception-devel-cuda
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG ROS_DISTRO
ARG LIB_DIR

ENV CCACHE_DIR="/root/.ccache"
ENV CMAKE_BUILD_PARALLEL_LEVEL=2 COLCON_PARALLEL_WORKERS=2

# Install rosdep dependencies
COPY --from=adsw-perception-depend /rosdep-adsw-perception-depend-packages.txt /tmp/rosdep-adsw-perception-depend-packages.txt
# hadolint ignore=SC2002
RUN --mount=type=ssh \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update \
  && cat /tmp/rosdep-adsw-perception-depend-packages.txt | xargs apt-get install -y --no-install-recommends \
  && /autoware/cleanup_apt.sh

COPY --from=adsw-perception-devel /opt/autoware /opt/autoware

# hadolint ignore=SC1091
RUN --mount=type=cache,target=${CCACHE_DIR} \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/param,target=/autoware/src/param \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/sensor_component,target=/autoware/src/sensor_component \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/sensor_kit,target=/autoware/src/sensor_kit \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/evaluator/autoware_perception_online_evaluator,target=/autoware/src/universe/autoware.universe/evaluator/autoware_perception_online_evaluator \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/perception_simulator_launch,target=/autoware/src/universe/autoware.universe/launch/perception_simulator_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/tier4_localization_launch,target=/autoware/src/universe/autoware.universe/launch/tier4_localization_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/tier4_map_launch,target=/autoware/src/universe/autoware.universe/launch/tier4_map_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/tier4_perception_launch,target=/autoware/src/universe/autoware.universe/launch/tier4_perception_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/launch/tier4_sensing_launch,target=/autoware/src/universe/autoware.universe/launch/tier4_sensing_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/localization,target=/autoware/src/universe/autoware.universe/localization \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/map,target=/autoware/src/universe/autoware.universe/map \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/obigo_launch,target=/autoware/src/universe/autoware.universe/obigo_launch \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/perception,target=/autoware/src/universe/autoware.universe/perception \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/sensing,target=/autoware/src/universe/autoware.universe/sensing \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/simulator/autoware_dummy_perception_publisher,target=/autoware/src/universe/autoware.universe/simulator/autoware_dummy_perception_publisher \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/simulator/tier4_dummy_object_rviz_plugin,target=/autoware/src/universe/autoware.universe/simulator/tier4_dummy_object_rviz_plugin \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/system/autoware_default_adapi_helpers/autoware_automatic_pose_initializer,target=/autoware/src/universe/autoware.universe/system/autoware_default_adapi_helpers/autoware_automatic_pose_initializer \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/system/autoware_velodyne_monitor,target=/autoware/src/universe/autoware.universe/system/autoware_velodyne_monitor \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/universe/autoware.universe/visualization,target=/autoware/src/universe/autoware.universe/visualization \
  --mount=type=bind,from=adsw-perception-depend,source=/autoware/src/vehicle,target=/autoware/src/vehicle \
  --mount=type=bind,from=rosdep-depend,source=/autoware/src/universe/external/trt_batched_nms,target=/autoware/src/universe/external/trt_batched_nms \
  --mount=type=bind,source=gpu-build/overrides/yolox-CMakeLists.txt,target=/autoware/src/universe/autoware.universe/perception/autoware_tensorrt_yolox/CMakeLists.txt \
  source /opt/ros/"$ROS_DISTRO"/setup.bash \
  && source /opt/autoware/setup.bash \
  && MAKEFLAGS="-j2 -l4" /autoware/build_and_clean.sh ${CCACHE_DIR} /opt/autoware

RUN --mount=type=cache,target=${CCACHE_DIR} \
  --mount=type=bind,from=rosdep-depend,source=/autoware/src/universe/external/trt_batched_nms,target=/autoware/src/universe/external/trt_batched_nms \
  --mount=type=bind,source=gpu-build/overrides/batched_nms_kernel.cpp,target=/autoware/src/universe/external/trt_batched_nms/src/nms/batched_nms_kernel.cpp \
  source /opt/ros/"$ROS_DISTRO"/setup.bash \
  && source /opt/autoware/setup.bash \
  && MAKEFLAGS="-j2 -l4" /autoware/build_and_clean.sh ${CCACHE_DIR} /opt/autoware "--packages-select trt_batched_nms"

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]



# hadolint ignore=DL3006
FROM base AS adsw-perception
#ARG LIB_DIR
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG OCI_REVISION=""
ARG OCI_REF_NAME=""
ARG OCI_CREATED=""
ARG OCI_VERSION=""
LABEL org.opencontainers.image.source="https://github.com/OSS-TEST-GROUP/katech-autoware" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.ref.name="${OCI_REF_NAME}" \
      org.opencontainers.image.created="${OCI_CREATED}" \
      org.opencontainers.image.version="${OCI_VERSION}"
ARG ROS_DISTRO
ARG SETUP_ARGS
ARG TARGETPLATFORM

# Set up runtime environment and artifacts
COPY --from=adsw-perception-depend /rosdep-adsw-perception-exec-depend-packages.txt /tmp/rosdep-adsw-perception-exec-depend-packages.txt

# hadolint ignore=SC2002
RUN --mount=type=ssh \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  ./setup-dev-env.sh -y --module all --no-nvidia --no-cuda-drivers --runtime openadkit \
  && pip uninstall -y ansible ansible-core \
  && apt-get update \
  && cat /tmp/rosdep-adsw-perception-exec-depend-packages.txt | xargs apt-get install -y --no-install-recommends \
  && if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
      export LIB_DIR="x86_64"; \
     elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
      export LIB_DIR="aarch64"; \
     fi \
  && echo "LIB_DIR ==============================is $LIB_DIR" \
  && /autoware/cleanup_system.sh $LIB_DIR $ROS_DISTRO

COPY --from=adsw-perception-devel /opt/autoware /opt/autoware

# Copy bash aliases
COPY docker/etc/.bash_aliases /root/.bash_aliases
RUN echo "source /opt/autoware/setup.bash" > /etc/bash.bashrc

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]


FROM base-cuda AS adsw-perception-cuda
#ARG LIB_DIR
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG OCI_REVISION=""
ARG OCI_REF_NAME=""
ARG OCI_CREATED=""
ARG OCI_VERSION=""
LABEL org.opencontainers.image.source="https://github.com/OSS-TEST-GROUP/katech-autoware" \
      org.opencontainers.image.revision="${OCI_REVISION}" \
      org.opencontainers.image.ref.name="${OCI_REF_NAME}" \
      org.opencontainers.image.created="${OCI_CREATED}" \
      org.opencontainers.image.version="${OCI_VERSION}"
ARG ROS_DISTRO
ARG TARGETPLATFORM

# Set up runtime environment and artifacts
COPY --from=adsw-perception-depend /rosdep-adsw-perception-exec-depend-packages.txt /tmp/rosdep-adsw-perception-exec-depend-packages.txt

# hadolint ignore=SC2002
RUN --mount=type=ssh \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  ./setup-dev-env.sh -y --module all --no-nvidia --no-cuda-drivers --runtime openadkit \
  && pip uninstall -y ansible ansible-core \
  && apt-get update \
  && cat /tmp/rosdep-adsw-perception-exec-depend-packages.txt | xargs apt-get install -y --no-install-recommends \
  && if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
      export LIB_DIR="x86_64"; \
     elif [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
      export LIB_DIR="aarch64"; \
     fi \
  && echo "LIB_DIR =============================is $LIB_DIR" \
  && /autoware/cleanup_system.sh $LIB_DIR $ROS_DISTRO

COPY --from=adsw-perception-devel-cuda /opt/autoware /opt/autoware

# Copy bash aliases
COPY docker/etc/.bash_aliases /root/.bash_aliases
RUN echo "source /opt/autoware/setup.bash" > /etc/bash.bashrc

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["/bin/bash"]

FROM adsw-perception-cuda AS trained-perception
RUN test -s /opt/autoware/lib/libautoware_tensorrt_yolox_gpu_preprocess.so
COPY src/universe/autoware.universe/perception/autoware_korean_traffic_light_models/requirements-onnx.txt /opt/katech/requirements-onnx.txt
RUN python3 -m pip install --no-cache-dir --only-binary=:all: -r /opt/katech/requirements-onnx.txt
COPY gpu-build/models/ /opt/katech/models/korean-traffic-light/
COPY gpu-build/sources.lock.json /opt/katech/sources.lock.json
COPY gpu-build/build-scope.json gpu-build/source-build-fixes.patch /opt/katech/
RUN /bin/bash -c 'source /opt/autoware/setup.bash && ros2 pkg prefix autoware_korean_traffic_light_models && ros2 pkg prefix autoware_lidar_centerpoint && ros2 pkg prefix autoware_tensorrt_yolox' && python3 -c 'import onnxruntime, numpy, PIL; print(onnxruntime.__version__)'
RUN test -s /opt/autoware/lib/libautoware_tensorrt_common.so && test -s /opt/autoware/lib/libautoware_tensorrt_yolox.so && test -s /opt/autoware/lib/libautoware_lidar_centerpoint_cuda_lib.so && test -s /opt/autoware/lib/libtrt_batched_nms_plugin.so && test -x /opt/autoware/lib/autoware_traffic_light_fine_detector/traffic_light_fine_detector_node
