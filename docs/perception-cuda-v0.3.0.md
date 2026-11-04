# 인지 CUDA v0.3.0: 설치·검증 안내

기준일: 2026-11-04. **amd64 CUDA 및 arm64 SBSA CUDA 패키지 업로드와 원격 manifest 검증 완료.**
패키지 발행 완료이며, 실보드 GPU·HIL·실차 검증 완료를 의미하지 않습니다. 한국 신호등 모델은 선택형 후보 상태를 유지합니다.

## 배포 이미지

[GitHub Packages의 adsw-perception](https://github.com/OSS-TEST-GROUP/katech-autoware/pkgs/container/adsw-perception)에 다음 태그를 발행했습니다.

| 태그 | 대상 |
| --- | --- |
| `v0.3.0` | linux/amd64 및 linux/arm64 자동 선택 |
| `v0.3.0-amd64-cuda` | x86-64 + NVIDIA GPU |
| `v0.3.0-arm64-cuda` | SBSA ARM64 + NVIDIA 외장 GPU, Jetson 제외 |

패키지의 기존 공개 범위 **Internal(조직 내부용)**을 유지했습니다. 접근 권한이 있는 계정의 GHCR 로그인이 필요합니다.
일반 공개·익명 다운로드 가능 상태가 아닙니다. 소스 문서의 공개 여부와 패키지 접근 권한은 별개입니다.

통합 manifest digest: `sha256:33c290738e467520b73f0d5d0db9e94efb2396ffabe92aaa28a919918d68c258`.

| 아키텍처 | 원격 manifest digest |
| --- | --- |
| amd64 | `sha256:c008816d15e53c85abef6f92f0c9bc38075f260f115ce610e0c9ee4f6bf988d7` |
| arm64 | `sha256:d55ceb92ba30d7bf53d25d75749e61f6de55e520e909aa8ed749944a76d46d07` |

원격 config digest가 최종 로컬 이미지 ID와 일치하고, 통합 manifest가 정확한 두 플랫폼을 가리키는지 확인했습니다.
기존 6개 태그(v0.2.0 및 latest 포함)의 digest는 모두 변경되지 않았습니다.
[원격 발행 검증 기록](perception-cuda-v0.3.0-publication.json)을 참조하십시오.

## 범위

- linux/amd64: NVIDIA GPU를 사용하는 x86-64 PC.
- linux/arm64: Ampere Altra 기반 **SBSA + NVIDIA 외장 GPU** 대상. Jetson/JetPack용 이미지가 아닙니다.
- ROS 2 Humble / Ubuntu 22.04 컨테이너, CUDA 12.4 계열. 호스트에는 호환 NVIDIA 드라이버와 NVIDIA Container Toolkit이 필요합니다.
- 기본 분할 실행과 판단·제어 이미지를 교체하지 않습니다. CARLA, C-Track, PCD, 비공개 자산은 포함하지 않습니다.
- 한국 신호등 YOLOX-S와 MobileNetV2 C 모델은 명시적 선택형 후보입니다. 기존 운영 출력을 자동 교체하지 않습니다.
- 후보 launch의 detector는 TensorRT GPU 추론, classifier 기본값은 ONNX Runtime CPU입니다. CUDA 이미지라고 모든 후보 노드가 자동으로 GPU를 쓰지는 않습니다.

## 현재 검증 결과

| 검사 | amd64 | arm64 |
| --- | --- | --- |
| CUDA 이미지 빌드 | 통과 | 통과(에뮬레이션 빌드) |
| ONNX 4개 크기·SHA-256 | 통과 | 통과 |
| YOLOX/MobileNetV2 batch 1·6 CPU 합성 입력 추론 | 통과 | QEMU 환경에서 통과 |
| 핵심 GPU 공유 라이브러리 5개 ELF 아키텍처 | 통과 | 통과 |
| CUDA 초기화·공유 라이브러리 로딩 | RTX 4080에서 통과 | 미검증 |
| YOLOX batch 1 TensorRT 엔진 생성·ROS 입력/출력 | RTX 4080에서 통과 | 미검증 |
| 실센서 정확도·장시간 운용·HIL·실차 | 미검증 | 미검증 |

GPU 시험은 416×416 합성 이미지에 대한 실행 smoke test입니다. 실제 정확도나 전체 인지 파이프라인 성능을 측정하지 않았습니다.
CenterPoint는 컴파일·컴포넌트 로딩까지 확인했으며 실제 LiDAR 추론/회귀 검증은 별도입니다.
ARM64 CPU 추론 성공을 실보드 GPU 정상 작동으로 해석하지 마십시오.
기계 판독 결과는 [검증 기록](perception-cuda-v0.3.0-validation.json)을 참조하십시오.

## 소스 및 로컬 이미지 식별

상위 소스: `d915aed53ff4d7be880ae32b68100840ef5da0c6`.
의존 소스 전체는 [sources.lock.json](../release/perception-cuda-v0.3.0/gpu-build/sources.lock.json)에 고정합니다.
이 소스에 [빌드/설치 수정 patch](../release/perception-cuda-v0.3.0/gpu-build/source-build-fixes.patch)를 recipe overlay로 적용했습니다.

| 대상 | 검증한 로컬 이미지 ID(레지스트리 manifest digest 아님) |
| --- | --- |
| amd64 | `sha256:4d5b5a9a334b8666be3c1c822cf68184c7181ab744b7e657020826df83bfb9a0` |
| arm64 | `sha256:9f5cff1bc42da05b59805a9167ec3d7ae75b7dc13168ae7294db792ce66bd1dd` |

로컬 태그: `katech-perception-local:v0.3.0-candidate-amd64-cuda` / `katech-perception-local:v0.3.0-candidate-arm64-cuda`.
위 후보 이미지에 [메타데이터 전용 Dockerfile](../release/perception-cuda-v0.3.0/publication/)을 적용해 OCI version `0.3.0`으로 발행했습니다.
발행 전 파일 계층(RootFS)과 라벨을 제외한 실행 설정이 검증한 후보와 완전히 동일한지 확인했습니다. 모델·실행 파일 재빌드는 없습니다.
최종 이미지 ID와 기반 후보의 대응 관계는 원격 발행 검증 기록에 있습니다.

수정 사항:

1. 인지 분할 의존성 메타데이터와 이전 simulator 패키지명 보완.
2. 컴파일 병렬도 제한 및 ARM 빌드 전용 CMake 3.28.4/Python 경로 지정.
3. YOLOX GPU 전처리 공유 라이브러리 설치 규칙 추가.
4. 외부 NMS 플러그인의 구현 없는 rotated 함수 참조 제거. 기존 플러그인은 `rotated=false`만 사용하며 해당 동작은 유지합니다. `rotated=true` 요청은 명시적 미지원 오류로 처리합니다. 회전 NMS 지원을 추가한 것은 아닙니다.

## 소스에서 다시 빌드

[빌드 묶음](../release/perception-cuda-v0.3.0/)에는 텍스트 recipe·보완 소스·잠금 정보만 들어 있습니다.
학습 모델은 공개 모델 Release에서 내려받고 크기와 SHA-256을 확인합니다. 데이터셋/사진/엔진/컨테이너 tar는 Git에 없습니다.

Docker buildx, git, Python 3와 충분한 디스크 공간을 준비합니다. 해당 플랫폼을 실행할 수 있는 기존 builder를 지정합니다.
ARM에서는 네이티브 ARM builder를 권장하며 x86 호스트의 ARM 에뮬레이션 빌드는 오래 걸립니다.
다음 명령의 경로와 builder 이름은 사용자 환경으로 바꾸십시오. workspace는 **존재하지 않는 새 디렉터리**여야 합니다.

```bash
python3 release/perception-cuda-v0.3.0/rebuild.py \
  --arch amd64 --builder YOUR_BUILDER --workspace /data/perception-build-amd64
```

ARM은 `--arch arm64`와 별도 workspace를 사용합니다. 이 도구는 호스트 드라이버나 에뮬레이터를 자동 설치하지 않고 이미지를 업로드하지 않습니다.
검증에 사용한 recipe는 동일하지만, 이 공개 재구성 도구를 다른 PC에서 처음부터 실행한 검증은 미실시입니다.
외부 apt/PyPI 공급원 변경 때문에 바이트 단위 동일 재빌드를 보장하지 않습니다.

## 타겟에서 시작하기

먼저 호스트 `nvidia-smi`와 컨테이너 GPU 노출을 확인합니다.
패키지 접근 권한이 있는 계정으로 로그인합니다. Password에는 `read:packages` 권한의 개인 토큰(classic)을 직접 입력하며 토큰을 명령줄·문서에 적지 않습니다.
통합 태그는 호스트 아키텍처에 맞는 이미지를 선택합니다. 실장비와 맞지 않는 `--platform` 강제 지정으로 GPU 호환성을 해결할 수는 없습니다.

```bash
docker login ghcr.io -u YOUR_GITHUB_USERNAME
docker pull ghcr.io/oss-test-group/adsw-perception:v0.3.0
docker run --rm --gpus all --entrypoint nvidia-smi \
  ghcr.io/oss-test-group/adsw-perception:v0.3.0
```

고정된 배포본을 받으려면 태그 대신 통합 digest를 사용할 수 있습니다.

```bash
docker pull ghcr.io/oss-test-group/adsw-perception@sha256:33c290738e467520b73f0d5d0db9e94efb2396ffabe92aaa28a919918d68c258
```

후보 모델 경로는 `/opt/katech/models/korean-traffic-light`입니다. 엔진 캐시는 **타겟별 쓰기 가능한 별도 폴더**를 사용합니다.
호스트 RTX 4080에서 만든 엔진을 ARM 장비로 복사하지 않습니다.
실행 컨테이너에서 `/opt/ros/humble/setup.bash`와 `/opt/autoware/setup.bash`를 source한 뒤:

```bash
ros2 run autoware_korean_traffic_light_models models download --directory /work/korean_tl
ros2 run autoware_korean_traffic_light_models models verify --directory /work/korean_tl
ros2 launch autoware_korean_traffic_light_models candidate.launch.py \
  enable_candidate:=true models_dir:=/work/korean_tl \
  image_topic:=/sensing/camera/camera6/image_raw \
  rough_roi_topic:=/perception/traffic_light_recognition/camera6/detection/rough/rois \
  expected_roi_topic:=/perception/traffic_light_recognition/camera6/detection/expect/rois
```

`/work`는 타겟별 호스트 디렉터리를 마운트하십시오. 위 카메라/ROI 토픽은 예시이며 실제 구성에 맞춰야 합니다.
출력은 `/korean_tl/candidate/signals`이며 기존 판단기에 자동 연결되지 않습니다. timestamp/frame_id/신호 ID 및 카메라 보정이 일치해야 합니다.
보드에서 엔진 생성, 추론, 메시지 연속성, timeout/UNKNOWN, 실제 데이터 정확도, 지연·메모리·발열을 확인한 뒤 기관의 절차에 따라 출력 전환을 검토하십시오.

## 발행 시 지켜야 할 사항

발행 목적지는 `ghcr.io/oss-test-group/adsw-perception`이며 두 플랫폼 태그와 통합 v0.3.0의 원격 검증을 완료했습니다.
업로드 토큰은 사용자 PC에서만 설정했으며 Git/문서에 포함하지 않았습니다.
기존 v0.2.0 및 latest, 판단·제어 이미지와 SILS 배포는 변경하지 않았습니다. 전체 모듈 Git 릴리스 태그는 생성하지 않았습니다.
배포 자료와 README는 `release/perception-cuda-v0.3.0`에서 `main`으로 병합해 관리합니다.
패키지는 이 저장소에 연결되어 있으며 GitHub Packages의 README는 연결 저장소의 안내를 사용합니다.
이번 기록은 기존 PC의 검증 결과와 원격 manifest 확인입니다. 다른 PC의 신규 전체 다운로드·실행, ARM 실보드 GPU 시험은 미실시입니다.
기존 `release/publish-ghcr.sh`는 세 모듈과 latest를 함께 취급하므로 이번 인지 단독 발행에 그대로 사용하지 않습니다.
