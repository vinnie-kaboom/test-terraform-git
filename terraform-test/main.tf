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
}

# Create a service account for the VM
resource "google_service_account" "vm_service_account" {
  account_id   = "bastion-vm-sa"
  display_name = "Bastion VM Service Account"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Create VPC Network
resource "google_compute_network" "vpc_network" {
  name                    = "${var.project_id}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = true
}

# Create firewall rule for SSH access
resource "google_compute_firewall" "bastion-ssh" {
  name    = "${var.project_id}-allow-bastion-ssh"
  network = google_compute_network.vpc_network.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_ranges
  target_tags   = ["bastion-host"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Create VM instance
resource "google_compute_instance" "vm_instance" {
  name         = "${var.project_id}-bastion"
  machine_type = var.machine_type
  zone         = var.zone
  project      = var.project_id

  tags = ["bastion-host"]

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

  # Use our created service account instead of the default one
  service_account {
    email = google_service_account.vm_service_account.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/compute.readonly"
    ]
  }

  metadata = {
    enable-oslogin         = "TRUE"
    enable-oslogin-2fa     = "TRUE"
    security-key-enforce-2fa = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "FALSE"
    enable-guest-attributes = "FALSE"
    
    startup-script = <<-EOT
      #!/bin/bash
      apt-get update && apt-get upgrade -y
      apt-get install -y \
        fail2ban \
        unattended-upgrades \
        apt-listchanges \
        libpam-google-authenticator
      
      # Configure automatic updates
      echo 'Unattended-Upgrade::Automatic-Reboot "true";' >> /etc/apt/apt.conf.d/50unattended-upgrades
      echo 'Unattended-Upgrade::Automatic-Reboot-Time "02:00";' >> /etc/apt/apt.conf.d/50unattended-upgrades
      
      # Configure SSH
      sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
      sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
      sed -i 's/#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config
      sed -i 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
      echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config
      
      # Configure PAM for 2FA
      echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
      
      # Configure firewall
      iptables -A INPUT -p tcp --dport 22 -j ACCEPT
      iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      iptables -P INPUT DROP
      
      DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
      
      systemctl restart sshd
    EOT
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot         = true
    enable_vtpm               = true
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_account.vm_service_account
  ]

  timeouts {
    create = "30m"
    delete = "30m"
    update = "30m"
  }
}

# SSH key setup resource
resource "null_resource" "ssh_key_setup" {
  triggers = {
    instance_id = google_compute_instance.vm_instance.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      # Create .ssh directory if it doesn't exist
      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      
      # Generate SSH key if it doesn't exist
      if [ ! -f ~/.ssh/google_compute_engine ]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/google_compute_engine -N ''
        chmod 600 ~/.ssh/google_compute_engine
        chmod 644 ~/.ssh/google_compute_engine.pub
      fi
      
      # Add key to OS Login
      gcloud compute os-login ssh-keys add --key-file=~/.ssh/google_compute_engine.pub
      
      # Get OS Login username and save it
      OS_LOGIN_USER=$(gcloud compute os-login describe-profile --format='get(posixAccounts[0].username)')
      echo "$OS_LOGIN_USER" > ~/.ssh/os_login_user
      
      # Output connection information
      echo "VM_IP=${google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip}" > ~/.ssh/vm_connection_info
      echo "OS_LOGIN_USER=$OS_LOGIN_USER" >> ~/.ssh/vm_connection_info
    EOT
  }

  depends_on = [
    google_compute_instance.vm_instance
  ]
}

# Single cleanup resource
resource "null_resource" "cleanup" {
  triggers = {
    instance_id = google_compute_instance.vm_instance.id
  }

  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      #!/bin/bash
      set -e
      
      # Remove OS Login SSH keys
      if [ -f ~/.ssh/google_compute_engine.pub ]; then
        FINGERPRINT=$(ssh-keygen -lf ~/.ssh/google_compute_engine.pub | awk '{print $2}')
        if [ ! -z "$FINGERPRINT" ]; then
          gcloud compute os-login ssh-keys remove --key="$FINGERPRINT" || true
        fi
      fi
      
      # Clean up local files
      rm -f ~/.ssh/google_compute_engine*
      rm -f ~/.ssh/os_login_user
      rm -f ~/.ssh/vm_connection_info
    EOT
  }
}

# Consolidated outputs
output "connection_details" {
  value = {
    instance_name = google_compute_instance.vm_instance.name
    public_ip     = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
    zone          = google_compute_instance.vm_instance.zone
    ssh_key_path  = "~/.ssh/google_compute_engine"
    setup_instructions = <<-EOT
      1. Install Google Authenticator app on your phone
      2. Wait a few minutes for the VM to complete its startup script
      3. SSH into the VM using: ssh -i ~/.ssh/google_compute_engine $(cat ~/.ssh/os_login_user)@${google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip}
      4. On first login, you'll set up 2FA
      5. Future logins will require both SSH key and 2FA code
    EOT
  }
}

output "vpc_network_details" {
  value = {
    name = google_compute_network.vpc_network.name
    id   = google_compute_network.vpc_network.id
  }
}

terraform {
  backend "gcs" {
    bucket = "sylvan-apogee-450014-a6-terraform-state"
    prefix = "terraform/state"
  }
}

