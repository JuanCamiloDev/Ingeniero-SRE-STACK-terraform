output "api_url" {
  description = "URL completa del endpoint POST /process."
  value       = "${aws_apigatewayv2_stage.main.invoke_url}/process"
}

output "results_bucket" {
  description = "Bucket S3 donde se persisten los resultados (prefijo results/)."
  value       = aws_s3_bucket.results.id
}

output "redis_endpoint" {
  description = "Endpoint primario de Redis (solo accesible desde el SG de Lambda)."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "lambda_function_name" {
  value = aws_lambda_function.processor.function_name
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}

output "api_access_log_group" {
  value = aws_cloudwatch_log_group.api_access.name
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "s3_vpc_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}
