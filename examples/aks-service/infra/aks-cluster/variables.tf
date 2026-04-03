variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "eastus"
}

variable "project_name" {
  type        = string
  description = "Project name used in resource naming"
  default     = "platform"
}

variable "resource_group_name" {
  type        = string
  description = "Existing resource group name. If empty, a new RG is created"
  default     = ""
}

variable "node_count" {
  type        = number
  description = "Number of nodes in the default node pool"
  default     = 1
}

variable "vm_size" {
  type        = string
  description = "VM size for the default node pool"
  default     = "Standard_B2s"
}
