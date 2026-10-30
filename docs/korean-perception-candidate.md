# k-autoware 한국 신호등 인지 소스 후보 (2026-10-30)

브랜치: `feature/korean-perception-20261030`.
SILS 전용 브랜치를 병합하지 않고 최신 main에서 분리했습니다.
학습 모델과 범용 오류 수정을 검토·빌드할 수 있는 소스 후보이지, HIL/실차 검증 완료본은 아닙니다.

## 변경 범위

- `katech-autoware-universe`: CenterPoint shuffle의 `dst_idx`/`src_idx` 경계 검사 오류 수정.
  기존 수정 `264f6ef8f6bdf944f26960df2415cb5d248b231d`의 최소 한 줄만 이식했습니다.
  모델 가중치, score threshold, 센서/LiDAR 설정은 변경하지 않았습니다.
- 한국 신호등 YOLOX-S scale_02와 MobileNetV2 C의 모델 계약·체크섬·선택형 ROS 평가 패키지.
- native fine detector에 `cuda_preprocess` 선택 인자 추가. 기존 기본값 true 유지,
  한국 모델 후보에서만 CPU cubic 전처리 사용.
- 상위 저장소의 두 `.repos`에서 universe 커밋을 고정하고 perception 빌드 대상에 새 패키지를 추가.
- 기존 SHA 고정 검사에서 구형 Ubuntu `mawk`가 `{40}`을 처리하지 못하던 호환 문제 수정.
  40자리 소문자 hexadecimal 검증 조건과 main/No-CUDA 발행 제한은 그대로 유지합니다.

**판단·제어·System 분할·차량 보정·기존 센서 및 기본 launch는 최신 main과 같습니다.**
CARLA bridge, C-Track/map/PCD/3D 자산, GT 위치, 시뮬레이션 신호 스케줄러는 추가하지 않습니다.
기존 production 모델을 자동 교체하지 않고, 새 후보 출력도 planner에 자동 연결하지 않습니다.

## 받기

```bash
git clone --branch feature/korean-perception-20261030 https://github.com/OSS-TEST-GROUP/katech-autoware.git
cd katech-autoware
mkdir -p src
vcs import src < autoware.repos
```

모델과 실행 절차는 universe의
`perception/autoware_korean_traffic_light_models/README.md`를 따릅니다.
상위 저장소의 기존 partition 빌드 절차를 사용할 수 있으나, 이번 브랜치의 전체 이미지 빌드는
별도 확인 대상입니다. 새 classifier의 ONNX Runtime은 opt-in 요구사항 파일로 설치합니다.
컨테이너 기본 실행에는 후보 노드가 추가되지 않습니다.

기존 공식 이미지 발행 절차는 No-CUDA 기준입니다. 이 후보의 native YOLOX detector는
NVIDIA/CUDA가 필요하므로 No-CUDA 이미지에 바로 사용할 수 없습니다. GPU perception 이미지의
별도 빌드·검증 및 발행 정책은 후속 작업이며, 이번 변경은 기존 발행 제한을 완화하지 않습니다.

## 파일 위치와 플랫폼

소스는 두 Git 저장소에, 학습 ONNX는 이미 공개한 공통
[모델 Release](https://github.com/OSS-TEST-GROUP/katech-autoware-sils/releases/tag/models-korean-tl-20261030)에 있습니다.
4개 모델 합계 89,468,762 bytes. Release 이름과 달리 CARLA 없이 사용할 수 있는 모델입니다.
데이터셋, 학습 사진/라벨, 개인 경로, GPU 엔진, 컨테이너 tar는 Git에 포함하지 않습니다.

amd64/ARM64 소스는 공유하지만 이미지와 GPU 엔진은 대상별 빌드·검증해야 합니다.
특히 ARM64/Jetson은 CUDA/TensorRT/JetPack 및 ONNX Runtime 설치 호환성을 확인해야 합니다.
기존 `main`/기존 Release/다른 기관 운영 컨테이너는 이번 브랜치 푸시로 바뀌지 않습니다.

## 병합 전 확인

1. 새 main 기반 perception 전체 빌드와 native detector+classifier 메시지 재생 검증.
2. 대상 GPU 엔진 재생성·수치/속도/오류 처리 및 실제 카메라 보정/ROI/신호 ID 검증.
3. amd64/ARM64 개별 컨테이너, HIL·차량 회귀 검증 후 승인된 방식으로 출력 전환.

현재 증거와 미검증 항목은 `korean-perception-validation.json`에 기록합니다.
