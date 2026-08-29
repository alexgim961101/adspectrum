# 실행 절차

인프라를 만들고, 확인하고, 내리는 절차. 비용 때문에 작업하지 않는 날은 내려 두므로
이 절차는 매일 반복된다.

`[미검증]`이 붙은 단계는 아직 직접 실행해 확인하지 않은 것이다. 확인한 뒤 표시를 지운다.

---

## 1. 로컬 준비

### 필요한 도구

| 도구 | 최소 버전 | 용도 |
|---|---|---|
| Terraform | 1.5.7 | EKS 모듈 v21이 요구하는 하한 |
| AWS CLI | 2.x | 자격증명, kubeconfig 갱신 |
| kubectl | 1.33+ | 클러스터 조작 |
| Helm | 3.x | ArgoCD 부트스트랩 |
| Docker | 20.x+ | 앱 이미지 빌드 |
| uv | 0.5+ | Python 앱 로컬 검증 |

macOS에서 Homebrew로 설치하면 Terraform은 1.5.7이 받아진다. HashiCorp가 그 다음
버전부터 라이선스를 BUSL로 바꾸면서 Homebrew가 마지막 오픈소스 버전에 머물러 있기
때문이고, 이 프로젝트에는 그대로 써도 문제가 없다.

### AWS 자격증명

```sh
aws configure           # 리전은 ap-northeast-2
aws sts get-caller-identity
```

EKS·VPC·IAM을 만들어야 하므로 관리자 수준 권한이 필요하다.

### 변수 파일

예산 알림 이메일은 개인정보라 저장소에 커밋하지 않는다. 직접 만든다.

```sh
cd infra/envs/dev
cat > terraform.tfvars <<'EOF'
budget_notification_email = "본인@example.com"
EOF
```

`*.tfvars`는 `.gitignore` 대상이다. 이 파일이 없으면 `terraform plan`이 변수를 묻는다.

---

## 2. 계정 사전 조건

GitHub Actions용 OIDC 자격증명 공급자가 계정에 있어야 한다. 이 프로젝트는 계정 공용
리소스를 소유하지 않고 참조만 하므로 Terraform이 만들지 않는다 (DECISIONS 003).

```sh
aws iam list-open-id-connect-providers
```

목록에 `token.actions.githubusercontent.com`이 없으면 `[미검증]` 아래 명령으로 만든다.

```sh
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

### 상태 백엔드와 CI 역할 (최초 1회)

Terraform 상태는 S3에 있고 DynamoDB로 잠근다. **이 셋은 Terraform이 만들지 않는다.**
자기 상태를 담은 저장소를 자기 상태로 관리하면 `destroy`가 자기 발밑을 지우고, CI의
plan 역할이 환경 안에 있으면 환경이 내려간 순간 plan도 못 돌린다 (DECISIONS 015).

```sh
ACC=894759291324; R=ap-northeast-2
B=adspectrum-tfstate-$ACC; T=adspectrum-tfstate-lock

aws s3api create-bucket --bucket "$B" --region "$R" \
  --create-bucket-configuration LocationConstraint="$R"
aws s3api put-public-access-block --bucket "$B" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$B" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$B" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
aws s3api put-bucket-lifecycle-configuration --bucket "$B" --lifecycle-configuration \
  '{"Rules":[{"ID":"expire-noncurrent","Status":"Enabled","Filter":{},"NoncurrentVersionExpiration":{"NoncurrentDays":90}}]}'

aws dynamodb create-table --table-name "$T" --region "$R" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

버전 관리를 켜는 이유는 상태를 실수로 덮어썼을 때 되돌릴 수 있어야 하기 때문이고,
수명주기 규칙은 그 이전 버전들이 무한히 쌓이지 않게 한다.

CI의 plan 역할은 읽기 전용이다. 신뢰 정책은 이 저장소의 `main` push와 PR 두 subject만
허용하고, 권한은 `ReadOnlyAccess`에 명시적 Deny를 얹어 상태 버킷 밖의 S3 객체와
비밀 값 조회를 막는다. 정책 문서는 DECISIONS 015에 근거와 함께 정리되어 있다.

```sh
aws iam get-role --role-name adspectrum-ci-plan --query 'Role.Arn' --output text
```

