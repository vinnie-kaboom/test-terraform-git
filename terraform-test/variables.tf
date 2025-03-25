variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "service_account_id" {
  description = "The ID of the service account"
  type        = string
  default     = "workload-identity-sa"
}

variable "workload_identity_pool_id" {
  description = "The ID of the workload identity pool"
  type        = string
  default     = "github-actions-pool"
}

variable "provider_id" {
  description = "The ID of the workload identity provider"
  type        = string
  default     = "github-provider"
}

variable "github_repo" {
  description = "The GitHub repository in format 'owner/repo'"
  type        = string
}