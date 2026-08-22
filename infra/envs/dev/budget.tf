# 비용 폭주 방지 장치. EKS 컨트롤플레인과 NAT Gateway는 사용하지 않아도
# 시간당 과금되므로 destroy를 잊으면 예산을 넘긴다.
# 실제 사용액이 80%에 닿았을 때와, 이번 달 예상액이 한도를 넘길 것으로
# 보일 때 각각 알린다. 후자가 있어야 다 쓰기 전에 대응할 수 있다.
resource "aws_budgets_budget" "monthly" {
  name         = "${local.project}-monthly"
  budget_type  = "COST"
  limit_amount = "60" # 약 8만 원
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_notification_email]
  }
}
