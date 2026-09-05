output "bucket_name" {
  description = "Nome do bucket S3 do data lake."
  value       = aws_s3_bucket.data_lake.bucket
}

output "lambda_function_name" {
  description = "Nome da função Lambda do pipeline."
  value       = aws_lambda_function.pipeline.function_name
}

output "lambda_function_arn" {
  description = "ARN da função Lambda do pipeline."
  value       = aws_lambda_function.pipeline.arn
}

output "rds_endpoint" {
  description = "Endpoint do RDS (host:port) — usar para configurar a conexão do Power BI/BI tool."
  value       = aws_db_instance.gold.endpoint
}

output "rds_database_name" {
  description = "Nome do banco de dados Postgres."
  value       = aws_db_instance.gold.db_name
}

output "db_credentials_secret_arn" {
  description = "ARN do secret com as credenciais do banco (username/password em JSON)."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "openaq_secret_arn" {
  description = "ARN do secret da API key da OpenAQ — popular manualmente após o apply, se for usar dados reais."
  value       = aws_secretsmanager_secret.openaq_api_key.arn
}
