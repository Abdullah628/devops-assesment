# ---- Required by the assessment: environment, region, cluster name, node
#      size, node count, and Kubernetes version ----

variable "environment" {
  description = "Deployment environment (dev | staging | prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name; used to prefix resource names."
  type        = string
  default     = "devops-assessment"
}

variable "cluster_name" {
  description = "EKS cluster name. Defaults to <project>-<environment> when empty."
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane and nodes."
  type        = string
  default     = "1.30"
}

variable "node_instance_type" {
  description = "EC2 instance type for the worker nodes (node size)."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_count" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

# ---- Network ----

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across (2+)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "eks_endpoint_public_access" {
  description = "Expose the EKS API endpoint publicly (kubectl from anywhere). Restrict/disable for prod."
  type        = bool
  default     = true
}

# ---- Database ----

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.3"
}

variable "db_instance_class" {
  description = "RDS instance class (DB size)."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage (GiB)."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Run an RDS standby in a second AZ (recommended for prod)."
  type        = bool
  default     = false
}

# ---- Observability ----

variable "log_retention_days" {
  description = "CloudWatch log retention (days)."
  type        = number
  default     = 30
}
