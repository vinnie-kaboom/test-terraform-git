output "connection_details" {
  value = {
    instance_name = google_compute_instance.vm_instance.name
    public_ip     = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
    zone          = google_compute_instance.vm_instance.zone
    ssh_key_path  = "~/.ssh/google_compute_engine"
    setup_instructions = <<-EOT
      1. Install Google Authenticator app on your phone
      2. SSH into the VM using the command below (you'll set up 2FA on first login)
      3. Future connections will require both SSH key and 2FA code
      
      SSH Command will be provided after the OS Login username is generated
    EOT
  }
}

output "ssh_command" {
  value = "Will be available after SSH key setup"
  depends_on = [null_resource.ssh_key_setup]
} 