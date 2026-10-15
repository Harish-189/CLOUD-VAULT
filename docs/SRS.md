---
title: "Software Requirements Specification: CloudVault"
subtitle: "Secure File Sharing with Expiring Links on AWS"
date: "October 2026"
---

# 1. Introduction

## 1.1 Purpose
This document specifies the requirements for **CloudVault**, a cloud-hosted web application that lets users upload files and share them through time-limited links. It is prepared for the Cloud Computing Hackathon and follows the structure of IEEE 830.

## 1.2 Scope
CloudVault provides upload, listing, expiring-link sharing and deletion of files. Files are stored in Amazon S3, metadata in Amazon DynamoDB, and the application runs in a Docker container on Amazon EC2. Infrastructure is defined with Terraform, deployed through GitHub Actions, and monitored with Amazon CloudWatch.

## 1.3 Definitions
| Term | Meaning |
|---|---|
| Presigned URL | A temporary S3 URL signed with AWS credentials that grants access to one object until it expires |
| IAM | AWS Identity and Access Management |
| IaC | Infrastructure as Code (Terraform) |
| TTL | Time-to-live of a share link |

## 1.4 References
AWS documentation (S3, DynamoDB, Lambda, IAM, CloudWatch); FastAPI documentation; Terraform AWS provider documentation.

# 2. Overall Description

## 2.1 Product Perspective
A standalone web application with a browser UI, a REST API, and AWS managed services as its back end.

## 2.2 User Classes
- **Uploader**: uploads files, generates and shares links, deletes files.
- **Recipient**: opens a shared link; needs no account.
- **Administrator**: operates the AWS infrastructure and monitors alarms.

## 2.3 Operating Environment
Browser (any modern one); server on Amazon Linux 2023 (EC2, Docker, Python 3.12); AWS region ap-south-1.

## 2.4 Constraints and Assumptions
- Maximum upload size is 10 MB (configurable).
- Link lifetime ranges from 60 seconds to 7 days.
- The prototype has no user authentication; this is listed as future work.

# 3. System Features and Functional Requirements

| ID | Requirement |
|---|---|
| FR-1 | The system shall let a user upload a file through the browser or the API. |
| FR-2 | The system shall store each uploaded file in S3 with server-side encryption and record its metadata (id, name, size, type, upload time) in DynamoDB. |
| FR-3 | The system shall list all stored files, newest first. |
| FR-4 | The system shall generate a presigned download link for a file with a user-selected lifetime between 60 seconds and 7 days. |
| FR-5 | The system shall reject link requests outside the allowed lifetime and requests for unknown files. |
| FR-6 | The system shall let a user delete a file, removing it from S3 and DynamoDB. |
| FR-7 | The system shall reject empty files and files above the size limit. |
| FR-8 | The system shall automatically delete files older than the retention period (default 7 days) using a scheduled AWS Lambda function. |
| FR-9 | The system shall expose a `/health` endpoint reporting service status. |

# 4. Cloud Architecture

| Layer | AWS service | Role |
|---|---|---|
| Compute | EC2 (t3.micro) + Docker | Runs the FastAPI application and serves the UI |
| Object storage | S3 | Private, encrypted, versioned bucket for files |
| Database | DynamoDB | File metadata, on-demand billing |
| Serverless | Lambda + EventBridge | Daily cleanup of expired files |
| Access control | IAM | Separate least-privilege roles for EC2 and Lambda; IMDSv2 enforced |
| Monitoring | CloudWatch + SNS | Container logs, CPU alarm, 5xx alarm, Lambda error alarm, email alerts |
| IaC | Terraform | Entire stack is reproducible with `terraform apply` |
| CI/CD | GitHub Actions | Tests, Docker build, Terraform validation, deploy via Systems Manager |

**Request flow.** Browser → EC2 (FastAPI) → S3 (object) and DynamoDB (metadata). For downloads, the API returns a presigned S3 URL, so the file itself is served directly by S3 and not through the server.

# 5. Non-Functional Requirements

| ID | Requirement |
|---|---|
| NFR-1 Security | The S3 bucket shall block all public access; objects are reachable only through presigned URLs. Data is encrypted at rest (AES-256). |
| NFR-2 Least privilege | IAM policies shall grant only the actions and resources each component needs. |
| NFR-3 Availability | The container shall restart automatically on failure. |
| NFR-4 Observability | Application logs shall be shipped to CloudWatch; alarms shall notify the administrator by email. |
| NFR-5 Reproducibility | All infrastructure shall be defined in Terraform. |
| NFR-6 Performance | API calls other than uploads shall respond within 1 second under normal load. |
| NFR-7 Maintainability | Unit tests shall run in CI on every push and pull request. |

# 6. External Interfaces

## 6.1 REST API
| Method | Path | Description |
|---|---|---|
| GET | `/health` | Service status |
| POST | `/api/files` | Upload a file (multipart) |
| GET | `/api/files` | List files |
| POST | `/api/files/{id}/link?ttl=` | Create an expiring download link |
| DELETE | `/api/files/{id}` | Delete a file |

## 6.2 User Interface
A single-page UI with an upload control, a file list, a lifetime selector per file, and Get link and Delete buttons.

# 7. Use Cases

**UC-1 Share a file.** The uploader selects a file and uploads it. The system stores it and shows it in the list. The uploader picks a lifetime and chooses Get link; the link is copied. The recipient opens it and downloads the file until the link expires.

**UC-2 Delete a file.** The uploader chooses Delete; the system removes the object and its metadata.

**UC-3 Automatic cleanup.** Once a day EventBridge triggers the Lambda function, which removes files older than the retention period.

# 8. Testing
Automated tests (pytest with mocked AWS via moto) cover health, upload, list, link creation, deletion, and invalid input. CI runs them on every push. A manual end-to-end check on the live deployment is part of the demo checklist.

# 9. Future Enhancements
User authentication (Amazon Cognito), HTTPS with an Application Load Balancer and ACM certificate, virus scanning of uploads, and download-count limits.
