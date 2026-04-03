# Terraform Platform

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

- **One workflow to rule them all** — teams write ~30 lines of YAML per environment to get full CI/CD
- **Client secret auth** — org-level secret, zero setup per new repo
- **Separate pipeline per environment** — deploy and manage each environment independently
- **Azure Blob Storage backend** — state + locking in a single resource (blob leases)
- **Manual approval gates** — Apply and Destroy require reviewer approval via GitHub Environments
- **Auto-created environments** — the Plan job creates `dev` and `dev-destroy` environments automatically
- **Safe by default** — Apply is skipped if no reviewers are configured yet
- **PR comments** — plan output posted as a PR comment for review

## Quick Start

### 1. Use in Your Service Repo

Create one workflow per environment. Example `.github/workflows/infra-dev.yml`:

```yaml
name: "Infrastructure - Dev"

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
      working_directory: ./infra/my-service
      environment: dev
      project_name: my-project
      service_name: my-service
    secrets: inherit
```

That's it. The workflow auto-derives:
- **State key:** `my-project/my-service/dev/terraform.tfstate`
- **Var file:** `-var-file=environments/dev.tfvars`

### 2. Add Terraform Code

Organise your infra folder with modules and service folders:

```
infra/
  modules/           # Reusable modules
    my-module/
      main.tf
      variables.tf
      outputs.tf
  my-service/         # Service root (working_directory points here)
    main.tf           # Calls modules, creates resources
    variables.tf
    outputs.tf
    provider.tf
    data.tf
    locals.tf
    environments/
      dev.tfvars
      qa.tfvars
```

```hcl
# infra/my-service/provider.tf
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
| `project_name` | **Yes** | — | Project name — groups services in the state path |
| `service_name` | No | Repo name | Service name within the project |
| `terraform_version` | No | `1.9.0` | Terraform version |
| `backend_resource_group` | No | `rg-terraform-state` | Resource group for state storage |
| `backend_storage_account` | No | `stpixeltechstate` | Storage account name |
| `backend_container` | No | `tfstate` | Blob container name |
| `additional_args` | No | `""` | Extra Terraform CLI args (appended after `-var-file`) |

### Auto-Derived Values

From `project_name` + `service_name` (defaults to repo name) + `environment`:

| What | Pattern | Example |
|---|---|---|
| State key | `<project_name>/<service_name>/<environment>/terraform.tfstate` | `storage/svc-blob-storage-example/dev/terraform.tfstate` |
| Var file | `environments/<environment>.tfvars` | `environments/dev.tfvars` |

## State File Convention

```
<project-name>/<service-name>/<environment>/terraform.tfstate
```

Examples:
```
storage/svc-blob-storage-example/dev/terraform.tfstate
platform/aks-cluster/prod/terraform.tfstate
data/sql-database/staging/terraform.tfstate
```

## Authentication

The workflow supports two authentication methods — auto-detected via the `ARM_CLIENT_SECRET` secret:

| Method | When | Setup per new repo |
|---|---|---|
| **Client Secret** | `ARM_CLIENT_SECRET` is set | **None** — works immediately for all repos in the org |
| **OIDC** | `ARM_CLIENT_SECRET` is empty | Requires federated credentials per repo/branch/environment |

We use **client secret** (org-level secret) for simplicity — any new repo in the org works instantly with zero Azure setup.

Org secrets:
- `ARM_CLIENT_ID` — App registration client ID
- `ARM_TENANT_ID` — Azure AD tenant ID
- `ARM_SUBSCRIPTION_ID` — Target subscription
- `ARM_CLIENT_SECRET` — Service principal client secret

The service principal needs `Contributor` + `Storage Blob Data Contributor` roles at subscription level.

> **Note:** To switch to OIDC (more secure, no secret rotation), remove `ARM_CLIENT_SECRET` and add federated credentials per repo. The workflow auto-detects.

## Onboarding a New Service

1. Create a new repo in the org
2. Add `infra/modules/` with reusable modules and `infra/<service-name>/` with your Terraform code (`provider.tf` must have `backend "azurerm" {}`)
3. Add one workflow per environment in `.github/workflows/` calling this reusable workflow (see Quick Start)
4. Push to `main` — pipeline creates environments automatically
5. Add reviewers to the environments
6. Done — Apply and Destroy are gated by approval

No Azure setup needed per repo — org secrets handle auth for all repos.

## File Structure

```
PixelTech-Solutions/Terraform/
├── .github/workflows/
│   └── terraform.yml              # Reusable workflow (the platform)
├── examples/
│   └── aks-service/               # Example consumer repo
│       ├── .github/workflows/
│       │   ├── deploy.yml         # Dev pipeline
│       │   ├── deploy-qa.yml      # QA pipeline
│       │   ├── deploy-uat.yml     # UAT pipeline
│       │   ├── deploy-prod.yml    # Prod pipeline
│       │   └── deploy-demo.yml    # Demo pipeline
│       └── infra/
│           ├── modules/
│           │   └── aks/
│           │       ├── main.tf
│           │       ├── variables.tf
│           │       └── outputs.tf
│           └── aks-cluster/           # Service folder
│               ├── main.tf
│               ├── variables.tf
│               ├── outputs.tf
│               ├── provider.tf
│               ├── data.tf
│               ├── locals.tf
│               └── environments/
│                   ├── dev.tfvars
│                   ├── qa.tfvars
│                   ├── uat.tfvars
│                   ├── prod.tfvars
│                   └── demo.tfvars
├── .gitignore
└── README.md
```
