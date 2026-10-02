# K-Autoware + CARLA 0.9.15 배포 가이드

## 1. 적용 범위와 검증 상태

이 문서는 K-Autoware의 Perception/Decision/Control 3개 파티션과 외부 CARLA 0.9.15 서버를 Town01에서 실행하는 절차입니다. 다음 구성을 기준으로 통합 주행과 신호등 정지·출발을 확인했습니다.

| 파티션 | 컨테이너 | 실행 장치 | 역할 |
| --- | --- | --- | --- |
| Perception | `adsw-perception-42` | NVIDIA GPU/CUDA | CARLA 연결, 센서 처리, 위치 추정, 객체·신호등 인지 |
| Decision | `adsw-decision-42` | CPU | 경로와 행동 계획 |
| Control | `adsw-control-42` | CPU | 차량 제어와 AD API |

공통 설정은 `ROS_DOMAIN_ID=42`, `RMW_IMPLEMENTATION=rmw_cyclonedds_cpp`입니다. CARLA 서버는 Autoware 이미지에 포함되지 않으며 먼저 별도로 실행해야 합니다.

현재 CARLA 운용 프로파일은 신호등 **색상만** CARLA ground truth(GT)를 사용합니다. 차량과 보행자를 포함한 객체 인지는 LiDAR/카메라 센서 기반이며 CARLA GT 객체를 사용하지 않습니다. 실차용 기본 설정에서는 신호등 GT 발행 파라미터가 `false`이므로 센서 기반 파이프라인을 그대로 사용할 수 있습니다.

상세 합격 기준과 장애 진단은 [CARLA 검증 매뉴얼](carla-validation-manual.md)을 따릅니다.

## 2. 소스 버전 준비

루트 저장소와 `src/universe/autoware.universe`는 별도 Git 저장소입니다. 새 배포본에는 두 저장소의 변경이 모두 들어 있어야 합니다. `autoware.repos`가 가리키는 Universe revision이 로컬 개발 revision보다 오래된 경우 루트 저장소만 clone해서는 동일한 이미지가 만들어지지 않습니다.

검증에 사용한 로컬 revision은 다음과 같습니다.

```text
oss_adsw:                        98441f0 이상
src/universe/autoware.universe:  3b291b7 이상
```

배포 전에 실제 revision과 작업 트리를 기록합니다.

```bash
cd "$HOME/oss/oss_adsw"
git rev-parse HEAD
git status --short
git -C src/universe/autoware.universe rev-parse HEAD
git -C src/universe/autoware.universe status --short
```

두 revision을 원격에 게시하기 전에는 위 값과 동일한 로컬 소스 트리를 보존해야 합니다. Universe 변경이 원격에 올라간 뒤 `autoware.repos`도 그 revision으로 갱신해야 새 clone의 재현성이 보장됩니다.

주요 반영 내용은 다음과 같습니다.

- CARLA용 CUDA Perception 이미지와 CPU Decision/Control 이미지
- CARLA sensor kit, 차량 명령 변환과 3개 파티션 launch
- fine detector 공유 라이브러리 설치 및 traffic-light classifier 입력 복구
- Town01의 36개 신호등 Lanelet2 regulatory element 생성 도구
- CARLA 신호등 색상 GT의 선택적 발행과 external-priority arbiter 설정
- LiDAR pose `x=-0.36`, `y=0`, `z=1.84`

## 3. 사전 요구 사항

- Ubuntu 22.04, x86_64/amd64
- Docker Engine와 Buildx
- NVIDIA 드라이버와 NVIDIA Container Toolkit
- Git, Git LFS, `jq`, `vcstool`
- CARLA 0.9.15 서버
- 충분한 디스크 공간과 빌드 메모리
- RViz를 표시할 경우 X11 GUI 세션

```bash
uname -m
docker info
docker buildx version
nvidia-smi
git lfs version
jq --version
vcs --version
df -h
docker system df
```

