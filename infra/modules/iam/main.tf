locals {
  # 파드별 최소 권한. 하나의 역할을 앱들이 공유하지 않고 ServiceAccount마다 분리한다.
  irsa = {
    "ad-event-generator" = {
      namespace       = var.app_namespace
      service_account = "ad-event-generator"
      policy          = data.aws_iam_policy_document.generator.json
    }
    "event-consumer" = {
      namespace       = var.app_namespace
      service_account = "event-consumer"
      policy          = data.aws_iam_policy_document.consumer.json
    }
    "metrics-api" = {
      namespace       = var.app_namespace
      service_account = "metrics-api"
      policy          = data.aws_iam_policy_document.metrics_api.json
    }
    "keda-operator" = {
      namespace       = var.keda_namespace
      service_account = "keda-operator"
      policy          = data.aws_iam_policy_document.keda.json
    }
    "grafana" = {
      namespace       = var.monitoring_namespace
      service_account = var.grafana_service_account
      policy          = data.aws_iam_policy_document.grafana.json
    }

    # 유일하게 직접 작성하지 않은 정책이다. 아래 policies/ 파일 주석 참조.
    "aws-load-balancer-controller" = {
      namespace       = var.alb_controller_namespace
      service_account = "aws-load-balancer-controller"
      policy          = file("${path.module}/policies/aws-load-balancer-controller.json")
    }
  }
}

# IRSA 신뢰 정책. sub 조건이 네임스페이스와 ServiceAccount 이름까지 고정하므로
# 다른 파드가 같은 역할을 맡을 수 없다. aud 조건은 토큰이 STS를 대상으로
# 발급된 것인지 확인한다.
data "aws_iam_policy_document" "trust" {
  for_each = local.irsa

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa

  name               = "${var.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json

  tags = { Name = "${var.name}-${each.key}" }
}

# 역할마다 정책이 다르고 공유하지 않으므로 인라인 정책으로 둔다.
# 역할을 지우면 정책도 함께 사라져 destroy 시 잔여물이 남지 않는다.
resource "aws_iam_role_policy" "irsa" {
  for_each = local.irsa

  name   = "${var.name}-${each.key}"
  role   = aws_iam_role.irsa[each.key].id
  policy = each.value.policy
}

# --- 파드별 권한 정의 ---

# 발행만 한다. 큐를 읽거나 지울 수 없다.
data "aws_iam_policy_document" "generator" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [var.queue_arn]
  }
}

# 소비와 집계 반영. GetQueueAttributes는 큐 길이를 메트릭으로 노출할 때 쓴다.
# DynamoDB는 UpdateItem만 있으면 되고 읽기 권한은 필요 없다 —
# 원자적 ADD 연산이 현재 값을 읽지 않기 때문이다.
data "aws_iam_policy_document" "consumer" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [var.queue_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.table_arn]
  }
}

# 조회 전용. 쓰기 권한이 없으므로 API가 침해되어도 집계 데이터가 변조되지 않는다.
data "aws_iam_policy_document" "metrics_api" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Query"]
    resources = [var.table_arn]
  }
}

# KEDA는 큐 길이만 읽는다. 메시지를 읽거나 지울 권한은 없다.
data "aws_iam_policy_document" "keda" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:GetQueueAttributes"]
    resources = [var.queue_arn]
  }
}

# CloudWatch 지표 조회 API는 리소스 단위 권한을 지원하지 않아 대상을 좁힐 수 없다.
# 대신 읽기 전용 동작만 허용한다. tag:GetResources는 Grafana의 CloudWatch
# 데이터소스가 차원 값을 탐색할 때 호출한다.
data "aws_iam_policy_document" "grafana" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}
