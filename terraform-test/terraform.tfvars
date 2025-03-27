project_id           = "sylvan-apogee-450014-a6"
region               = "us-central1"
zone                 = "us-central1-a"
instance_name        = "bastion"
machine_type         = "e2-micro"
network_name         = "vpc"
allowed_ssh_ranges   = ["35.235.240.0/20"]
github_repo          = "vinnie-kaboom/test-terraform-git"
iap_authorized_users = [
  "user:vincent.zamora@gmail.com"  
]
service_account_email = "workload-identity-sa@sylvan-apogee-450014-a6.iam.gserviceaccount.com"
service_account_id    = "workload-identity-sa"
user_email            = "vincent.zamora@gmail.com"