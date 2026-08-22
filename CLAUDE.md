# adspectrum

매드업 DevOps Engineer 지원용 포트폴리오 프로젝트. 마감: 2026-08-29경 (약 7일).

## 반드시 먼저 읽을 것

`docs/SPEC.md` — 승인된 설계 스펙. 아키텍처, 컴포넌트 스펙,
일정, 컷라인, 의사결정이 전부 여기에 있다. 구현은 이 스펙을 따른다.
스펙과 충돌하는 변경이 필요하면 임의로 진행하지 말고 사용자에게 먼저 확인한다.

## 핵심 제약

- 기간 7일: 스펙 10장의 일정과 컷라인 우선순위를 지킨다. 범위 확장 금지.
- 비용: spot 노드, 단일 NAT, 미작업 시 `terraform destroy`. Terraform 멱등성은 절대 컷 불가.
- 리전 `ap-northeast-2`, Python 3.12 + uv + ruff + pytest, Terraform state는 로컬(.gitignore).
- 이 레포는 채용 담당자가 열람하는 포트폴리오다: 커밋 이력, README, 코드 품질 자체가 산출물이다.

## 문서 구조

docs/ 하위는 대주제 파일로만 관리한다. 파일은 첫 내용이 생길 때 만들고, 빈 문서를 미리 만들지 않는다.
README에는 실존하는 문서만 링크한다.

- `README.md` — 쇼케이스: 개요, 다이어그램, 데모 캡처, 공고 매칭 맵, 문서 링크
- `docs/SPEC.md` — 승인된 계획. 동결. 변경은 사용자 승인 후에만
- `docs/RUNBOOK.md` — 재현 절차(부트스트랩, 검증, 부하 테스트, destroy). 실제 실행해 검증한 명령만 기록
- `docs/DECISIONS.md` — 의사결정·트러블슈팅 기록. 상황→선택지→결정→이유 형식, append-only
- `docs/API.md` — 외부 계약: 이벤트 스키마(인바운드) + metrics-api 엔드포인트(아웃바운드). 실측 예시 기반
- `docs/images/` — 데모 캡처 이미지

위 목록에 없는 문서(ARCHITECTURE.md, CHANGELOG 등)는 추가하지 않는다.
