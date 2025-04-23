variable "project_id" {
  description = "The project ID to deploy to"
  type        = string
  default     = "sylvan-apogee-450014-a6"
}

variable "region" {
  description = "The region to deploy to"
  type        = string
  default     = "us-east1"  # Changed from us-central1 to us-east1 for better capacity
}

variable "zone" {
  description = "The zone to deploy to"
  type        = string
  default     = "us-east1-b"  # Changed to match new region
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
  description = "The machine type for the bastion VM"
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
  description = "GitHub repository name"
  type        = string
}

variable "support_email" {
  description = "Email address for support"
  type        = string
}

variable "iap_authorized_users" {
  description = "List of IAP authorized users"
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
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-2"  # Changed from e2-small to e2-standard-2 for better availability
}

variable "node_count" {
  description = "Number of nodes in the GKE node pool"
  type        = number
  default     = 1
}

variable "node_disk_size" {
  description = "Disk size for GKE nodes in GB"
  type        = number
  default     = 20
}

variable "node_tags" {
  description = "Tags to apply to GKE nodes"
  type        = list(string)
  default     = ["gke-node"]
}

variable "user_email" {
  description = "Email address of the user"
  type        = string
}

variable "ssh_user" {
  description = "SSH user for the bastion VM"
  type        = string
  default     = "ubuntu"
}

variable "ssh_pub_key_path" {
  description = "Path to the SSH public key"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}