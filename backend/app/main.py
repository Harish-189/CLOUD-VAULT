"""CloudVault API: secure file sharing with expiring links on AWS (S3 + DynamoDB)."""
import os
import time
import uuid
from pathlib import Path

import boto3
from botocore.config import Config
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

BUCKET = os.getenv("S3_BUCKET", "cloudvault-files")
TABLE = os.getenv("DDB_TABLE", "cloudvault-files")
REGION = os.getenv("AWS_REGION", "ap-south-1")
MAX_BYTES = int(os.getenv("MAX_UPLOAD_BYTES", str(10 * 1024 * 1024)))
DEFAULT_TTL = int(os.getenv("DEFAULT_LINK_TTL", "900"))  # seconds
MAX_TTL = 7 * 24 * 3600

app = FastAPI(title="CloudVault", version="1.0.0")


def s3():
    return boto3.client("s3", region_name=REGION, config=Config(signature_version="s3v4"))


def table():
    return boto3.resource("dynamodb", region_name=REGION).Table(TABLE)


@app.get("/health")
def health():
    return {"status": "ok", "bucket": BUCKET, "table": TABLE, "region": REGION}


@app.post("/api/files")
async def upload(file: UploadFile = File(...)):
    data = await file.read()
    if not data:
        raise HTTPException(400, "Empty file")
    if len(data) > MAX_BYTES:
        raise HTTPException(413, f"File exceeds {MAX_BYTES} bytes")
    file_id = uuid.uuid4().hex
    safe_name = Path(file.filename or "file").name
    key = f"uploads/{file_id}/{safe_name}"
    s3().put_object(
        Bucket=BUCKET, Key=key, Body=data,
        ContentType=file.content_type or "application/octet-stream",
        ServerSideEncryption="AES256",
    )
    item = {
        "file_id": file_id, "name": safe_name, "key": key,
        "size": len(data), "uploaded_at": int(time.time()),
        "content_type": file.content_type or "application/octet-stream",
    }
    table().put_item(Item=item)
    return item


@app.get("/api/files")
def list_files():
    items = table().scan().get("Items", [])
    items.sort(key=lambda i: int(i["uploaded_at"]), reverse=True)
    return [{**i, "size": int(i["size"]), "uploaded_at": int(i["uploaded_at"])} for i in items]


@app.post("/api/files/{file_id}/link")
def create_link(file_id: str, ttl: int = DEFAULT_TTL):
    if not 60 <= ttl <= MAX_TTL:
        raise HTTPException(400, "ttl must be between 60 seconds and 7 days")
    item = table().get_item(Key={"file_id": file_id}).get("Item")
    if not item:
        raise HTTPException(404, "File not found")
    url = s3().generate_presigned_url(
        "get_object", Params={"Bucket": BUCKET, "Key": item["key"]}, ExpiresIn=ttl
    )
    return {"url": url, "expires_in": ttl}


@app.delete("/api/files/{file_id}")
def delete_file(file_id: str):
    item = table().get_item(Key={"file_id": file_id}).get("Item")
    if not item:
        raise HTTPException(404, "File not found")
    s3().delete_object(Bucket=BUCKET, Key=item["key"])
    table().delete_item(Key={"file_id": file_id})
    return JSONResponse({"deleted": file_id})


_frontend = Path(__file__).resolve().parents[2] / "frontend"
if not _frontend.exists():
    _frontend = Path("/app/frontend")
if _frontend.exists():
    app.mount("/", StaticFiles(directory=str(_frontend), html=True), name="ui")
