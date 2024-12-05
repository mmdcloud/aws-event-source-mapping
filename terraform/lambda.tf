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