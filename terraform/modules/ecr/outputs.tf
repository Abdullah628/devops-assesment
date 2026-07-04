output "repository_urls" {
  description = "Map of repository name -> repository URL."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository name -> ARN."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "registry_id" {
  description = "The AWS account/registry ID hosting the repositories."
  value       = values(aws_ecr_repository.this)[0].registry_id
}
