variable "cluster_name" {
  description = "EKS cluster name (used to build the log group paths)."
  type        = string
}

variable "log_retention_days" {
  description = "How long to retain CloudWatch logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
