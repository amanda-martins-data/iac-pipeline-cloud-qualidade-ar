locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ---------------------------------------------------------------------------
# Rede: usa a VPC default da conta/região para manter o projeto enxuto.
# Em um ambiente de produção real isso seria uma VPC dedicada com
# subnets privadas — ver docs/architecture.md, seção "Limitações".
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------------------------------------------------------------------------
# Storage: bucket S3 para as camadas Bronze e Silver do lake.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "data_lake" {
  bucket = "${local.name_prefix}-data-lake"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ---------------------------------------------------------------------------
# Secrets: API key da OpenAQ e credenciais do banco.
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "openaq_api_key" {
  name = "${local.name_prefix}-openaq-api-key"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "openaq_api_key" {
  secret_id     = aws_secretsmanager_secret.openaq_api_key.id
  secret_string = var.openaq_api_key != "" ? var.openaq_api_key : "placeholder-set-me"

  lifecycle {
    ignore_changes = [secret_string] # rotação/edição manual não deve ser sobrescrita pelo Terraform
  }
}

resource "random_password" "db_master" {
  length  = 24
  special = false # evita caracteres que exigem escaping na connection string
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${local.name_prefix}-db-credentials"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "pipeline_app"
    password = random_password.db_master.result
  })
}

# ---------------------------------------------------------------------------
# RDS Postgres: camada Gold, pronta para consumo por BI.
# ---------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  description = "Permite acesso Postgres apenas da Lambda do pipeline."
  vpc_id      = data.aws_vpc.default.id
  tags        = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "lambda" {
  name_prefix = "${local.name_prefix}-lambda-"
  description = "Security group da Lambda do pipeline (egress apenas)."
  vpc_id      = data.aws_vpc.default.id
  tags        = var.tags

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # precisa alcançar OpenAQ, Secrets Manager e S3
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "rds_from_lambda" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.lambda.id
}

# ---------------------------------------------------------------------------
# VPC Endpoints: a Lambda roda dentro da VPC (para alcançar o RDS de forma
# privada), mas isso significa que ela NÃO tem rota de saída para a
# internet por padrão. Em vez de pagar por um NAT Gateway (~US$32/mês)
# só para a Lambda falar com S3 e Secrets Manager, usamos VPC Endpoints:
# o de S3 é Gateway (gratuito); o de Secrets Manager é Interface (custo
# menor, cobrado por hora). A API pública da OpenAQ continua inalcançável
# sem NAT — por isso `openaq_use_synthetic = true` é o padrão (ver
# docs/architecture.md, seção "Rede e custos").
# ---------------------------------------------------------------------------

data "aws_route_tables" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.default.ids
  tags              = var.tags
}

resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.name_prefix}-vpce-"
  description = "Permite HTTPS da Lambda para os VPC endpoints de interface (Secrets Manager)."
  vpc_id      = data.aws_vpc.default.id
  tags        = var.tags

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = var.tags
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = data.aws_subnets.default.ids
  tags       = var.tags
}

resource "aws_db_instance" "gold" {
  identifier     = "${local.name_prefix}-gold"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  max_allocated_storage = var.db_allocated_storage_gb * 3 # autoscaling até 3x

  db_name  = var.db_name
  username = "pipeline_app"
  password = random_password.db_master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = 7
  skip_final_snapshot     = var.environment != "prod"
  deletion_protection     = var.environment == "prod"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# IAM: role e política de menor privilégio para a Lambda.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "S3DataLakeReadWrite"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/*"]
  }

  statement {
    sid       = "SecretsRead"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.openaq_api_key.arn, aws_secretsmanager_secret.db_credentials.arn]
  }

  statement {
    sid = "Logs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid = "VpcNetworkInterfaces"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"] # a API do EC2 para ENIs não suporta escopo por recurso
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${local.name_prefix}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ---------------------------------------------------------------------------
# Lambda: o pipeline em si.
# ---------------------------------------------------------------------------

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/.build/lambda_package.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-pipeline"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "pipeline" {
  function_name = "${local.name_prefix}-pipeline"
  role          = aws_iam_role.lambda.arn
  handler       = "lambda_handler.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout_seconds
  memory_size   = var.lambda_memory_mb

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  layers = [var.psycopg2_layer_arn]

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      BUCKET_NAME          = aws_s3_bucket.data_lake.bucket
      OPENAQ_SECRET_ARN     = aws_secretsmanager_secret.openaq_api_key.arn
      DB_SECRET_ARN         = aws_secretsmanager_secret.db_credentials.arn
      DB_HOST               = aws_db_instance.gold.address
      DB_NAME               = var.db_name
      OPENAQ_USE_SYNTHETIC  = tostring(var.openaq_use_synthetic)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
  tags       = var.tags
}

# ---------------------------------------------------------------------------
# Agendamento: EventBridge dispara a Lambda periodicamente.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${local.name_prefix}-schedule"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = aws_lambda_function.pipeline.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pipeline.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
