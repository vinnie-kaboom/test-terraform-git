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
  disable_on_destroy         = false
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

# Create subnet for cluster nodes
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_id}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = "10.0.0.0/24"
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

# Add IAP firewall rule
resource "google_compute_firewall" "iap_ssh" {
  name    = "${var.project_id}-allow-iap-ssh"
  network = google_compute_network.vpc_network.name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Only allow connections from IAP's IP range
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion-host"]
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
      "https://www.googleapis.com/auth/cloud-platform" # This gives access to all necessary APIs
    ]
  }

  metadata = {
    enable-oslogin           = "TRUE"
    enable-oslogin-2fa       = "TRUE"
    security-key-enforce-2fa = "TRUE"
    block-project-ssh-keys   = "TRUE"
    serial-port-enable       = "FALSE"
    enable-guest-attributes  = "FALSE"

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
    enable_secure_boot          = true
    enable_vtpm                 = true
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

# Add this resource to create a bucket for SSH keys
resource "google_storage_bucket" "ssh_keys_bucket" {
  name          = "${var.project_id}-ssh-keys"
  location      = var.region
  force_destroy = true # Allows deletion of bucket with contents

  uniform_bucket_level_access = true

  versioning {
    enabled = true # Enables versioning for recovery
  }
}

resource "null_resource" "ssh_key_setup" {
  triggers = {
    instance_id = google_compute_instance.vm_instance.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      #!/bin/bash
      set -e
      
      # Set up paths
      SSH_DIR="/home/runner/.ssh"
      KEY_PATH="$SSH_DIR/google_compute_engine"
      BUCKET_NAME="${var.project_id}-ssh-keys"
      
      # Create .ssh directory
      mkdir -p "$SSH_DIR"
      chmod 700 "$SSH_DIR"
      
      # Check if keys exist in bucket first
      if gsutil -q stat "gs://$BUCKET_NAME/google_compute_engine"; then
        echo "Downloading existing keys from bucket..."
        gsutil cp "gs://$BUCKET_NAME/google_compute_engine" "$KEY_PATH"
        gsutil cp "gs://$BUCKET_NAME/google_compute_engine.pub" "$KEY_PATH.pub"
        chmod 600 "$KEY_PATH"
        chmod 644 "$KEY_PATH.pub"
      else
        echo "Generating new SSH keys..."
        ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N ''
        chmod 600 "$KEY_PATH"
        chmod 644 "$KEY_PATH.pub"
        
        # Upload new keys to bucket
        gsutil cp "$KEY_PATH" "gs://$BUCKET_NAME/google_compute_engine"
        gsutil cp "$KEY_PATH.pub" "gs://$BUCKET_NAME/google_compute_engine.pub"
      fi
      
      # Add key to OS Login
      gcloud compute os-login ssh-keys add --key-file="$KEY_PATH.pub"
      
      # Get OS Login username and save it
      OS_LOGIN_USER=$(gcloud compute os-login describe-profile --format='get(posixAccounts[0].username)')
      echo "$OS_LOGIN_USER" > "$SSH_DIR/os_login_user"
      
      # Save connection info
      echo "VM_IP=${google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip}" > "$SSH_DIR/vm_connection_info"
      echo "OS_LOGIN_USER=$OS_LOGIN_USER" >> "$SSH_DIR/vm_connection_info"
      
      # Upload connection info to bucket
      gsutil cp "$SSH_DIR/os_login_user" "gs://$BUCKET_NAME/os_login_user"
      gsutil cp "$SSH_DIR/vm_connection_info" "gs://$BUCKET_NAME/vm_connection_info"
    EOT
  }

  depends_on = [
    google_compute_instance.vm_instance,
    google_storage_bucket.ssh_keys_bucket
  ]
}

resource "null_resource" "cleanup" {
  triggers = {
    instance_id = google_compute_instance.vm_instance.id
    bucket_name = "${var.project_id}-ssh-keys" # Store bucket name in triggers
    ssh_dir     = "/home/runner/.ssh"
    key_path    = "/home/runner/.ssh/google_compute_engine"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      #!/bin/bash
      set -e
      
      SSH_DIR="${self.triggers.ssh_dir}"
      KEY_PATH="${self.triggers.key_path}"
      BUCKET_NAME="${self.triggers.bucket_name}"
      
      # Remove OS Login SSH keys
      if [ -f "$KEY_PATH.pub" ]; then
        FINGERPRINT=$(ssh-keygen -lf "$KEY_PATH.pub" | awk '{print $2}')
        if [ ! -z "$FINGERPRINT" ]; then
          gcloud compute os-login ssh-keys remove --key="$FINGERPRINT" || true
        fi
      fi
      
      # Clean up local files
      rm -f "$KEY_PATH"*
      rm -f "$SSH_DIR/os_login_user"
      rm -f "$SSH_DIR/vm_connection_info"
      
      # Note: The bucket and its contents will be automatically deleted
      # due to force_destroy = true in the bucket configuration
    EOT
  }
}

# Add outputs to show bucket information
output "ssh_keys_bucket" {
  value = {
    name     = google_storage_bucket.ssh_keys_bucket.name
    location = google_storage_bucket.ssh_keys_bucket.location
    url      = "gs://${google_storage_bucket.ssh_keys_bucket.name}"
  }
}

# Update the output to show simplified connection instructions
output "connection_details" {
  value = {
    instance_name      = google_compute_instance.vm_instance.name
    zone               = google_compute_instance.vm_instance.zone
    project_id         = var.project_id
    connect_command    = "gcloud compute ssh ${google_compute_instance.vm_instance.name} --project=${var.project_id} --zone=${google_compute_instance.vm_instance.zone} --tunnel-through-iap"
    setup_instructions = <<-EOT
      To connect to your VM:

      1. Make sure you're logged into gcloud:
         gcloud auth login

      2. Run this command:
         gcloud compute ssh ${google_compute_instance.vm_instance.name} \
           --project=${var.project_id} \
           --zone=${google_compute_instance.vm_instance.zone} \
           --tunnel-through-iap

      3. On first login, you'll set up 2FA with Google Authenticator
      4. Future logins will require your 2FA code

      Note: If you get permission errors, run the commands shown in the post_setup_instructions output.
    EOT
  }
}

output "vpc_network_details" {
  value = {
    name = google_compute_network.vpc_network.name
    id   = google_compute_network.vpc_network.id
  }
}

# Make sure IAP API is enabled
resource "google_project_service" "iap_api" {
  project = var.project_id
  service = "iap.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Add output to show manual IAM setup instructions
output "post_setup_instructions" {
  value = <<-EOT
    After deployment, please run these commands manually to set up IAM permissions:

    gcloud projects add-iam-policy-binding ${var.project_id} \
      --member="serviceAccount:${google_service_account.vm_service_account.email}" \
      --role="roles/iap.tunnelResourceAccessor"

    gcloud compute instances add-iam-policy-binding ${google_compute_instance.vm_instance.name} \
      --project=${var.project_id} \
      --zone=${google_compute_instance.vm_instance.zone} \
      --member="serviceAccount:${google_service_account.vm_service_account.email}" \
      --role="roles/compute.osLogin"
  EOT
}

# Create cluster nodes
resource "google_compute_instance" "cluster_nodes" {
  count        = var.node_count
  name         = "${var.cluster_name}-node-${count.index + 1}"
  machine_type = var.node_machine_type
  zone         = var.cluster_zone
  project      = var.project_id

  tags = var.node_tags

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = var.node_disk_size
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {
      // Ephemeral public IP
    }
  }

  service_account {
    email  = google_service_account.vm_service_account.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_compute_subnetwork.subnet,
    google_service_account.vm_service_account
  ]
}

# Add firewall rule for cluster nodes
resource "google_compute_firewall" "cluster_nodes" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_ranges = ["10.0.0.0/16"]
  target_tags   = var.node_tags
}

# Output cluster node information
output "cluster_nodes" {
  value = {
    for instance in google_compute_instance.cluster_nodes :
    instance.name => {
      private_ip = instance.network_interface[0].network_ip
      public_ip  = instance.network_interface[0].access_config[0].nat_ip
    }
  }
  description = "Information about the cluster nodes"
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0" # Update to use version 6.x
    }
  }

  backend "gcs" {
    bucket = "sylvan-apogee-450014-a6-terraform-state"
    prefix = "terraform/state"
  }
}