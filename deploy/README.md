# deploy — ArgoCD가 바라보는 경로

클러스터 안의 모든 변경은 이 디렉터리를 거친다. `kubectl apply`로 직접 넣은 것은
ArgoCD가 되돌린다(`selfHeal`). 유일한 예외는 `bootstrap/`이며, ArgoCD 자신을 설치하는
과정이라 GitOps 바깥에 있다.

```
deploy/
├── bootstrap/   ArgoCD 설치 스크립트와 app-of-apps의 뿌리 (1회 수동 실행)
├── apps/        뿌리가 관리하는 자식 Application. 파일 하나가 컴포넌트 하나
└── values/      애플리케이션 values. CI가 이미지 태그를 여기에 갱신한다 (3일차)
```

## 동작 방식

```
install.sh ──Helm──▶ ArgoCD
     └─apply─▶ root Application
                  └─감시─▶ deploy/apps/*.yaml
                              └─▶ 각 컴포넌트 (Helm 차트 또는 charts/)
```

뿌리 Application 하나만 손으로 넣으면, 그 뒤로는 `deploy/apps/`에 파일을 추가하는
커밋만으로 컴포넌트가 늘어난다. 이것이 app-of-apps 패턴이다.

## 컴포넌트

| 파일 | 무엇 | 쓰이는 시점 |
|---|---|---|
| `aws-load-balancer-controller.yaml` | Ingress → 실제 ALB 생성 | 3일차 API 노출, 6일차 카나리 |
| `keda.yaml` | 큐 길이 기반 오토스케일링 | 5일차 |
| `argo-rollouts.yaml` | 카나리 배포와 자동 롤백 | 6일차 |
| `kube-prometheus-stack.yaml` | Prometheus, Grafana, kube-state-metrics | 5·6일차 관측 |

## 값을 고칠 때 주의할 것

**Application 이름은 Helm 릴리스 이름이 된다.** `kube-prometheus-stack`의 이름을 바꾸면
Grafana ServiceAccount 이름이 함께 바뀌고, IRSA 신뢰 정책이 그 이름을 고정하고 있어
CloudWatch 조회 권한이 끊긴다. 이름을 바꾸려면 `infra/modules/iam`의 변수도 함께 고쳐야 한다.

**역할 ARN은 계정마다 다르다.** 다른 계정에 배포하려면 `deploy/apps/`의 ARN을 모두 바꿔야 한다.
GitOps는 Git에 있는 것이 곧 클러스터 상태여야 하므로 값을 배포 시점에 주입하지 않는다.
