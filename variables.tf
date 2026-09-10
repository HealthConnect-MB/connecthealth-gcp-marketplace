# ==============================================================================
# ConnectHealth - Google Cloud Marketplace Variables (variables.tf)
# GKE-only: Cloud Run / hl7-worker / cloud-armor / load-balancer / monitoring
# / standalone-Filestore variables were removed along with that support - see
# Services/main.tf and Services/variables.tf for details.
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud project ConnectHealth will deploy into."
  type        = string
}

variable "region" {
  description = "The primary Google Cloud region for deployment (e.g. us-east1)."
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "Zone for zonal resources."
  type        = string
  default     = "us-east1-b"
}

variable "name_prefix" {
  description = "Prefix for resource naming."
  type        = string
  default     = "connecthealth-prod"
}

variable "project_name" {
  description = "Project name used for labeling and resource identification."
  type        = string
  default     = "connecthealth"
}

variable "environment" {
  description = "Target deployment environment (e.g. production, dev)."
  type        = string
  default     = "production"
}

# --- Alerting & Audit ---
variable "enable_audit_trail" {
  description = "Enable Data Access audit logging exported to GCS bucket."
  type        = bool
  default     = true
}

variable "enable_cloud_armor" {
  description = "Create a Cloud Armor WAF security policy (OWASP rules, rate limiting, malicious-IP blocking) for the application's Ingress load balancer. Attach it by passing the cloud_armor_policy_name output into the Helm chart's cloudArmor.securityPolicyName."
  type        = bool
  default     = true
}

# --- HL7 Connectivity (Network-level foundation only - NCC hub, dedicated
# subnet, firewall rules. The Cloud Run HL7 worker pool that used to consume
# this was removed with the rest of Cloud Run support; this flag still
# stands up the main-stack network side for a future GKE-based listener.) ---
variable "enable_hl7_connectivity" {
  type    = bool
  default = false
}

variable "connector_supernet_cidr" {
  description = "Supernet covering all connector VPCs (default 100.64.0.0/12)."
  type        = string
  default     = "100.64.0.0/12"
}

variable "hl7_subnet_cidr" {
  description = "Dedicated subnet CIDR for HL7 worker pool ingress."
  type        = string
  default     = "172.28.6.0/27"
}

# --- VPC Addressing (AWS Parity: 172.28.0.0/16) ---
variable "vpc_cidr_block" {
  description = "CIDR block for the primary VPC."
  type        = string
  default     = "172.28.0.0/16"
}

variable "private_subnet_cidr" {
  description = "CIDR for the application's private subnet. One subnet is all that's needed: GCP subnets are regional and span every zone in the region, so this single subnet gives the same multi-zone coverage AWS needed two zonal subnets (PrivateSubnet1 + PrivateSubnet2) to achieve."
  type        = string
  default     = "172.28.1.0/24"
}

variable "filestore_reserved_range_cidr" {
  description = "Reserved CIDR range for Filestore private service access. Still needed even though the standalone Filestore instance module was removed - GKE's dynamically-provisioned Filestore (via the CSI driver) uses this same private-services-access peering."
  type        = string
  default     = "172.28.5.0/24"
}

variable "enable_cloud_nat" {
  description = "Enable Cloud NAT for private subnet egress."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs on private subnet."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Resource labels."
  type        = map(string)
  default = {
    environment = "production"
    project     = "connecthealth"
    compliance  = "hipaa-gdpr-soc2"
  }
}

# --- GKE ---
variable "pods_cidr_block" {
  description = "Secondary CIDR block for GKE Pods."
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr_block" {
  description = "Secondary CIDR block for GKE Services."
  type        = string
  default     = "10.8.0.0/20"
}

# --- Application domain / TLS ---------------------------------------------
variable "app_domain" {
  description = "Fully-qualified hostname the application is served on, e.g. app.example.com. REQUIRED - the application only supports HTTPS, so there is no valid deployment without a domain to issue a certificate for. A DNS A record for this name must resolve to the ingress static IP before the application is installed, or the Google-managed certificate cannot be validated."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.app_domain))
    error_message = "app_domain must be a fully-qualified lowercase hostname such as app.example.com. It cannot be empty: the application is HTTPS-only and will not function when served over plain HTTP on a bare IP."
  }
}

variable "ssl_certificate_name" {
  description = "Name of a pre-existing GCP SSL certificate to serve on the Ingress. Empty = have GKE create a Google-managed certificate for app_domain."
  type        = string
  default     = ""
}

variable "dns_managed_zone" {
  description = "Cloud DNS managed zone in this project hosting app_domain. Set to have Terraform create the A record automatically; empty means you create it yourself."
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

variable "alert_email" {
  description = "Email address for operational alerts - the equivalent of the AWS template's AlertEmail parameter, which fed an SNS email subscription. This stack creates 11 alert policies (CPU, memory, load-balancer 5xx and latency, Firestore volume and latency, Pub/Sub backlog, oldest-message age, send-rate spike, subscription-created). Left empty, no notification channel is created and every one of those policies evaluates and fires with nowhere to deliver - so a deployment that skips this is silently unmonitored."
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Guard the stack's data-bearing resources - the GKE cluster, PHI flows bucket, audit-log bucket and LB access-log bucket - against deletion. FALSE by default so a deployment can always be removed from the Infrastructure Manager console without editing the blueprint. Set true for an environment holding real data; clearing it later needs an apply before a delete will succeed."
  type        = bool
  default     = false
}
