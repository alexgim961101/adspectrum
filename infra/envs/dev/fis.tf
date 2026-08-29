# spot 회수를 실제로 일으켜 보는 실험. SPEC 13장에 "spot 중단으로 노드 소실"을
# 위험으로 적어 두고 대응은 문서로만 있었다. 대응이 동작하는지 확인하려면 회수를
# 기다리는 것이 아니라 일으켜야 한다.
#
# 확인하려는 것은 셋이다.
#   - Karpenter가 회수 알림을 받아 노드를 미리 비우는가
#   - 컨슈머가 SIGTERM을 받고 처리 중이던 배치를 마치는가 (유실 없이)
#   - metrics-api의 파드 분산이 실제로 가용성을 지키는가

data "aws_iam_policy_document" "fis_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fis" {
  name               = "${local.project}-fis"
  assume_role_policy = data.aws_iam_policy_document.fis_trust.json

  tags = { Name = "${local.project}-fis" }
}

# 실험이 EC2에 회수 신호를 보낼 수 있게 한다. AWS 관리형 정책을 쓰는 이유는
# FIS 액션이 요구하는 권한 집합이 서비스 쪽에서 정의되기 때문이다.
resource "aws_iam_role_policy_attachment" "fis_ec2" {
  role       = aws_iam_role.fis.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access"
}

resource "aws_fis_experiment_template" "spot_interruption" {
  description = "Karpenter 노드 하나에 spot 회수를 일으킨다"
  role_arn    = aws_iam_role.fis.arn

  action {
    name      = "interrupt-spot-node"
    action_id = "aws:ec2:send-spot-instance-interruptions"

    target {
      key   = "SpotInstances"
      value = "karpenter-node"
    }

    parameter {
      key = "durationBeforeInterruption"
      # 실제 spot 회수와 같은 2분 예고를 준다. 더 짧게 주면 대응 과정을
      # 관찰할 시간이 없다.
      value = "PT2M"
    }
  }

  target {
    name           = "karpenter-node"
    resource_type  = "aws:ec2:spot-instance"
    selection_mode = "COUNT(1)"

    resource_tag {
      key   = "karpenter.sh/nodepool"
      value = "default"
    }
  }

  # 중단 조건을 두지 않는다. 실험 자체가 노드 하나를 회수하는 것으로 끝나고,
  # 그 영향은 클러스터가 흡수해야 하는 것이 이 실험의 요지다.
  stop_condition {
    source = "none"
  }

  tags = { Name = "${local.project}-spot-interruption" }
}
