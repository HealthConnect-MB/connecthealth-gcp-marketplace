# Replaces ComplianceKMSKey + ComplianceKMSKeyAlias. GCP has no alias
# resource to create separately - the crypto key's resource name is the
# stable reference every other module/module consumer uses directly.
# NAME MUST NOT COLLIDE WITH THE BOOTSTRAP KEYRING. Network/bootstrap.sh
# creates "connecthealth-<environment>-keyring" to encrypt the Terraform
# STATE BUCKET, before Terraform ever runs. This keyring is a different
# thing: the CMEK protecting APPLICATION data (GCS buckets, Pub/Sub topics,
# audit logs). Both resolve from similar inputs, so without the "-app"
# segment here they collide on the exact same name and Terraform fails with
# "KeyRing ... already exists" (409) - the bootstrap script having already
# claimed it. Note also that KMS key rings can NEVER be deleted in GCP, so a
# collision cannot be cleaned up after the fact; the names must differ.
resource "google_kms_key_ring" "this" {
  project  = var.project_id
  name     = "${var.name_prefix}-app-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "compliance" {
  name            = "${var.name_prefix}-compliance-key"
  key_ring        = google_kms_key_ring.this.id
  purpose         = "ENCRYPT_DECRYPT"
  rotation_period = "${var.rotation_period_seconds}s"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  destroy_scheduled_duration = var.destroy_scheduled_duration

  labels = var.labels

  # No prevent_destroy: it cannot be driven by a variable, so it made every
  # customer teardown fail with no parameter they could set to proceed.
  #
  # The protection that remains is stronger than it looks. destroy_scheduled_duration
  # above means a "destroyed" key version enters a scheduled-destruction window
  # rather than disappearing - it can be restored during that window. And GCP
  # never deletes the key ring itself under any circumstances.
}

# Root module accumulates {role, member} pairs across kms/iam/storage/
# firestore/pubsub/secret-manager as each is created, and passes them in here
# - replaces the 6 Sid statements in AWS's KeyPolicy document (IAM root is
# implicit via project-level KMS admin IAM in GCP, not a key-policy Sid).
#
# Keyed by list index, not role|member: some bindings' member values (e.g.
# google_project_service_identity.pubsub.email in Services/main.tf) are
# unknown until apply, since they belong to resources created in this same
# plan. A for_each key derived from those values is itself unknown, which
# Terraform can't resolve ("Invalid for_each argument"). Index is stable
# because `bindings` is a fixed literal list at the call site, not something
# reordered between applies.
resource "google_kms_crypto_key_iam_member" "bindings" {
  for_each = { for idx, b in var.bindings : tostring(idx) => b }

  crypto_key_id = google_kms_crypto_key.compliance.id
  role          = each.value.role
  member        = each.value.member
}
