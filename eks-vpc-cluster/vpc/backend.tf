# Параметри навмисно не зберігаються в Git. Перед init скопіюйте
# backend.hcl.example у backend.hcl і впишіть назву власного S3 bucket.
terraform {
  backend "s3" {}
}

