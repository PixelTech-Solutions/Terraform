# Terraform Platform Engineering — GitHub + Azure

A reusable Terraform CI/CD platform that teams **import** into their repos. They set a few variables and get automatic **init → plan → apply → destroy** pipelines with state stored in Azure.

> Equivalent of a GitLab CI/CD Terraform template, but for **GitHub Actions + Azure**.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  terraform-platform repo (this repo)                    │
│  ┌───────────────────────────────────────────────────┐  │
│  │ .github/workflows/terraform.yml (reusable)        │  │
│  │  format → validate → plan → apply → destroy       │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────┘
                          │  uses: org/terraform-platform/...@main
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
   ┌──────────┐    ┌──────────┐    ┌──────────┐
   │ Team A   │    │ Team B   │    │ Team C   │
   │ AKS svc  │    │ SQL DB   │    │ Storage  │
   │ ~10 lines│    │ ~10 lines│    │ ~10 lines│
   └──────────┘    └──────────┘    └──────────┘
          │               │               │
          └───────────────┼───────────────┘
                          ▼
          ┌───────────────────────────────┐
          │  Azure Blob Storage           │
          │  (State + Lease Locking)      │
          │  ┌─────────────────────────┐  │
          │  │ teamA/aks/dev/tf.state  │  │
          │  │ teamA/aks/prod/tf.state │  │
          │  │ teamB/sql/dev/tf.state  │  │
          │  └─────────────────────────┘  │
          └───────────────────────────────┘
```

## Comparison: GitLab+AWS vs GitHub+Azure

| Concept | GitLab + AWS | GitHub + Azure |
|---|---|---|
| CI Template | `include: template` | `uses: org/repo/.github/workflows/terraform.yml@main` |
| State Storage | S3 bucket | Azure Blob Storage |
| State Locking | DynamoDB | Native blob lease (built-in, no extra resource) |
| Auth | IAM Role | OIDC federated credentials (no secrets to rotate) |
| Manual Approval | `when: manual` | GitHub Environments with protection rules |
| Variables | CI/CD Variables | Repository/Org secrets + workflow inputs |

## Quick Start

### 1. Bootstrap State Backend (one-time per subscription)

```bash
# Login to Azure
az login

# Create state storage for dev environment
./scripts/bootstrap-backend.sh dev eastus <your-subscription-id>
```

### 2. Setup OIDC Authentication (one-time per repo)

```bash
# Creates service principal with federated credentials for GitHub
./scripts/setup-oidc.sh <your-github-org> <your-repo-name> <your-subscription-id>
```

Then add the output values as GitHub repository secrets:
- `ARM_CLIENT_ID`
- `ARM_TENANT_ID`
- `ARM_SUBSCRIPTION_ID`

> No `ARM_CLIENT_SECRET` needed — OIDC handles it with short-lived tokens!

### 3. Setup GitHub Environments

In your GitHub repo → Settings → Environments, create:

| Environment | Protection Rules |
|---|---|
| `dev-plan` | None (auto-runs) |
| `dev` | Required reviewers (for apply approval) |
| `prod-plan` | None |
| `prod` | Required reviewers + deployment branch = `main` |
| `dev-destroy` | Required reviewers (extra safety) |
| `prod-destroy` | Required reviewers (extra safety) |

### 4. Use in Your Team's Repo

Create `.github/workflows/deploy.yml` in your service repo:

```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
    paths: ["infra/**"]
  pull_request:
    branches: [main]
    paths: ["infra/**"]
  workflow_dispatch:
    inputs:
      destroy:
        description: "Destroy infrastructure?"
        type: boolean
        default: false

jobs:
  terraform:
    uses: <your-org>/terraform-platform/.github/workflows/terraform.yml@main
    with:
      working_directory: ./infra
      environment: dev
      backend_key: "myteam/myservice/dev/terraform.tfstate"
      destroy: ${{ github.event.inputs.destroy == 'true' }}
    secrets: inherit
```

That's it. **~15 lines** and your team has full Terraform CI/CD.

### 5. Add Terraform Code

```hcl
# infra/provider.tf
terraform {
  backend "azurerm" {}  # Configured by pipeline
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

## Pipeline Stages

```
Push/PR ──► Format Check ──► Validate ──► Plan ──► Apply (manual approval)
                                                 └──► Destroy (manual approval)
```

| Stage | Trigger | Details |
|---|---|---|
| **Format** | Auto | `terraform fmt -check` |
| **Validate** | Auto | `terraform validate` |
| **Plan** | Auto | Creates plan, posts summary to PR |
| **Apply** | Manual (GitHub Environment approval) | Only on `main` branch, uses saved plan |
| **Destroy** | Manual (workflow_dispatch + approval) | Separate environment for extra safety |

## Workflow Inputs Reference

| Input | Required | Default | Description |
|---|---|---|---|
| `working_directory` | No | `.` | Path to Terraform root module |
| `environment` | **Yes** | — | `dev`, `staging`, `prod` |
| `terraform_version` | No | `1.9.0` | Terraform version |
| `backend_resource_group` | No | `rg-terraform-state` | RG for state storage |
| `backend_storage_account` | No | `stterraformstate` | Storage account name |
| `backend_container` | No | `tfstate` | Blob container name |
| `backend_key` | **Yes** | — | State file path (e.g. `team/svc/env/tf.tfstate`) |
| `destroy` | No | `false` | `true` to destroy instead of apply |
| `additional_args` | No | `""` | Extra Terraform CLI args |

## State File Convention

```
<team>/<service>/<environment>/terraform.tfstate
```

Examples:
```
platform/networking/dev/terraform.tfstate
team-alpha/aks-cluster/prod/terraform.tfstate
team-beta/sql-database/staging/terraform.tfstate
```

## Subscription-Level Access

The OIDC setup script assigns **Contributor** at the subscription level. To restrict to specific resource groups, modify the role assignment scope in `scripts/setup-oidc.sh`:

```bash
# Subscription-level (default)
--scope "/subscriptions/${SUBSCRIPTION_ID}"

# Resource-group level (more restrictive)
--scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-team-a"
```

## File Structure

```
terraform-platform/
├── .github/workflows/
│   └── terraform.yml          # Reusable workflow (the template)
├── scripts/
│   ├── bootstrap-backend.sh   # One-time: create state storage
│   └── setup-oidc.sh          # One-time: setup GitHub↔Azure OIDC
├── examples/
│   └── aks-service/           # Example consumer repo
│       ├── .github/workflows/
│       │   └── deploy.yml     # ~15 lines to import the template
│       └── infra/
│           ├── provider.tf
│           └── main.tf
└── README.md
```
