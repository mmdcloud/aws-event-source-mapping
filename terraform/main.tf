data "aws_caller_identity" "current" {}

# Lambda Function Code Bucket
module "lambda_function_code_bucket" {
  source      = "./modules/s3"
  bucket_name = "event-source-mapping-function-code-bucket-${data.aws_caller_identity.current.account_id}"
  objects = [
    {
      key    = "lambda.zip"
      source = "./files/lambda.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "POST", "GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  force_destroy = true
}

# DynamoDB Table
module "dynamodb" {
  source = "./modules/dynamodb"
  name   = "event-source-mapping-records"
  attributes = [
    {
      name = "id"
      type = "S"
    },
    {
      name = "name"
      type = "S"
    }
  ]
  billing_mode          = "PROVISIONED"
  hash_key              = "id"
  range_key             = "name"
  read_capacity         = 20
  write_capacity        = 20
  ttl_attribute_name    = "TimeToExist"
  ttl_attribute_enabled = true
}

# SQS
module "sqs" {
  source                        = "./modules/sqs"
  queue_name                    = "event-source-mapping-queue"
  delay_seconds                 = 0
  maxReceiveCount               = 3
  dlq_message_retention_seconds = 86400
  dlq_name                      = "event-source-mapping-dlq"
  max_message_size              = 262144
  message_retention_seconds     = 345600
  visibility_timeout_seconds    = 30
  receive_wait_time_seconds     = 0
  policy                        = ""
}

# Lambda function IAM Role
module "lambda_function_iam_role" {
  source             = "./modules/iam"
  role_name          = "_event_source_mapping_lambda_function_iam_role"
  role_description   = "_event_source_mapping_lambda_function_iam_role"
  policy_name        = "_event_source_mapping_lambda_function_iam_policy"
  policy_description = "_event_source_mapping_lambda_function_iam_policy"
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
  policy             = <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
            "Action": [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
              "mediaconvert:*"
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
          "Resource": "${module.sqs.arn}"
        },
        {
          "Effect": "Allow",
          "Action": [
            "dynamodb:PutItem",
            "dynamodb:DescribeTable"
          ],
          "Resource": "${module.dynamodb.arn}"
        }
      ]
    }
    EOF
}

# Lambda function to process media files
module "lambda_function" {
  source        = "./modules/lambda"
  function_name = "event-source-mapping-function"
  role_arn      = module.lambda_function_iam_role.arn
  env_variables = {}
  handler       = "lambda.lambda_handler"
  runtime       = "python3.12"
  s3_bucket     = module.lambda_function_code_bucket.bucket
  s3_key        = "lambda.zip"
  depends_on    = [module.lambda_function_iam_role, module.lambda_function_code_bucket]
}

resource "aws_lambda_event_source_mapping" "sqs_event_trigger" {
  event_source_arn = module.sqs.arn
  function_name    = module.lambda_function.arn
  enabled          = true
  batch_size       = 10
}

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
  uri                     = "arn:aws:apigateway:${var.region}:sqs:path/${data.aws_caller_identity.current.account_id}/${module.sqs.name}"
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
