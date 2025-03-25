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

variable "zone" {
  description = "The GCP zone for the VM instance"
  type        = string
  default     = "us-central1-a"  # Default zone in us-central1 region
}

variable "allowed_ssh_ranges" {
  description = "List of IP ranges allowed to SSH to bastion host"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # WARNING: Change this to your specific IP ranges
}

variable "support_email" {
  description = "Email address for IAP brand support"
  type        = string
}

variable "iap_authorized_users" {
  description = "List of users authorized to access the bastion via IAP"
  type        = list(string)
  validation {
    condition     = can([for m in var.iap_authorized_users : regex("^user:", m)])
    error_message = "Each member in iap_authorized_users must start with 'user:'"
  }
}

variable "allowed_internal_ranges" {
  description = "List of internal IP ranges allowed to access bastion"
  type        = list(string)
  default     = []
}

variable "disk_encryption_key" {
  description = "KMS key for disk encryption"
  type        = string
  default     = null  # If you want to use default Google encryption
}