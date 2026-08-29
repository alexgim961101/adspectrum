locals {
  region  = "ap-northeast-2"
  project = "adspectrum"

  # 이미지를 굽는 애플리케이션. envs/dev의 app_names와 같은 목록이어야 한다.
  app_names = ["ad-event-generator", "event-consumer", "metrics-api"]

  # CI 역할의 신뢰 정책 대상. OIDC subject에는 이름이 아니라 숫자 ID가 실린다
  # (DECISIONS 010). 값 확인:
  #   gh api repos/alexgim961101/adspectrum --jq '{owner: .owner.id, repo: .id}'
  github_repository          = "alexgim961101/adspectrum"
  github_repository_owner_id = "74600075"
  github_repository_id       = "1343590586"
  github_branch              = "main"
}
