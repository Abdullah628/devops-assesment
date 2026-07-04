output "eks_log_group_name" {
  description = "CloudWatch log group for EKS control-plane logs."
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

output "application_log_group_name" {
  description = "CloudWatch log group for application/container logs."
  value       = aws_cloudwatch_log_group.application.name
}
