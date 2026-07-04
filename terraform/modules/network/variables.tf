variable "name_prefix" {
  description = "Prefix for all resource names (e.g. devops-assessment-dev)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Subnets are derived from this."
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across (2+ recommended)."
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name — used for the kubernetes.io/cluster subnet tags."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default     = {}
}
