resource "aws_sqs_queue" "event-source-mapping-queue" {
  name                       = "event-source-mapping-queue"
  delay_seconds              = 0
  max_message_size           = 262144
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600
  receive_wait_time_seconds  = 0
  tags = {
    Name = "event-source-mapping-queue"
  }
}

# DynamoDB Table For storing media records
resource "aws_dynamodb_table" "event-source-mapping-records" {
  name           = "event-source-mapping-records"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "id"
  range_key      = "name"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "name"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }

  tags = {
    Name = "event-source-mapping"
  }
}

# Lambda Function Role
resource "aws_iam_role" "event-source-mapping-function-role" {
  name               = "event-source-mapping-function-role"
  assume_role_policy = <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
    }
    EOF
  tags = {
    Name = "event-source-mapping"
  }
}

# Lambda Function Policy
resource "aws_iam_policy" "event-source-mapping-function-policy" {
  name        = "event-source-mapping-function-policy"
  description = "AWS IAM Policy for managing aws lambda role"
  policy      = <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
      {
          "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          "Resource": "arn:aws:logs:*:*:*",
          "Effect": "Allow"
      },
      {
        "Effect": "Allow",
        "Action": [
            "sqs:ReceiveMessage",
            "sqs:GetQueueAttributes",
            "sqs:DeleteMessage"
        ],
        "Resource": "${aws_sqs_queue.event-source-mapping-queue.arn}"
      },
      {
        "Effect": "Allow",
        "Action": [
            "dynamodb:PutItem",
            "dynamodb:DescribeTable"
        ],
        "Resource": "${aws_dynamodb_table.event-source-mapping-records.arn}"
       }          
      ]
    }
    EOF
  tags = {
    Name = "event-source-mapping"
  }
}

# Lambda Function Role-Policy Attachment
resource "aws_iam_role_policy_attachment" "event-source-mapping-function-policy-attachment" {
  role       = aws_iam_role.event-source-mapping-function-role.name
  policy_arn = aws_iam_policy.event-source-mapping-function-policy.arn
}

resource "aws_lambda_function" "event-source-mapping-function" {
  filename      = "./files/lambda.zip"
  function_name = "event-source-mapping-function"
  role          = aws_iam_role.event-source-mapping-function-role.arn
  handler       = "lambda.lambda_handler"
  runtime       = "python3.12"
  depends_on    = [aws_iam_role_policy_attachment.event-source-mapping-function-policy-attachment]
  tags = {
    Name = "event-source-mapping"
  }
}

resource "aws_lambda_event_source_mapping" "sqs_event_trigger" {
  event_source_arn = aws_sqs_queue.event-source-mapping-queue.arn
  function_name    = aws_lambda_function.event-source-mapping-function.arn
  enabled          = true
  batch_size       = 10
}

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
  rest_api_id      = aws_api_gateway_rest_api.event-source-mapping-api.id
  resource_id      = aws_api_gateway_resource.api.id
  api_key_required = false
  http_method      = "POST"
  authorization    = "NONE"
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