**zsh에서 정책 JSON을 작성할 때 주의한다.** `"arn:aws:dynamodb:$R:$ACC:table/$T"`처럼
쓰면 zsh가 `$ACC:t`를 변수 수식자(basename)로 해석해 ARN이 조용히 깨진다. 중괄호로
`${ACC}`처럼 감싸거나 파일을 스크립트로 생성한다. 실제로 겪었다.

### ArgoCD 배포 키 (최초 1회)

저장소가 비공개라 ArgoCD가 clone하려면 자격이 필요하다. 개인 SSH 키 대신 이 저장소에만
유효한 **읽기 전용 배포 키**를 쓴다. 유출되어도 다른 저장소에 영향이 없고 쓰기도 불가능하다.

```sh
ssh-keygen -t ed25519 -f ~/.ssh/adspectrum-argocd-deploy -N "" -C "argocd-readonly@adspectrum"
gh repo deploy-key add ~/.ssh/adspectrum-argocd-deploy.pub \
  --repo alexgim961101/adspectrum --title argocd-readonly
```

키는 홈 디렉터리에만 두고 저장소에 커밋하지 않는다. `install.sh`가 이 파일을 읽어
argocd 네임스페이스에 repository 시크릿을 만든다. 클러스터를 다시 만들어도 키는 그대로
재사용하므로 이 절차는 반복하지 않는다.

키를 분실하면 GitHub에서 기존 배포 키를 지우고 위 명령을 다시 실행한다.

```sh
gh repo deploy-key list --repo alexgim961101/adspectrum
```

---

## 3. 인프라 생성

```sh
cd infra/envs/dev
terraform init          # S3 백엔드에 연결하고 잠금 테이블을 확인한다
terraform plan -out=tfplan
terraform apply tfplan
```

계획을 파일로 저장해 넘기는 이유는 검토한 계획이 그대로 실행되게 하기 위해서다.
`terraform apply`만 실행하면 apply 시점에 계획을 다시 계산하므로, 검토한 것과
실행되는 것이 원리상 다를 수 있다. 계획 파일을 넘기면 확인 프롬프트도 뜨지 않는다.

`tfplan`에는 모든 값이 평문으로 들어간다. `.gitignore` 대상이지만 다 쓰면 지운다.

소요 시간은 **실측 12분**이다(2026-08-23, 리소스 72개). 대부분 EKS 컨트롤플레인 생성이고,
VPC·SQS·DynamoDB·ECR·IAM은 3분 안에 끝난다. `Still creating... [10m30s elapsed]` 같은 줄이
계속 올라오는 것은 정상이다.

**중단해야 하면 Ctrl+C를 한 번만 누른다.** Terraform이 진행 중인 작업을 마치고 state를
기록한 뒤 종료한다. 두 번 누르면 강제 종료되어 이미 만들어진 리소스가 state에 기록되지
않을 수 있고, 다음 apply에서 중복 생성으로 실패한다.

중간에 실패하면 그냥 다시 실행한다. 만들어진 것은 state에 남아 있어 남은 것부터 이어서 만든다.

---

## 4. 생성 확인

여기까지의 완료 기준은 노드가 Ready이고 큐·테이블·리포지토리가 생성된 것이다.

```sh
terraform output

aws eks update-kubeconfig --region ap-northeast-2 --name adspectrum-eks
kubectl get nodes
```

### 파드 수용량 확인 (반드시)

```sh
kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.pods}{"\n"}{end}'
```

**110이 나와야 한다.** 17이면 VPC CNI의 prefix delegation이 노드에 반영되지 않은 것이고,
그대로 두면 플랫폼 컴포넌트만으로 파드 자리가 차서 오토스케일링이 성립하지 않는다
(DECISIONS 001). 이 경우 애드온 설정을 확인한 뒤 노드그룹을 교체한다.

2026-08-23 첫 실행에서 두 노드 모두 `pods=110`, 할당 가능 메모리 `3372960Ki`(약 3.2GiB)로 확인했다.

```sh
kubectl -n kube-system get ds aws-node \
  -o jsonpath='{.spec.template.spec.containers[0].env}' | tr ',' '\n' | grep -i prefix
```

### 리전 서비스 확인

