output "flows_bucket_name" {
  value = google_storage_bucket.flows.name
}

output "flows_bucket_url" {
  value = google_storage_bucket.flows.url
}

output "lb_logs_bucket_name" {
  value = google_storage_bucket.lb_logs.name
}
