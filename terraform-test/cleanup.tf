# Cleanup resource to remove SSH keys when destroying
resource "null_resource" "cleanup" {
  triggers = {
    instance_id = google_compute_instance.vm_instance.id
    ssh_key_path = var.ssh_key_path
  }

  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      # Remove OS Login SSH keys
      gcloud compute os-login ssh-keys list | ForEach-Object {
        if ($_ -match "fingerprint: (.*)") {
          gcloud compute os-login ssh-keys remove --key $matches[1]
        }
      }
      
      # Remove local SSH keys
      if (Test-Path ${self.triggers.ssh_key_path}) {
        Remove-Item ${self.triggers.ssh_key_path}
        Remove-Item ${self.triggers.ssh_key_path}.pub
      }
    EOT
    interpreter = ["PowerShell", "-Command"]
  }
} 