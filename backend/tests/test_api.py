import os
import sys
from pathlib import Path

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ.update(
    AWS_ACCESS_KEY_ID="test", AWS_SECRET_ACCESS_KEY="test",
    AWS_REGION="ap-south-1", S3_BUCKET="t-bucket", DDB_TABLE="t-table",
)


@pytest.fixture()
def client():
    with mock_aws():
        region = "ap-south-1"
        boto3.client("s3", region_name=region).create_bucket(
            Bucket="t-bucket", CreateBucketConfiguration={"LocationConstraint": region}
        )
        boto3.resource("dynamodb", region_name=region).create_table(
            TableName="t-table",
            KeySchema=[{"AttributeName": "file_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "file_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        from app.main import app
        yield TestClient(app)


def test_health(client):
    assert client.get("/health").json()["status"] == "ok"


def test_upload_list_link_delete(client):
    r = client.post("/api/files", files={"file": ("a.txt", b"hello", "text/plain")})
    assert r.status_code == 200
    fid = r.json()["file_id"]
    assert len(client.get("/api/files").json()) == 1
    link = client.post(f"/api/files/{fid}/link?ttl=120").json()
    assert "X-Amz-Signature" in link["url"] and link["expires_in"] == 120
    assert client.delete(f"/api/files/{fid}").status_code == 200
    assert client.get("/api/files").json() == []


def test_rejects_bad_ttl_and_missing(client):
    assert client.post("/api/files/nope/link").status_code == 404
    r = client.post("/api/files", files={"file": ("a.txt", b"x", "text/plain")})
    fid = r.json()["file_id"]
    assert client.post(f"/api/files/{fid}/link?ttl=5").status_code == 400
