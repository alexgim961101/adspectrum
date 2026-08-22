# adspectrum

광고 이벤트 파이프라인을 EKS 위에 IaC와 GitOps로 구축·운영하는 개인 프로젝트. 구축 기간을 1주로 잡고 시작했다.

## 반드시 먼저 읽을 것

`docs/specs/2026-08-22-adspectrum-design.md` — 승인된 설계 스펙. 아키텍처, 컴포넌트 스펙,
일정, 컷라인, 의사결정이 전부 여기에 있다. 구현은 이 스펙을 따른다.
스펙과 충돌하는 변경이 필요하면 임의로 진행하지 말고 사용자에게 먼저 확인한다.

## 핵심 제약

- 기간 7일: 스펙 10장의 일정과 컷라인 우선순위를 지킨다. 범위 확장 금지.
- 비용: spot 노드, 단일 NAT, 미작업 시 `terraform destroy`. Terraform 멱등성은 절대 컷 불가.
- 리전 `ap-northeast-2`, Python 3.12 + uv + ruff + pytest, Terraform state는 로컬(.gitignore).
- 이 레포는 공개를 전제로 한다: 커밋 이력, README, 코드 품질 자체가 산출물이다.
