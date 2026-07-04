variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane and nodes."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs where worker nodes run."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (for internet-facing load balancers)."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is reachable publicly (kept for kubectl access; restrict via CIDRs in prod)."
  type        = bool
  default     = true
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes (node size)."
  type        = string
}

variable "node_desired_count" {
  description = "Desired number of worker nodes."
  type        = number
}

variable "node_min_count" {
  description = "Minimum number of worker nodes."
  type        = number
}

variable "node_max_count" {
  description = "Maximum number of worker nodes."
  type        = number
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
