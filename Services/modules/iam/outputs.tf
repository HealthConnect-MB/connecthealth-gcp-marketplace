output "run_sa_email" {
  value = google_service_account.run_sa.email
}

output "run_sa_member" {
  value       = "serviceAccount:${google_service_account.run_sa.email}"
  description = "Pre-formatted for use in other modules' IAM bindings."
}

output "run_sa_id" {
  value = google_service_account.run_sa.id
}
