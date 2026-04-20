output "dynamodb_table_name" {
  value = aws_dynamodb_table.url_table.name
}

output "api_gateway_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}