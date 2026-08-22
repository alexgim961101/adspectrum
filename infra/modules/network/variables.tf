variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름. 서브넷의 kubernetes.io/cluster 태그에만 사용하며 실제 의존성은 없다"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR"
  type        = string
}

variable "azs" {
  description = "서브넷을 배치할 가용영역 목록"
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "EKS 컨트롤플레인은 최소 2개 AZ의 서브넷을 요구한다."
  }
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록. azs와 같은 순서로 대응된다"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록. azs와 같은 순서로 대응된다"
  type        = list(string)
}
