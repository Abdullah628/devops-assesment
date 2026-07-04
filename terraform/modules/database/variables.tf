variable "name_prefix" {
  description = "Prefix for names/tags."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database lives in."
  type        = string
}

variable "db_subnet_ids" {
  description = "Private DB subnet IDs (2+ AZs)."
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group allowed to reach the DB on 5432 (the EKS node/cluster SG)."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.3"
}

variable "instance_class" {
  description = "RDS instance class (size)."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial storage (GiB)."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Autoscaling storage ceiling (GiB)."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username (the password is managed by RDS in Secrets Manager)."
  type        = string
  default     = "appuser"
}

variable "multi_az" {
  description = "Run a standby in a second AZ (recommended for prod)."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup retention in days."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Block accidental deletion (enable in prod)."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (true for disposable dev DBs)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
