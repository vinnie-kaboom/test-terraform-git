# Add this at the top of your main.tf
data "google_project_service" "iap" {
  service = "iap.googleapis.com"
}

provider "google" {
  project = var.project_id
  region  = var.region

  timeouts {
    create = "30m"
    update = "30m"
  }
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "iap.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Service Account
resource "google_service_account" "workload_identity_sa" {
  account_id   = var.service_account_id
  display_name = "Workload Identity Service Account"
  description  = "Service account for GitHub Actions Workload Identity"
  depends_on   = [google_project_service.required_apis]
}

# Grant necessary IAM roles
resource "google_project_iam_member" "workload_identity_admin" {
  project    = var.project_id
  role       = "roles/iam.workloadIdentityPoolAdmin"
  member     = "serviceAccount:${google_service_account.workload_identity_sa.email}"
  depends_on = [google_service_account.workload_identity_sa]
}

# Workload Identity Pool
resource "google_iam_workload_identity_pool" "main" {
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = "GitHub Actions Pool"
  description              = "Identity pool for GitHub Actions"
  depends_on               = [google_project_service.required_apis, google_project_iam_member.workload_identity_admin]
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

# Create VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = true
  depends_on              = [google_project_service.required_apis]
}

# IAP firewall rule
resource "google_compute_firewall" "iap-ssh" {
  name    = "${var.project_id}-allow-iap-ssh"
  network = google_compute_network.vpc_network.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Only allow SSH from IAP's IP range
  source_ranges = ["35.235.240.0/20"]  # Google's IAP range
  target_tags   = ["bastion-host"]
}

# Remove or modify the previous SSH firewall rule to only allow IAP
resource "google_compute_firewall" "bastion-ssh" {
  name    = "${var.project_id}-allow-bastion-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Only allow SSH from internal IPs and IAP
  source_ranges = concat(["35.235.240.0/20"], var.allowed_internal_ranges)
  target_tags   = ["bastion-host"]
}

# IAP OAuth brand (required for IAP)
resource "google_iap_brand" "project_brand" {
  support_email     = var.support_email
  application_title = "${var.project_id} Bastion Access"
  project          = var.project_id
  depends_on       = [
    google_project_service.required_apis,
    data.google_project_service.iap
  ]

  lifecycle {
    prevent_destroy = true  # Prevent accidental deletion
  }
}

# IAP OAuth client
resource "google_iap_client" "project_client" {
  display_name = "Bastion IAP Client"
  brand        = google_iap_brand.project_brand.name
}

# IAP tunnel IAM binding
resource "google_iap_tunnel_instance_iam_binding" "enable_iap" {
  project  = var.project_id
  zone     = var.zone
  instance = google_compute_instance.vm_instance.name
  role     = "roles/iap.tunnelResourceAccessor"
  members  = var.iap_authorized_users
  depends_on = [google_compute_instance.vm_instance, google_iap_brand.project_brand]
}

# Modify the VM instance with enhanced security
resource "google_compute_instance" "vm_instance" {
  name         = "${var.project_id}-bastion"
  machine_type = "e2-micro"
  zone         = var.zone
  depends_on   = [google_project_service.required_apis]

  tags = ["bastion-host"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
      type  = "pd-standard"
    }
    # Enable disk encryption
    kms_key_self_link = var.disk_encryption_key
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
      # Keep external IP for IAP access
    }
  }

  # Enhanced metadata for security
  metadata = {
    enable-oslogin = "TRUE"
    enable-oslogin-2fa = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable = "FALSE"
    enable-guest-attributes = "FALSE"
    
    # Startup script for additional hardening
    startup-script = <<-EOF
      #!/bin/bash
      # Update system
      apt-get update && apt-get upgrade -y

      # Install necessary security packages
      apt-get install -y \
        fail2ban \
        unattended-upgrades \
        apt-listchanges

      # Configure unattended-upgrades
      echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> /etc/apt/apt.conf.d/50unattended-upgrades
      echo 'Unattended-Upgrade::Automatic-Reboot-Time "02:00";' >> /etc/apt/apt.conf.d/50unattended-upgrades

      # Harden SSH configuration
      sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
      sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
      sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
      
      # Restart SSH service
      systemctl restart sshd

      # Setup basic firewall rules
      iptables -A INPUT -p tcp --dport 22 -j ACCEPT
      iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      iptables -P INPUT DROP
      
      # Install iptables-persistent to save rules
      DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
    EOF
  }

  # Enhanced service account configuration
  service_account {
    email  = google_service_account.workload_identity_sa.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/servicecontrol"
    ]
  }

  # Enable confidential computing if available
  confidential_instance_config {
    enable_confidential_compute = true
  }

  # Enable shielded VM options
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                = true
    enable_integrity_monitoring = true
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

output "bastion_details" {
  description = "Details of the bastion host"
  value = {
    name         = google_compute_instance.vm_instance.name
    external_ip  = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
    internal_ip  = google_compute_instance.vm_instance.network_interface[0].network_ip
    ssh_command  = "gcloud compute ssh ${google_compute_instance.vm_instance.name} --zone=${var.zone}"
  }
}

output "security_details" {
  description = "Security-related details for the bastion host"
  value = {
    iap_tunnel_command = "gcloud compute start-iap-tunnel ${google_compute_instance.vm_instance.name} 22 --local-host-port=localhost:2222 --zone=${var.zone}"
    oslogin_enabled    = true
    shielded_vm       = true
    confidential_computing = true
  }
}
