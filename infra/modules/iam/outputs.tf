output "irsa_role_arns" {
  description = "역할 이름 → ARN. ServiceAccount의 eks.amazonaws.com/role-arn 어노테이션에 넣는다"
  value       = { for name, role in aws_iam_role.irsa : name => role.arn }
}
