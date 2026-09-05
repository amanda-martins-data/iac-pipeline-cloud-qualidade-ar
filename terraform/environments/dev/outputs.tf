output "bucket_name" {
  value = module.pipeline.bucket_name
}

output "lambda_function_name" {
  value = module.pipeline.lambda_function_name
}

output "rds_endpoint" {
  value = module.pipeline.rds_endpoint
}

output "db_credentials_secret_arn" {
  value = module.pipeline.db_credentials_secret_arn
}

output "openaq_secret_arn" {
  value = module.pipeline.openaq_secret_arn
}
