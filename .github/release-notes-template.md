# vX.Y.Z

## 변경 내용

- `<주요 변경 요약>`

## 검증

- [ ] linux/amd64 manifest 및 기동 확인
- [ ] linux/arm64 manifest 및 BSP 기동 확인
- [ ] Perception → Decision → Control 순차 실행 확인
- [ ] 외부 PC RViz2 연동 확인
- [ ] Planning Simulation Lane Driving 확인

## 소스

- Git revision: `<full-commit-sha>`
- Dependency lock: `release/autoware-release.repos`
- Base image lock: `release/base-images.env`

## 컨테이너

| 컴포넌트 | 스냅샷 태그 | 릴리즈 태그 | Digest |
| --- | --- | --- | --- |
| Perception | `main-YYYYMMDD-abcdef0` | `vX.Y.Z` | `sha256:...` |
| Decision | `main-YYYYMMDD-abcdef0` | `vX.Y.Z` | `sha256:...` |
| Control | `main-YYYYMMDD-abcdef0` | `vX.Y.Z` | `sha256:...` |

## 알려진 제약

- No-CUDA 릴리즈
- 기존 `autoware-partition:adsw-*` 경로는 `v1.0.0`까지 호환 포인터로 유지
