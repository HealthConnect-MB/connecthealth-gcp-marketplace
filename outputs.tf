# ==============================================================================
# ConnectHealth - Google Cloud Marketplace Root Outputs (outputs.tf)
# Standardized outputs rendered on the Google Cloud Marketplace Solutions page.
# GKE-only: Cloud Run / load-balancer / HL7-worker / Filestore outputs were
# removed along with that support - see Services/outputs.tf for details.
# ==============================================================================

# --- Marketplace GKE Deployment Outputs (Prerequisites for Marketplace App) ---
output "gke_cluster_name" {
  value       = module.services.gke_cluster_name
  description = "Name of the GKE Cluster to select in GCP Marketplace deployment UI."
}

output "gke_cluster_endpoint" {
  value       = module.services.gke_cluster_endpoint
  description = "Control plane IP endpoint of the GKE Cluster."
}

output "gke_cluster_location" {
  value       = module.services.gke_cluster_location
  description = "Region/Location of the GKE Cluster."
}

output "gcp_service_account_email" {
  value       = module.services.gcp_service_account_email
  description = "GCP Service Account email for Workload Identity binding in Marketplace Helm values.yaml."
}

output "flows_bucket_name" {
  value       = module.services.flows_bucket_name
  description = "GCS Bucket name for ConnectHealth flow data storage."
}

output "vpc_network_name" {
  value       = module.vpc.network_name
  description = "VPC Network name."
}

output "private_subnet_id" {
  value       = module.vpc.private_subnet_id
  description = "Regional private subnet ID. GCP subnets span all zones in the region, so this single subnet backs the GKE cluster's nodes across every zone."
}

# --- Step 14 Required Output: service_url ---
output "service_url" {
  value       = module.services.service_url
  description = "The URL or access instruction to ConnectHealth application."
}

# Step 14 Required Output: default_username
output "default_username" {
  value       = module.services.default_username
  description = "The initial administrator username."
}

# Step 14 Required Output: default_password_secret
output "default_password_secret" {
  value       = module.services.default_password_secret
  description = "A reference to the initial administrator password, stored securely in Secret Manager."
}

output "kms_key_id" {
  value       = module.services.kms_key_id
  description = "Resource ID of the CMEK compliance key."
}

# --- Values needed when installing the ConnectHealth Marketplace Helm app
# into the cluster this stack created ---
output "ingress_static_ip_address" {
  value       = module.services.ingress_static_ip_address
  description = "Create a DNS A record for your ConnectHealth domain pointing at this IP BEFORE installing the application, so the Google-managed TLS certificate can validate and provision."
}

output "ingress_static_ip_name" {
  value       = module.services.ingress_static_ip_name
  description = "Set as ingress.staticIpName in the application's Helm values."
}

output "cloud_armor_policy_name" {
  value       = module.services.cloud_armor_policy_name
  description = "Set as cloudArmor.securityPolicyName in the application's Helm values to enforce the WAF on the Ingress load balancer."
}

# --- Remaining values the application's Helm chart needs. Every one of these
# maps to a specific key the container reads at startup; a missing one does
# not fail the deploy, it fails silently at runtime. GCP_CONTEXT_DATABASE is
# the cautionary example: unset, the app falls back to Firestore's
# "(default)" database, which this stack never creates, and the context store
# dies with gRPC "5 NOT_FOUND" while the app otherwise appears healthy. ---
output "firestore_database_name" {
  value       = module.services.firestore_database_name
  description = "Set as config.firestoreContextDatabase in the Helm values (container env GCP_CONTEXT_DATABASE). REQUIRED - the app defaults to Firestore's \"(default)\" database, which this stack does not create."
}

output "container_sync_topic_name" {
  value       = module.services.container_sync_topic_name
  description = "Set as config.pubsubTopicId in the Helm values (container env GCP_PUBSUB_TOPIC_ID / GCP_SYNC_TOPIC_NAME)."
}

output "secret_name_prefix" {
  value       = module.services.secret_name_prefix
  description = "Set as the Helm chart's GCP_SECRET_BASE_PREFIX - the Secret Manager name prefix the app creates and reads its own secrets under."
}

# --- Application log buckets. Set these into the Helm values before installing
# the app, or its audit and log screens silently show only 30 days. ---
output "app_audit_log_bucket" {
  value       = module.services.app_audit_log_bucket
  description = "Helm: config.auditLog.bucket (container env GCP_AUDIT_LOG_BUCKET)."
}

output "app_operational_log_bucket" {
  value       = module.services.app_operational_log_bucket
  description = "Helm: config.applicationLog.bucket (container env GCP_APPLICATION_LOG_BUCKET)."
}

output "app_log_bucket_location" {
  value       = module.services.app_log_bucket_location
  description = "Helm: config.auditLog.location AND config.applicationLog.location. A mismatch makes log queries return nothing rather than failing."
}

output "app_audit_log_name" {
  value       = module.services.app_audit_log_name
  description = "Helm: config.auditLog.logName (container env GCP_AUDIT_LOG_NAME)."
}

# --- Application domain / TLS ---
output "app_url" {
  value       = module.services.app_url
  description = "Where the application is reachable once deployed."
}

output "app_domain" {
  value       = module.services.app_domain
  description = "Helm: ingress.hosts[0].host (and managedCertificate.domains[0] when GKE issues the cert)."
}

output "ssl_certificate_name" {
  value       = module.services.ssl_certificate_name
  description = "Helm: ingress.preSharedCertName."
}

output "dns_record_managed_by_terraform" {
  value       = module.services.dns_record_managed_by_terraform
  description = "False means create the A record yourself, pointing app_domain at ingress_static_ip_address, BEFORE deploying the chart."
}

# Required by the Marketplace deployment form. The Filestore CSI driver
# provisions into this reserved range by NAME (not CIDR) - see the chart's
# filestore.storageClass.reservedIpRange. Without this output a customer has no
# way to supply it except by guessing the naming convention or hunting through
# the console, and a wrong value leaves pods stuck in ContainerCreating with
# MountVolume.MountDevice DeadlineExceeded rather than failing visibly.
output "filestore_reserved_range_name" {
  value       = google_compute_global_address.filestore_range.name
  description = "Name of the reserved private-service-access range Filestore provisions into. Paste into the Marketplace field 'Filestore reserved IP range name'."
}
