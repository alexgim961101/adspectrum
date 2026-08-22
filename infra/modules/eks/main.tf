# EKS 클러스터는 직접 작성하지 않고 공식 모듈을 쓴다. 컨트롤플레인, 노드그룹,
# 보안 그룹 규칙, 노드 IAM 역할 사이의 결합이 많아 직접 구성하면 실수 비용이 크다.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.25"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # 퍼블릭 엔드포인트는 모듈 기본값이 false다. 로컬에서 kubectl과 helm으로
  # 부트스트랩해야 하므로 열어 둔다. 접근은 IAM으로 인증되지만 소스 IP 제한은
  # 걸지 않았다 (DECISIONS 002).
  # 프라이빗 엔드포인트도 함께 켜서 노드는 VPC 내부 경로로 컨트롤플레인에 붙는다.
  endpoint_public_access  = true
  endpoint_private_access = true

  # aws-auth ConfigMap 대신 EKS Access Entry API로 접근 권한을 관리한다.
  # ConfigMap 방식은 잘못 수정하면 클러스터 접근이 통째로 끊긴다.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # IRSA용 OIDC 프로바이더를 만든다. iam 모듈이 이 ARN으로 신뢰 정책을 건다.
  enable_irsa = true

  # 컨트롤플레인 로그는 수집량만큼 과금되고 audit 로그는 양이 많다.
  # 이 프로젝트의 관측 책임은 Prometheus/Grafana에 있어 끈다 (DECISIONS 002).
  enabled_log_types           = []
  create_cloudwatch_log_group = false

  # 비용을 아끼려고 매일 destroy하므로 삭제 대기 기간을 최소값으로 둔다.
  # 기본 30일이면 재생성할 때마다 삭제 대기 상태의 키가 쌓인다.
  kms_key_deletion_window_in_days = 7

  addons = {
    # 노드보다 먼저 적용해야 한다. 노드가 뜬 뒤에 바꾸면 이미 기존 방식으로
    # 할당된 ENI 설정이 남아 파드 수용량이 늘지 않는다 (DECISIONS 001).
    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    # coredns는 스케줄될 노드가 있어야 하므로 노드그룹 이후에 적용한다.
    coredns    = {}
    kube-proxy = {}
  }

  # 프라이빗 서브넷이라 SSH가 불가능하다. 노드 디버깅이 필요할 때
  # Session Manager로 접속할 수 있도록 권한만 미리 붙여 둔다.
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      capacity_type  = "SPOT"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }
}
