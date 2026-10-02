# K-Autoware + CARLA 검증 매뉴얼

## 1. 목적과 합격 기준

이 매뉴얼은 CARLA 0.9.15 Town01과 K-Autoware 3개 파티션을 재현 가능하게 검증하는 절차입니다. 한 단계가 실패하면 다음 단계로 넘어가지 말고 해당 단계의 로그와 토픽을 먼저 확인합니다.

최종 합격 기준:

- Perception/Decision/Control 컨테이너가 모두 유지된다.
- map, TF, localization, route, trajectory가 정상이다.
- LiDAR와 카메라 센서 데이터가 지속적으로 들어온다.
- 객체 인지는 센서 기반으로 동작한다.
- RED에서 ego가 정지선 앞에 정지한다.
- GREEN에서 최종 신호등 결과가 바뀌고 ego가 다시 출발한다.
- 주행 중 원인 불명의 emergency stop이나 중복 노드가 없다.

시험 기록에는 루트/Universe Git SHA, 이미지 ID, CARLA 버전, 맵 경로, 실행 명령과 로그를 남깁니다.

## 2. 공통 ROS 명령 환경

아래 검증 명령은 특별한 설명이 없으면 Perception 컨테이너에서 실행합니다.

```bash
docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ros2 topic list
'
```

다른 명령을 실행할 때 마지막 `ros2 ...` 부분만 바꿉니다.

## 3. 기동 전 확인

CARLA와 모든 파티션을 종료한 상태에서 다음을 확인합니다.

```bash
cd "$HOME/oss/oss_adsw"
git rev-parse HEAD
git -C src/universe/autoware.universe rev-parse HEAD

docker image inspect \
  katech-autoware-carla-test:adsw-perception-carla-cuda \
  katech-autoware-carla-test:adsw-decision-carla \
  katech-autoware-carla-test:adsw-control-carla \
  --format '{{.Id}} {{.RepoTags}}'

test -f "$HOME/autoware_data/maps/Town01/lanelet2_map.osm"
test -f "$HOME/autoware_data/maps/Town01/pointcloud_map.pcd"
test -f "$HOME/autoware_data/maps/Town01/map_projector_info.yaml"
```

`objects.json`의 LiDAR pose는 `x=-0.36`, `y=0`, `z=1.84`여야 합니다. CARLA용 Perception 시작 스크립트가 이 파일을 `objects_definition_file`로 전달하는 것도 함께 확인합니다.

```bash
rg -n '"x"|"y"|"z"' \
  src/universe/autoware.universe/simulator/autoware_carla_interface/config/objects.json
rg -n 'objects_definition_file|publish_ground_truth_traffic_lights' \
  partition/start_script/adsw-perception-carla.sh
```

## 4. 기동 순서

1. CARLA 0.9.15 서버를 Town01로 실행합니다.
2. CARLA가 RPC 요청을 받을 수 있을 때 세 파티션을 실행합니다.
3. Perception → Decision → Control 기동이 끝날 때까지 기다립니다.

```bash
cd "$HOME/oss/oss_adsw"

./partition/run_partitions.sh \
  --repo katech-autoware-carla-test \
  --simulator-mode carla \
  --map-path "$HOME/autoware_data/maps/Town01" \
  --domain-id 42 \
  --delay 10
```

재시험할 때는 CARLA와 세 파티션을 모두 종료하고 같은 순서로 다시 시작합니다.

## 5. 컨테이너와 ROS graph

```bash
docker ps --filter 'name=adsw-'

docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ros2 node list | sort | uniq -d
'
```

정상 기준:

- `adsw-perception-42`, `adsw-decision-42`, `adsw-control-42`가 모두 실행 중이다.
- 중복 node name 출력이 없다.
- Perception 로그에 CARLA version mismatch, CUDA/TensorRT 초기화 실패, 패키지 누락이 없다.

## 6. Map과 TF

```bash
docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ros2 topic info /map/vector_map
ros2 topic info /map/vector_map_marker
ros2 topic info /map/pointcloud_map
timeout 10 ros2 run tf2_ros tf2_echo map base_link
'
```

정상 기준:

- 세 map topic의 publisher가 각각 1이다.
- `map -> base_link` transform이 연속으로 갱신된다.
- RViz에 pointcloud map과 vector map이 같은 좌표에 표시된다.

publisher가 0이면 `log/perception_log.txt`에서 map container/loader의 최초 오류를 찾습니다. 임시 loader를 중복 실행하지 말고 CARLA와 세 파티션을 함께 재시작한 뒤 다시 확인합니다.

## 7. 센서와 객체 인지

```bash
docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
timeout 10 ros2 topic hz /sensing/lidar/top/pointcloud_before_sync
timeout 10 ros2 topic hz /sensing/camera/camera6/image_raw
'
```

카메라와 LiDAR 메시지가 지속적으로 수신되어야 합니다. camera6는 약 10 Hz가 정상 기준입니다. RViz에서 CenterPoint 기반 detected object가 실제 차량 위치와 대체로 일치하는지 확인합니다.

