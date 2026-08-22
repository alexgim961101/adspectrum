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
