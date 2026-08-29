output "cluster_name" {
  description = "클러스터 이름"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "쿠버네티스 API 서버 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "API 서버 인증서. kubeconfig 구성에 쓴다"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "IRSA 신뢰 정책의 주체가 되는 OIDC 프로바이더 ARN"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "OIDC 발급자 URL(스킴 제외). 신뢰 정책의 sub/aud 조건 키 접두사로 쓴다"
  value       = module.eks.oidc_provider
}

output "node_security_group_id" {
  description = "노드 보안 그룹. 추가 규칙이 필요할 때 참조한다"
  value       = module.eks.node_security_group_id
}

output "karpenter_service_account_role_arn" {
  description = "Karpenter 컨트롤러가 쓰는 IAM 역할 ARN"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_node_iam_role_name" {
  description = "Karpenter가 만든 노드에 붙는 IAM 역할 이름. EC2NodeClass가 참조한다"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_interruption_queue_name" {
  description = "spot 회수 알림을 받는 SQS 큐 이름"
  value       = module.karpenter.queue_name
}
