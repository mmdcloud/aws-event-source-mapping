data "aws_caller_identity" "current" {}

resource "aws_iam_role" "api_gateway_execution_role" {
  name = "api_gateway_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_gateway_sqs_full_access" {
  role       = aws_iam_role.api_gateway_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_api_gateway_rest_api" "event-source-mapping-api" {
  name = "event-source-mapping-api"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.event-source-mapping-api.id
  parent_id   = aws_api_gateway_rest_api.event-source-mapping-api.root_resource_id
  path_part   = "api"  
}

resource "aws_api_gateway_method" "event-source-mapping-api-method" {
  rest_api_id   = aws_api_gateway_rest_api.event-source-mapping-api.id
  resource_id   = aws_api_gateway_resource.api.id
  api_key_required = false  
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "event-source-mapping-api-integration" {
  rest_api_id             = aws_api_gateway_rest_api.event-source-mapping-api.id
  resource_id             = aws_api_gateway_resource.api.id
  http_method             = aws_api_gateway_method.event-source-mapping-api-method.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.api_gateway_execution_role.arn
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.event-source-mapping-queue.name}"
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$input.body"        
  }
}

resource "aws_api_gateway_method_response" "method_response_200" {
  rest_api_id = aws_api_gateway_rest_api.event-source-mapping-api.id
  resource_id = aws_api_gateway_resource.api.id
  http_method = aws_api_gateway_method.event-source-mapping-api-method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "integration_response_200" {
  rest_api_id = aws_api_gateway_rest_api.event-source-mapping-api.id
  resource_id = aws_api_gateway_resource.api.id
  http_method = aws_api_gateway_method.event-source-mapping-api-method.http_method
  status_code = aws_api_gateway_method_response.method_response_200.status_code  
  depends_on = [
    aws_api_gateway_integration.event-source-mapping-api-integration
  ]
}

resource "aws_api_gateway_deployment" "event-source-mapping-api-deployment" {
  rest_api_id = aws_api_gateway_rest_api.event-source-mapping-api.id  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.api.id,
      aws_api_gateway_method.event-source-mapping-api-method.id,
      aws_api_gateway_integration.event-source-mapping-api-integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "event-source-mapping-api-stage" {
  deployment_id = aws_api_gateway_deployment.event-source-mapping-api-deployment.id
  rest_api_id   = aws_api_gateway_rest_api.event-source-mapping-api.id
  stage_name    = "dev"
}