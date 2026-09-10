data "terraform_remote_state" "network" {
  count   = var.network_state_bucket != null ? 1 : 0
  backend = "gcs"

  config = {
    bucket = var.network_state_bucket
    prefix = var.network_state_prefix
  }
}

locals {
  network_id        = var.network_id_override != null ? var.network_id_override : data.terraform_remote_state.network[0].outputs.network_id
  private_subnet_id = var.private_subnet_id_override != null ? var.private_subnet_id_override : data.terraform_remote_state.network[0].outputs.private_subnet_id
  # No try()/fallback on these two on purpose. They previously fell back to
  # "${var.name_prefix}-pods", which silently produced a name that does NOT
  # match the range the Network stack creates (its name_prefix carries a
  # "-network" suffix), and the failure only surfaced much later as an opaque
  # 'Pod secondary range not found' from the GKE API. Reading straight from
  # remote state means a missing output fails immediately and obviously.
  pods_range_name     = var.pods_range_name_override != null ? var.pods_range_name_override : data.terraform_remote_state.network[0].outputs.pods_range_name
  services_range_name = var.services_range_name_override != null ? var.services_range_name_override : data.terraform_remote_state.network[0].outputs.services_range_name
}


# --- Google-managed service identities needed for CMEK bindings on the KMS key ---
data "google_storage_project_service_account" "gcs" {
  project = var.project_id
}

resource "google_project_service_identity" "pubsub" {
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"
}

module "iam" {
  source = "./modules/iam"

  project_id  = var.project_id
  name_prefix = var.name_prefix
}

module "kms" {
  source = "./modules/kms"

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  labels      = var.labels

  bindings = [
    { role = "roles/cloudkms.cryptoKeyEncrypterDecrypter", member = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}" },
    { role = "roles/cloudkms.cryptoKeyEncrypterDecrypter", member = "serviceAccount:${google_project_service_identity.pubsub.email}" },
    { role = "roles/cloudkms.cryptoKeyDecrypter", member = module.iam.run_sa_member },
  ]
}

module "secret_manager" {
  source = "./modules/secret-manager"

  project_id             = var.project_id
  name_prefix            = var.name_prefix
  environment            = var.environment
  run_sa_member          = module.iam.run_sa_member
  admin_initial_password = var.admin_initial_password
}

module "storage" {
  source = "./modules/storage"

  project_id    = var.project_id
  region        = var.region
  name_prefix   = var.name_prefix
  kms_key_id    = module.kms.key_id
  run_sa_member = module.iam.run_sa_member
  labels        = var.labels

  # Passing kms_key_id only creates a dependency on the KEY, not on the IAM
  # bindings that authorize the GCS service agent to USE that key. Without
  # this, Terraform starts creating CMEK-encrypted buckets in parallel with
  # those bindings and the API rejects them with "Permission denied on Cloud
  # KMS key. Please ensure that your Cloud Storage service account has been
  # authorized to use this key." Depending on the whole module forces the
  # bindings to land first.
  enable_deletion_protection = var.enable_deletion_protection

  depends_on = [module.kms]
}

# Filestore is intentionally NOT a Terraform-managed resource here: this
# environment is GKE-only, and on GKE, Filestore is provisioned dynamically
# per-PVC by the Filestore CSI driver via the Helm chart's StorageClass
# (dev/helm/templates/storageclass.yaml) - the same pattern already backing
# the live connecthealth-nfs-pvc. A standalone google_filestore_instance
# module (used previously, and still appropriate for a Cloud Run deployment,
# which has no CSI driver) was removed since it would only ever be created
# and billed without anything using it, now that Cloud Run support is gone.

module "firestore" {
  source = "./modules/firestore"

  project_id                 = var.project_id
  region                     = var.region
  name_prefix                = var.name_prefix
  run_sa_member              = module.iam.run_sa_member
  enable_deletion_protection = var.enable_deletion_protection
}

module "pubsub" {
  source = "./modules/pubsub"

  project_id    = var.project_id
  name_prefix   = var.name_prefix
  kms_key_id    = module.kms.key_id
  run_sa_member = module.iam.run_sa_member
  labels        = var.labels

  # Same CMEK ordering requirement as module.storage above - without this the
  # topics race the Pub/Sub service agent's cryptoKeyEncrypterDecrypter
  # binding and fail with "Cloud Pub/Sub did not have the necessary
  # permissions configured to support this operation."
  depends_on = [module.kms]
}

# --- GKE Cluster (the only deployment target - Cloud Run support removed) ---
module "gke" {
  source = "./modules/gke"

  project_id                 = var.project_id
  region                     = var.region
  name_prefix                = var.name_prefix
  network_id                 = local.network_id
  subnet_id                  = local.private_subnet_id
  pods_range_name            = local.pods_range_name
  services_range_name        = local.services_range_name
  labels                     = var.labels
  enable_deletion_protection = var.enable_deletion_protection

  depends_on = [data.terraform_remote_state.network]
}

# Allow GKE Kubernetes Service Account to authenticate as GCP Service Account via Workload Identity.
# Namespace/KSA name must match Helm's values.yaml serviceAccount block
# (dev/helm/values.yaml: serviceAccount.name) exactly, or the pod won't be
# able to impersonate this SA at runtime.
resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = module.iam.run_sa_id
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.gke_ksa_namespace}/${var.gke_ksa_name}]"
}

