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