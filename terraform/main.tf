terraform{
    required_providers{
        aws = {
            source = "hashicorp/aws"
            version = "~>5.0"
        }
    }
    required_version = ">=1.3.0"

    backend "s3" {
    bucket = "url-shortener-tfstate-sid"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws"{
    region=var.aws_region
}

resource "aws_dynamodb_table" "url_table"{
    name = "url-shortner"
    billing_mode = "PAY_PER_REQUEST"
    hash_key = "short_code"

    attribute{
        name = "short_code"
        type = "S"
    }
    tags = {
        Project = "url-shortener"
    }
}

# Lambda function 1: Create short URL
resource "aws_lambda_function" "create_url" {
  filename         = "../lambda/create_url.zip"
  function_name    = "create-url"
  role             = aws_iam_role.lambda_role.arn
  handler          = "create_url.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("../lambda/create_url.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Project = "url-shortener"
  }
}

# Lambda function 2: Redirect to long URL
resource "aws_lambda_function" "redirect_url" {
  filename         = "../lambda/redirect_url.zip"
  function_name    = "redirect-url"
  role             = aws_iam_role.lambda_role.arn
  handler          = "redirect_url.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("../lambda/redirect_url.zip")

  tracing_config {
    mode = "Active"
  }

  tags = {
    Project = "url-shortener"
  }
}

# Create the API
resource "aws_apigatewayv2_api" "url_shortener_api" {
  name          = "url-shortener-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["Content-Type"]
  }
}

# Stage (think of this as the "environment" — like prod/dev)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.url_shortener_api.id
  name        = "$default"
  auto_deploy = true
}

# Integration 1: connect API Gateway to create-url Lambda
resource "aws_apigatewayv2_integration" "create_url" {
  api_id             = aws_apigatewayv2_api.url_shortener_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.create_url.invoke_arn
  integration_method = "POST"
}

# Integration 2: connect API Gateway to redirect-url Lambda
resource "aws_apigatewayv2_integration" "redirect_url" {
  api_id             = aws_apigatewayv2_api.url_shortener_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.redirect_url.invoke_arn
  integration_method = "POST"
}

# Route 1: POST /create → create-url Lambda
resource "aws_apigatewayv2_route" "create_url" {
  api_id    = aws_apigatewayv2_api.url_shortener_api.id
  route_key = "POST /create"
  target    = "integrations/${aws_apigatewayv2_integration.create_url.id}"
}

# Route 2: GET /{short_code} → redirect-url Lambda
resource "aws_apigatewayv2_route" "redirect_url" {
  api_id    = aws_apigatewayv2_api.url_shortener_api.id
  route_key = "GET /{short_code}"
  target    = "integrations/${aws_apigatewayv2_integration.redirect_url.id}"
}

# Permission: allow API Gateway to invoke create-url Lambda
resource "aws_lambda_permission" "create_url" {
  statement_id  = "AllowAPIGatewayInvokeCreate"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.url_shortener_api.execution_arn}/*/*"
}

# Permission: allow API Gateway to invoke redirect-url Lambda
resource "aws_lambda_permission" "redirect_url" {
  statement_id  = "AllowAPIGatewayInvokeRedirect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redirect_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.url_shortener_api.execution_arn}/*/*"
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "url_shortener" {
  dashboard_name = "url-shortener"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = "us-east-1"
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "create-url"],
            ["AWS/Lambda", "Invocations", "FunctionName", "redirect-url"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = "us-east-1"
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", "create-url"],
            ["AWS/Lambda", "Errors", "FunctionName", "redirect-url"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Duration (ms)"
          region = "us-east-1"
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "create-url"],
            ["AWS/Lambda", "Duration", "FunctionName", "redirect-url"]
          ]
        }
      }
    ]
  })
}

# CloudWatch Alarm: alert when errors spike
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "url-shortener-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 2
  alarm_description   = "Triggers when Lambda errors exceed 2 in 1 minute"

  dimensions = {
    FunctionName = "create-url"
  }
}

# S3 bucket to host the frontend
resource "aws_s3_bucket" "frontend" {
  bucket = "url-shortener-frontend-sid"

  tags = {
    Project = "url-shortener"
  }
}

# Allow public read access
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Bucket policy: allow anyone to read
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

# Enable static website hosting
resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }
}

# Upload index.html to S3
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "../frontend/index.html"
  content_type = "text/html"
  etag         = filemd5("../frontend/index.html")
}