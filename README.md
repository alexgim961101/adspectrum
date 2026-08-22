# adspectrum

광고 성과 이벤트를 실시간으로 수집·집계하는 이벤트 드리븐 파이프라인을
AWS EKS 위에 IaC(Terraform)와 GitOps(ArgoCD)로 구축·운영하는 프로젝트.

> 이름은 프리즘을 통과한 빛이 스펙트럼이 되듯,
> 파편화된 광고 이벤트 스트림을 분해·집계해 보이게 만든다는 의미입니다.

## 아키텍처 개요

```
ad-event-generator (노출/클릭 시뮬레이터)
  → SQS (이벤트 큐)
  → EKS 위 consumer 워커 (KEDA 큐 길이 기반 오토스케일링)
  → DynamoDB (집계 저장)
  → metrics API (성과 조회, Argo Rollouts 카나리 배포)
  → Prometheus + Grafana (처리량/랙/스케일링 관측)
```

## 문서

- [설계 스펙](docs/SPEC.md) — 아키텍처, 컴포넌트 스펙, 일정, 컷라인
- [의사결정 기록](docs/DECISIONS.md) — 구현 중 내린 판단과 근거, 겪은 문제
