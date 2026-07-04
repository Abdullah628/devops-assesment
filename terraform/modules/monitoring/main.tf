# Monitoring module — CloudWatch log storage for the platform.
#
# EKS control-plane logging is enabled in the eks module
# (enabled_cluster_log_types); EKS writes those logs to this well-known log
# group name. We declare it here so retention is managed (and costs bounded)
# rather than left to an auto-created, never-expiring group.

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# Log group for application/container logs (e.g. shipped by Fluent Bit /
# Container Insights running as a DaemonSet on the nodes).
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${var.cluster_name}/application"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