CARLA 0.9.15 Python wheel은 이미지 빌드 중 설치되고 SHA-256을 확인합니다. 호스트에 별도 CARLA Python 패키지를 설치할 필요는 없습니다.

## 4. Town01 맵 준비

권장 경로는 `$HOME/autoware_data/maps/Town01`입니다.

```text
Town01/
  lanelet2_map.osm
  pointcloud_map.pcd
  map_projector_info.yaml
```

`map_projector_info.yaml`은 다음과 같아야 합니다.

```yaml
projector_type: Local
```

### 4.1 전체 신호등 metadata 생성

`partition/generate_town01_traffic_lights.py`는 실행 중인 CARLA Town01에서 landmark, actor, bounding box를 읽어 36개 신호등의 Lanelet2 요소를 생성합니다. CARLA 서버를 Town01로 먼저 실행한 뒤, 원본을 보존한 상태에서 새 파일로 생성합니다.

```bash
cd "$HOME/oss/oss_adsw"
MAP_PATH="$HOME/autoware_data/maps/Town01"

python3 partition/generate_town01_traffic_lights.py \
  --host 127.0.0.1 \
  --port 2000 \
  --input "$MAP_PATH/lanelet2_map.before_traffic_light.osm" \
  --output "$MAP_PATH/lanelet2_map.generated.osm"
```

도구가 landmark/actor/bounding-box를 각각 36개 확인하고 정상 종료한 뒤 생성 파일을 검토하여 `lanelet2_map.osm`으로 적용합니다. ID는 OpenDRIVE signal ID에서 결정적으로 생성합니다.

```text
generated_id = int("900" + signal_id(3자리) + suffix(3자리))
physical light way suffix = 010
regulatory group suffix   = 020
```

예를 들어 signal 379의 regulatory group ID는 `900379020`입니다. 이 규칙은 CARLA 신호등 색상과 Lanelet2 신호등 그룹을 연결할 때도 사용합니다.

## 5. 이미지 빌드

소스나 C++/Python 패키지가 변경되었으면 저장소 최상위에서 세 이미지를 다시 빌드합니다.

```bash
cd "$HOME/oss/oss_adsw"
mkdir -p log
set -o pipefail

./partition/partition_build.sh \
  --repo katech-autoware-carla-test \
  --platform linux/amd64 \
  --carla 2>&1 | tee log/carla-build.log
```

첫 빌드는 오래 걸리고 큰 디스크 공간을 사용합니다. 빌드 중에는 `df -h`와 `docker system df`로 공간을 확인합니다. 사용 중인 이미지·캐시를 무분별하게 삭제하지 말고, 정리가 필요하면 삭제 대상을 먼저 확인합니다.

빌드 결과:

```bash
docker image inspect \
  katech-autoware-carla-test:adsw-perception-carla-cuda \
  katech-autoware-carla-test:adsw-decision-carla \
  katech-autoware-carla-test:adsw-control-carla \
  --format '{{.RepoTags}} {{.Os}}/{{.Architecture}}'
```

Decision과 Control의 `-carla`는 실행 프로파일 구분이며 CUDA 사용을 뜻하지 않습니다.

## 6. 실행과 종료

CARLA 0.9.15 서버를 Town01로 먼저 실행한 다음 Autoware 세 파티션을 실행합니다.

```bash
cd "$HOME/oss/oss_adsw"

./partition/run_partitions.sh \
  --repo katech-autoware-carla-test \
  --simulator-mode carla \
  --map-path "$HOME/autoware_data/maps/Town01" \
  --domain-id 42 \
  --carla-host 127.0.0.1 \
  --carla-port 2000 \
  --carla-map Town01 \
  --delay 10
```

CARLA가 다른 PC에 있으면 `--carla-host`에 실제 IP를 지정하고 RPC/센서 통신에 필요한 네트워크를 허용합니다. GUI 없이 실행할 때는 `--headless`를 추가합니다.

CARLA 프로파일은 다음 설정을 자동 적용합니다.

