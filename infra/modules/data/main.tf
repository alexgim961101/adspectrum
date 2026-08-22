# --- SQS ---

# 처리에 반복 실패한 메시지가 모이는 큐. 원인을 조사할 시간을 벌기 위해
# 보관 기간을 최대치(14일)로 둔다. 메인 큐보다 길어야 의미가 있다.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-events-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  tags = { Name = "${var.name}-events-dlq" }
}

resource "aws_sqs_queue" "events" {
  name = "${var.name}-events"

  # long polling. 0이면 빈 응답을 즉시 돌려주어 요청 수와 비용이 늘고
  # 메시지 도착이 지연된다.
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = true

  # consumer는 처리에 실패한 메시지를 삭제하지 않는다. 재전달이 반복되면
  # maxReceiveCount를 넘겨 DLQ로 격리되고, 나머지 메시지 처리는 계속된다.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = { Name = "${var.name}-events" }
}

# DLQ를 이 메인 큐 전용으로 제한한다. 지정하지 않으면 계정 내 다른 큐도
# 이 DLQ를 대상으로 삼을 수 있어 격리된 메시지의 출처가 섞인다.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.events.arn]
  })
}

# --- DynamoDB ---

# 캠페인별 분 단위 집계 테이블. 조회는 항상 "특정 캠페인의 기간"이라
# PK를 캠페인, SK를 분 버킷으로 두면 Query 한 번으로 구간을 읽는다.
# 트래픽 패턴을 예측할 수 없고 데모 볼륨이 작아 온디맨드로 둔다.
resource "aws_dynamodb_table" "metrics" {
  name         = "${var.name}-metrics"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  # 키가 아닌 속성(impressions, clicks, conversions, cost_micro)은
  # DynamoDB가 스키마를 요구하지 않으므로 선언하지 않는다.
  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  tags = { Name = "${var.name}-metrics" }
}

# --- ECR ---

resource "aws_ecr_repository" "apps" {
  for_each = toset(var.app_names)

  name = "${var.name}/${each.value}"

  # 같은 태그에 다른 이미지를 덮어쓸 수 없게 한다. GitOps에서 Git에 적힌
  # 이미지 태그가 특정 아티팩트를 유일하게 가리켜야 하기 때문이다.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # 이미지가 남아 있는 리포지토리는 기본적으로 삭제되지 않는다.
  # destroy 후 재apply를 수동 개입 없이 반복해야 하므로 강제 삭제를 허용한다.
  force_delete = true

  tags = { Name = "${var.name}-${each.value}" }
}

resource "aws_ecr_lifecycle_policy" "apps" {
  for_each = aws_ecr_repository.apps

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "태그 없는 이미지는 7일 후 삭제한다"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
