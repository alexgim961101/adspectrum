terraform {
  required_version = ">= 1.5.7"

  # envs/dev와 같은 버킷을 쓰되 키를 나눈다. 두 스택의 수명이 다르므로 상태도
  # 분리해야 한다 — dev를 destroy할 때 이쪽 상태가 함께 움직이면 안 된다.
  backend "s3" {
    bucket         = "adspectrum-tfstate-894759291324"
    key            = "shared/terraform.tfstate"
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
