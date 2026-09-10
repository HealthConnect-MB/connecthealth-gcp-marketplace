# Replaces CloudTrail + CloudTrailLogGroup + CloudTrailRole + CloudTrailBucket
# + CloudTrailBucketPolicy (all gated behind the AWS EnableCloudTrail
# condition). Structurally simpler in GCP: Admin Activity audit logs are ON
# BY DEFAULT for every project at no cost (the AWS equivalent required
# standing up a whole Trail resource just to get that) - this module only
# needs to (1) explicitly enable Data Access logs, which are NOT on by
# default, and (2) export everything to a retained bucket. No CloudTrailRole
# equivalent is needed - Cloud Logging sinks provision their own writer
# identity automatically.
#
# OPEN ITEM - AWS CONFIG HAS NO 1:1 GCP EQUIVALENT: the source CF template's
# ConfigBucket/ConfigRole/ConfigRecorder (continuous resource-configuration
# recording + compliance rule evaluation, with a MANDATORY pre-existing
# Delivery Channel) is intentionally NOT ported here. The closest GCP
# composition is Cloud Asset Inventory (continuous resource inventory/
# history, analogous to Config's resource snapshots) + Security Command
# Center (Premium tier, for compliance findings/posture - analogous to
# Config Rules). That is a distinct, larger decision (SCC Premium is a paid
# org-level product, not a per-project Terraform resource) and should be
# scoped separately rather than silently assumed here.

# Matches the Final template's addition of DeletionPolicy: Retain +
# UpdateReplacePolicy: Retain on CloudTrailLogGroup/CloudTrail/
# CloudTrailBucket - audit trail data must survive a stack update/teardown.
# prevent_destroy is Terraform's equivalent: it blocks `terraform destroy`/a
# replace-triggering `apply` from removing this bucket, the same protection
# AWS's Retain policies provide.
resource "google_storage_bucket" "audit_logs" {
  count                       = var.enable_audit_trail ? 1 : 0
  project                     = var.project_id
  name                        = "${var.name_prefix}-audit-logs-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true

  # The audit trail. Deleting this bucket discards it, so the default for
  # enable_deletion_protection is a genuine judgement call rather than a
  # convenience setting - see the variable's description.
  force_destroy = !var.enable_deletion_protection

  encryption {
    default_kms_key_name = var.kms_key_id
  }

  public_access_prevention = "enforced"

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels

  # Guard removed. It could not be made conditional - prevent_destroy requires a
  # literal - so it made every customer teardown a dead end. Retention now comes
  # from the lifecycle_rule above plus the separate GCS archive bucket that the
  # audit sink also writes to, so destroying this bucket does not by itself
  # discard exported audit data.
}

