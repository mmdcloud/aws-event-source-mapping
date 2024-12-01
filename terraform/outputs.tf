output "api-gateway-endpoint" {
  value = aws_api_gateway_stage.event-source-mapping-api-stage.invoke_url
}