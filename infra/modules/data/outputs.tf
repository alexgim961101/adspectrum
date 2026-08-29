output "queue_url" {
  description = "메인 큐 URL. generator와 consumer의 환경변수로 주입한다"
  value       = aws_sqs_queue.events.url
}

output "queue_arn" {
  description = "메인 큐 ARN. IRSA 정책의 리소스 범위로 쓴다"
  value       = aws_sqs_queue.events.arn
}

output "queue_name" {
  description = "메인 큐 이름. CloudWatch 큐 깊이 지표의 차원 값이다"
  value       = aws_sqs_queue.events.name
}

output "dlq_url" {
  description = "DLQ URL"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "DLQ ARN"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "DLQ 이름. DLQ 적재 패널의 지표 차원 값이다"
  value       = aws_sqs_queue.dlq.name
}

output "table_name" {
  description = "집계 테이블 이름. consumer와 metrics-api의 환경변수로 주입한다"
  value       = aws_dynamodb_table.metrics.name
}

output "table_arn" {
  description = "집계 테이블 ARN. IRSA 정책의 리소스 범위로 쓴다"
  value       = aws_dynamodb_table.metrics.arn
}
