# Replaces EHRConnectContextTable (DynamoDB, PAY_PER_REQUEST, HASH id + RANGE
# sk, PITR enabled, TTL disabled). Firestore Native mode is the serverless/
# on-demand-billing analog of DynamoDB PAY_PER_REQUEST; the composite
# id+sk key becomes a Firestore document path (collection "id", document
# "sk", or a composite document ID "id#sk" depending on the app's access
# pattern - confirm which against actual ConnectHealth flow-context read/write
# calls before cutover).
#
# NOTE ON A DROPPED GUARANTEE: DynamoDB's SSESpecification let AWS attach the
# ComplianceKMSKey directly (SSEType: KMS). Firestore Native mode does NOT
# currently support customer-managed encryption keys in all configurations -
# confirm current CMEK support for your region before relying on this for a
# HIPAA/BAA encryption requirement; Firestore is Google-encrypted-at-rest by
# default regardless.
resource "google_firestore_database" "context" {
  project                           = var.project_id
  name                              = "${var.name_prefix}-context"
  location_id                       = var.region
  type                              = "FIRESTORE_NATIVE"
  concurrency_mode                  = "OPTIMISTIC"
  app_engine_integration_mode       = "DISABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"

  # Driven by the same variable as the cluster and bucket guards. Hardcoding
  # DELETE_PROTECTION_ENABLED made every teardown fail here: like GKE's
  # deletion_protection and a bucket's force_destroy, this is a resource
  # attribute read from Terraform STATE, so a customer deleting their deployment
  # from the console has no way to clear it - the delete simply cannot proceed.
  #
  # Point-in-time recovery above stays on regardless, so the data protection
  # that matters day-to-day is unaffected by this setting.
  delete_protection_state = var.enable_deletion_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
}

# Replaces TaskRole's DynamoDBContextAccess statement.
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = var.run_sa_member

  condition {
    title       = "connecthealth-context-db-only"
    description = "Scopes access to the connecthealth context Firestore database only."
    expression  = "resource.name == \"projects/${var.project_id}/databases/${google_firestore_database.context.name}\""
  }
}
