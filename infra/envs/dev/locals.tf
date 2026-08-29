data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  region       = "ap-northeast-2"
  project      = "adspectrum"
  environment  = "dev"
  cluster_name = "${local.project}-eks"

  # 표준 지원 중인 최신 EKS 버전. 부트스트랩할 도구(ArgoCD, KEDA 등)에서
  # 호환 문제가 나오면 한 단계 낮춰 대응한다.
  kubernetes_version = "1.36"

  # AZ 이름(ap-northeast-2a 등)은 계정마다 다른 물리 AZ에 매핑되므로
  # 하드코딩하지 않고 조회 결과의 앞 2개를 쓴다.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # 프라이빗을 /20으로 넓게 잡는 이유: VPC CNI가 파드마다 서브넷 IP를 하나씩
  # 소비하므로 노드 수보다 훨씬 많은 주소가 필요하다.
  # 퍼블릭에는 ALB와 NAT Gateway만 있으므로 /24로 충분하다.
  vpc_cidr             = "10.0.0.0/16"
  private_subnet_cidrs = ["10.0.0.0/20", "10.0.16.0/20"]
  public_subnet_cidrs  = ["10.0.32.0/24", "10.0.33.0/24"]

  # 클러스터 밖에 두는 비밀의 위치. 파라미터 자체는 Terraform이 만들지 않는다 —
  # destroy와 함께 지워지면 클러스터를 다시 세울 때마다 사람이 값을 넣어야 한다
  # (DECISIONS 017). 여기서는 읽을 대상의 범위만 정한다.
  secret_parameter_arn_prefix = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.project}"

}
