# Terraform Platform Engineering

A reusable Terraform CI/CD platform for **GitHub Actions + Azure**. Teams import one workflow, set a few variables, and get automatic **format → validate → plan → apply → destroy** pipelines with remote state in Azure Blob Storage.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  PixelTech-Solutions/Terraform (this repo)              │
│  ┌───────────────────────────────────────────────────┐  │
│  │ .github/workflows/terraform.yml (reusable)        │  │
│  │  Format → Validate → Plan → Apply → Destroy       │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────┬───────────────────────────────┘
                          │  uses: PixelTech-Solutions/Terraform/...@main
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
   ┌──────────┐    ┌──────────┐    ┌──────────┐
   │ svc-blob │    │ svc-aks  │    │ svc-sql  │
   │ ~30 lines│    │ ~30 lines│    │ ~30 lines│
   └──────────┘    └──────────┘    └──────────┘
          │               │               │
          └───────────────┼───────────────┘
                          ▼
          ┌───────────────────────────────┐
          │  Azure Blob Storage           │
          │  stpixeltechstate / tfstate   │
          │  ┌─────────────────────────┐  │
          │  │ svc-blob/dev/tf.state   │  │
          │  │ svc-aks/prod/tf.state   │  │
          │  │ svc-sql/dev/tf.state    │  │
          │  └─────────────────────────┘  │
          │  Locking: Built-in blob lease │
          └───────────────────────────────┘
```

## Features

- **One workflow to rule them all** — teams write ~30 lines of YAML to get full CI/CD
- **OIDC authentication** — no client secrets to manage or rotate
- **Azure Blob Storage backend** — state + locking in a single resource (blob leases)
- **Manual approval gates** — Apply and Destroy require reviewer approval via GitHub Environments
- **Auto-created environments** — the Plan job creates `dev` and `dev-destroy` environments automatically
- **Safe by default** — Apply is skipped if no reviewers are configured yet
- **PR comments** — plan output posted as a PR comment for review

## Quick Start

### 1. Use in Your Service Repo

Create `.github/workflows/infra.yml`:

```yaml
name: Infrastructure

on:
  push:
    branches: [main]
    paths: [infra/**]
  pull_request:
    paths: [infra/**]
  workflow_dispatch:

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  dev:
    uses: PixelTech-Solutions/Terraform/.github/workflows/terraform.yml@main
    with:
      working_directory: ./infra
      environment: dev
    secrets: inherit
```

That's it. The workflow auto-derives:
- **State key:** `<repo-name>/dev/terraform.tfstate`
- **Var file:** `-var-file=environments/dev.tfvars`

### 2. Add Terraform Code

```hcl
# infra/provider.tf
terraform {
  required_version = ">= 1.9.0"
  backend "azurerm" {}   # Configured automatically by the pipeline
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

### 3. Push and Set Up Reviewers

1. Push to `main` — the pipeline runs Format → Validate → Plan
2. Environments `dev` and `dev-destroy` are auto-created
3. Go to **Settings → Environments → `dev`** → add Required reviewers
4. Go to **Settings → Environments → `dev-destroy`** → add Required reviewers
5. Next push — Apply pauses with a "Review deployments" button

## Pipeline Flow

```
On PR:
  Format ──► Validate ──► Plan (posts comment to PR)

On push to main:
  Format ──► Validate ──► Plan ─┬──► Apply ⏸️  [Review deployments]
                                └──► Destroy ⏸️ [Review deployments]
```

| Stage | Trigger | Details |
|---|---|---|
| **Format** | Auto | `terraform fmt -check -recursive -diff` |
| **Validate** | Auto | `terraform init -backend=false` + `terraform validate` |
| **Plan** | Auto | Full init, plan, artifact upload, env creation |
| **Apply** | Manual approval | Downloads saved plan, `terraform apply -auto-approve tfplan` |
| **Destroy** | Manual approval | `terraform plan -destroy` + `terraform destroy -auto-approve` |

## Workflow Inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `working_directory` | No | `.` | Path to Terraform root module |
| `environment` | **Yes** | — | `dev`, `staging`, `prod` |
| `service_name` | No | Repo name | Used for state key and tfvars path |
| `terraform_version` | No | `1.9.0` | Terraform version |
| `backend_resource_group` | No | `rg-terraform-state` | Resource group for state storage |
| `backend_storage_account` | No | `stpixeltechstate` | Storage account name |
| `backend_container` | No | `tfstate` | Blob container name |
| `additional_args` | No | `""` | Extra Terraform CLI args (appended after `-var-file`) |

### Auto-Derived Values

From `service_name` (defaults to repo name) + `environment`:

| What | Pattern | Example |
|---|---|---|
| State key | `<service_name>/<environment>/terraform.tfstate` | `svc-blob-storage-example/dev/terraform.tfstate` |
| Var file | `environments/<environment>.tfvars` | `environments/dev.tfvars` |

## State File Convention

```
<service-name>/<environment>/terraform.tfstate
```

Examples:
```
svc-blob-storage-example/dev/terraform.tfstate
svc-aks-cluster/prod/terraform.tfstate
svc-sql-database/staging/terraform.tfstate
```

## Authentication

This platform uses **OIDC (OpenID Connect)** federated credentials — no client secrets needed.

GitHub Actions requests a short-lived token from Azure AD on every workflow run. To set up:

1. Create an **App Registration** in Azure AD
2. Create a **Service Principal** and assign `Contributor` + `Storage Blob Data Contributor` roles
3. Add **Federated Credentials** for your repo (main branch, PRs, and each environment)
4. Set org/repo secrets: `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`

## Onboarding a New Service

1. Create a new repo in the org
2. Add `infra/` folder with your Terraform code (`provider.tf` must have `backend "azurerm" {}`)
3. Add `.github/workflows/infra.yml` calling this reusable workflow (see Quick Start)
4. Add federated credentials in Azure for the new repo
5. Push to `main` — pipeline creates environments automatically
6. Add reviewers to the environments
7. Done — Apply and Destroy are gated by approval

## File Structure

```
PixelTech-Solutions/Terraform/
├── .github/workflows/
│   └── terraform.yml          # Reusable workflow (the platform)
├── examples/
│   └── aks-service/           # Example consumer repo
│       ├── .github/workflows/
│       │   └── deploy.yml
│       └── infra/
│           ├── main.tf
│           ├── provider.tf
│           ├── variables.tf
│           ├── outputs.tf
│           └── environments/
│               ├── dev.tfvars
│               ├── qa.tfvars
│               ├── uat.tfvars
│               ├── prod.tfvars
│               └── demo.tfvars
├── .gitignore
└── README.md
```
