############################
# General
############################
variable "aws_region" {
  description = "Región AWS donde se despliega el stack."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para nombrar todos los recursos."
  type        = string
  default     = "sre-cache"
}

variable "environment" {
  description = "Nombre del entorno (se usa en tags)."
  type        = string
  default     = "dev"
}

############################
# Red
############################
variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs de las 2 subnets públicas (una por AZ)."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Se requieren exactamente 2 subnets públicas."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs de las 2 subnets privadas (una por AZ)."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Se requieren exactamente 2 subnets privadas."
  }
}

variable "single_nat_gateway" {
  description = "true = un solo NAT Gateway (barato, sin alta disponibilidad). false = un NAT por AZ."
  type        = bool
  default     = true
}

variable "lambda_allow_internet_egress" {
  description = "Si es true, el SG de Lambda permite HTTPS (443) hacia internet vía NAT. Por defecto false: solo Redis:6379 y S3 (prefix list)."
  type        = bool
  default     = false
}

############################
# Redis
############################
variable "redis_node_type" {
  description = "Tipo de nodo ElastiCache."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  description = "Versión del motor Redis."
  type        = string
  default     = "7.1"
}

variable "cache_ttl_seconds" {
  description = "TTL explícito de cada clave en Redis."
  type        = number
  default     = 60
}

############################
# Lambda
############################
variable "lambda_memory_mb" {
  description = "Memoria de la Lambda (MB)."
  type        = number
  default     = 256
}

variable "lambda_timeout_seconds" {
  description = "Timeout de la Lambda (s)."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Retención de logs de CloudWatch (Lambda y API Gateway)."
  type        = number
  default     = 14
}

############################
# API Gateway
############################
variable "api_stage_name" {
  description = "Nombre del stage del HTTP API."
  type        = string
  default     = "v1"
}

variable "api_throttling_rate_limit" {
  description = "Rate limit del stage (requests/segundo, promedio sostenido)."
  type        = number
  default     = 50
}

variable "api_throttling_burst_limit" {
  description = "Burst limit del stage (requests concurrentes permitidos en ráfaga)."
  type        = number
  default     = 100
}

variable "cors_allow_origins" {
  description = "Orígenes permitidos por CORS. El requerimiento pide cualquier origen."
  type        = list(string)
  default     = ["*"]
}

############################
# S3
############################
variable "s3_admin_principal_arns" {
  description = <<-EOT
    ARNs adicionales (ej. tu usuario/rol IAM) autorizados a operar sobre los OBJETOS del bucket
    (necesario para ejecutar `aws s3 ls` como evidencia). Vacío = solo el rol de Lambda.
    Para roles asumidos usa el ARN del ROL (arn:aws:iam::<cuenta>:role/<nombre>), no el de la sesión.
  EOT
  type        = list(string)
  default     = []
}

variable "s3_force_destroy" {
  description = "Permite que `terraform destroy` borre el bucket aunque tenga objetos/versiones (útil en entornos de práctica)."
  type        = bool
  default     = true
}