```sh
aws sqs list-queues --queue-name-prefix adspectrum --region ap-northeast-2
aws dynamodb describe-table --table-name adspectrum-metrics --region ap-northeast-2 \
  --query 'Table.{status:TableStatus,keys:KeySchema}'
aws ecr describe-repositories --region ap-northeast-2 \
  --query 'repositories[?starts_with(repositoryName, `adspectrum/`)].repositoryName'
```

---

## 4a. 앱 이미지 빌드와 푸시

ArgoCD가 앱을 동기화하려면 ECR에 이미지가 먼저 있어야 한다. 평소에는 CI가 대신하므로,
이 절차는 클러스터를 새로 만들어 ECR이 빈 상태이거나 CI 없이 재현할 때만 쓴다.

### 로컬 검증

앱마다 독립 패키지라 디렉터리를 옮겨 가며 실행한다.

```sh
cd apps/ad-event-generator   # event-consumer, metrics-api도 같다
uv sync
uv run ruff check .
uv run ruff format --check .
uv run pytest
```

컨테이너 밖에서 직접 실행할 때는 `PYTHONPATH`가 필요하다. 패키지로 설치하지 않고
소스를 그대로 쓰기 때문이며, 이미지 안에서는 `ENV PYTHONPATH=/app/src`가 같은 일을 한다.

```sh
PYTHONPATH=src uv run python -m generator.main
```

### 빌드와 푸시

```sh
aws ecr get-login-password --region ap-northeast-2 \
  | docker login --username AWS --password-stdin \
    894759291324.dkr.ecr.ap-northeast-2.amazonaws.com

TAG=$(git rev-parse --short HEAD)
for app in ad-event-generator event-consumer metrics-api; do
  docker buildx build --platform linux/amd64 --provenance=false \
    -t 894759291324.dkr.ecr.ap-northeast-2.amazonaws.com/adspectrum/$app:$TAG \
    --push apps/$app
done
```

**빌드와 푸시를 쪼개지 않는다.** `--load`로 받아 두었다가 나중에 `docker push`로 밀면,
buildx가 함께 만드는 provenance attestation이 불변 태그를 차지하고 진짜 이미지는 400으로
거부된다. `describe-images`에는 태그가 보이므로 성공한 것처럼 착각하기 쉽다 (DECISIONS 012).
`--provenance=false`는 그 매니페스트를 아예 만들지 않는다.

**`--platform linux/amd64`를 빼면 안 된다.** 개발 환경이 Apple Silicon(arm64)이고 노드는
`t3.medium`(amd64)이라, 기본값으로 빌드하면 파드가 `exec format error`로 죽는다
(DECISIONS 008). CI는 x86 러너에서 돌아 이 실수가 드러나지 않으므로 로컬에서만 주의하면 된다.

**ECR 리포지토리는 태그 불변(IMMUTABLE)이다.** 같은 태그를 두 번 밀 수 없다. 이미지를
다시 구우려면 커밋을 하나 더 쌓아 새 SHA를 만든다. 태그가 곧 배포 산출물의 신원이라
같은 태그가 다른 내용을 가리키는 상황을 원천 차단한 것이다.

### 태그 반영

```sh
sed -i '' "s/^  tag: \"\"$/  tag: \"$TAG\"/" deploy/values/*.yaml
git commit -am "chore(deploy): 이미지 태그 갱신 [skip ci]"
git push origin main
```

ArgoCD는 Git만 본다. 푸시하지 않으면 ECR에 이미지가 있어도 배포되지 않는다.

### 확인

```sh
aws ecr describe-images --region ap-northeast-2 \
  --repository-name adspectrum/metrics-api \
  --query 'imageDetails[].imageTags' --output text
```

---

## 4b. ArgoCD 부트스트랩

인프라가 준비된 뒤 한 번만 실행한다. 이후 클러스터 안의 모든 변경은 Git을 통해서만 이루어진다.

```sh
deploy/bootstrap/install.sh
```

스크립트는 실행 전에 kubectl 컨텍스트가 대상 클러스터를 가리키는지 확인한다.
다른 클러스터에 설치하는 사고를 막기 위한 것이며, 어긋나면 전환 명령과 함께 중단한다.

### 알림 목적지

Alertmanager가 알림을 보낼 곳이다. 웹훅 URL은 **SSM 파라미터 스토어**에 두고
External Secrets Operator가 클러스터로 당겨 온다. 사람이 클러스터에 직접 넣지
않으므로, 클러스터를 몇 번을 다시 만들어도 이 값은 그대로 남는다 (DECISIONS 017).

