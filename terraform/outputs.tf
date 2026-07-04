# ---- Required by the assessment: cluster name, endpoint, registry name,
#      and network ID ----

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "registry_urls" {
  description = "ECR repository URLs (backend, frontend)."
  value       = module.ecr.repository_urls
}

output "vpc_id" {
  description = "Network ID (the VPC)."
  value       = module.network.vpc_id
}

# ---- Useful extras ----

output "cluster_certificate_authority" {
  description = "Cluster CA data (for building a kubeconfig)."
  value       = module.eks.cluster_certificate_authority
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN (for IRSA / service-account roles)."
  value       = module.eks.oidc_provider_arn
}

output "db_address" {
  description = "Private RDS hostname (point DB_HOST / the private DNS CNAME here)."
  value       = module.database.db_address
}

output "db_master_secret_arn" {
  description = "Secrets Manager ARN holding the RDS master credentials."
  value       = module.database.master_user_secret_arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
