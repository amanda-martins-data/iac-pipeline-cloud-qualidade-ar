terraform {
  required_version = ">= 1.6"

  # Backend local por padrão — deliberadamente simples para um projeto
  # de portfólio rodado por uma pessoa só. Em um time real, isso seria
  # um backend remoto (S3 + DynamoDB para lock), configurado à parte
  # via `terraform init -backend-config=...` para não hardcodar nomes
  # de bucket de state no código versionado.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

module "pipeline" {
  source = "../../modules/pipeline"

  project_name = "air-quality-pipeline"
  environment  = "dev"
  aws_region   = var.aws_region

  lambda_source_dir  = "${path.module}/../../../src"
  psycopg2_layer_arn = var.psycopg2_layer_arn

  openaq_use_synthetic = var.openaq_use_synthetic
  openaq_api_key       = var.openaq_api_key

  db_instance_class       = var.db_instance_class
  db_allocated_storage_gb = var.db_allocated_storage_gb

  schedule_expression = var.schedule_expression

  tags = {
    Project     = "air-quality-pipeline"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
