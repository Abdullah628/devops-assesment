# Root module — wires the custom modules together into one platform.
#
#   network  ->  eks  ->  database (uses the EKS node SG as its only ingress)
#            ->  ecr
#            ->  monitoring
#
# Dependencies flow through module outputs (e.g. the database's allowed source
# SG is the EKS cluster SG), so Terraform figures out the correct order.

locals {
  # Effective cluster name: explicit override, else <project>-<environment>.
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}"
  name_prefix  = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "network" {
  source = "./modules/network"

  name_prefix  = local.name_prefix
  vpc_cidr     = var.vpc_cidr
  azs          = var.availability_zones
  cluster_name = local.cluster_name
  tags         = local.common_tags
}

module "ecr" {
  source = "./modules/ecr"

  name_prefix      = local.name_prefix
  repository_names = ["backend", "frontend"]
  tags             = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name           = local.cluster_name
  kubernetes_version     = var.kubernetes_version
  private_subnet_ids     = module.network.private_app_subnet_ids
  public_subnet_ids      = module.network.public_subnet_ids
  endpoint_public_access = var.eks_endpoint_public_access

  node_instance_type = var.node_instance_type
  node_desired_count = var.node_desired_count
  node_min_count     = var.node_min_count
  node_max_count     = var.node_max_count

  tags = local.common_tags
}

module "database" {
  source = "./modules/database"

  name_prefix   = local.name_prefix
  vpc_id        = module.network.vpc_id
  db_subnet_ids = module.network.private_db_subnet_ids
  # Only the EKS nodes' security group may reach the database on 5432.
  allowed_security_group_id = module.eks.cluster_security_group_id

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  # Harden prod: protect from deletion and keep a final snapshot.
  deletion_protection = var.environment == "prod"
  skip_final_snapshot = var.environment != "prod"

  tags = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  cluster_name       = local.cluster_name
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}
