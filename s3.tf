locals {
  bucket_name = "${local.name}-results-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

resource "aws_s3_bucket" "results" {
  bucket        = local.bucket_name
  force_destroy = var.s3_force_destroy

  tags = { Name = local.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket = aws_s3_bucket.results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Con versionado, las versiones antiguas se acumulan: se expiran a los 30 dias.
resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.results]
}

# Bucket policy: solo el rol de Lambda (más, opcionalmente, administradores explícitos) opera sobre objetos.
# - El rol de Lambda solo puede entrar a través del VPC Endpoint.
# - Se exige TLS.
# Las acciones de configuración del bucket (Terraform) no se tocan, así no te bloqueas a ti mismo.
data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "AllowLambdaRole"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.results.arn}/results/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda.arn]
    }
  }

  statement {
    sid       = "AllowLambdaRoleList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.results.arn]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda.arn]
    }
  }

  statement {
    sid       = "DenyObjectAccessExceptLambdaAndAdmins"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.results.arn, "${aws_s3_bucket.results.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = concat([aws_iam_role.lambda.arn], var.s3_admin_principal_arns)
    }
  }

  statement {
    sid       = "DenyLambdaOutsideVpcEndpoint"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.results.arn, "${aws_s3_bucket.results.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda.arn]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.s3.id]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.results.arn, "${aws_s3_bucket.results.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "results" {
  bucket = aws_s3_bucket.results.id
  policy = data.aws_iam_policy_document.bucket.json

  # Evita "OperationAborted: conflicting conditional operation" al aplicar en paralelo.
  depends_on = [aws_s3_bucket_public_access_block.results]
}
