resource "aws_elasticache_subnet_group" "redis" {
  name        = "${local.name}-redis-subnets"
  description = "Subnets privadas para Redis"
  subnet_ids  = aws_subnet.private[*].id
}

# Replication group de 1 nodo (sin replicas) para poder activar cifrado en tránsito y en reposo.
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${local.name}-redis"
  description          = "Cache Redis para ${local.name}"

  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  port                 = 6379
  parameter_group_name = "default.redis7"

  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  snapshot_retention_limit = 0
  apply_immediately        = true

  tags = { Name = "${local.name}-redis" }
}