# --- Ingress front door (consumed by the Helm chart, not by Terraform) ------
# The L7 load balancer itself is created by GKE's Ingress controller when the
# Helm chart's Ingress object is applied - Terraform does not and cannot
# create it. What Terraform DOES pre-provision here is the two things that
# must exist BEFORE that Ingress is deployed:
#
#   1. A reserved static global IP. Without this the LB gets an ephemeral IP
#      that is only knowable after deploy, which makes it impossible to point
#      DNS at the app ahead of time - and a Google-managed certificate cannot
#      finish provisioning until DNS already resolves to the LB. Reserving it
#      here breaks that chicken-and-egg: the IP is a Terraform output, so DNS
#      can be pointed at it before the app is ever deployed.
#   2. The Cloud Armor policy, which GKE attaches to the Ingress backend via
#      the chart's BackendConfig (spec.securityPolicy.name).
resource "google_compute_global_address" "ingress_ip" {
  project      = var.project_id
  name         = "${var.name_prefix}-ingress-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

module "cloud_armor" {
  source = "./modules/cloud-armor"
  count  = var.enable_cloud_armor ? 1 : 0

  project_id  = var.project_id
  name_prefix = var.name_prefix
}

module "audit_logging" {
  source = "./modules/audit-logging"

  project_id         = var.project_id
  region             = var.region
  name_prefix        = var.name_prefix
  kms_key_id         = module.kms.key_id
  enable_audit_trail = var.enable_audit_trail
  labels             = var.labels

  # Application log retention (Cloud Logging buckets the app reads back).
  # The cluster/namespace/container triple scopes the operational-log sink to
  # this app's containers - passing the cluster name from module.gke rather
  # than hardcoding it keeps the filter correct if the cluster is renamed.
  app_log_retention_days   = var.app_log_retention_days
  audit_log_retention_days = var.audit_log_retention_days
  app_audit_log_name       = var.app_audit_log_name
  gke_cluster_name         = module.gke.cluster_name
  gke_namespace            = var.gke_ksa_namespace
  gke_container_name       = var.gke_container_name

  enable_deletion_protection = var.enable_deletion_protection

  # Same CMEK ordering requirement as module.storage above.
  depends_on = [module.kms]
}

# Restores the CloudWatch alarm coverage from the AWS template (12 alarms:
# ECS CPU/memory, ALB latency + 5xx, 3 SQS, 5 DynamoDB) plus the SNS email
# subscription. This module was briefly removed with Cloud Run - its metric
# FILTERS were Cloud Run specific, but the alerting itself is required on any
# platform. The CPU/memory policies now watch k8s_container metrics instead.
module "monitoring" {
  source = "./modules/monitoring"

  project_id  = var.project_id
  name_prefix = var.name_prefix
  alert_email = var.alert_email

  gke_cluster_name   = module.gke.cluster_name
  gke_namespace      = var.gke_ksa_namespace
  gke_container_name = var.gke_container_name

  container_sync_topic_name = module.pubsub.container_sync_topic_name
  firestore_database_name   = module.firestore.database_name
}

# --- DNS A record for the application domain -------------------------------
# Created only when the domain's zone is hosted in this project's Cloud DNS.
# This is what makes routing automatic: Google will not issue the managed
# certificate until app_domain already resolves to the load balancer's IP, so
# creating the record here removes the manual step (and the failure mode where
# the certificate sticks in FailedNotVisible because DNS was set up too late).
#
# When the zone lives elsewhere - a registrar, Route 53, another project -
# leave dns_managed_zone empty and create the record from the
# ingress_static_ip_address output before deploying the chart.
resource "google_dns_record_set" "app" {
  count = var.app_domain != "" && var.dns_managed_zone != "" ? 1 : 0

  project      = var.project_id
  managed_zone = var.dns_managed_zone
  name         = "${var.app_domain}." # Cloud DNS requires the trailing dot here
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.ingress_ip.address]
}

# A CAA record naming pki.goog, without which Google will not issue the
# managed certificate at all.
#
# The apex connecthealth.ai carries `0 issue "amazon.com"` left over from AWS
# ACM. CAA is inherited down the DNS tree, so with no record of its own the app
# subdomain inherited that apex record and Google was forbidden from issuing -
# the certificate came back FAILED_CAA_FORBIDDEN rather than simply timing out,
# which is the tell that distinguishes this from a DNS-not-yet-propagated stall.
#
# CAA is evaluated at the CLOSEST ancestor that has a record, so publishing one
# on the app subdomain overrides the apex for this name only. That keeps the fix
# inside the Cloud DNS zone this stack already manages: no change at the
# registrar, and certificates issued by Amazon for other names on the domain are
# unaffected. Note a failed managed certificate never retries on its own - after
# this record exists the ManagedCertificate must be deleted and recreated.
resource "google_dns_record_set" "app_caa" {
  count = var.app_domain != "" && var.dns_managed_zone != "" ? 1 : 0

  project      = var.project_id
  managed_zone = var.dns_managed_zone
  name         = "${var.app_domain}."
  type         = "CAA"
  ttl          = 300
  rrdatas      = ["0 issue \"pki.goog\""]
}
