terraform {
  required_version = ">= 1.5"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "cloudvault"
}

variable "github_repo" {
  type        = string
  description = "HTTPS clone URL of your public GitHub repo, e.g. https://github.com/team/cloudvault.git"
}

variable "alert_email" {
  type        = string
  description = "Email that receives CloudWatch alarm notifications"
}

variable "retention_days" {
  type    = number
  default = 7
}

data "aws_caller_identity" "me" {}

locals {
  bucket_name = "${var.project}-files-${data.aws_caller_identity.me.account_id}"
  table_name  = "${var.project}-files"
}

# ---------- Storage: S3 (private + encrypted) ----------
resource "aws_s3_bucket" "files" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "files" {
  bucket                  = aws_s3_bucket.files.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "files" {
  bucket = aws_s3_bucket.files.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "files" {
  bucket = aws_s3_bucket.files.id
  versioning_configuration { status = "Enabled" }
}

# ---------- Database: DynamoDB ----------
resource "aws_dynamodb_table" "files" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "file_id"
  attribute {
    name = "file_id"
    type = "S"
  }
}

# ---------- Access control: IAM (least privilege) ----------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "app_access" {
  statement {
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.files.arn}/uploads/*"]
  }
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem", "dynamodb:Scan"]
    resources = [aws_dynamodb_table.files.arn]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.project}-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy" "app" {
  name   = "${var.project}-app-access"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_access.json
}

# Lets GitHub Actions redeploy through AWS Systems Manager (no SSH needed).
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-app-profile"
  role = aws_iam_role.app.name
}

# ---------- Monitoring: CloudWatch + SNS ----------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project}/app"
  retention_in_days = 14
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${var.project}-ec2-high-cpu"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { InstanceId = aws_instance.app.id }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "${var.project}-app-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "\"500 Internal Server Error\""
  metric_transformation {
    name      = "AppServerErrors"
    namespace = var.project
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "${var.project}-app-5xx"
  namespace           = var.project
  metric_name         = "AppServerErrors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ---------- Compute: EC2 running the Docker container ----------
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "web" {
  name        = "${var.project}-web"
  description = "HTTP in, all out"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  iam_instance_profile   = aws_iam_instance_profile.app.name
  vpc_security_group_ids = [aws_security_group.web.id]
  monitoring             = true

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y docker git
    systemctl enable --now docker
    git clone ${var.github_repo} /opt/app
    cd /opt/app
    docker build -f backend/Dockerfile -t cloudvault .
    docker run -d --restart always --name cloudvault -p 80:8000 \
      -e S3_BUCKET=${aws_s3_bucket.files.id} \
      -e DDB_TABLE=${aws_dynamodb_table.files.name} \
      -e AWS_REGION=${var.region} \
      --log-driver=awslogs \
      --log-opt awslogs-region=${var.region} \
      --log-opt awslogs-group=${aws_cloudwatch_log_group.app.name} \
      --log-opt awslogs-create-group=false \
      cloudvault
  EOF

  tags = { Name = "${var.project}-app" }
}

# ---------- Serverless: scheduled cleanup Lambda ----------
data "archive_file" "cleanup" {
  type        = "zip"
  source_file = "${path.module}/../lambda/cleanup.py"
  output_path = "${path.module}/cleanup.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_access" {
  statement {
    actions   = ["s3:DeleteObject"]
    resources = ["${aws_s3_bucket.files.arn}/uploads/*"]
  }
  statement {
    actions   = ["dynamodb:Scan", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.files.arn]
  }
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project}-cleanup-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project}-cleanup-access"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_access.json
}

resource "aws_lambda_function" "cleanup" {
  function_name    = "${var.project}-cleanup"
  role             = aws_iam_role.lambda.arn
  handler          = "cleanup.handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.cleanup.output_path
  source_code_hash = data.archive_file.cleanup.output_base64sha256
  environment {
    variables = {
      S3_BUCKET      = aws_s3_bucket.files.id
      DDB_TABLE      = aws_dynamodb_table.files.name
      RETENTION_DAYS = tostring(var.retention_days)
    }
  }
}

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${var.project}-daily-cleanup"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "cleanup" {
  rule = aws_cloudwatch_event_rule.daily.name
  arn  = aws_lambda_function.cleanup.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project}-cleanup-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = aws_lambda_function.cleanup.function_name }
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

output "app_url" {
  value = "http://${aws_instance.app.public_ip}"
}

output "bucket" {
  value = aws_s3_bucket.files.id
}

output "table" {
  value = aws_dynamodb_table.files.name
}
