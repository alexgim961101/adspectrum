output "irsa_role_arns" {
  description = "역할 이름 → ARN. ServiceAccount의 eks.amazonaws.com/role-arn 어노테이션에 넣는다"
  value       = { for name, role in aws_iam_role.irsa : name => role.arn }
}

output "github_actions_role_arn" {
  description = "GitHub Actions가 맡을 역할 ARN. 워크플로의 role-to-assume에 넣는다"
  value       = aws_iam_role.github_actions.arn
}
