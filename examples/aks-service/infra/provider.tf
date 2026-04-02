terraform {
  required_version = ">= 1.9.0"

  # Backend is configured dynamically by the CI/CD pipeline.
  # Do NOT hardcode backend config here.
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

  # These are injected by the workflow via environment variables:
  #   ARM_CLIENT_ID, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
  # Authentication is handled by OIDC — no secrets in code.
}
