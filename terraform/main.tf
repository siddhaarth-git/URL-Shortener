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