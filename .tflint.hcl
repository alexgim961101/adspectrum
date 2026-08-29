# 코어 규칙만으로는 AWS 리소스의 잘못된 속성을 잡지 못한다.
# 예: 존재하지 않는 인스턴스 타입, 유효하지 않은 IAM 정책 참조.
plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  # 모듈 안까지 들어가 검사한다. 외부 모듈(terraform-aws-modules)까지 훑으면
  # 우리가 고칠 수 없는 경고가 쏟아지므로 호출만 검사한다.
  call_module_type = "local"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}
