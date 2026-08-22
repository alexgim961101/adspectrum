provider "aws" {
  region = local.region

  # 공통 태그는 프로바이더에서 일괄 부여한다. 각 모듈은 Name과
  # kubernetes.io/* 같은 리소스 고유 태그만 직접 지정한다.
  default_tags {
    tags = {
      Project     = local.project
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}
