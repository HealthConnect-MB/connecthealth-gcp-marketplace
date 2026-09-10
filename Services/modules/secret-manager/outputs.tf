output "secret_name_prefix" {
  value       = "connecthealth-${var.name_prefix}-${var.environment}"
  description = "Prefix the app must use for every secret name it creates at runtime, matching the scoped IAM condition."
}

output "admin_initial_password_secret_id" {
  value       = google_secret_manager_secret.admin_initial_password.id
  description = "Secret Manager Secret ID holding the initial administrator password."
}

