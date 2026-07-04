output "db_endpoint" {
  description = "Connection endpoint (host:port) of the RDS instance."
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "Hostname of the RDS instance (point DB_HOST / the private DNS CNAME here)."
  value       = aws_db_instance.this.address
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.this.db_name
}

output "db_security_group_id" {
  description = "Security group protecting the database."
  value       = aws_security_group.rds.id
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS master credentials."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
