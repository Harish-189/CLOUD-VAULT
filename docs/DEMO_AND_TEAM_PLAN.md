# Demo script, final checklist and team commit plan

## Team commit plan (split so every member has meaningful commits)
Create the repo, then each member works on a branch and opens a PR into `main`.

| Member | Branch | Owns | Suggested commits |
|---|---|---|---|
| 1 (lead) | `feat/backend-api` | `backend/app/main.py`, `requirements.txt` | API skeleton; upload; list; link; delete; validation |
| 2 | `feat/frontend` | `frontend/index.html` | Layout; upload; file list; link and delete actions |
| 3 | `feat/infra` | `infra/main.tf`, `docker-compose.yml`, `backend/Dockerfile` | S3 + DynamoDB; IAM; EC2; Lambda; CloudWatch |
| 4 | `feat/ci-docs` | `.github/`, `docs/`, `backend/tests/`, `lambda/` | Tests; CI; deploy workflow; SRS; README |

Everyone: commit small and often, with real messages ("add ttl validation to link endpoint"), not one big dump.

## Order of work tonight (about 90 minutes)
1. Create GitHub repo, push everything, each member adds their own commits (30 min).
2. Run tests locally (5 min).
3. `terraform apply` from one laptop with AWS credentials (15 min incl. wait).
4. Open the URL, upload a file, create a link, open it (5 min).
5. Add GitHub secrets/variable so the deploy workflow works (10 min).
6. Convert `docs/SRS.md` to Word (command in the notes below) and upload it to the form (10 min).

## Live demo script (3-4 minutes)
1. Open the public URL; show the UI.
2. Upload a file; show it in the list.
3. AWS console, S3: the object is there, bucket is private, encrypted.
4. AWS console, DynamoDB: the metadata item.
5. Click Get link with 15 minutes; open it in a private window; the download works. Mention that a link older than its lifetime returns AccessDenied.
6. IAM: show the two roles and their narrow policies.
7. CloudWatch: the log group with request logs, the alarms.
8. Lambda: the cleanup function and its daily EventBridge rule (use Test to run it live).
9. GitHub: commit history per member; Actions tab with a green CI run.
10. Terraform: "the whole stack above was created by `terraform apply`".

## Final checklist before 3:00 PM
- [ ] Public URL loads from a phone on mobile data
- [ ] Test upload, link, delete all work on the live site
- [ ] SNS email subscription confirmed
- [ ] Every member has commits in GitHub history
- [ ] CI run is green
- [ ] SRS uploaded and GitHub link submitted: https://forms.gle/ZJjqfMG2mVFxr8aq9
- [ ] Each member submitted feedback: https://forms.gle/pTboDWE5gVcJRt7E7
- [ ] AWS console tabs pre-opened: S3, DynamoDB, IAM, CloudWatch, Lambda
- [ ] Do not run `terraform destroy` until judging is over

## Notes
- Word version of the SRS: `pandoc docs/SRS.md -o docs/SRS.docx`
- The EC2 URL is HTTP only. That is fine for a demo; HTTPS via a load balancer is listed under future work in the SRS.
- If the site is unreachable after apply, wait 3 minutes (the instance is still building the container), then check `/var/log/cloud-init-output.log` on the instance via the console's Session Manager.
