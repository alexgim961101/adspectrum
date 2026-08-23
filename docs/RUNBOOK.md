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
| Helm | 3.x | 2일차 ArgoCD 부트스트랩 |
| Docker | 20.x+ | 3일차 이미지 빌드 |
| uv | 0.5+ | 3일차 Python 앱 |

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
terraform init
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

1일차 완료 기준은 노드가 Ready이고 큐·테이블·리포지토리가 생성된 것이다.

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
그대로 두면 플랫폼 컴포넌트만으로 파드 자리가 차서 5일차 오토스케일링이 성립하지 않는다
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

## 4b. ArgoCD 부트스트랩

인프라가 준비된 뒤 한 번만 실행한다. 이후 클러스터 안의 모든 변경은 Git을 통해서만 이루어진다.

```sh
deploy/bootstrap/install.sh
```

스크립트는 실행 전에 kubectl 컨텍스트가 대상 클러스터를 가리키는지 확인한다.
다른 클러스터에 설치하는 사고를 막기 위한 것이며, 어긋나면 전환 명령과 함께 중단한다.

### 동기화 확인

```sh
kubectl get applications -n argocd
```

`root`와 자식 4개(`aws-load-balancer-controller`, `keda`, `argo-rollouts`,
`kube-prometheus-stack`)가 모두 `Synced` / `Healthy`여야 한다.

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

## 5. 인프라 삭제

작업을 마치면 반드시 내린다. EKS 컨트롤플레인과 NAT Gateway는 사용하지 않아도
시간당 과금된다.

```sh
cd infra/envs/dev
terraform destroy
rm -f tfplan
```

### 2일차 이후의 주의

ArgoCD로 Ingress를 배포한 뒤부터는 destroy가 한 번에 끝나지 않는다. AWS Load Balancer
Controller가 만든 ALB는 Terraform이 모르는 리소스인데 서브넷과 보안 그룹을 점유하고
있어서, VPC 삭제 단계에서 막힌다. 클러스터 안의 Ingress를 먼저 지워 ALB가 회수되기를
기다린 뒤 destroy한다. `[미검증]`

```sh
kubectl delete ingress --all --all-namespaces
# ALB가 사라질 때까지 대기
aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query 'LoadBalancers[].LoadBalancerName'
terraform destroy
```

### 삭제 후 남는 것

의도적으로 남기는 것과 시간이 지나야 사라지는 것을 구분해야 한다.
아래는 2026-08-23 첫 destroy에서 확인한 결과다.

| 대상 | 상태 | 이유 |
|---|---|---|
| KMS 키 | `PendingDeletion` (7일 뒤 삭제) | 삭제 대기 기간. 과금되지 않는다 |
| GitHub Actions OIDC 공급자 | 그대로 남음 | 계정 공용 리소스라 소유하지 않는다 (DECISIONS 003) |
| NAT Gateway | `deleted` 상태로 목록에 잠시 표시 | AWS가 삭제 기록을 일정 기간 보여준다. 과금 없음 |
| VPC · EKS · SQS · DynamoDB · ECR · IAM 역할 · 예산 | 전부 삭제됨 | — |

삭제 확인 명령:

```sh
terraform state list          # 0줄이어야 한다
aws eks list-clusters --region ap-northeast-2
aws ec2 describe-vpcs --region ap-northeast-2 \
  --filters "Name=tag:Project,Values=adspectrum" --query 'Vpcs[].VpcId'
aws sqs list-queues --queue-name-prefix adspectrum --region ap-northeast-2
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
| `state lock` 오류 | 다른 터미널에서 Terraform이 실행 중이다. 끝날 때까지 기다린다 |
| kubectl 접근 거부 | `aws eks update-kubeconfig`를 다시 실행한다. 자격증명이 바뀌면 갱신이 필요하다 |

노드에 직접 들어가야 하면 SSH가 아니라 Session Manager를 쓴다. 프라이빗 서브넷이라
SSH 경로가 없고 키 페어도 두지 않았다. `[미검증]`

```sh
aws ssm start-session --target <인스턴스ID> --region ap-northeast-2
```
