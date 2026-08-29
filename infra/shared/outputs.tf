output "ecr_repository_urls" {
  description = "앱 이름 → ECR 리포지토리 URL. CI가 푸시 대상으로 쓴다"
  value       = { for name, repo in aws_ecr_repository.apps : name => repo.repository_url }
}

output "github_actions_role_arn" {
  description = "CI가 ECR에 푸시할 때 맡는 역할"
  value       = aws_iam_role.github_actions.arn
}
