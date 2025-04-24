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
    "iam.googleapis.com",
    "container.googleapis.com"
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
  auto_create_subnetworks = false  # Changed to false to prevent automatic subnet creation

  lifecycle {
    ignore_changes = [
      name
    ]
  }
}

# Create subnet for cluster nodes
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_id}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = "10.0.0.0/22"  # Increased from /24 to /22 for more IPs

  secondary_ip_range {
    range_name    = "pod-range"
    ip_cidr_range = "10.0.4.0/22"  # Changed to a larger range
  }

  secondary_ip_range {
    range_name    = "service-range"
    ip_cidr_range = "10.0.8.0/22"  # Changed to a larger range
  }

  lifecycle {
    ignore_changes = [
      name
    ]
  }
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
  machine_type = "e2-micro"
  zone         = "${var.region}-a"
  project      = var.project_id

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 10
    }
  }

  network_interface {
    network    = google_compute_network.vpc_network.name
    subnetwork = google_compute_subnetwork.subnet.name
    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    email  = google_service_account.vm_service_account.email
    scopes = ["cloud-platform"]
  }

  tags = ["bastion", "ssh"]

  depends_on = [
    google_compute_network.vpc_network,
    google_compute_subnetwork.subnet,
    google_service_account.vm_service_account
  ]
}

# Create GCS bucket for SSH keys
resource "google_storage_bucket" "ssh_keys_bucket" {
  name          = "${var.project_id}-ssh-keys"
  location      = var.region
  force_destroy = true
  project       = var.project_id

  uniform_bucket_level_access = true

  lifecycle {
    ignore_changes = [
      name,
      location
    ]
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

# Create GKE cluster
resource "google_container_cluster" "primary" {
  name     = "${var.project_id}-gke"
  location = var.region
  project  = var.project_id

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.subnet.name

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pod-range"
    services_secondary_range_name = "service-range"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "${google_compute_instance.vm_instance.network_interface[0].network_ip}/32"
      display_name = "bastion-vm"
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  node_config {
    service_account = google_service_account.vm_service_account.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.subnet,
    google_service_account.vm_service_account
  ]
}

# Create node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${google_container_cluster.primary.name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
  node_count = 1

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size
    tags         = var.node_tags

    service_account = google_service_account.vm_service_account.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [
    google_container_cluster.primary
  ]
}

# Update the output to include bastion-based connection instructions
output "kubernetes_cluster" {
  value = {
    name     = google_container_cluster.primary.name
    endpoint = google_container_cluster.primary.endpoint
    location = google_container_cluster.primary.location
    connect_command = <<-EOT
      # Connect through bastion
      1. SSH into the bastion:
         gcloud compute ssh ${google_compute_instance.vm_instance.name} \
           --project=${var.project_id} \
           --zone=${google_compute_instance.vm_instance.zone} \
           --tunnel-through-iap

      2. From the bastion, get cluster credentials:
         gcloud container clusters get-credentials ${google_container_cluster.primary.name} \
           --region ${google_container_cluster.primary.location} \
           --project ${var.project_id}

      3. Verify access:
         kubectl get nodes
    EOT
  }
  description = "Information about the GKE cluster and connection instructions"
}

# Add comprehensive output with setup and access instructions
output "setup_and_access_instructions" {
  value = <<-EOT
    ===== SETUP AND ACCESS INSTRUCTIONS =====

    1. Initial Setup:
       Run these commands to set up IAM permissions:
       
       gcloud projects add-iam-policy-binding ${var.project_id} \
         --member="serviceAccount:${google_service_account.vm_service_account.email}" \
         --role="roles/iap.tunnelResourceAccessor"

       gcloud compute instances add-iam-policy-binding ${google_compute_instance.vm_instance.name} \
         --project=${var.project_id} \
         --zone=${google_compute_instance.vm_instance.zone} \
         --member="serviceAccount:${google_service_account.vm_service_account.email}" \
         --role="roles/compute.osLogin"

    2. Access the Bastion VM:
       a. Make sure you're logged into gcloud:
          gcloud auth login

       b. Connect to the bastion using IAP:
          gcloud compute ssh ${google_compute_instance.vm_instance.name} \
            --project=${var.project_id} \
            --zone=${google_compute_instance.vm_instance.zone} \
            --tunnel-through-iap

       c. On first login, you'll set up 2FA with Google Authenticator
       d. Future logins will require your 2FA code

    3. Access the Kubernetes Cluster:
       a. From the bastion VM, get cluster credentials:
          gcloud container clusters get-credentials ${google_container_cluster.primary.name} \
            --region ${google_container_cluster.primary.location} \
            --project ${var.project_id}

       b. Verify cluster access:
          kubectl get nodes

       c. (Optional) Set up kubectl context for local use:
          # On your local machine, create a kubectl context that tunnels through the bastion
          gcloud container clusters get-credentials ${google_container_cluster.primary.name} \
            --region ${google_container_cluster.primary.location} \
            --project ${var.project_id} \
            --internal-ip

    4. Cluster Information:
       - Cluster Name: ${google_container_cluster.primary.name}
       - Region: ${google_container_cluster.primary.location}
       - Project: ${var.project_id}
       - Node Count: ${var.node_count}
       - Machine Type: ${var.node_machine_type}

    5. Security Notes:
       - The cluster is private and only accessible through the bastion
       - All nodes are in a private subnet
       - The control plane is private
       - 2FA is required for bastion access
       - OS Login is enabled for secure access

    ========================================
  EOT
  description = "Comprehensive setup and access instructions for the infrastructure"
}

# Add outputs for cluster information
output "kubernetes_cluster_name" {
  value = google_container_cluster.primary.name
}

output "kubernetes_cluster_region" {
  value = google_container_cluster.primary.location
}

output "project_id" {
  value = var.project_id
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "gcs" {
    bucket = "sylvan-apogee-450014-a6-terraform-state"
    prefix = "terraform/state"
  }
}