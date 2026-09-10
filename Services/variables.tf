variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east1"
}

variable "zone" {
  description = "Zone for zonal resources."
  type        = string
  default     = "us-east1-b"
}

variable "name_prefix" {
  type    = string
  default = "connecthealth-prod"
}

variable "project_name" {
  type    = string
  default = "connecthealth"
}

variable "environment" {
  type    = string
  default = "production"
}

# --- Remote state or direct module overrides ---
variable "network_state_bucket" {
  description = "GCS bucket where the Network stack's remote state is stored (leave null when passing direct network overrides)."
  type        = string
  default     = null
}

variable "network_state_prefix" {
  description = "Prefix for the Network stack's remote state object."
  type        = string
  default     = "network/prod"
}

variable "network_id_override" {
  description = "Direct override for VPC Network ID (bypasses remote state when using unified root module)."
  type        = string
  default     = null
}

variable "private_subnet_id_override" {
  description = "Direct override for Private Subnet ID."
  type        = string
  default     = null
}

# --- Audit (matches CF CreateCloudTrail) ---
variable "enable_audit_trail" {
  type    = bool
  default = true
}

# --- Cloud Armor WAF (replaces AWS WebACL) ---
# When true, creates the WAF policy (OWASP CRS rules, per-IP rate limiting,
# malicious-IP reputation blocking). It is attached to the application's
# Ingress load balancer by the Helm chart's BackendConfig, using this stack's
# `cloud_armor_policy_name` output - so leaving this false means that output
# is null and the chart's cloudArmor.securityPolicyName should stay empty.
variable "enable_cloud_armor" {
  description = "Create a Cloud Armor WAF security policy for the application's Ingress load balancer."
  type        = bool
  default     = true
}

variable "labels" {
  type = map(string)
  default = {
    environment = "production"
    project     = "connecthealth"
    layer       = "services"
    compliance  = "hipaa-gdpr-soc2"
  }
}

# --- GKE (the only deployment target - Cloud Run support removed) ---
variable "pods_range_name_override" {
  description = "Override for GKE Pods secondary IP range name."
  type        = string
  default     = null
}

variable "services_range_name_override" {
  description = "Override for GKE Services secondary IP range name."
  type        = string
  default     = null
}

# --- Workload Identity binding target (must match the Kubernetes ServiceAccount
# the Helm chart creates - see dev/helm/values.yaml serviceAccount block and
# dev/helm/templates/serviceaccount.yaml) ---
variable "gke_ksa_namespace" {
  description = "Kubernetes namespace of the KSA that authenticates as run_sa via Workload Identity."
  type        = string
  default     = "default"
}

variable "gke_ksa_name" {
  description = "Kubernetes ServiceAccount name that authenticates as run_sa via Workload Identity."
  type        = string
  default     = "connecthealth-be"
}

# --- Application log retention (see modules/audit-logging) ---
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
  description = "Cloud Logging log name the application writes its audit trail to. Must match the container's GCP_AUDIT_LOG_NAME."
  type        = string
  default     = "ehrconnect-audit"
}

variable "gke_container_name" {
  description = "Container name, used to scope the operational-log sink. Must match the Helm chart's container name."
  type        = string
  default     = "connecthealth-be"
}

variable "alert_email" {
  description = "Email address for operational alerts (replaces AWS AlertEmail / SNSEmailSubscription). Empty disables the notification channel, and the alert policies then fire with nowhere to deliver."
  type        = string
  default     = ""
}

# --- Application domain / TLS ---------------------------------------------
# The hostname the application is served on. Supplying it turns on the whole
# TLS path: the Helm chart requests a Google-managed certificate for it, binds
# the Ingress to the reserved static IP, and redirects HTTP to HTTPS.
#
# Leave EMPTY to run on the bare load-balancer IP over plain HTTP. That is a
# valid testing mode, but note it forces the application's ENVIRONMENT to
# "development": the backend hardcodes an https:// scheme whenever ENVIRONMENT
# is "production", so on an HTTP-only deployment the workflow editor's iframe
# points at a port nothing is listening on. Running "development" in turn makes
# the app resolve its Node-RED UI assets from src/ rather than dist/, which the
# runtime image does not ship - so /api/workflow-engine/base-ui-components.js
# and twiml-editor-widget.js return 404. Supplying a domain here resolves both.
variable "app_domain" {
  description = "Fully-qualified hostname the application is served on, e.g. app.example.com. REQUIRED - the application only supports HTTPS, so there is no valid deployment without a domain to issue a certificate for. A DNS A record for this name must resolve to the ingress static IP before the application is installed, or the Google-managed certificate cannot be validated."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.app_domain))
    error_message = "app_domain must be a fully-qualified lowercase hostname such as app.example.com. It cannot be empty: the application is HTTPS-only and will not function when served over plain HTTP on a bare IP."
  }
}

# When the domain's DNS is hosted in this project's Cloud DNS, Terraform can
# create the A record itself and the routing becomes fully automatic. When DNS
# lives elsewhere (registrar, Route 53, another project), leave this empty and
# create the record by hand from the ingress_static_ip_address output.
variable "dns_managed_zone" {
  description = "Cloud DNS managed zone name in THIS project that hosts app_domain. Set to have Terraform create the A record automatically. Empty = create the record yourself."
  type        = string
  default     = ""
}

# Certificate that already exists in GCP as a compute SSL certificate,
# referenced by NAME. The Helm chart attaches it to the Ingress with the
# ingress.gcp.kubernetes.io/pre-shared-cert annotation.
#
# Use this when the certificate is managed outside this stack. Leave empty to
# have GKE create and renew a Google-managed certificate instead, which
# requires app_domain's DNS to already resolve to the ingress IP.
#
# Nothing validates the name at deploy time: if it does not exist, the load
# balancer comes up with no certificate and HTTPS simply fails.
variable "ssl_certificate_name" {
  description = "Name of a pre-existing GCP SSL certificate to serve on the Ingress, e.g. \"connecthealth\". Empty = have GKE create a Google-managed certificate for app_domain."
  type        = string
  default     = ""
}

variable "admin_initial_password" {
  description = "Initial password for the built-in 'administrator' account (the GCP equivalent of the AWS template's AdminInitialPassword parameter). Minimum 8 characters. Leave empty to auto-generate a strong random password. Either way it is stored in Secret Manager and named by the default_password_secret output; the application forces a password change at first login."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.admin_initial_password == "" || length(var.admin_initial_password) >= 8
    error_message = "admin_initial_password must be at least 8 characters, or empty to auto-generate."
  }
}

variable "enable_deletion_protection" {
  description = "Guard the stack's data-bearing resources - the GKE cluster, PHI flows bucket, audit-log bucket and LB access-log bucket - against deletion. FALSE by default, deliberately: a customer deploys this blueprint from a read-only source in another project and can only pass parameters, so a guard they cannot turn off makes every teardown a dead end. Set true for an environment holding real data, and be aware that clearing it later requires an apply BEFORE a delete will succeed, because these are resource attributes read from Terraform state rather than from configuration."
  type        = bool
  default     = false
}
