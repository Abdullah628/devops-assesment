output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64 CA data for the cluster (for kubeconfig)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "The cluster security group EKS manages for control-plane<->node traffic."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  description = "IAM role ARN of the worker nodes."
  value       = aws_iam_role.node.arn
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (for IRSA)."
  value       = aws_iam_openid_connect_provider.oidc.arn
}
