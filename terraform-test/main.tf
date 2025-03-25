provider "google" {
  project = var.project_id
  region  = var.region
}

# Service Account
resource "google_service_account" "workload_identity_sa" {
  account_id   = var.service_account_id
  display_name = "Workload Identity Service Account"
  description  = "Service account for GitHub Actions Workload Identity"
}

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "main" {
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = "GitHub Actions Pool"
  description              = "Identity pool for GitHub Actions"
}

# Workload Identity Provider
resource "google_iam_workload_identity_pool_provider" "main" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.main.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "GitHub Actions Provider"
  
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# IAM binding
resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.workload_identity_sa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.main.name}/attribute.repository/${var.github_repo}"
  ]
}

# Create VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = true
}

# Create a VM instance
resource "google_compute_instance" "vm_instance" {
  name         = "${var.project_id}-vm"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"  # Debian is a good low-cost choice
      size  = 10  # Minimum size in GB
      type  = "pd-standard"  # Standard persistent disk is cheaper than SSD
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
      # Include this empty block to give the VM an external IP address
    }
  }

  # Add some labels for better organization
  labels = {
    environment = "development"
    purpose     = "${var.project_id}-testing"
  }

  # Enable deletion protection to prevent accidental deletion
  deletion_protection = false

  # Associate the service account with the VM
  service_account {
    email  = google_service_account.workload_identity_sa.email
    scopes = ["cloud-platform"]
  }
}

# Output the VM's IP address
output "public_ip" {
  value = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
}

# Output the Workload Identity Pool Provider ID
output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.main.name
}

# Output the service account email
output "service_account_email" {
  value = google_service_account.workload_identity_sa.email
}

# Outputs
output "vm_instance_details" {
  description = "Details of the created VM instance"
  value = {
    name         = google_compute_instance.vm_instance.name
    machine_type = google_compute_instance.vm_instance.machine_type
    zone         = google_compute_instance.vm_instance.zone
    public_ip    = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
  }
}

output "vpc_network_details" {
  description = "Details of the created VPC network"
  value = {
    name = google_compute_network.vpc_network.name
    id   = google_compute_network.vpc_network.id
  }
}

output "workload_identity_details" {
  description = "Details of the Workload Identity configuration"
  value = {
    pool_name           = google_iam_workload_identity_pool.main.name
    provider_name       = google_iam_workload_identity_pool_provider.main.name
    service_account     = google_service_account.workload_identity_sa.email
  }
}