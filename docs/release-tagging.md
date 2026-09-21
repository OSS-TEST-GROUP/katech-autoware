# KATECH 태깅 및 릴리즈 규칙

## 1. 적용 대상

- 소스 정본: `https://github.com/OSS-TEST-GROUP/katech-autoware`
- 기본 브랜치: `main`
- 컨테이너 정본: GitHub Container Registry(GHCR)
- 대상 이미지:
  - `ghcr.io/oss-test-group/adsw-perception`
  - `ghcr.io/oss-test-group/adsw-decision`
  - `ghcr.io/oss-test-group/adsw-control`

Git 태그와 컨테이너 태그는 서로 다른 체계로 관리한다. Git 태그는 소스 릴리스를,
컨테이너 태그는 빌드 산출물을 식별한다.

## 2. Git 릴리즈 태그

정식 릴리즈는 `vMAJOR.MINOR.PATCH` 형식의 annotated tag를 사용한다.

- 첫 공식 릴리즈: `v0.1.0`
- 호환성이 깨지는 변경: MAJOR 증가
- 하위 호환 기능 추가: MINOR 증가
- 하위 호환 버그 수정: PATCH 증가
- 사전 릴리즈: `v1.2.0-rc1` 또는 `v1.2.0-beta1`

한번 원격에 push한 태그는 이동하거나 덮어쓰지 않는다. 잘못 발행한 경우 기존 태그를
옮기지 않고 다음 PATCH 버전을 발행한다. GitHub Release에는 변경 내용, 검증 결과,
세 컨테이너의 스냅샷 태그와 digest를 기록한다.

## 3. 컨테이너 태그

각 컴포넌트 저장소에 다음 태그를 함께 관리한다.

| 종류 | 형식 | 불변성 | 용도 |
| --- | --- | --- | --- |
| 스냅샷 | `main-YYYYMMDD-<shortsha>` | 불변 | 배포, 재현, 롤백 |
| 릴리즈 | `vMAJOR.MINOR.PATCH` | 불변 | Git 릴리즈와 대응 |
| 최신 포인터 | `latest` | 이동 | 개발 PC의 최신 이미지 pull |
| 네이티브 staging | `<snapshot>-amd64`, `<snapshot>-arm64` | 불변 | manifest 조립 입력 |

예: `ghcr.io/oss-test-group/adsw-perception:main-20260731-c128be8`

운영·보드 배포와 기관 간 검증에는 스냅샷 또는 릴리즈 태그만 사용한다. `latest`는
편의용이며 배포 기준으로 사용하지 않는다.

기존 `ghcr.io/oss-test-group/autoware-partition:adsw-*` 태그는 이전 사용자를 위해
같은 digest의 이동 포인터로 유지한다. 이 호환 경로는 deprecated이며 `v1.0.0`에서
종료한다.

## 4. 릴리즈 입력 고정

릴리즈 빌드는 다음 입력을 고정한다.

- 상위 저장소의 `main` 커밋
- `release/autoware-release.repos`에 기록된 32개 의존 저장소의 전체 commit SHA
- `release/base-images.env`에 기록된 ROS base image digest
- No-CUDA, `linux/amd64`와 `linux/arm64`

개발용 `autoware.repos`의 이동 브랜치는 릴리즈 빌드에 사용하지 않는다. 네이티브
staging 빌드는 top-level checkout 또는 의존 저장소가 dirty이거나, lock과 실제
checkout SHA가 다르거나, 현재 브랜치가 `main`이 아니면 중단한다.

이 규칙은 같은 배포 이미지를 digest로 다시 선택하고 롤백할 수 있게 한다. 다만 apt
저장소 등 외부 패키지 공급원이 시간에 따라 바뀔 수 있으므로 완전한 bit-for-bit 재빌드를
보장한다는 의미는 아니다.

## 5. v0.1.0 발행 절차

### 5.1 공통 스냅샷 확정

릴리즈 커밋을 `main`에 merge하고 아래 값을 한 번만 계산해 amd64와 arm64 담당자에게
동일하게 전달한다. 날짜는 UTC 기준이다.

