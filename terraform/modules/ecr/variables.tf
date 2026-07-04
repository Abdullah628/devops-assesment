variable "name_prefix" {
  description = "Prefix for tags/names."
  type        = string
}

variable "repository_names" {
  description = "ECR repository names to create (one per image)."
  type        = list(string)
  default     = ["backend", "frontend"]
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
