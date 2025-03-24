provider "google" {
  project     = "sylvan-apogee-450014-a6"
  region      = "us-central1"
  zone        = "us-central1-a"
  credentials = file("./sylvan-apogee-450014-a6-981355801382.json")
}


# Create a VPC network
resource "google_compute_network" "vpc_network" {
  name                    = "sylvan-apogee-450014-a6-network"
  auto_create_subnetworks = "true"
}

# Create a service account
resource "google_service_account" "workload_identity_sa" {
  account_id   = "workload-identity-sa"
  display_name = "Service Account for Workload Identity"
}

# Create Workload Identity Pool
resource "google_iam_workload_identity_pool" "main" {
  workload_identity_pool_id = "sylvan-apogee-450014-a6-pool"
  display_name             = "sylvan-apogee-450014-a6 Identity Pool"
  description             = "Identity pool for automated workloads"
}

# Create Workload Identity Pool Provider
resource "google_iam_workload_identity_pool_provider" "main" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.main.workload_identity_pool_id
  workload_identity_pool_provider_id = "my-provider"
  display_name                       = "My Provider"
  
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"  # Example for GitHub Actions
  }
}

# IAM binding for the service account
resource "google_service_account_iam_binding" "workload_identity_binding" {
  service_account_id = google_service_account.workload_identity_sa.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.main.name}/attribute.repository/your-org/your-repo"
  ]
}

# Create a VM instance
resource "google_compute_instance" "vm_instance" {
  name         = "sylvan-apogee-450014-a6t-vm"
  machine_type = "e2-micro"  # Very small, cost-effective instance type

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
    purpose     = "sylvan-apogee-450014-a6-testing"
  }

  # Enable deletion protection to prevent accidental deletion
  deletion_protection = false

  # Associate the service account with the VM
  service_account {
    email  = google_service_account.workload_identity_sa.email
    scopes = ["cloud-platform"]
  }

  # Use preemptible instance for even lower cost (but with limitations)
  # scheduling {
  #   preemptible = true
  #   automatic_restart = false
  #   on_host_maintenance = "TERMINATE"
  # }
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