- `carla_sensor_kit`과 `sample_vehicle`
- `/exec/.../autoware_carla_interface/config/objects.json`
- LiDAR pose `x=-0.36`, `y=0`, `z=1.84`
- traffic-light fine detection 비활성화, HSV classifier 설정 유지
- `publish_ground_truth_traffic_lights:=true`
- traffic-light arbiter의 `external_priority: true`

실행 터미널의 `Ctrl-C`로 세 파티션을 함께 종료합니다. 재시작할 때는 센서 actor와 simulation clock의 잔존 상태를 피하기 위해 **CARLA와 세 파티션을 모두 종료한 뒤 CARLA부터 함께 재시작**합니다.

로그는 다음 위치에 저장됩니다.

```text
log/perception_log.txt
log/decision_log.txt
log/control_log.txt
```

## 7. 신호등 모드

| 모드 | 용도 | 색상 공급원 | 비고 |
| --- | --- | --- | --- |
| CARLA 검증 기본 | 시뮬레이션 주행 검증 | CARLA actor GT | external topic이 최종 결과보다 우선 |
| 센서 기반 | 실차 및 인식 성능 검증 | 카메라 ROI + classifier | GT 파라미터를 끄고 classifier 결과 사용 |

CARLA 기본 모드의 데이터 흐름은 다음과 같습니다.

```text
CARLA traffic-light actor
  -> /perception/traffic_light_recognition/external/traffic_signals
  -> traffic-light arbiter (external priority)
  -> /perception/traffic_light_recognition/traffic_signals
  -> planning
```

센서 기반 구성에서 YOLOX fine detector는 램프의 위치를 좁히는 역할이고, HSV 또는 CNN classifier가 색상을 판정합니다. YOLOX만으로 신호등 색상을 결정하는 구조가 아닙니다. 현재 소스는 fine detection을 끄면 classifier가 `expect/rois`를 직접 사용하도록 되어 있습니다.

실차 배포에서는 `publish_ground_truth_traffic_lights`의 기본값 `false`를 유지하고 CARLA 전용 시작 스크립트를 사용하지 않습니다.

## 8. 배포 직후 필수 확인

```bash
docker ps --filter 'name=adsw-'

docker exec adsw-perception-42 bash -lc '
source /opt/ros/humble/setup.bash
source /opt/autoware/setup.bash
export ROS_DOMAIN_ID=42
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
ros2 node list | sort | uniq -d
ros2 topic info /map/vector_map
ros2 topic info /map/pointcloud_map
'
```

중복 노드 출력은 없어야 하며 map topic의 publisher는 각각 1이어야 합니다. 이후 초기 pose, goal, Auto와 RED/GREEN 동작은 [CARLA 검증 매뉴얼](carla-validation-manual.md)의 순서로 확인합니다.

## 9. 알려진 주의 사항

- `/map/vector_map` publisher가 0이면 RViz 설정 문제가 아니라 map loader 기동 실패일 수 있습니다. `log/perception_log.txt`의 최초 오류를 확인하고 CARLA와 전체 파티션을 깨끗하게 재시작합니다.
- 임시 진단 노드를 여러 번 실행하면 동일한 node name이 남아 duplicate-node 검사와 emergency 판단을 방해할 수 있습니다.
- Auto가 활성화되지 않거나 주행 중 emergency stop이 발생하면 localization, route, hazard status와 중복 노드를 먼저 확인합니다.
- 소스만 수정하고 이미지를 재빌드하지 않으면 컨테이너에는 이전 classifier/launch 설정이 남습니다.
- 외부 CARLA client에서 actor 수가 0으로 보이는 현상만으로 인터페이스 실패를 판단하지 않습니다. CARLA interface 로그와 ROS sensor/status topic을 함께 확인합니다.
- GT 신호등 색상은 시뮬레이션 통합 검증용 임시 경로입니다. 실차 인지 성능을 입증하지 않습니다.