객체 분류가 `UNKNOWN`으로 보이는 문제를 GT 객체로 우회하지 않습니다. 차량·보행자 분류 개선은 센서 모델, pointcloud 품질, detector 학습/파라미터를 별도 검증합니다. 신호등 색상 GT를 사용하더라도 객체 인지는 계속 센서 기반이어야 합니다.

## 8. 초기 위치, 경로와 Auto

1. RViz의 `2D Pose Estimate`로 ego가 있는 차선 위에 위치와 방향을 지정합니다.
2. localization이 안정되고 RViz ego pose가 CARLA 차량과 함께 움직이는지 확인합니다.
3. `2D Goal Pose`를 연결된 차선 위에 지정합니다.
4. route와 trajectory가 생성되는지 확인합니다.
5. Auto 버튼이 활성화된 뒤 주행을 시작합니다.

초기 pose를 적용했는데 CARLA만 이동하고 RViz ego가 초기 위치에 남거나 회전하면 TF/localization을 먼저 확인합니다. pose를 반복 입력해서 상태를 더 복잡하게 만들지 않습니다.

Auto가 활성화되지 않으면 route, trajectory, localization과 hazard status를 확인합니다.

```bash
docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
timeout 10 ros2 topic echo /system/emergency/hazard_status --once
'
```

정상 주행 전 `level: 0`, `emergency: false`여야 합니다. 주행 중 멈추면 같은 topic, 세 파티션 로그와 중복 노드를 동시에 확인합니다.

## 9. 신호등 end-to-end 검증

### 9.1 CARLA GT 입력 확인

```bash
docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
timeout 10 ros2 topic echo \
  /perception/traffic_light_recognition/external/traffic_signals --once
'
```

현재 ego가 접근하는 신호의 Lanelet2 group ID와 CARLA 색상이 출력되어야 합니다. 색상 enum은 `UNKNOWN=0`, `RED=1`, `AMBER=2`, `GREEN=3`입니다. 원형 점등 신호는 `shape=1`, `status=2`입니다.

### 9.2 Planning 입력 확인

```bash
docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
timeout 10 ros2 topic echo \
  /perception/traffic_light_recognition/traffic_signals --once
'
```

external topic과 최종 topic의 group ID와 색상이 같아야 합니다. 최종 topic이 계속 RED인데 external은 GREEN이면 arbiter의 `external_priority: true` 적용 여부와 Perception 이미지 revision을 확인합니다.

### 9.3 실제 동작 판정

동일 신호에서 다음 두 상태를 모두 확인합니다.

| 시험 | ROS 최종 색상 | 합격 기준 |
| --- | --- | --- |
| RED | `color: 1` | ego가 정지선 전에 안정적으로 정지 |
| GREEN | `color: 3` | emergency 없이 trajectory를 따라 재출발 |

RViz 표시만 보지 말고 최종 topic과 CARLA 차량 움직임을 함께 기록합니다. RED에서 통과하면 Lanelet group ID, stop line 연결, external/final topic을 우선 확인합니다. GREEN인데 출발하지 않으면 hazard status, trajectory, planning 로그를 확인합니다.

## 10. 센서 기반 신호등 파이프라인 진단

CARLA GT 모드는 통합 주행 검증용입니다. HSV/CNN 인식률을 검증할 때는 GT 발행과 external priority를 끈 별도 센서 프로파일을 사용합니다.

예상 데이터 흐름:

```text
camera6 image_raw + map/projection
  -> rough/rois, expect/rois
  -> optional YOLOX fine detector (detection/rois)
  -> HSV or CNN classifier
  -> traffic_signals
```

기본 진단:

```bash
docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
timeout 10 ros2 topic hz /sensing/camera/camera6/image_raw
timeout 10 ros2 topic hz /perception/traffic_light_recognition/camera6/detection/rough/rois
timeout 10 ros2 topic hz /perception/traffic_light_recognition/camera6/detection/expect/rois
'
```

fine detection을 켠 경우에만 `detection/rois`와 YOLOX/TensorRT 상태를 검사합니다. 끈 경우 classifier는 `expect/rois`를 직접 사용하므로 `detection/rois`가 비어 있는 것은 실패 조건이 아닙니다. source를 수정했다면 반드시 Perception 이미지를 재빌드한 후 시험합니다.

## 11. 증거 보관과 결과 보고

시험 후 다음을 보관합니다.

```bash
cd "$HOME/oss/oss_adsw"
git rev-parse HEAD
git -C src/universe/autoware.universe rev-parse HEAD
docker image inspect katech-autoware-carla-test:adsw-perception-carla-cuda \
  --format '{{.Id}} {{.Created}}'
cp log/perception_log.txt log/perception_log.validation.txt
cp log/decision_log.txt log/decision_log.validation.txt
cp log/control_log.txt log/control_log.validation.txt
```

최종 보고에는 다음을 적습니다.

- CARLA 서버 버전, host/port, Town 이름
- 루트와 Universe Git SHA, Docker image ID
- map 경로와 전체 36개 신호등 metadata 적용 여부
- map/TF/sensor/object 인지 결과
- RED 정지와 GREEN 재출발 결과
- emergency 발생 여부와 남은 이슈
