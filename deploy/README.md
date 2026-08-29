# deploy — ArgoCD가 바라보는 경로

클러스터 안의 모든 변경은 이 디렉터리를 거친다. `kubectl apply`로 직접 넣은 것은
ArgoCD가 되돌린다(`selfHeal`). 유일한 예외는 `bootstrap/`이며, ArgoCD 자신을 설치하는
과정이라 GitOps 바깥에 있다.

```
deploy/
├── bootstrap/    ArgoCD 설치 스크립트와 app-of-apps의 뿌리 (1회 수동 실행)
├── apps/         뿌리가 관리하는 자식 Application. 파일 하나가 컴포넌트 하나
├── values/       애플리케이션 values. CI가 이미지 태그를 여기에 갱신한다
├── dashboards/   Grafana 대시보드 정의(ConfigMap). 차트가 아닌 평범한 매니페스트
├── secrets/      비밀을 어디서 가져올지(ClusterSecretStore)와 무엇을 가져올지(ExternalSecret)
└── karpenter/    어떤 노드를 언제 만들고 없앨지(NodePool, EC2NodeClass)
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

플랫폼 컴포넌트는 외부 Helm 저장소를, 앱 3종은 이 레포의 `charts/`를 바라본다.
대시보드만 차트가 아니라 매니페스트 디렉터리를 그대로 가리킨다.

| 파일 | 무엇 | 차트 출처 |
|---|---|---|
| `aws-load-balancer-controller.yaml` | Ingress → 실제 ALB 생성 | 외부 |
| `keda.yaml` | 큐 길이 기반 오토스케일링 | 외부 |
| `argo-rollouts.yaml` | 카나리 배포와 자동 롤백 | 외부 |
| `kube-prometheus-stack.yaml` | Prometheus, Grafana, kube-state-metrics | 외부 |
| `grafana-dashboards.yaml` | 대시보드 정의 | `deploy/dashboards` |
| `external-secrets.yaml` | SSM의 비밀을 k8s Secret으로 동기화 | 외부 |
| `external-secrets-config.yaml` | 비밀 저장소와 동기화 대상 정의 | `deploy/secrets` |
| `karpenter.yaml` | 노드 오토스케일링 | 외부(OCI) |
| `karpenter-config.yaml` | 노드 조건과 정리 정책 | `deploy/karpenter` |
| `ad-event-generator.yaml` | 이벤트 시뮬레이터 | `charts/ad-event-generator` |
| `event-consumer.yaml` | SQS → DynamoDB 집계 | `charts/event-consumer` |
| `metrics-api.yaml` | 조회 API (Rollout) | `charts/metrics-api` |

## 앱 Application이 소스를 둘 쓰는 이유

차트는 `charts/<앱>/`에, 값은 `deploy/values/<앱>.yaml`에 있다. 서로 다른 디렉터리라
`sources`를 둘로 나누고, 값 쪽 소스에 `ref: values`라는 이름을 붙여
`$values/deploy/values/<앱>.yaml`로 참조한다. `ref`만 있는 소스는 파일을 가져오기만 하고
렌더링하지 않는다.

값을 차트 안에 두면 간단해지지만, CI가 이미지 태그를 갱신할 때 `charts/`를 건드리게 된다.
그러면 CI 트리거의 `paths` 필터(`apps/**`, `charts/**`)에 걸려 빌드가 자기 자신을 다시 부른다.
값을 `deploy/` 아래로 뺀 것은 그 고리를 끊기 위한 경로 분리다.

**이미지 태그에는 기본값이 없다.** 차트가 `required`로 막아 두어서 태그가 비면 렌더링 단계에서
실패한다. `latest`로 조용히 배포되거나, CI가 갱신을 빠뜨린 채 이전 이미지가 그대로 도는 것보다
동기화가 실패하는 편이 낫다.

## 값을 고칠 때 주의할 것

**Application 이름은 Helm 릴리스 이름이 된다.** `kube-prometheus-stack`의 이름을 바꾸면
Grafana ServiceAccount 이름이 함께 바뀌고, IRSA 신뢰 정책이 그 이름을 고정하고 있어
CloudWatch 조회 권한이 끊긴다. 이름을 바꾸려면 `infra/modules/iam`의 변수도 함께 고쳐야 한다.

**역할 ARN은 계정마다 다르다.** 다른 계정에 배포하려면 `deploy/apps/`의 ARN을 모두 바꿔야 한다.
GitOps는 Git에 있는 것이 곧 클러스터 상태여야 하므로 값을 배포 시점에 주입하지 않는다.

## 동기화 순서

대부분의 Application은 순서를 따지지 않고 실패하면 재시도로 회복한다. 예외가 하나
있다. `external-secrets-config`와 `karpenter-config`는 `argocd.argoproj.io/sync-wave: "1"`을
달아 뒤에 동기화한다 — 둘 다 앞 물결의 차트가 설치하는 CRD가 있어야 존재할 수 있고,
ExternalSecret은 대상 네임스페이스(`monitoring`)도 먼저 생겨야 한다.

재시도로도 결국 회복되지만, 순서가 분명한 의존은 순서로 표현하는 편이 읽기 쉽다.

## GitOps 바깥에 있는 것 두 가지

의도적인 예외이고, 둘 다 "자기 자신을 관리할 수 없다"는 같은 이유에서 나온다.

**ArgoCD 자신** — ArgoCD가 자기 매니페스트를 동기화하다 실패하면 복구 수단까지 함께 사라진다.
`install.sh`로만 설치하고 갱신한다.

**저장소 접근 키** — 저장소가 비공개일 때 ArgoCD가 clone하려면 읽기 전용 배포 키가
필요한데, 이 키를 Git에 넣으면 저장소를 읽을 수 있는 사람이 곧 키를 얻는다. 부트스트랩
시점에 사람이 주입하는 **유일한 비밀**이며, 순환 때문에 옮길 수 없다 — 이 키가 있어야
저장소를 읽고, 저장소를 읽어야 External Secrets 설정을 가져온다. 나머지 비밀은 SSM에
두고 External Secrets가 당겨 온다 (DECISIONS 017).
