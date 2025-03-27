#!/bin/bash

echo "Checking Terraform state..."

# Initialize Terraform
terraform init

# Check state
terraform show

# List resources in state
terraform state list

# Check specific resource
terraform state show google_compute_instance.vm_instance

# Verify plan doesn't show changes
terraform plan -no-color > plan.txt
if grep -q "No changes" plan.txt; then
  echo "✅ State is up to date"
else
  echo "❌ State needs updating"
  cat plan.txt
fi 