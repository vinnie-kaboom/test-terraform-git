variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "sylvan-apogee-450014-a6"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "allowed_ssh_ranges" {
  description = "List of IP ranges allowed to SSH to bastion"
  type        = list(string)
  default     = ["35.235.240.0/20"] # IAP IP range
}

variable "service_account_email" {
  description = "Email of the service account"
  type        = string
  default     = "workload-identity-sa@sylvan-apogee-450014-a6.iam.gserviceaccount.com"
}

variable "service_account_id" {
  description = "The ID of the service account"
  type        = string
  default     = "workload-identity-sa"
}

variable "service_account_display_name" {
  description = "Display name for the service account"
  type        = string
  default     = "Workload Identity Service Account"
}

variable "instance_name" {
  description = "Name of the bastion instance"
  type        = string
  default     = "bastion"
}

variable "machine_type" {
  description = "Machine type for the bastion instance"
  type        = string
  default     = "e2-micro"
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "vpc"
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

variable "support_email" {
  description = "Support email for IAP OAuth consent screen"
  type        = string
}

variable "iap_authorized_users" {
  description = "List of users authorized to use IAP tunnel (e.g., ['user:example@gmail.com'])"
  type        = list(string)
}

variable "allowed_internal_ranges" {
  description = "List of internal IP ranges allowed to access bastion"
  type        = list(string)
  default     = []
}

variable "disk_encryption_key" {
  description = "KMS key for disk encryption"
  type        = string
  default     = null # If you want to use default Google encryption
}

variable "ssh_key_path" {
  description = "Path to save the generated SSH key"
  default     = "~/.ssh/google_compute_engine"
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "test-cluster"
}

variable "cluster_zone" {
  description = "Zone for the cluster nodes"
  type        = string
  default     = "us-central1-a"
}

variable "node_machine_type" {
  description = "Machine type for cluster nodes"
  type        = string
  default     = "e2-medium"
}

variable "node_count" {
  description = "Number of nodes in the cluster"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Size of the boot disk for each node"
  type        = number
  default     = 20
}

variable "node_tags" {
  description = "Tags to apply to cluster nodes"
  type        = list(string)
  default     = ["cluster-node"]
}

variable "user_email" {
  description = "Email of the user for SSH access"
  type        = string
}

variable "ssh_user" {
  description = "Username for SSH access to cluster nodes"
  type        = string
  default     = "ubuntu"
}

variable "ssh_pub_key_path" {
  description = "Path to the public SSH key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}