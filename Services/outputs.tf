output "gke_cluster_name" {
  value       = module.gke.cluster_name
  description = "GKE Cluster Name for ConnectHealth deployment."
}

output "gke_cluster_endpoint" {
  value       = module.gke.cluster_endpoint
  description = "GKE Cluster control plane IP endpoint."
}

output "gke_cluster_location" {
  value       = module.gke.location
  description = "GKE Cluster location (region)."
}

# GCP Marketplace Solutions Page standardized outputs
output "service_url" {
  value       = "Deploy ConnectHealth via Marketplace GKE package into cluster: ${module.gke.cluster_name}"
  description = "The URL to access the ConnectHealth application."
}

output "default_username" {
  value       = "admin"
  description = "The initial administrator username."
}

output "default_password_secret" {
  value       = module.secret_manager.admin_initial_password_secret_id
  description = "Secret Manager Secret ID holding the initial administrator password."
}

output "admin_initial_password_secret_id" {
  value       = module.secret_manager.admin_initial_password_secret_id
  description = "Secret Manager Secret ID holding the initial administrator password."
}

output "run_sa_email" {
  value       = module.iam.run_sa_email
  description = "GCP Service Account email for Workload Identity."
}

output "gcp_service_account_email" {
  value       = module.iam.run_sa_email
  description = "GCP Service Account email to bind in Kubernetes values.yaml for Workload Identity."
}

output "kms_key_id" {
  value = module.kms.key_id
}

# --- Values the Helm chart needs at install time (see README "Deploying the
# application" - these three feed directly into the chart's values.yaml) ---
output "ingress_static_ip_name" {
  value       = google_compute_global_address.ingress_ip.name
  description = "Pass as ingress.staticIpName in the Helm chart - becomes the Ingress's kubernetes.io/ingress.global-static-ip-name annotation."
}

output "ingress_static_ip_address" {
  value       = google_compute_global_address.ingress_ip.address
  description = "Point the application's DNS A record at this IP BEFORE deploying the chart with a managed certificate - Google cannot finish provisioning the cert until the domain already resolves here."
}

output "cloud_armor_policy_name" {
  value       = var.enable_cloud_armor ? module.cloud_armor[0].security_policy_name : null
  description = "Pass as cloudArmor.securityPolicyName in the Helm chart - attached to the Ingress backend via the BackendConfig CRD. Null when enable_cloud_armor is false; leave the chart's cloudArmor.securityPolicyName empty in that case."
}

output "flows_bucket_name" {
  value       = module.storage.flows_bucket_name
  description = "Feeds the Helm chart's config.gcsBucketName (container env GCS_BUCKET_NAME / GCP_STORAGE_BUCKET_NAME)."
}

output "audit_logs_bucket_name" {
  value = module.audit_logging.audit_logs_bucket_name
}

output "firestore_database_name" {
  value       = module.firestore.database_name
  description = "Feeds the Helm chart's config.firestoreContextDatabase (container env GCP_CONTEXT_DATABASE). Must be set explicitly - the app otherwise falls back to Firestore's \"(default)\" database, which this stack never creates, and the Node-RED context store fails at startup with gRPC 5 NOT_FOUND."
}

output "container_sync_topic_name" {
  value       = module.pubsub.container_sync_topic_name
  description = "Feeds the Helm chart's config.pubsubTopicId (container env GCP_PUBSUB_TOPIC_ID / GCP_SYNC_TOPIC_NAME)."
}

output "alerts_topic_name" {
  value = module.pubsub.alerts_topic_name
}

output "secret_name_prefix" {
  value       = module.secret_manager.secret_name_prefix
  description = "Feeds the Helm chart's GCP_SECRET_BASE_PREFIX - the Secret Manager name prefix the app creates and reads its own secrets under."
}

# --- Application log buckets, consumed by the Helm chart ---
output "app_audit_log_bucket" {
  value       = module.audit_logging.app_audit_log_bucket
  description = "Set as the Helm chart's config.auditLog.bucket (container env GCP_AUDIT_LOG_BUCKET)."
}

output "app_operational_log_bucket" {
  value       = module.audit_logging.app_operational_log_bucket
  description = "Set as config.applicationLog.bucket (container env GCP_APPLICATION_LOG_BUCKET)."
}

output "app_log_bucket_location" {
  value       = module.audit_logging.app_log_bucket_location
  description = "Set as config.auditLog.location AND config.applicationLog.location. A mismatch makes the app's log queries silently return nothing."
}

output "app_audit_log_name" {
  value       = module.audit_logging.app_audit_log_name
  description = "Set as config.auditLog.logName (container env GCP_AUDIT_LOG_NAME)."
}

# --- Application domain / TLS, consumed by the Helm chart ------------------
output "app_domain" {
  value       = var.app_domain
  description = "Hostname the app is served on. Set as the chart's ingress.hosts[0].host AND ingress.managedCertificate.domains[0]. Empty means HTTP on the bare LB IP."
}

output "app_url" {
  value       = var.app_domain != "" ? "https://${var.app_domain}" : "http://${google_compute_global_address.ingress_ip.address}"
  description = "Where the application will be reachable once deployed."
}

output "tls_enabled" {
  value       = var.app_domain != ""
  description = "Whether a managed certificate will be requested. Drives the chart's ingress.managedCertificate.enabled, ingress.httpsRedirect, and config.environment (production only makes sense with TLS - see the app_domain variable for why)."
}

output "dns_record_managed_by_terraform" {
  value       = var.app_domain != "" && var.dns_managed_zone != ""
  description = "False means you must create the A record yourself, pointing app_domain at ingress_static_ip_address, BEFORE deploying the chart."
}

output "ssl_certificate_name" {
  value       = var.ssl_certificate_name
  description = "Set as the chart's ingress.preSharedCertName. When empty, set ingress.managedCertificate.enabled = true instead and let GKE issue the certificate."
}
