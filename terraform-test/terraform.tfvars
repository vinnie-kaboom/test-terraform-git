project_id        = "sylvan-apogee-450014-a6"
region            = "us-central1"
zone              = "us-central1-a"
instance_name     = "bastion"
machine_type      = "e2-micro"
network_name      = "vpc"
allowed_ssh_ranges = ["35.235.240.0/20"]
github_repo  = "vinnie-kaboom/test-terraform-git"
iap_authorized_users = [
  "user:vincent.zamora@gmail.com"  
]