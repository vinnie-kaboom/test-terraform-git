# Add this at the top of your main.tf
data "google_project_service" "iap" {
  service = "iap.googleapis.com"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "30m"
    update = "30m"
  }
}

# Create service account
resource "google_service_account" "service-account-1" {
  account_id   = var.service_account_id
  display_name = "Workload Identity Service Account"
  description  = "Service account for GitHub Actions Workload Identity"
  project      = var.project_id
}

# Create Workload Identity Pool
resource "google_iam_workload_identity_pool" "main" {
  workload_identity_pool_id = "github-actions-pool"
  display_name             = "GitHub Actions Pool"
  description              = "Identity pool for GitHub Actions"
  project                  = var.project_id
}

# Create Workload Identity Provider
resource "google_iam_workload_identity_pool_provider" "main" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.main.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Actions Provider"
  project                           = var.project_id

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Create VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = "${var.project_id}-${var.network_name}"
  project                 = var.project_id
  auto_create_subnetworks = true

  lifecycle {
    prevent_destroy = false
  }
}

# Create firewall rule for SSH access
resource "google_compute_firewall" "bastion-ssh" {
  name    = "${var.project_id}-allow-${var.instance_name}-ssh"
  network = google_compute_network.vpc_network.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_ranges
  target_tags   = ["${var.instance_name}-host"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Create VM instance
resource "google_compute_instance" "vm_instance" {
  name         = "${var.project_id}-${var.instance_name}"
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  tags = ["${var.instance_name}-host"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {}
  }

  service_account {
    email  = google_service_account.service-account-1.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin         = "TRUE"
    enable-oslogin-2fa     = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "FALSE"
    enable-guest-attributes = "FALSE"
    
    startup-script = <<-EOT
      #!/bin/bash
      apt-get update && apt-get upgrade -y
      apt-get install -y \
        fail2ban \
        unattended-upgrades \
        apt-listchanges
      
      echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> /etc/apt/apt.conf.d/50unattended-upgrades
      echo 'Unattended-Upgrade::Automatic-Reboot-Time "02:00";' >> /etc/apt/apt.conf.d/50unattended-upgrades
      
      sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
      sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
      sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
            
      systemctl restart sshd
      
      iptables -A INPUT -p tcp --dport 22 -j ACCEPT
      iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      iptables -P INPUT DROP
            
      DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    EOT
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot         = true
    enable_vtpm               = true
  }

  depends_on = [
    google_project_service.required_apis
  ]

  timeouts {
    create = "30m"
    delete = "30m"
    update = "30m"
  }
}

# Outputs
output "vm_instance_details" {
  value = {
    name         = google_compute_instance.vm_instance.name
    machine_type = google_compute_instance.vm_instance.machine_type
    zone         = google_compute_instance.vm_instance.zone
    public_ip    = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
  }
}

output "vpc_network_details" {
  value = {
    name = google_compute_network.vpc_network.name
    id   = google_compute_network.vpc_network.id
  }
}

output "workload_identity_provider" {
  value = "${google_iam_workload_identity_pool.main.name}/providers/${google_iam_workload_identity_pool_provider.main.workload_identity_pool_provider_id}"
}
