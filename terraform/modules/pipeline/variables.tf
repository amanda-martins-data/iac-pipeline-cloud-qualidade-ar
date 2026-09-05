variable "project_name" {
  description = "Prefixo usado no nome de todos os recursos (ex.: air-quality-pipeline)."
  type        = string
}

variable "environment" {
  description = "Nome do ambiente (dev, staging, prod) — vira sufixo e tag em todos os recursos."
  type        = string
}

variable "aws_region" {
  description = "Região AWS onde os recursos serão provisionados."
  type        = string
  default     = "us-east-1"
}

variable "lambda_source_dir" {
  description = "Diretório com o código-fonte da Lambda (será zipado pelo Terraform)."
  type        = string
}

variable "lambda_timeout_seconds" {
  description = "Timeout da função Lambda."
  type        = number
  default     = 60
}

variable "lambda_memory_mb" {
  description = "Memória alocada para a Lambda."
  type        = number
  default     = 256
}

variable "psycopg2_layer_arn" {
  description = <<-EOT
    ARN de uma Lambda Layer pública contendo psycopg2-binary para a
    runtime Python escolhida (ex.: uma camada do projeto Klayers —
    https://github.com/keithrozario/Klayers). Não fixamos um ARN
    default de terceiros no código: ARNs de layer são específicos por
    região e mudam de versão; o valor correto deve ser resolvido no
    momento do deploy e passado explicitamente.
  EOT
  type        = string
}

variable "schedule_expression" {
  description = "Expressão do EventBridge para agendar a execução (rate ou cron)."
  type        = string
  default     = "rate(1 day)"
}

variable "openaq_use_synthetic" {
  description = "Se true, a Lambda usa dados sintéticos em vez de chamar a API real da OpenAQ."
  type        = bool
  default     = true
}

variable "openaq_api_key" {
  description = "API key da OpenAQ (opcional — só necessária se openaq_use_synthetic = false). Nunca é gravada em outputs."
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_instance_class" {
  description = "Classe da instância RDS."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage_gb" {
  description = "Armazenamento alocado para o RDS, em GB."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Nome do banco de dados Postgres criado no RDS."
  type        = string
  default     = "air_quality"
}

variable "log_retention_days" {
  description = "Retenção dos logs da Lambda no CloudWatch."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
