data "aws_availability_zones" "available" {
  state = "available"
}

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

  # 컨테이너 이미지를 빌드해 배포하는 애플리케이션. ECR 리포지토리와
  # IRSA 역할이 이 목록을 기준으로 만들어진다.
  app_names = ["ad-event-generator", "event-consumer", "metrics-api"]

  # CI 역할의 신뢰 정책 대상. 이 저장소의 main 브랜치 워크플로만 ECR에 푸시할 수 있다.
  github_repository = "alexgim961101/adspectrum"
}
