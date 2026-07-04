# STAGING environment — closer to prod (more nodes), separate network + state.
# Apply with:  terraform apply -var-file=staging.tfvars

environment  = "staging"
aws_region   = "eu-north-1"
project_name = "devops-assessment"

kubernetes_version = "1.30"

node_instance_type = "m7i-flex.large"
node_desired_count = 2 # more capacity than dev
node_min_count     = 2
node_max_count     = 3

# Different CIDR from dev so the two VPCs never overlap (and could be peered).
vpc_cidr           = "10.1.0.0/16"
availability_zones = ["eu-north-1a", "eu-north-1b"]

db_instance_class        = "db.t3.micro"
db_engine_version        = "16"
db_allocated_storage     = 20
db_multi_az              = false
db_backup_retention_days = 0 # Free Tier requires 0 (prod would use 7+)
