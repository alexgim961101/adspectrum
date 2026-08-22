# GitHub Actions OIDC 프로바이더는 계정에 하나만 존재하는 공용 리소스이고
# 이미 만들어져 있다. 이 프로젝트가 소유하면 destroy할 때 같은 계정의 다른
# 프로젝트 CI까지 끊기므로, 만들지 않고 참조만 한다 (DECISIONS 003).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# 지정한 저장소의 지정한 브랜치에서 실행된 워크플로만 이 역할을 맡을 수 있다.
# sub 조건을 저장소까지만 열어 두면 같은 저장소의 임의 브랜치나 PR에서도
# 역할을 맡을 수 있으므로 브랜치까지 고정한다.
data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

data "aws_iam_policy_document" "github_ecr" {
  # 로그인 토큰 발급은 리소스 단위 권한을 지원하지 않는다.
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # 푸시는 이 프로젝트의 리포지토리 3개로만 제한한다.
  # DescribeImages는 태그가 이미 있는지 확인해 중복 빌드를 건너뛸 때 쓴다
  # (ECR 태그가 IMMUTABLE이라 같은 태그 재푸시는 실패한다).
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
    ]
    resources = values(var.ecr_repository_arns)
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.name}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = { Name = "${var.name}-github-actions" }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${var.name}-github-actions-ecr"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_ecr.json
}
