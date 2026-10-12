# Los SG se crean vacios y las reglas son recursos aparte: evita dependencias

resource "aws_security_group" "lambda" {
  name_prefix = "${local.name}-lambda-"
  description = "SG de la Lambda: solo sale hacia Redis (6379) y S3 (443 via prefix list)"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-lambda-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "redis" {
  name_prefix = "${local.name}-redis-"
  description = "SG de Redis: solo acepta 6379 desde el SG de Lambda"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name}-redis-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda -> Redis :6379 - unico destino de red interno
resource "aws_vpc_security_group_egress_rule" "lambda_to_redis" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "Lambda hacia Redis"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.redis.id
}

# Lambda -> S3 via Gateway Endpoint
resource "aws_vpc_security_group_egress_rule" "lambda_to_s3" {
  security_group_id = aws_security_group.lambda.id
  description       = "Lambda hacia S3 por el VPC Endpoint"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}

# Opcional: HTTPS saliente a internet via NAT
resource "aws_vpc_security_group_egress_rule" "lambda_to_internet" {
  count = var.lambda_allow_internet_egress ? 1 : 0

  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS saliente a internet via NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# Redis <- Lambda :6379 (unico ingress permitido)
resource "aws_vpc_security_group_ingress_rule" "redis_from_lambda" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis acepta solo desde el SG de Lambda"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.lambda.id
}
