# KATECH CARLA 빌드 및 연동 시험 안내

## 1. 전달 범위와 검증 상태

이 문서는 `feature/carla-perception-cuda` 브랜치를 받아 로컬 Docker 이미지를 빌드하고 외부 CARLA 서버와 연동 시험하는 절차입니다.

기능 구성과 정적 검증을 완료한 개발 브랜치입니다. 전체 Docker 빌드 성공 및 CARLA에서의 주행 성공은 아직 확인하지 않았습니다. 아래 시험 결과를 바탕으로 수정·검증한 뒤 정식 릴리즈합니다.

| 파티션 | 동작 | GPU |
| --- | --- | --- |
| Perception | 센서 처리·위치 추정·인식, CARLA 인터페이스와 차량 명령 변환 | NVIDIA CUDA 사용 |
| Decision | 판단·경로 계획 | CPU |
| Control | 제어 명령 생성, 차량 설명/TF, AD API | CPU |

CARLA 서버는 담당자가 별도로 실행합니다. Autoware의 기존 dummy perception/vehicle simulator는 CARLA 모드에서 실행하지 않습니다. 차량 설명을 위한 robot_state_publisher는 유지하고 기존 vehicle interface만 비활성화합니다.

현재 선택된 Universe 소스는 `7d4cf908b2c5113164e9e5a311071ed3c4aeb693`입니다. Universe 소스 수정 없이 상위 저장소의 빌드·실행 설정으로 구성했습니다.

## 2. 준비 환경

- Autoware 호스트: Ubuntu 22.04, x86_64/amd64.
- Docker Engine와 Buildx: 현재 사용자로 Docker 실행 가능.
- NVIDIA 드라이버와 NVIDIA Container Toolkit: 컨테이너에 GPU 전달 가능.
- Git, Git LFS, jq, vcstool(`vcs` 명령).
- 의존성 다운로드를 위한 인터넷 연결과 충분한 디스크/메모리.
- RViz를 같은 PC에서 사용할 경우 X11 GUI 세션.
- 외부 CARLA 서버: **0.9.15**. 실제 사용 버전이 다르면 시험 전에 알려주시기 바랍니다.

현재 소스에 맞춘 Python 3.10용 CARLA 0.9.15 wheel은 Docker 빌드 중 자동 설치됩니다. 호스트에 CARLA Python 모듈을 별도로 설치할 필요는 없습니다. wheel의 SHA-256도 빌드에서 확인합니다.

```bash
uname -m
docker info
docker buildx version
nvidia-smi
git lfs version
jq --version
vcs --version
```

`uname -m`은 `x86_64`여야 합니다. 호스트의 `nvidia-smi` 성공만으로 컨테이너 GPU 사용까지 검증된 것은 아닙니다. 실행 시 GPU 전달과 TensorRT 노드 초기화도 확인해야 합니다.

## 3. 브랜치 받기

기존 개발 폴더와 분리하여 새로 clone합니다. 원격에 해당 브랜치가 게시된 후 실행할 수 있습니다.

```bash
git clone --branch feature/carla-perception-cuda --single-branch \
  https://github.com/OSS-TEST-GROUP/katech-autoware.git katech-autoware-carla
cd katech-autoware-carla
git lfs pull
git branch --show-current
git rev-parse HEAD
bash tests/test_carla_profile.sh
bash tests/release_tagging_test.sh
bash tests/publish_ghcr_test.sh
```

시험 결과에는 `git rev-parse HEAD`의 값을 함께 기록합니다. 테스트 통과는 정적/모의 검증 결과이며 실제 이미지 빌드·주행 시험을 대체하지 않습니다.

## 4. 로컬 이미지 빌드

저장소 최상위에서 실행합니다. 아래 `REPO`는 로컬 이미지 이름이며 레지스트리 로그인은 필요하지 않습니다.

```bash
REPO=katech-autoware-carla-test
mkdir -p log
set -o pipefail
./partition/partition_build.sh \
  --repo "$REPO" \
  --platform linux/amd64 \
  --carla 2>&1 | tee log/carla-build.log
```

