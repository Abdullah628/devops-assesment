# DEV environment — small & cheap. No secrets here (RDS password is managed by
# AWS Secrets Manager), so this file is safe to commit.
# Apply with:  terraform apply -var-file=dev.tfvars

environment  = "dev"
aws_region   = "eu-north-1"
project_name = "devops-assessment"

kubernetes_version = "1.30"

# Free-tier-eligible instance type (t3.medium is NOT free-tier eligible).
node_instance_type = "m7i-flex.large"
node_desired_count = 1
node_min_count     = 1
node_max_count     = 2

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["eu-north-1a", "eu-north-1b"]

db_instance_class        = "db.t3.micro"
db_engine_version        = "16"
db_allocated_storage     = 20
db_multi_az              = false
db_backup_retention_days = 0 # Free Tier requires 0
