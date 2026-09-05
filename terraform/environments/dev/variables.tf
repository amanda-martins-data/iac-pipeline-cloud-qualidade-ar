variable "aws_region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "psycopg2_layer_arn" {
  description = "ARN da Lambda Layer com psycopg2-binary (ver README para como obter)."
  type        = string
}

variable "openaq_use_synthetic" {
  description = "Se true, roda com dados sintéticos (recomendado até configurar a API key real)."
  type        = bool
  default     = true
}

variable "openaq_api_key" {
  description = "API key da OpenAQ (opcional)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 20
}

variable "schedule_expression" {
  type    = string
  default = "rate(1 day)"
}
