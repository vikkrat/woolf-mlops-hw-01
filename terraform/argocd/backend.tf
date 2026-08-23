terraform {
  # Backend values are supplied through backend.hcl and are intentionally
  # excluded from Git. Use backend.hcl.example as a template.
  backend "s3" {}
}

