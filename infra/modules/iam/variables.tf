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

variable "alb_controller_namespace" {
  description = "AWS Load Balancer Controller 네임스페이스"
  type        = string
  default     = "kube-system"
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

variable "external_secrets_namespace" {
  description = "External Secrets Operator가 설치되는 네임스페이스"
  type        = string
  default     = "external-secrets"
}

variable "secret_parameter_arn_prefix" {
  description = "ESO가 읽을 SSM 파라미터 ARN 접두사"
  type        = string
}
