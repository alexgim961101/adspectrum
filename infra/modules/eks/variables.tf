variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS 버전. 도구 호환 문제가 생기면 이 값을 내려 대응한다"
  type        = string
}

variable "vpc_id" {
  description = "클러스터를 배치할 VPC"
  type        = string
}

variable "subnet_ids" {
  description = "노드와 컨트롤플레인 ENI가 위치할 프라이빗 서브넷"
  type        = list(string)
}

variable "node_instance_types" {
  description = "노드 인스턴스 타입. prefix delegation을 쓰므로 Nitro 기반이어야 한다"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "노드 희망 개수"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "노드 최소 개수"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "노드 최대 개수. 클러스터 오토스케일러가 없으므로 자동으로 늘지 않는다"
  type        = number
  default     = 4
}
