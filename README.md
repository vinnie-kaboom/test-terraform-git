# test-terraform-git

## Working with Encrypted State Files

The Terraform state files are encrypted using GPG before being committed to the repository.

### Local Development

1. Set the encryption password:
```bash
export ENCRYPTION_PASSWORD='your-secure-password'
```

2. Decrypt state files before running Terraform:
```bash
./scripts/manage-state.sh decrypt
terraform plan
```

3. Encrypt state files before committing:
```bash
./scripts/manage-state.sh encrypt
git add *.tfstate.gpg
git commit -m "Update state"
```

### Important Notes
- Never commit unencrypted state files
- Keep the encryption password secure
- Store the encryption password in GitHub Secrets as ENCRYPTION_PASSWORD