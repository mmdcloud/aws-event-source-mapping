import boto3
import json

def lambda_handler(event,context):
    client = boto3.resource('dynamodb')

    body = json.loads(event["Records"][0]["body"])

    table = client.Table("event-source-mapping-records")

    table.put_item(Item= {'id': body["id"],'name':  body["name"]})