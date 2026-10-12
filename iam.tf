data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Logs en CloudWatch + permisos de ENI necesarios para ejecutar dentro de una VPC.
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Mínimo privilegio sobre S3: solo el prefijo results/ del bucket. Se usa el nombre calculado
# (no aws_s3_bucket.results.arn) para que la política del rol no dependa del bucket.
data "aws_iam_policy_document" "lambda_s3" {
  statement {
    sid       = "ResultsObjects"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["arn:aws:s3:::${local.bucket_name}/results/*"]
  }

  statement {
    sid       = "ListResultsPrefix"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.bucket_name}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["results/*"]
    }
  }
}

resource "aws_iam_role_policy" "lambda_s3" {
  name   = "s3-results-access"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_s3.json
}
