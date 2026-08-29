module "network" {
  source = "../../modules/network"

  name         = local.project
  cluster_name = local.cluster_name

  cidr_block           = local.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = local.public_subnet_cidrs
  private_subnet_cidrs = local.private_subnet_cidrs
}

module "data" {
  source = "../../modules/data"

  name = local.project
}

module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = local.kubernetes_version

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids
}

module "iam" {
  source = "../../modules/iam"

  name = local.project

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  queue_arn = module.data.queue_arn
  table_arn = module.data.table_arn

  secret_parameter_arn_prefix = local.secret_parameter_arn_prefix

}
