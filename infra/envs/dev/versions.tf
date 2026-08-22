terraform {
  # EKS 모듈 v21이 요구하는 하한이다.
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.61"
    }
  }
}
