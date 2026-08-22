variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC 프로바이더 ARN. IRSA 신뢰 정책의 주체다"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC 발급자 URL(스킴 제외). 신뢰 정책 조건 키의 접두사다"
  type        = string
}

variable "queue_arn" {
  description = "이벤트 메인 큐 ARN"
  type        = string
}

variable "table_arn" {
  description = "집계 테이블 ARN"
  type        = string
}

variable "ecr_repository_arns" {
  description = "앱 이름 → ECR 리포지토리 ARN. CI 역할의 푸시 대상 범위다"
  type        = map(string)
}

variable "app_namespace" {
  description = "애플리케이션 3종이 배포될 네임스페이스"
  type        = string
  default     = "adspectrum"
}

variable "keda_namespace" {
  description = "KEDA 오퍼레이터 네임스페이스"
  type        = string
  default     = "keda"
}

variable "monitoring_namespace" {
  description = "kube-prometheus-stack 네임스페이스"
  type        = string
  default     = "monitoring"
}

variable "grafana_service_account" {
  description = "Grafana ServiceAccount 이름. Helm 릴리스 이름에 따라 달라진다"
  type        = string
  default     = "kube-prometheus-stack-grafana"
}

variable "github_repository" {
  description = "CI가 실행될 GitHub 저장소 (owner/repo)"
  type        = string
}

variable "github_branch" {
  description = "ECR 푸시를 허용할 브랜치. 이 브랜치의 워크플로만 역할을 맡을 수 있다"
  type        = string
  default     = "main"
}
