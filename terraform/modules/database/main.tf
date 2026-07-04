# Database module — a PRIVATE RDS PostgreSQL instance.
#
# Privacy is enforced three ways (see docs/database-connectivity.md):
#   1. publicly_accessible = false  (no public IP)
#   2. lives in the private DB subnets (no internet route)
#   3. security group admits 5432 ONLY from the EKS node/cluster security group
#
# The master password is NEVER in Terraform: `manage_master_user_password`
# makes RDS create and rotate it in AWS Secrets Manager.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.db_subnet_ids
  tags       = merge(var.tags, { Name = "${var.name_prefix}-db-subnets" })
}

# Firewall: only traffic from the allowed (EKS node) security group on 5432.
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "Allow PostgreSQL from the EKS nodes only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name_prefix}-rds-sg" })
}

resource "aws_security_group_rule" "rds_ingress_from_nodes" {
  type                     = "ingress"
  description              = "PostgreSQL from EKS nodes"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = var.allowed_security_group_id # a SG, not a CIDR
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true
  storage_type          = "gp3"

  db_name  = var.db_name
  username = var.master_username
  # No password here — RDS manages it in Secrets Manager and can auto-rotate it.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # the core privacy switch
  multi_az               = var.multi_az

  backup_retention_period = var.backup_retention_days
  deletion_protection     = var.deletion_protection
  # For a disposable dev/assessment DB, allow a clean `terraform destroy`.
  skip_final_snapshot = var.skip_final_snapshot

  tags = merge(var.tags, { Name = "${var.name_prefix}-db" })
}
