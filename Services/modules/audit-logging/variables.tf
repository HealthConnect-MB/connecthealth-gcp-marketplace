variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "kms_key_id" {
  type = string
}

variable "enable_audit_trail" {
  description = "Matches CF CreateCloudTrail (default true). Set false only if org-wide log export already covers this project, to avoid duplicate export/storage cost - same rationale as the AWS parameter's guidance."
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "Matches CloudTrailLogGroup RetentionInDays: 2557 / CloudTrailBucket ExpirationInDays: 2555."
  type        = number
  default     = 2555
}

variable "labels" {
  type = map(string)
}

# --- Application log retention (Cloud Logging buckets) ---
# Distinct from the CloudTrail-equivalent GCS export above. Two things the app
# itself reads back through the Logging API:
#   * its own audit trail  (log name below)
#   * its operational/container logs
# Both otherwise land in the project's _Default bucket at 30-day retention.
# AWS kept the equivalent CloudWatch log groups at 2192 and 365 days, so the
# _Default fallback is a large reduction that is easy to miss.
variable "app_log_retention_days" {
  description = "Retention for the OPERATIONAL Cloud Logging bucket (container/application logs the in-app log screen reads). Mirrors the AWS template's CloudWatchLogGroup RetentionInDays: 365."
  type        = number
  default     = 365
}

variable "audit_log_retention_days" {
  description = "Retention for the AUDIT Cloud Logging bucket. Mirrors the AWS template's AuditLogGroup RetentionInDays: 2192 (~6 years), which is the HIPAA audit-retention requirement - do not lower this without a documented reason."
  type        = number
  default     = 2192
}

variable "app_audit_log_name" {
  description = "Cloud Logging log name the application writes its audit trail to. Must match the container's GCP_AUDIT_LOG_NAME (default 'ehrconnect-audit' in gcpAuditLogStore.service.ts)."
  type        = string
  default     = "ehrconnect-audit"
}

variable "gke_cluster_name" {
  description = "Cluster name used to scope the operational-log sink to this app's containers. Always supplied by module.gke - the stack has no deployment mode without a cluster, so there is no empty case to guard against."
  type        = string
}

variable "gke_namespace" {
  description = "Kubernetes namespace the application runs in, used to scope the operational-log sink."
  type        = string
  default     = "default"
}

variable "gke_container_name" {
  description = "Container name used to scope the operational-log sink."
  type        = string
  default     = "connecthealth-be"
}

variable "enable_deletion_protection" {
  description = "When true, the audit-log bucket refuses to be destroyed while it still holds objects. False by default so a customer teardown succeeds unattended; exported audit data is also written to the separate GCS archive bucket by the audit sink, so this bucket is not the only copy."
  type        = bool
  default     = false
}