스크립트가 `autoware.repos`의 소스를 `src/`에 가져온 뒤 베이스 이미지와 세 파티션을 빌드합니다. 처음 빌드할 때 시간이 오래 걸릴 수 있습니다. 기존 `src/`가 있으면 갱신을 시도하므로 새 clone에서 시작하는 것을 권장합니다. 기존 스크립트는 빌드 종료 시 Docker dangling 이미지 정리도 수행합니다.

이번 시험에는 `--push`, `--native-staging`, `--no-cuda`를 추가하지 않습니다. 기존 정식 배포 절차는 CPU 멀티아키텍처용이며 CARLA 개발 이미지를 게시하는 절차가 아닙니다.

빌드가 성공하면 다음 이미지가 로컬에 있어야 합니다.

```bash
docker image inspect \
  katech-autoware-carla-test:adsw-perception-carla-cuda \
  katech-autoware-carla-test:adsw-decision-carla \
  katech-autoware-carla-test:adsw-control-carla \
  --format '{{.RepoTags}} {{.Os}}/{{.Architecture}}'
```

Decision과 Control의 `-carla`는 실행 설정 구분용이며 CUDA를 사용한다는 뜻이 아닙니다. 기존 CPU 이미지에는 새 시작 스크립트가 없을 수 있으므로 이번 브랜치에서 세 이미지를 모두 빌드합니다.

## 5. CARLA와 맵 준비

담당자가 CARLA 0.9.15 서버를 먼저 실행하고 서버 IP, RPC 포트, 맵 이름을 확인합니다. 기본값은 `127.0.0.1:2000`, `Town01`입니다. 다른 PC에서 실행하면 실제 서버 IP를 사용하고 RPC 및 센서 스트리밍 연결이 가능하도록 네트워크를 준비합니다.

현재 표준 인터페이스는 접속 후 지정 맵을 로드하고 ego 차량·센서를 생성하며 시뮬레이션 tick을 진행합니다. 다른 브리지나 시나리오 프로그램이 같은 역할을 동시에 수행하지 않도록 합니다. 기존 CARLA 세션의 맵과 차량 구성이 재설정될 수 있으므로 시험용 서버를 사용합니다.

Autoware에는 CARLA 맵과 일치하는 좌표계의 Lanelet2/pointcloud 맵이 필요합니다. 기존 `sample-map-planning`을 그대로 사용하지 않습니다. 현재 인터페이스 README는 y축 반전 맵과 Local projector를 전제로 합니다.

```text
Town01/
  lanelet2_map.osm
  pointcloud_map.pcd
  map_projector_info.yaml
```

`map_projector_info.yaml` 내용:

```yaml
projector_type: Local
```

맵과 인식 모델 데이터는 Git clone만으로 모두 준비되는 것이 아닙니다. 이미지 빌드/기동에서 모델 파일 누락이 발생하면 에러에 표시된 경로와 사용 모델 정보를 전달해 주십시오. 센서 모델은 현재 `awsim_sensor_kit`, 차량 모델은 `sample_vehicle`를 기본으로 사용합니다.

## 6. 실행

저장소 최상위에서 실제 환경에 맞춰 `MAP_PATH`와 `CARLA_SERVER`를 수정합니다.

```bash
MAP_PATH="$HOME/autoware_map/Town01"
CARLA_SERVER=127.0.0.1
unset PARTITION_IMAGE_TAG

./partition/run_partitions.sh \
  --repo katech-autoware-carla-test \
  --map-path "$MAP_PATH" \
  --domain-id 42 \
  --simulator-mode carla \
  --carla-host "$CARLA_SERVER" \
  --carla-port 2000 \
  --carla-map Town01
```

로컬 빌드 이미지에는 `--image-tag`를 지정하지 않습니다. 이 옵션은 별도 컴포넌트 레지스트리에서 정식 태그를 찾는 용도입니다. GUI 없이 실행하려면 `--headless`를 추가합니다.

