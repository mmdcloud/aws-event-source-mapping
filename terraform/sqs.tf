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