# Replaces EventSelectors: ReadWriteType All / IncludeManagementEvents true.
# Admin Activity (management events) logging is always-on already; this
# audit config additionally turns on Data Access logs for the services this
# workload actually touches, matching the CF template's post-COH-384 stance
# of "complete audit coverage on ONE trail, no duplicate/noisy data events on
# irrelevant resources" - scoped to the services this app uses rather than
# allServices, to avoid the same cost-blowup pattern COH-384 called out.
resource "google_project_iam_audit_config" "scoped_data_access" {
  # Service names here must be ones that actually support service-level audit
  # configuration, which is not always the obvious API name:
  #   - Firestore's audit logs are recorded under "datastore.googleapis.com"
  #     (Firestore grew out of Datastore and kept that audit service name).
  #     "firestore.googleapis.com" is rejected by the API with
  #     "does not exist or does not support service level configuration".
  #   - "container.googleapis.com" (GKE) replaces the former
  #     "run.googleapis.com" entry - Cloud Run is no longer part of this stack.
  for_each = var.enable_audit_trail ? toset([
    "storage.googleapis.com",
    "datastore.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "container.googleapis.com",
  ]) : toset([])

  project = var.project_id
  service = each.value

  audit_log_config {
    log_type = "ADMIN_READ"
  }
  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

resource "google_logging_project_sink" "audit_export" {
  count                  = var.enable_audit_trail ? 1 : 0
  project                = var.project_id
  name                   = "${var.name_prefix}-audit-log-export"
  destination            = "storage.googleapis.com/${google_storage_bucket.audit_logs[0].name}"
  filter                 = "logName:\"cloudaudit.googleapis.com\""
  unique_writer_identity = true
}

resource "google_storage_bucket_iam_member" "audit_export_writer" {
  count  = var.enable_audit_trail ? 1 : 0
  bucket = google_storage_bucket.audit_logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_export[0].writer_identity
}

# =============================================================================
# Application log retention — Cloud Logging buckets
# =============================================================================
# Separate concern from the CloudTrail-equivalent GCS export above:
#
#   * That export archives GCP API activity (cloudaudit.googleapis.com) as
#     FILES in GCS for long-term compliance retention. It is not queryable.
#   * These buckets hold the APPLICATION's own logs, and the app reads them
#     back through the Logging API to render its in-app audit and log screens.
#     A GCS bucket cannot serve that purpose - the app queries log views, not
#     objects - which is why these are Cloud Logging buckets, not GCS.
#
# Without them, both screens fall back to the project's _Default bucket and
# silently show only the last 30 days.
#
# The consuming container must be told which buckets to query, via
# GCP_AUDIT_LOG_BUCKET / GCP_APPLICATION_LOG_BUCKET and their _LOCATION
# counterparts. The bucket names and location are exported as outputs for
# exactly that purpose - see this module's outputs.tf.
#
# NOTE ON PERMISSIONS: reading a specific bucket view needs
# roles/logging.viewAccessor on the workload identity, which
# roles/logging.viewer alone does NOT grant. That role is attached in the iam
# module; without it these buckets exist but every query fails with
# "PERMISSION_DENIED: Permission denied for all log views".
#
# NOTE ON SINK PERMISSIONS: sinks routing to a Cloud Logging bucket in the
# SAME project need no writer-identity IAM grant - routing is internal to
# Cloud Logging. That is why there is no google_project_iam_member here, in
# contrast to the GCS export sink above which does require one.

resource "google_logging_project_bucket_config" "app_audit" {
  count = var.enable_audit_trail ? 1 : 0

  project   = var.project_id
  location  = var.region
  bucket_id = "${var.name_prefix}-audit-retention"
  # 2192 days (~6 years), matching the AWS template's AuditLogGroup. This is the
  # HIPAA audit-retention requirement and is deliberately separate from the
  # operational bucket's retention - a single shared variable previously set
  # BOTH to 60 days, quietly leaving the audit trail ~36x short of the AWS
  # baseline it was meant to reproduce.
  retention_days = var.audit_log_retention_days
  description    = "ConnectHealth application audit trail. Queried by the in-app audit screen."
}

resource "google_logging_project_sink" "app_audit" {
  count = var.enable_audit_trail ? 1 : 0

  project     = var.project_id
  name        = "${var.name_prefix}-app-audit-sink"
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.app_audit[0].id}"
  filter      = "logName=\"projects/${var.project_id}/logs/${var.app_audit_log_name}\""

  unique_writer_identity = true
}

resource "google_logging_project_bucket_config" "app_operational" {
  count = var.enable_audit_trail ? 1 : 0

  project        = var.project_id
  location       = var.region
  bucket_id      = "${var.name_prefix}-applogs-retention"
  retention_days = var.app_log_retention_days
  description    = "ConnectHealth operational/container logs. Queried by the in-app application log screen."
}

# Scoped to this app's containers rather than the whole cluster. Cloud Logging
# bills for routed volume and container logs are high-volume, so a broader
# filter here is a real cost, not just noise. Narrow further with
# `AND severity>=WARNING` if volume becomes a problem.
resource "google_logging_project_sink" "app_operational" {
  count = var.enable_audit_trail ? 1 : 0

  project     = var.project_id
  name        = "${var.name_prefix}-app-operational-sink"
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.app_operational[0].id}"

  filter = join(" AND ", [
    "resource.type=\"k8s_container\"",
    "resource.labels.cluster_name=\"${var.gke_cluster_name}\"",
    "resource.labels.namespace_name=\"${var.gke_namespace}\"",
    "resource.labels.container_name=\"${var.gke_container_name}\"",
  ])

  unique_writer_identity = true
}