발급 절차 (최초 1회):

1. <https://api.slack.com/apps> → **Create New App** → **From scratch**
2. 이름을 정하고 알림을 받을 워크스페이스를 고른다
3. **Features → Incoming Webhooks**를 켠다
4. **Add New Webhook to Workspace** → 채널 선택 → **Allow**
5. 표시된 `https://hooks.slack.com/services/...`를 복사한다

채널은 이 시점에 고정된다. 나중에 바꾸려면 웹훅을 다시 발급한다.

**URL을 화면에 남기지 않고 저장한다.** 명령 이력이나 로그에 남으면 그 자체로 유출이다.

```sh
printf '웹훅 URL: '
stty -echo; IFS= read -r W; stty echo; printf '\n'
aws ssm put-parameter --region ap-northeast-2 \
  --name /adspectrum/alertmanager/slack-webhook \
  --type SecureString --value "$W" --overwrite >/dev/null
unset W
```

`stty -echo`로 입력을 숨긴다. `read -p`로 프롬프트를 주는 방식은 bash 전용이라
zsh에서는 `read: -p: no coprocess`로 실패한다 — zsh에서 `-p`는 코프로세스에서
읽으라는 다른 뜻이다. 위 형태는 두 셸에서 모두 동작한다.

목적지가 살아 있는지는 클러스터 없이도 확인할 수 있다. URL을 출력하지 않고 응답 코드만 본다.

```sh
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' \
  -d '{"text":"adspectrum 연결 확인"}' \
  "$(aws ssm get-parameter --region ap-northeast-2 \
      --name /adspectrum/alertmanager/slack-webhook --with-decryption \
      --query 'Parameter.Value' --output text)"
```

`200`이면 채널에 메시지가 도착한다. `403`이나 `404`면 웹훅이 폐기됐거나 URL이 잘못됐다.

**파라미터는 `terraform destroy`로 지워지지 않는다.** Terraform이 만들지 않기
때문이며, 그래야 클러스터를 다시 세울 때 사람이 다시 입력하지 않는다. 목적지를
바꾸려면 위 `put-parameter`를 다시 실행하면 되고, 클러스터는 `refreshInterval`
(1시간) 안에 새 값을 가져간다. 즉시 반영하려면 다음을 실행한다.

```sh
kubectl annotate externalsecret alertmanager-slack -n monitoring \
  force-sync=$(date +%s) --overwrite
```

파라미터가 없으면 `ExternalSecret`이 오류 상태로 남고 Alertmanager 파드는 시크릿을
기다린다. 값을 넣는 순간 스스로 회복하므로 순서를 지킬 필요는 없다.

### 동기화 확인

```sh
kubectl get applications -n argocd
```

`root`와 자식 7개가 모두 `Synced` / `Healthy`여야 한다.

| 플랫폼 | 앱 |
|---|---|
| `aws-load-balancer-controller`, `keda`, `argo-rollouts`, `kube-prometheus-stack` | `ad-event-generator`, `event-consumer`, `metrics-api` |

앱 3종은 `deploy/values/`의 이미지 태그가 ECR에 실제로 있어야 동기화된다. 태그가 비어 있으면
차트의 `required`가 걸려 렌더링 단계에서 실패한다 (4a 참조).

### UI 접근

외부에 노출하지 않으므로 port-forward로 접근한다. ALB를 띄우지 않아 비용과 공격 표면을 모두 줄인다.

