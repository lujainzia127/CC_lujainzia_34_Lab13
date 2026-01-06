#######################################
# Terraform Backend (S3 Remote State)
#######################################
terraform {
  backend "s3" {
    bucket       = "myapp-s3-bucket-demo1"
    key          = "myapp/terraform.tfstate"
    region       = "me-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

#######################################
# AWS Provider
#######################################
provider "aws" {
  shared_config_files      = ["~/.aws/config"]
  shared_credentials_files = ["~/.aws/credentials"]
}

#######################################
# IAM Group
#######################################
resource "aws_iam_group" "developers" {
  name = "developers"
  path = "/groups/"
}

output "group_details" {
  value = {
    group_name = aws_iam_group.developers.name
    group_arn  = aws_iam_group.developers.arn
    unique_id  = aws_iam_group.developers.unique_id
  }
}

#######################################
# IAM Group Policies
#######################################
resource "aws_iam_group_policy_attachment" "developer_ec2_fullaccess" {
  group      = aws_iam_group.developers.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_group_policy_attachment" "change_password" {
  group      = aws_iam_group.developers.name
  policy_arn = "arn:aws:iam::aws:policy/IAMUserChangePassword"
}

#######################################
# Task 7 — Create Multiple IAM Users from CSV
#######################################
resource "aws_iam_user" "users" {
  for_each = { for user in local.users : user.user_name => user }

  name          = each.value.user_name
  path          = "/users/"
  force_destroy = true

  tags = {
    DisplayName = each.value.user_name
    CreatedBy   = "Terraform"
  }
}

#######################################
# Add All Users to Developers Group
#######################################
resource "aws_iam_user_group_membership" "users_membership" {
  for_each = aws_iam_user.users

  user = each.value.name
  groups = [
    aws_iam_group.developers.name
  ]
}

#######################################
# Create Login Profiles for All Users
#######################################
resource "null_resource" "create_login_profiles" {
  for_each = aws_iam_user.users

  triggers = {
    password_hash = sha256(var.iam_password)
    user          = each.value.name
  }

  depends_on = [aws_iam_user.users]

  provisioner "local-exec" {
    command = "${path.module}/create-login-profile.sh ${each.value.name} '${var.iam_password}'"
  }
}

#######################################
# Create Access Keys for All Users
#######################################
resource "aws_iam_access_key" "users_access_keys" {
  for_each = aws_iam_user.users
  user     = each.value.name
}

#######################################
# Outputs — User Details
#######################################
output "all_users_details" {
  value = {
    for user_name, user in aws_iam_user.users : user_name => {
      user_arn       = user.arn
      user_unique_id = user.unique_id
      access_key_id  = aws_iam_access_key.users_access_keys[user_name].id
    }
  }
}

#######################################
# Outputs — Access Key Secrets (Sensitive)
#######################################
output "all_access_key_secrets" {
  value = {
    for user_name, key in aws_iam_access_key.users_access_keys :
    user_name => key.secret
  }
  sensitive = true
}
