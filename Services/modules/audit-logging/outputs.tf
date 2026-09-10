output "audit_logs_bucket_name" {
  value = var.enable_audit_trail ? google_storage_bucket.audit_logs[0].name : null
}

# --- Feed these into the Helm chart's config.auditLog / config.applicationLog ---
# The container reads them as GCP_AUDIT_LOG_BUCKET / GCP_APPLICATION_LOG_BUCKET
# and their _LOCATION counterparts. Getting the location wrong makes the app's
# log queries return an EMPTY LIST rather than erroring, so a mistake here
# looks like "no records" instead of a failure - always take the location from
# this output rather than typing it.
output "app_audit_log_bucket" {
  value       = var.enable_audit_trail ? google_logging_project_bucket_config.app_audit[0].bucket_id : null
  description = "Cloud Logging bucket holding the application audit trail. Set as the Helm chart's config.auditLog.bucket (container env GCP_AUDIT_LOG_BUCKET)."
}

output "app_operational_log_bucket" {
  value       = var.enable_audit_trail ? google_logging_project_bucket_config.app_operational[0].bucket_id : null
  description = "Cloud Logging bucket holding operational/container logs. Set as config.applicationLog.bucket (container env GCP_APPLICATION_LOG_BUCKET). Null when no cluster name was supplied."
}

output "app_log_bucket_location" {
  value       = var.region
  description = "Location of both application log buckets. Set as config.auditLog.location and config.applicationLog.location - these MUST match or the app's log queries silently return nothing."
}

output "app_audit_log_name" {
  value       = var.app_audit_log_name
  description = "Log name the app writes its audit trail to. Set as config.auditLog.logName (container env GCP_AUDIT_LOG_NAME)."
}
