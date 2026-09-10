# Replaces TaskExecutionRole + TaskRole combined. Cloud Run has no separate
# execution-role/task-role split the way ECS does (execution role = image
# pull + log/secret plumbing done by the platform; task role = app runtime
# permissions) - one service identity covers both here.
#
# Resource-scoped bindings (Secrets Manager prefix, Filestore-equivalent
# network ACL, the flows bucket, the Firestore database, Pub/Sub topics/
# subscriptions, KMS decrypt) are granted by each OWNING module
# (storage/firestore/pubsub/secret-manager/filestore/kms) once that resource
# exists, not here - this avoids a dependency cycle where iam would need
# outputs from modules that themselves need the service account email as
# input. This module only grants the project-scoped roles that have no
# resource-level scoping option to begin with.
resource "google_service_account" "run_sa" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-run-sa"
  display_name = "ConnectHealth Cloud Run service identity"
  description  = "Single identity for both connecthealth-backend and connecthealth-frontend Cloud Run services (replaces AWS TaskExecutionRole + TaskRole)."
}

# Replaces TaskExecutionRole's AmazonECSTaskExecutionRolePolicy (ECR pull).
# NOTE - CROSS-PROJECT IMAGE: this grant only covers pulling from a
# repository IN THIS project. The container image actually lives in a
# different GCP project/account (same situation as AWS: ContainerImage
# pointed at an externally-owned ECR repo, account 709825985650, not one
# this template created). This binding is harmless but insufficient on its
# own for that case - the SOURCE project's Artifact Registry repo must
# separately grant this service account (run_sa.email, below) the
# roles/artifactregistry.reader role (or equivalent) on ITS side, exactly
# like AWS's cross-account ECR pulls require a repository resource policy
# on the source account granting the pulling role access.
resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# Replaces TaskRole's CloudWatchLogsAccess statement. NOTE: AWS scoped this
# tightly to two specific log-group ARNs (+ /audit variant); GCP's
# roles/logging.logWriter is project-scoped with no per-log-name IAM
# condition available - this is a real, documented reduction in the
# tightness of the original guarantee, not an oversight.
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

resource "google_project_iam_member" "metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# The app does not only WRITE audit entries - GcpAuditLogStore also QUERIES
# them back (the in-app audit trail view reads
# "projects/<project>/logs/ehrconnect-audit"). roles/logging.logWriter above
# grants write only, so without this the read path fails at runtime with
# "7 PERMISSION_DENIED: Permission denied for all log views". logging.viewer
# is sufficient because the app queries its own custom log name, not Data
# Access logs (which would additionally require logging.privateLogViewer).
resource "google_project_iam_member" "log_viewer" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# roles/logging.viewer alone is NOT enough once the app is pointed at a
# dedicated log bucket rather than the project's default scope. Setting
# GCP_AUDIT_LOG_BUCKET / GCP_APPLICATION_LOG_BUCKET makes the app query
# ".../buckets/<name>/views/_AllLogs", and reading a specific bucket view
# requires logging.views.access, which only this role carries. Without it the
# audit and application log screens fail at runtime with
# "7 PERMISSION_DENIED: Permission denied for all log views" even though
# ordinary log reads work fine.
resource "google_project_iam_member" "log_view_accessor" {
  project = var.project_id
  role    = "roles/logging.viewAccessor"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# Below: project-scoped roles needed when this SA is bound to a GKE pod via
# Workload Identity rather than run natively as a Cloud Run service identity
# (see google_service_account_iam_member.workload_identity_user in
# Services/main.tf). Cloud Run's runtime already gets log/metric delivery
# and image pulls handled by the platform; a GKE pod authenticating as this
# SA needs to reach Secret Manager, GCS, Firestore and Pub/Sub directly, the
# same way the resource-scoped grants in storage/firestore/pubsub/
# secret-manager would if this were Cloud Run - granted project-wide here
# instead because those modules scope their bindings to run_sa_member at
# resource-creation time, before a GKE-specific identity exists to scope to.
resource "google_project_iam_member" "secret_manager_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

resource "google_project_iam_member" "storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

resource "google_project_iam_member" "datastore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

resource "google_project_iam_member" "pubsub_editor" {
  project = var.project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# NOTE: TaskRole's LicenseManagerAccess statement (AWS License Manager
# checkout/checkin for BYOL enforcement) has NO GCP equivalent - AWS License
# Manager is AWS-specific. If license enforcement is still required on GCP,
# it needs a custom mechanism (self-hosted licensing service, or GCP
# Marketplace's own procurement/metering API) - out of scope for this
# Terraform port, flagged in the top-level README.
