# 개인 이메일 주소는 저장소에 커밋하지 않는다.
# gitignore된 terraform.tfvars에 값을 넣는다 (RUNBOOK 참조).
variable "budget_notification_email" {
  description = "예산 임계 초과 알림을 받을 이메일 주소"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_notification_email))
    error_message = "유효한 이메일 주소를 입력해야 한다."
  }
}