스크립트가 Perception에만 `--gpus all`을 적용하고 모든 파티션에 동일한 ROS_DOMAIN_ID를 전달합니다. CARLA 전용 시작 스크립트는 시뮬레이션 시간을 사용합니다. 같은 domain과 컨테이너 이름으로 실행 중인 기존 Autoware는 먼저 종료합니다. 실행 스크립트는 같은 이름의 컨테이너를 제거하고 재생성합니다.

종료는 실행 터미널에서 `Ctrl-C`입니다. 재실행하면 기존 파티션 로그가 초기화되므로 필요한 로그는 먼저 보관합니다.

## 7. 연동 시험과 결과 전달

1. 세 컨테이너가 유지되는지, Perception 로그에 버전 불일치·GPU·TensorRT·누락 패키지 에러가 없는지 확인합니다.
2. CARLA 센서·차량 상태와 `/clock`이 수신되는지 확인합니다.
3. RViz에서 맵과 차량 좌표가 맞는지 확인하고, 표준 절차에 따라 GNSS 초기화/초기 위치와 목적지를 지정합니다.
4. 경로·trajectory 생성 후 Engage/Auto를 요청하여 CARLA 차량이 실제로 움직이고 목표에 도달하는지 확인합니다.
5. dummy simulator가 실행되지 않고 차량 명령 변환 노드가 하나만 실행되는지 확인합니다.

```bash
docker ps --filter 'name=adsw-'
docker exec adsw-perception-42 bash -lc \
  'source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; ros2 node list'
docker exec adsw-perception-42 bash -lc \
  'source /opt/ros/humble/setup.bash; source /opt/autoware/setup.bash; ros2 topic list'
```

주요 확인 토픽:

- `/clock`
- `/sensing/lidar/top/pointcloud_before_sync`
- `/vehicle/status/velocity_status`
- `/localization/kinematic_state`
- `/control/command/control_cmd`
- `/control/command/actuation_cmd`

토픽 목록에 이름이 보이는 것과 실제 메시지 수신은 다릅니다. 필요하면 동일한 컨테이너에서 `ros2 topic hz <토픽>` 또는 `ros2 topic echo <토픽> --once`로 확인합니다.

문제가 있으면 아래 정보를 전달합니다.

- Git 커밋 SHA, CARLA 버전/실행 명령, 서버 IP·포트·맵.
- OS, GPU 모델, NVIDIA 드라이버, Docker/Buildx 버전.
- `log/carla-build.log`와 실패한 최초 오류 주변 내용.
- `log/perception_log.txt`, `log/decision_log.txt`, `log/control_log.txt`.
- 프로세스가 너무 일찍 종료되어 파일 로그가 없으면 실행 터미널 출력.
- 맵 표시/위치 초기화/경로 생성/Engage/차량 이동 중 어디까지 성공했는지.

## 8. 흔한 증상

| 증상 | 확인 사항 |
| --- | --- |
| 브랜치를 찾을 수 없음 | 브랜치 원격 게시 여부, 저장소 URL과 접근 권한 |
| `vcs`, `jq`를 찾을 수 없음 | 호스트 빌드 도구 설치 |
| Docker socket permission denied | 현재 사용자의 Docker 접근 권한 |
| NVIDIA runtime/device 오류 | Container Toolkit 및 GPU 전달 설정 |
| CARLA client/server version mismatch | 서버 0.9.15 여부 |
| CARLA connection timeout | 서버 기동, IP·포트·방화벽 |
| 맵 파일 누락 또는 RViz 좌표 불일치 | Town 맵, 파일명, 좌표계와 Local projector |
| 패키지/모델 파일 누락, TensorRT 초기화 실패 | 최초 오류와 경로를 포함한 로그 전달 |
| topic은 있지만 차량이 움직이지 않음 | localization, route, engage, control/actuation 토픽 단계별 확인 |

이번 시험 결과가 확인되기 전에는 배포용 릴리즈 태그를 생성하거나 기존 정식 이미지를 덮어쓰지 않습니다.