```sh
kubectl port-forward -n argocd svc/argocd-server 8080:80
# http://localhost:8080 · 사용자 admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 메모리 여유 확인

노드 2대의 할당 가능 메모리가 약 6.4GiB뿐이라 플랫폼 컴포넌트가 다 올라간 뒤 확인해야 한다
(DECISIONS 001).

```sh
kubectl get pods -A --field-selector=status.phase=Pending
kubectl describe nodes | grep -A 5 "Allocated resources"
```

`Pending` 파드가 있고 사유가 메모리 부족이면 노드 타입 상향을 검토한다.

---

## 4c. CI (GitHub Actions)

`apps/**`를 고쳐 main에 push하면 배포까지 자동으로 간다.
4a의 수동 절차는 CI 없이 재현하거나 급히 이미지를 구울 때만 쓴다.

```
push(main) ─▶ 변경 감지 ─▶ 검사(ruff·pytest) ─▶ 이미지 푸시(ECR)
                                                      │
                          deploy/values 태그 갱신 커밋 ◀┘
                                     │
                                     └─▶ ArgoCD가 감지해 배포
```

`pull_request`에서는 검사와 차트 렌더링까지만 돌고 AWS를 건드리는 잡은 실행되지 않는다.
CI 역할의 신뢰 정책이 `refs/heads/main`으로 잠겨 있어 PR에서는 역할 자체를 맡을 수 없다.

### 상태 확인

```sh
gh run list --limit 5
gh run view <run-id> --json jobs --jq '.jobs[] | "\(.conclusion) \(.name)"'
gh run view <run-id> --log-failed
```

### 다시 실행

```sh
gh run rerun <run-id> --failed
```

ECR이 태그 불변이라 같은 커밋을 다시 돌리면 푸시가 실패할 수 있는데, 워크플로가
`describe-images`로 먼저 확인해 이미 있는 태그는 빌드를 건너뛴다.

### 주의: 커밋 메시지에 `[skip ci]`를 쓰지 않는다

CI가 되미는 태그 갱신 커밋에만 붙이는 표식이다. **GitHub은 커밋 메시지 본문까지 검사하므로**,
설명하려고 적은 것도 그대로 인식해 실행을 건너뛴다. 이 프로젝트에서 실제로 겪었다
(DECISIONS 011).

### GitHub 저장소 ID가 바뀌면

CI 역할의 신뢰 정책이 OIDC subject를 고정하는데, 여기에 저장소와 소유자의 숫자 ID가 들어간다
(DECISIONS 010). 저장소를 새로 만들면 값을 다시 확인해 `infra/envs/dev/locals.tf`에 반영한다.

```sh
gh api repos/<owner>/<repo> --jq '{owner: .owner.id, repo: .id}'
```

---

## 4d. 데모 재현 (오토스케일링·카나리)

앱 3종이 Synced/Healthy가 된 뒤에 실행한다. 아래 실측값은 2026-08-28 기준이다.

### 관측 도구 접근

```sh
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000/d/adspectrum/adspectrum · 사용자 admin
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo

kubectl port-forward -n argocd svc/argocd-server 8080:80
```

ALB 주소는 Ingress에서 얻는다. 생성 직후 약 100초 동안은 `000`(연결 실패)이 나온다.

```sh
ALB=$(kubectl get ingress metrics-api -n adspectrum -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB/healthz"
```

**ArgoCD는 Git을 3분마다 본다.** 데모 중에는 커밋 직후 새로고침을 요청해 기다리는
시간을 줄인다. 동기화 자체는 여전히 ArgoCD가 한다.

```sh
kubectl patch application <앱> -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### 오토스케일링 (성공 기준 3)

부하는 `kubectl`이 아니라 커밋으로 넣는다. `deploy/values/ad-event-generator.yaml`을
고치고 push하면 그것이 곧 부하 주입이다.

| 단계 | 값 | 관측된 결과 |
|---|---|---|
| 부하 주입 | `EVENTS_PER_SEC: "300"` | 70초 뒤 레플리카 2 → 3 |
| 부하 증폭 | `replicaCount: 2` (초당 600건) | 40초 뒤 레플리카 5(상한). 큐 150~330 유지 |
| 부하 중단 | `replicaCount: 0` | 55초 뒤 큐 0, **2분 30초 뒤 레플리카 0** |

컨슈머 파드 하나가 초당 약 200건을 소화한다. 초당 300건은 파드 3개로 감당돼 큐가 쌓이지
않으므로, 상한까지 올리려면 발행을 600건으로 늘려야 한다.

```sh
watch -n5 'kubectl get deploy event-consumer -n adspectrum; kubectl get hpa -n adspectrum'
```

**초당 5건을 계속 흘리면 0까지 내려가지 않는다.** 유입이 있는 한 큐가 완전히 비지 않기
때문이다. scale-to-zero를 보려면 발행을 멈춰야 한다.

### 노드 오토스케일링과 spot 회수 (Karpenter)

파드 오토스케일링(KEDA)과 노드 오토스케일링(Karpenter)이 함께 도는지 본다.

```sh
kubectl get nodes -L karpenter.sh/nodepool,node.kubernetes.io/instance-type
kubectl get nodeclaims
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 -f
```

`karpenter.sh/nodepool` 라벨이 붙은 노드가 Karpenter가 만든 것이고, 없는 노드가 관리형
노드그룹이다. 부하를 올리면 컨슈머 파드가 늘고, 자리가 모자라면 `NodeClaim`이 생긴다.

부하를 내리면 `consolidateAfter`(1분) 뒤에 빈 노드가 정리된다. 관리형 노드그룹은 그대로
남는다 — 플랫폼 컴포넌트가 그 위에 있기 때문이다.

**spot 회수를 직접 일으킨다.** 회수를 기다리는 것이 아니라 만드는 것이 요점이다.

```sh
tpl=$(terraform -chdir=infra/envs/dev output -raw fis_spot_interruption_template_id)
aws fis start-experiment --region ap-northeast-2 \
  --experiment-template-id "$tpl" --query 'experiment.id' --output text
```

2분 예고 뒤에 인스턴스가 회수된다. 그동안 볼 것은 셋이다.

```sh
# 1. Karpenter가 회수 알림을 받아 노드를 비우는가
kubectl get nodes -w

# 2. 컨슈머가 처리 중이던 배치를 마치고 나가는가 (유실 없이)
kubectl logs -n adspectrum -l app.kubernetes.io/name=event-consumer -f | grep -i shutdown

# 3. 회수 뒤 DLQ가 비어 있는가 — 처리 중이던 메시지는 재전달되어야 한다
aws sqs get-queue-attributes --region ap-northeast-2 \
  --queue-url https://sqs.ap-northeast-2.amazonaws.com/894759291324/adspectrum-events-dlq \
  --attribute-names ApproximateNumberOfMessages --query 'Attributes'
```

실험은 Karpenter가 만든 노드 하나만 고른다(`karpenter.sh/nodepool` 태그). 관리형
노드그룹은 대상이 아니므로 플랫폼 컴포넌트가 함께 흔들리지 않는다.

### 알림이 실제로 울리는지

규칙이 발화해 Slack까지 가는지는 두 가지로 만든다.

```sh
# 스키마 위반 메시지 → ConsumerInvalidMessages
aws sqs send-message --region ap-northeast-2 \
  --queue-url https://sqs.ap-northeast-2.amazonaws.com/894759291324/adspectrum-events \
  --message-body '{"broken":"schema"}'

# 발화 여부 확인
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
curl -s localhost:9093/api/v2/alerts | python3 -m json.tool | grep alertname
```

`FAULT_RATE=0.5` 배포는 카나리 롤백과 `MetricsApiErrorBudgetBurningFast`를 동시에 만든다.

### 카나리 자동 롤백 (성공 기준 4)

분석에는 트래픽이 필요하다. 요청이 없으면 카나리의 5xx 비율을 계산할 표본이 없다.

```sh
k6 run -e BASE_URL="http://$ALB" -e DURATION=25m loadtest/k6-api.js
```

`deploy/values/metrics-api.yaml`의 `FAULT_RATE`를 `"0.5"`로 올려 push하면 결함 버전이
카나리로 나간다. 진행은 플러그인으로 본다.

```sh
kubectl argo rollouts get rollout metrics-api -n adspectrum --watch
kubectl get analysisrun -n adspectrum
```

실측 결과 (초당 30요청 공급 기준):

| 시나리오 | `FAULT_RATE` | 결과 |
|---|---|---|
| 결함 주입 | `0.5` | 20% 단계에서 85초 만에 중단, 가중치 자동 복구 (측정값 0.51, 0.48) |
| 기준선 아래 | `0.02` | 20% → 50% → 100% 승격, 약 3분 30초 (측정값 0.011~0.027) |

복구도 커밋이다. `FAULT_RATE`를 `"0"`으로 되돌려 push하면 Rollout이 Healthy로 돌아온다.
중단된 Rollout은 사람이 손대지 않아도 안정 버전 100%를 유지한다.

```sh
kubectl argo rollouts version   # 플러그인이 없으면 설치한다
```

플러그인은 컨트롤러와 같은 버전을 쓴다(차트 2.41.1 → v1.9.1). Homebrew의 argoproj tap은
tap 신뢰 설정과 Xcode CLT를 요구하므로, 공식 릴리스 바이너리를 `~/.local/bin`에 두는
편이 간단하다.

```sh
curl -sSL -o ~/.local/bin/kubectl-argo-rollouts \
  https://github.com/argoproj/argo-rollouts/releases/download/v1.9.1/kubectl-argo-rollouts-darwin-arm64
chmod +x ~/.local/bin/kubectl-argo-rollouts
```

---

## 5. 인프라 삭제

작업을 마치면 반드시 내린다. EKS 컨트롤플레인과 NAT Gateway는 사용하지 않아도
시간당 과금된다.

```sh
cd infra/envs/dev
terraform destroy
rm -f tfplan
```

자동화 스크립트나 비대화식 셸에서는 `-auto-approve`를 붙인다. 대화식으로 실행할 때는
붙이지 않는 편이 낫다 — 삭제 목록을 눈으로 확인하는 단계가 사라진다.

### Ingress가 있으면 ALB를 먼저 회수한다

metrics-api를 Ingress로 노출한 뒤부터는 destroy가 한 번에 끝나지 않는다. ALB는
AWS Load Balancer Controller가 Ingress를 보고 만든 것이라 **Terraform state에 없는데**
서브넷과 보안 그룹을 점유하고 있어서 VPC 삭제 단계에서 막힌다.

Ingress를 그냥 지우면 안 된다. ArgoCD의 `selfHeal`이 3분 안에 되살리고, 그러면
**ALB가 새로 하나 더 생긴다.** 자동 동기화를 먼저 끈다.

```sh
# 1. root와 metrics-api의 자동 동기화 중지
#    root를 함께 끄지 않으면 root가 metrics-api Application을 원상 복구한다
for app in root metrics-api; do
  kubectl patch application "$app" -n argocd --type merge \
    -p '{"spec":{"syncPolicy":{"automated":null}}}'
done

# 2. Ingress 삭제
kubectl delete ingress metrics-api -n adspectrum

# 3. ALB가 사라질 때까지 대기 (실측 약 1분)
until [ -z "$(aws elbv2 describe-load-balancers --region ap-northeast-2 \
    --query 'LoadBalancers[?contains(LoadBalancerName,`adspectrum`)].LoadBalancerArn' \
    --output text)" ]; do sleep 15; done

# 4. 타깃 그룹까지 회수됐는지 확인 (비어 있어야 한다)
aws elbv2 describe-target-groups --region ap-northeast-2 \
  --query 'TargetGroups[?contains(TargetGroupName,`adspectrum`)].TargetGroupName'

terraform destroy
```

컨트롤러는 ALB와 타깃 그룹, 자기가 만든 보안 그룹까지 스스로 정리한다. 이전 destroy에서
확인했고, 남은 보안 그룹은 전부 Terraform이 만든 EKS 것뿐이었다.

2026-08-28 재확인: Ingress 삭제 후 ALB가 사라지기까지 15초가 걸리지 않았고, 우리 VPC에
속한 타깃 그룹도 함께 사라졌다. 계정에 `k8s-ingressn-*` 타깃 그룹이 남아 있는데 다른
VPC 소속이라 이 프로젝트의 잔여물이 아니다 — 고아 리소스를 검사할 때 **VPC ID로
걸러야** 남의 리소스를 지우는 사고가 나지 않는다.

### 삭제 후 남는 것

의도적으로 남기는 것과 시간이 지나야 사라지는 것을 구분해야 한다.
아래는 2026-08-23 ArgoCD까지 올린 상태에서 destroy한 뒤 확인한 결과다(74개 삭제, 약 11분).
2026-08-28 앱 3종까지 올린 상태에서 다시 확인했다 — **74개 삭제, 11분 15초**, `state list` 0줄,
고아 리소스(EKS·VPC·SQS·ECR·IAM 역할·로드밸런서·인스턴스·미사용 ENI) 없음.

| 대상 | 상태 | 이유 |
|---|---|---|
| KMS 키 | `PendingDeletion` (7일 뒤) | 삭제 대기 기간. 재생성할 때마다 하나씩 늘지만 과금되지 않는다 |
| GitHub Actions OIDC 공급자 | 남음 | 계정 공용 리소스라 소유하지 않는다 (DECISIONS 003) |
| GitHub 배포 키 | 남음 | AWS가 아니라 GitHub에 있다. **지우면 다음 부트스트랩이 실패한다** |
| `~/.ssh/adspectrum-argocd-deploy` | 남음 | 위와 같은 이유로 유지한다 |
| NAT Gateway | `deleted` 상태로 잠시 표시 | AWS가 삭제 기록을 일정 기간 보여준다. 과금 없음 |
| VPC · EKS · SQS · DynamoDB · ECR · IAM 역할 · 예산 | 전부 삭제됨 | — |

### 다시 올릴 때: ECR이 비어 있다

`force_delete = true`라 destroy가 ECR 리포지토리를 이미지째 지운다. 그래야 destroy가
수동 개입 없이 끝난다(성공 기준 1). 대신 다시 `apply`하면 리포지토리가 빈 상태로 생기고,
`deploy/values`에 적힌 태그를 가리키는 이미지가 없어 ArgoCD 동기화가 실패한다.

부트스트랩 전에 4a의 빌드·푸시를 한 번 돌린다. 태그를 `deploy/values`에 적힌 값과 똑같이
주면 커밋을 새로 만들 필요가 없다.

```sh
grep -h '  tag:' deploy/values/*.yaml    # 지금 배포에 걸려 있는 태그 확인
```

앱을 고칠 예정이라면 그냥 push해서 CI에 맡기는 편이 빠르다.

### 삭제 확인

```sh
terraform state list          # 0줄이어야 한다

aws eks list-clusters --region ap-northeast-2
aws ec2 describe-vpcs --region ap-northeast-2 \
  --filters "Name=tag:Project,Values=adspectrum" --query 'Vpcs[].VpcId'
aws sqs list-queues --queue-name-prefix adspectrum --region ap-northeast-2
aws iam list-roles --query 'Roles[?starts_with(RoleName,`adspectrum`)].RoleName'
```

### 고아 리소스 검사

클러스터가 만든 리소스는 Terraform이 모른다. 아래가 전부 비어 있어야 한다.

```sh
aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query 'LoadBalancers[].LoadBalancerName'
aws ec2 describe-network-interfaces --region ap-northeast-2 \
  --filters "Name=status,Values=available" --query 'NetworkInterfaces[].NetworkInterfaceId'
aws ec2 describe-instances --region ap-northeast-2 \
  --filters "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId'
```

`terraform.tfstate`는 빈 상태로 남고 직전 상태는 `terraform.tfstate.backup`에 보관된다.
둘 다 커밋 대상이 아니다.

---

## 6. 문제 해결

| 증상 | 원인과 대응 |
|---|---|
| 노드그룹 생성 실패 | spot 용량 부족. 다시 실행하거나 `locals.tf`의 AZ 선택을 바꾼다 |
| 애드온 관련 오류 | EKS 1.36 호환 문제일 수 있다. `locals.tf`의 `kubernetes_version`을 한 단계 낮추고 다시 apply |
| `EntityAlreadyExists` (OIDC) | 계정에 이미 GitHub OIDC 공급자가 있는데 만들려 한 경우. 2장 참조 |
| apply가 중간에 멈춤 | 다시 실행한다. state에 남은 것부터 이어서 만든다 |
| `dial tcp: lookup budgets.amazonaws.com: no such host` | 일시적 DNS 실패다. 리소스 하나만 남으므로 `plan` → `apply`를 다시 돌리면 끝난다 (2026-08-28 실측) |
| ECR 푸시가 400 Bad Request | 4a의 빌드·푸시를 쪼갠 경우다. attestation이 태그를 차지했다 (DECISIONS 012) |
| `state lock` 오류 | 다른 터미널에서 Terraform이 실행 중이다. 끝날 때까지 기다린다 |
| kubectl 접근 거부 | `aws eks update-kubeconfig`를 다시 실행한다. 자격증명이 바뀌면 갱신이 필요하다 |

노드에 직접 들어가야 하면 SSH가 아니라 Session Manager를 쓴다. 프라이빗 서브넷이라
SSH 경로가 없고 키 페어도 두지 않았다. `[미검증]`

```sh
aws ssm start-session --target <인스턴스ID> --region ap-northeast-2
```
