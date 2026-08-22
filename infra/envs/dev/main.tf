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

  name      = local.project
  app_names = local.app_names
}
