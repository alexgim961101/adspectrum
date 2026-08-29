# GitHub Actions OIDC 프로바이더는 계정에 하나만 존재하는 공용 리소스이고
# 이미 만들어져 있다. 이 프로젝트가 소유하면 destroy할 때 같은 계정의 다른
# 프로젝트 CI까지 끊기므로, 만들지 않고 참조만 한다 (DECISIONS 003).
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  # GitHub이 OIDC subject에 소유자·저장소의 숫자 ID를 함께 싣는 immutable subject로
  # 전환했다. 이름은 바뀌거나 반납 후 남이 차지할 수 있지만 ID는 바뀌지 않는다.
  # 이름만 고정하던 예전 형식(repo:owner/repo:ref:...)은 더 이상 토큰과 일치하지
  # 않는다 (DECISIONS 010).
  #
  #   repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/<branch>
  github_subject = format(
    "repo:%s@%s/%s@%s:ref:refs/heads/%s",
    split("/", local.github_repository)[0],
    local.github_repository_owner_id,
    split("/", local.github_repository)[1],
    local.github_repository_id,
    local.github_branch,
  )
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
      values   = [local.github_subject]
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
    resources = [for r in aws_ecr_repository.apps : r.arn]
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.project}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json

  tags = { Name = "${local.project}-github-actions" }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.project}-github-actions-ecr"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_ecr.json
}
