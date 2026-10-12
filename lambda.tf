locals {
  lambda_name = "${local.name}-processor"
}

# Empaquetado reproducible: el handler solo usa libreria estandar
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/.build/lambda.zip"
  excludes    = ["__pycache__", "tests", "tests/*"]
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "processor" {
  function_name = local.lambda_name
  description   = "Cache-aside con Redis y persistencia en S3"
  role          = aws_iam_role.lambda.arn

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]

  memory_size = var.lambda_memory_mb
  timeout     = var.lambda_timeout_seconds

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      REDIS_HOST        = aws_elasticache_replication_group.redis.primary_endpoint_address
      REDIS_PORT        = "6379"
      REDIS_TLS         = "true"
      RESULTS_BUCKET    = aws_s3_bucket.results.id
      CACHE_TTL_SECONDS = tostring(var.cache_ttl_seconds)
      AWS_S3_REGION     = var.aws_region
      LOG_LEVEL         = "INFO"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy.lambda_s3,
    aws_vpc_security_group_egress_rule.lambda_to_redis,
    aws_vpc_security_group_egress_rule.lambda_to_s3,
  ]
}
