terraform {
  # EKS 모듈 v21이 요구하는 하한이다.
  required_version = ">= 1.5.7"

  # 상태를 S3에 두고 DynamoDB로 잠근다. CI가 PR마다 plan을 돌리려면 상태에
  # 접근할 수 있어야 하는데, 로컬 파일은 러너에서 읽을 방법이 없다 (DECISIONS 015).
  #
  # 이 버킷과 잠금 테이블은 Terraform이 만들지 않는다. 자기 상태를 담은 저장소를
  # 자기 상태로 관리하면 destroy가 자기 발밑을 지운다. 계정 사전 조건으로 두고
  # 생성 절차는 RUNBOOK 2장에 있다.
  backend "s3" {
    bucket         = "adspectrum-tfstate-894759291324"
    key            = "envs/dev/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "adspectrum-tfstate-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.61"
    }
  }
}
