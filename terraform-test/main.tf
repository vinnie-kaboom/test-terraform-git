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
    security-key-enforce-2fa = "TRUE"  # Forces security key/authenticator app
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
      
      # Additional 2FA setup
      apt-get install -y libpam-google-authenticator
      
      # Configure PAM for 2FA
      echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
      
      # Update SSHD config
      sed -i 's/ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
      echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config
      
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

# Generate SSH key and configure OS Login
resource "null_resource" "ssh_key_setup" {
  triggers = {
    instance_id = google_compute_instance.vm_instance.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      # Generate SSH key if it doesn't exist
      if [ ! -f ~/.ssh/google_compute_engine ]; then
        mkdir -p ~/.ssh
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/google_compute_engine -N ''
      fi
      
      # Add key to OS Login
      gcloud compute os-login ssh-keys add --key-file=~/.ssh/google_compute_engine.pub
      
      # Get OS Login username
      OS_LOGIN_USER=$(gcloud compute os-login describe-profile --format='get(posixAccounts[0].username)')
      
      # Output connection information
      echo "VM IP: ${google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip}"
      echo "OS Login username: $OS_LOGIN_USER"
      echo "SSH command: ssh -i ~/.ssh/google_compute_engine $OS_LOGIN_USER@${google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip}"
    EOT
  }

  depends_on = [
    google_compute_instance.vm_instance
  ]
}

# Update the cleanup resource to use bash
resource "null_resource" "cleanup" {
  triggers = {
    instance_id = google_compute_instance.vm_instance.id
    ssh_key_path = "~/.ssh/google_compute_engine"
  }

  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      #!/bin/bash
      # Remove OS Login SSH keys
      gcloud compute os-login ssh-keys list | while read -r line; do
        if [[ $line =~ fingerprint:[[:space:]](.*) ]]; then
          gcloud compute os-login ssh-keys remove --key="${BASH_REMATCH[1]}"
        fi
      done
      
      # Remove local SSH keys
      rm -f ${self.triggers.ssh_key_path}
      rm -f ${self.triggers.ssh_key_path}.pub
    EOT
  }
}

# Outputs
output "connection_details" {
  value = {
    instance_name = google_compute_instance.vm_instance.name
    public_ip     = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
    zone          = google_compute_instance.vm_instance.zone
    ssh_key_path  = var.ssh_key_path
    setup_instructions = <<-EOT
      1. Install Google Authenticator app on your phone
      2. Run: gcloud compute ssh ${google_compute_instance.vm_instance.name} --zone=${var.zone}
      3. Follow the 2FA setup prompts
      4. Future connections: ssh -i ${var.ssh_key_path} $OS_LOGIN_USER@${google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip}
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

