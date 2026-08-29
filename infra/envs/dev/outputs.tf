output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "EKS 노드가 배치될 프라이빗 서브넷"
  value       = module.network.private_subnet_ids
}

output "public_subnet_ids" {
  description = "ALB와 NAT Gateway가 배치될 퍼블릭 서브넷"
  value       = module.network.public_subnet_ids
}

output "nat_public_ip" {
  description = "프라이빗 서브넷 아웃바운드 트래픽의 출발지 IP"
  value       = module.network.nat_public_ip
}

output "queue_url" {
  description = "이벤트 큐 URL"
  value       = module.data.queue_url
}

output "dlq_url" {
  description = "DLQ URL"
  value       = module.data.dlq_url
}

output "table_name" {
  description = "집계 테이블 이름"
  value       = module.data.table_name
}

output "ecr_repository_urls" {
  description = "앱 이름 → ECR 리포지토리 URL"
  value       = module.data.ecr_repository_urls
}

output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "쿠버네티스 API 서버 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "kubeconfig를 갱신하는 명령"
  value       = "aws eks update-kubeconfig --region ${local.region} --name ${module.eks.cluster_name}"
}

output "irsa_role_arns" {
  description = "ServiceAccount 어노테이션에 넣을 IRSA 역할 ARN"
  value       = module.iam.irsa_role_arns
}

output "github_actions_role_arn" {
  description = "CI 워크플로의 role-to-assume 값"
  value       = module.iam.github_actions_role_arn
}

output "fis_spot_interruption_template_id" {
  description = "spot 회수 실험 템플릿 ID. aws fis start-experiment에 넘긴다"
  value       = aws_fis_experiment_template.spot_interruption.id
}
