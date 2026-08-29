provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project   = local.project
      Scope     = "shared"
      ManagedBy = "terraform"
    }
  }
}
