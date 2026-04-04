# Terraform Platform

Reusable Terraform workflow for GitHub Actions and Azure.

## What It Does

- Runs `terraform fmt`, `validate`, and `plan`
- Gates `apply` and `destroy` with GitHub Environments
- Supports one workflow per environment

## Example Usage

```yaml
name: Infrastructure - Dev

on:
  push:
    branches: [main]
    paths: [infra/**]
  workflow_dispatch:

jobs:
  dev:
    uses: your-org/terraform-platform/.github/workflows/terraform.yml@main
    with:
      working_directory: ./infra/my-service
      environment: dev
      project_name: my-project
      service_name: my-service
    secrets: inherit
```

Derived values:
- State key in Blob storage: `my-project/my-service/dev/terraform.tfstate`
- Var file: `environments/dev.tfvars`

## Terraform Layout

```text
infra/
  modules/
    my-module/
      main.tf
      variables.tf
      outputs.tf
  my-service/
    main.tf
    variables.tf
    outputs.tf
    provider.tf
    data.tf
    locals.tf
    environments/
      dev.tfvars
      qa.tfvars
```

`provider.tf` needs an empty `azurerm` backend block:

```hcl
terraform {
  required_version = ">= 1.9.0"

  backend "azurerm" {}

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

## Workflow Inputs

| Input | Required | Default |
|---|---|---|
| `working_directory` | No | `.` |
| `environment` | Yes | — |
| `project_name` | Yes | — |
| `service_name` | No | Repo name |
| `terraform_version` | No | `1.9.0` |
| `additional_args` | No | `""` |

## Notes

- `apply` and `destroy` require reviewers on matching GitHub Environments
- `plan` uploads a saved plan artifact and comments on pull requests
- Azure credentials can be passed with inherited GitHub secrets

## Repo Layout

```text
.
├── .github/workflows/
│   └── terraform.yml
├── examples/
│   └── aks-service/
│       ├── .github/workflows/
│       │   ├── deploy.yml
│       │   ├── deploy-demo.yml
│       │   ├── deploy-qa.yml
│       │   ├── deploy-uat.yml
│       │   └── deploy-prod.yml
│       └── infra/
│           ├── modules/aks/
│           └── aks-cluster/
└── README.md
```
