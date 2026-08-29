variable "name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "max_receive_count" {
  description = "이 횟수만큼 수신되고도 삭제되지 않은 메시지를 DLQ로 보낸다"
  type        = number
  default     = 3
}

variable "visibility_timeout_seconds" {
  description = "consumer가 메시지를 받은 뒤 처리에 쓸 수 있는 시간. 초과하면 다른 consumer에게 재전달된다"
  type        = number
  default     = 60
}
