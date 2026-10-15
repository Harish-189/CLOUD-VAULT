# CloudVault

Secure file sharing with expiring links, built on AWS for the Cloud Computing Hackathon.

**Stack:** FastAPI, S3, DynamoDB, EC2 + Docker, Lambda + EventBridge, IAM, CloudWatch + SNS, Terraform, GitHub Actions.

## Run the tests (no AWS needed)
```bash
cd backend
pip install -r requirements.txt pytest httpx "moto[s3,dynamodb]"
python -m pytest -q
```

## Deploy to AWS
Prerequisites: AWS CLI configured (`aws configure`), Terraform >= 1.5, repo pushed to a **public** GitHub repo.

```bash
cd infra
terraform init
terraform apply \
  -var 'github_repo=https://github.com/<you>/cloudvault.git' \
  -var 'alert_email=<your email>'
```
Wait 2-3 minutes after apply, then open the `app_url` output. Confirm the SNS subscription email so alarms reach you.

## Redeploys via GitHub Actions
In the repo settings add secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and variable `INSTANCE_ID` (EC2 instance id). Pushes to `main` run CI, then redeploy.

## Tear down after the event
```bash
terraform destroy
```
(Empty the S3 bucket first if it contains files, since versioning is on.)

## Layout
```
backend/   FastAPI app, tests, Dockerfile
frontend/  static UI
lambda/    scheduled cleanup function
infra/     Terraform
docs/      SRS, demo script, team plan
.github/   CI and deploy workflows
```
