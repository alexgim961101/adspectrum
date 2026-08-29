# 레지스트리는 클러스터의 일부가 아니다. 환경을 지웠다 만들 때마다 이미지를 다시
# 굽는 것은 낭비이고, 무엇보다 CI가 클러스터 상태에 묶이게 된다 — 환경이 내려가
# 있으면 푸시가 실패한다. 실제로 그 실패를 겪고 이쪽으로 옮겼다 (DECISIONS 020).
resource "aws_ecr_repository" "apps" {
  for_each = toset(local.app_names)

  name = "${local.project}/${each.value}"

  # 같은 태그에 다른 이미지를 덮어쓸 수 없게 한다. GitOps에서 Git에 적힌
  # 이미지 태그가 특정 아티팩트를 유일하게 가리켜야 하기 때문이다.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # 환경과 함께 지워지지 않는 스택이므로 강제 삭제를 켜지 않는다. 이 리포지토리를
  # 지우려면 이미지를 어떻게 할지 사람이 먼저 정해야 한다.
  force_delete = false

  tags = { Name = "${local.project}-${each.value}" }
}

# 태그가 불변이라 오래된 이미지가 계속 쌓인다. 배포에 쓰이지 않는 옛 태그는
# 개수로 잘라 낸다. 저장 비용보다는 목록이 길어져 무엇이 최신인지 흐려지는 쪽이 문제다.
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
      },
      {
        # 환경과 함께 지워지지 않으니 태그가 계속 쌓인다. 개수로 자른다.
        rulePriority = 2
        description  = "태그 있는 이미지는 최근 20개만 남긴다"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}
