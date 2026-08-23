#!/usr/bin/env bash
#
# ArgoCD를 설치하고 app-of-apps의 뿌리를 적용한다.
# 클러스터를 새로 만든 뒤 한 번만 실행하며, 이후 모든 변경은 Git을 통해 이루어진다.
#
# 사용법: deploy/bootstrap/install.sh
#
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-adspectrum-eks}"
REGION="${AWS_REGION:-ap-northeast-2}"
ARGOCD_NAMESPACE="argocd"
ARGOCD_CHART_VERSION="10.4.0"

# 비공개 저장소를 읽기 위한 배포 키. 저장소에 커밋하지 않으며
# 최초 1회 발급 절차는 RUNBOOK 2장에 있다.
REPO_URL="${REPO_URL:-git@github.com:alexgim961101/adspectrum.git}"
DEPLOY_KEY="${DEPLOY_KEY:-$HOME/.ssh/adspectrum-argocd-deploy}"
REPO_SECRET_NAME="adspectrum-repo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[31m오류: %s\033[0m\n' "$*" >&2; exit 1; }

# --- 안전 장치 ---------------------------------------------------------------
# 다른 클러스터(로컬 kind 등)에 실수로 설치하는 사고를 막는다.
# 이 스크립트는 클러스터 전체를 바꾸므로 대상 확인이 가장 중요하다.

log "대상 클러스터 확인"
current_context="$(kubectl config current-context 2>/dev/null || true)"
[ -n "$current_context" ] || fail "kubectl 컨텍스트가 없다. aws eks update-kubeconfig를 먼저 실행한다."

expected_suffix="cluster/${CLUSTER_NAME}"
if [[ "$current_context" != *"$expected_suffix" ]]; then
  fail "현재 컨텍스트가 '${current_context}'다. '${CLUSTER_NAME}'이 아니다.
  다음 명령으로 전환한다:
    aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER_NAME}"
fi
echo "  ${current_context}"

kubectl get nodes >/dev/null 2>&1 || fail "클러스터에 접근할 수 없다. 자격증명과 네트워크를 확인한다."
echo "  노드 $(kubectl get nodes --no-headers | wc -l | tr -d ' ')대 확인"

[ -f "$DEPLOY_KEY" ] || fail "배포 키가 없다: ${DEPLOY_KEY}
  비공개 저장소를 읽으려면 읽기 전용 배포 키가 필요하다. RUNBOOK 2장 참조."
echo "  배포 키 확인"

# --- ArgoCD 설치 -------------------------------------------------------------
# ArgoCD 자신은 GitOps로 관리하지 않는다. 자기 자신을 동기화하다 실패하면
# 복구 수단까지 사라지기 때문이다. 여기서만 설치하고 갱신한다.

log "Helm 저장소 준비"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null

# helm --wait을 쓰지 않는다. Helm 4에서 대기 중 취소되면 릴리스가 failed로 남고
# 만들던 리소스까지 사라져 원인을 찾기 어렵다. 설치와 대기를 분리하면
# 어느 컴포넌트가 준비되지 않았는지 그대로 보인다.
log "ArgoCD 설치 (차트 ${ARGOCD_CHART_VERSION})"
helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGOCD_NAMESPACE" \
  --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  --values "${SCRIPT_DIR}/values-argocd.yaml"

log "기동 대기"
for target in \
  statefulset/argocd-application-controller \
  deployment/argocd-repo-server \
  deployment/argocd-server \
  deployment/argocd-redis
do
  echo "  ${target}"
  kubectl rollout status "$target" -n "$ARGOCD_NAMESPACE" --timeout=5m
done

# --- 뿌리 Application 적용 ---------------------------------------------------

# --- 저장소 접근 자격 등록 -------------------------------------------------
# 비공개 저장소이므로 ArgoCD가 clone할 수단이 필요하다. 개인 SSH 키 대신
# 이 저장소에만 유효한 읽기 전용 배포 키를 쓴다. 키가 유출되어도 다른
# 저장소에 영향이 없고 쓰기도 불가능하다.
#
# 이 시크릿이 GitOps 바깥에 있는 이유: Git에 넣으려면 개인키를 커밋해야 하고,
# 그러면 저장소를 읽을 수 있는 사람이 곧 키를 얻는다. 부트스트랩 시점에만
# 사람이 주입하는 것이 이 프로젝트 범위에서 가장 단순한 방법이다.
# (외부 비밀 저장소 연동은 SPEC 12장에서 범위 제외)

log "저장소 접근 자격 등록"
kubectl create secret generic "$REPO_SECRET_NAME" \
  --namespace "$ARGOCD_NAMESPACE" \
  --from-literal=type=git \
  --from-literal=url="$REPO_URL" \
  --from-file=sshPrivateKey="$DEPLOY_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label secret "$REPO_SECRET_NAME" \
  --namespace "$ARGOCD_NAMESPACE" \
  argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
echo "  ${REPO_URL}"

log "app-of-apps 뿌리 적용"
kubectl apply -f "${SCRIPT_DIR}/root-app.yaml"

# --- 안내 -------------------------------------------------------------------

log "완료"
cat <<'EOF'

동기화 상태 확인:
  kubectl get applications -n argocd -w

UI 접근 (외부에 노출하지 않으므로 port-forward를 쓴다):
  kubectl port-forward -n argocd svc/argocd-server 8080:80
  http://localhost:8080

초기 admin 비밀번호:
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d; echo

EOF
