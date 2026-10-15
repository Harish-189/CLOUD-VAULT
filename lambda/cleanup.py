"""Scheduled Lambda: delete files older than RETENTION_DAYS from S3 and DynamoDB."""
import os
import time

import boto3

BUCKET = os.environ["S3_BUCKET"]
TABLE = os.environ["DDB_TABLE"]
RETENTION_DAYS = int(os.getenv("RETENTION_DAYS", "7"))


def handler(event, context):
    cutoff = int(time.time()) - RETENTION_DAYS * 86400
    s3 = boto3.client("s3")
    table = boto3.resource("dynamodb").Table(TABLE)
    deleted = 0
    scan = table.scan()
    items = scan["Items"]
    while "LastEvaluatedKey" in scan:
        scan = table.scan(ExclusiveStartKey=scan["LastEvaluatedKey"])
        items += scan["Items"]
    for item in items:
        if int(item["uploaded_at"]) < cutoff:
            s3.delete_object(Bucket=BUCKET, Key=item["key"])
            table.delete_item(Key={"file_id": item["file_id"]})
            deleted += 1
    print(f"cleanup deleted={deleted} cutoff={cutoff}")
    return {"deleted": deleted}