```bash
git checkout main
git pull --ff-only origin main
git status --short

SOURCE_SHA=$(git rev-parse HEAD)
SNAPSHOT_TAG="main-$(date -u +%Y%m%d)-$(git rev-parse --short=7 HEAD)"
printf 'SOURCE_SHA=%s\nSNAPSHOT_TAG=%s\n' "$SOURCE_SHA" "$SNAPSHOT_TAG"
```

### 5.2 네이티브 staging 빌드

각 장비는 새 clone에서 시작한다. GHCR token은 명령행이나 파일에 평문으로 남기지 않고
표준 입력으로 로그인한다.

최초 발행 전 GitHub 조직 관리자는 `adsw-build-base`, `adsw-perception`,
`adsw-decision`, `adsw-control` 패키지가 이 저장소의 Actions에서 write 가능하도록
연결한다. 최종 세 컴포넌트 패키지는 외부 pull이 가능하도록 public으로 설정하고,
`adsw-build-base`는 배포 대상으로 안내하지 않는다.

amd64 PC:

```bash
./partition/partition_build.sh \
  --native-staging \
  --snapshot-tag "$SNAPSHOT_TAG" \
  --platform linux/amd64 \
  --no-cuda
```

arm64 BSP:

```bash
./partition/partition_build.sh \
  --native-staging \
  --snapshot-tag "$SNAPSHOT_TAG" \
  --platform linux/arm64 \
  --no-cuda
```

스크립트는 각 아키텍처에 대해 `adsw-build-base`와 세 컴포넌트의 staging 태그를 push한다.
세 최종 이미지에는 `revision`, `ref.name`, `created`, `version`, `source` OCI 라벨이
포함된다.

### 5.3 Git 태그와 최종 manifest 발행

두 아키텍처 staging 빌드가 성공한 뒤 동일한 `SOURCE_SHA`에 annotated tag를 생성한다.

```bash
git fetch --tags origin
git tag -a v0.1.0 "$SOURCE_SHA" -m "v0.1.0 — KATECH Autoware Partition initial release"
git push origin v0.1.0
```

GitHub의 `production` environment에는 필수 승인자를 설정한다. 이후
`Publish verified Autoware Partition images` workflow를 `main`에서 수동 실행하고,
앞서 확정한 `SNAPSHOT_TAG`와 `v0.1.0`을 입력한다.

워크플로는 다음 조건을 모두 확인한 뒤에만 발행한다.

1. Git 태그, workflow commit, 스냅샷 short SHA가 모두 같은 소스를 가리킨다.
2. amd64와 arm64 staging 이미지의 revision/version/source 라벨이 일치한다.
3. 기존 스냅샷이나 `v0.1.0`이 다른 digest를 가리키면 즉시 실패한다.
4. 세 컴포넌트 모두 검증된 뒤 스냅샷 manifest를 만들고 `latest`, `v0.1.0`,
   기존 호환 포인터를 갱신한다.
5. 최종 manifest가 linux/amd64와 linux/arm64를 각각 하나씩 포함하는지 재검증한다.

워크플로 성공 후 `.github/release-notes-template.md`를 채워 GitHub Release를 발행한다.

## 6. 배포 확인

```bash
docker buildx imagetools inspect \
  ghcr.io/oss-test-group/adsw-perception:v0.1.0
docker buildx imagetools inspect \
  ghcr.io/oss-test-group/adsw-decision:v0.1.0
docker buildx imagetools inspect \
  ghcr.io/oss-test-group/adsw-control:v0.1.0
```

보드 및 검증 환경에서는 세 이미지의 릴리즈 버전 또는 스냅샷을 동일하게 맞춘다. 검증이
끝나면 이미지 digest, BSP/PC 아키텍처 확인, Lane Driving 결과를 GitHub Release와
배포 기록에 남긴다.

## 7. 금지 사항

- 이미 push된 Git 태그, 스냅샷 태그 또는 릴리즈 이미지 태그 이동
- 기능 브랜치 또는 dirty checkout에서 staging push
- 두 아키텍처에 서로 다른 스냅샷 값 사용
- lock manifest 대신 개발용 이동 브랜치로 릴리즈 빌드
- `latest`를 보드·운영 배포 기준으로 사용
- 검증 workflow를 거치지 않은 수동 manifest 및 릴리즈 alias 생성
- 토큰, 비밀번호 또는 registry credential을 저장소·스크립트·로그에 평문 저장
