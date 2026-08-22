output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록 (AZ 이름 오름차순)"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록 (AZ 이름 오름차순)"
  value       = [for s in aws_subnet.private : s.id]
}

output "nat_public_ip" {
  description = "NAT Gateway의 고정 공인 IP. 아웃바운드 트래픽의 출발지 주소다"
  value       = aws_eip.nat.public_ip
}
