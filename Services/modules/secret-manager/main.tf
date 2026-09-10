# Replaces TaskRole's RestrictedSecretsManagerAccess statement. AWS granted
# CreateSecret/UpdateSecret/DeleteSecret/PutSecretValue (the app itself
# manages its own secrets at runtime under the connecthealth-<stack>-<env>/*
# prefix) rather than Terraform pre-creating fixed secrets. Same model here:
# grant the service account a custom role scoped by an IAM condition on the
# name prefix, so it can create/read/update/delete secrets matching
# "connecthealth-<name_prefix>-<environment>-*" without a project-wide
# roles/secretmanager.admin grant.
resource "google_project_iam_custom_role" "secret_manager_scoped" {
  project     = var.project_id
  role_id     = replace("${var.name_prefix}_secret_admin_scoped", "-", "_")
  title       = "ConnectHealth scoped Secret Manager admin"
  description = "Full lifecycle on connecthealth-* secrets only, via IAM condition. Mirrors AWS TaskRole's RestrictedSecretsManagerAccess."
  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.get",
    "secretmanager.secrets.update",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.list",
    "secretmanager.versions.add",
    "secretmanager.versions.access",
    "secretmanager.versions.get",
    "secretmanager.versions.list",
    "secretmanager.versions.disable",
    "secretmanager.versions.destroy",
  ]
}

resource "google_project_iam_member" "secret_manager_scoped_binding" {
  project = var.project_id
  role    = google_project_iam_custom_role.secret_manager_scoped.id
  member  = var.run_sa_member

  condition {
    title       = "connecthealth-secret-prefix-only"
    description = "Restricts to secrets named ${var.name_prefix}-${var.environment}/*, matching AWS's Resource ARN scoping."
    # name_prefix is already "connecthealth-<env>" (see envs/<env>/terraform.tfvars) -
    # prepending a literal "connecthealth-" here duplicated it into
    # "connecthealth-connecthealth-dev-dev-*", which no real secret the app
    # creates would ever match.
    expression = "resource.name.startsWith(\"projects/${var.project_id}/secrets/${var.name_prefix}-${var.environment}\")"
  }
}

# Replaces the RestrictedSecretsManagerAccess statement's separate
# "secretsmanager:ListSecrets on Resource: *" allowance (AWS could not scope
# ListSecrets to a prefix). GCP's secretmanager.secrets.list above is already
# part of the scoped custom role/condition, so no extra project-wide grant is
# needed here - a tightening relative to the AWS original, not a gap.

# The application seeds its built-in "administrator" account from
# ADMIN_INITIAL_PASSWORD on first boot (see ensureAdminAccount() in the app),
# exactly as it does on AWS where the value comes from the AdminInitialPassword
# CloudFormation parameter. This is the GCP equivalent of that parameter: set
# admin_initial_password in terraform.tfvars, or supply it in the Infrastructure
# Manager / Marketplace deployment form.
#
# Left empty, Terraform generates a strong random password instead - convenient,
# but the deployer then has to read it back out of Secret Manager before the
# first login, so an explicitly-supplied value is usually what you want.
resource "random_password" "admin_initial" {
  count            = var.admin_initial_password == "" ? 1 : 0
  length           = 24
  special          = true
  override_special = "!@#$%^&*"
}

locals {
  admin_initial_password = var.admin_initial_password != "" ? var.admin_initial_password : random_password.admin_initial[0].result
}

resource "google_secret_manager_secret" "admin_initial_password" {
  project   = var.project_id
  secret_id = "${var.name_prefix}-${var.environment}-admin-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "admin_initial_password" {
  secret      = google_secret_manager_secret.admin_initial_password.id
  secret_data = local.admin_initial_password
}

