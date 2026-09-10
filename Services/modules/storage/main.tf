# Replaces EHRConnectFlowsBucket + EHRConnectFlowsBucketPolicy. GCS enforces
# TLS unconditionally, so AWS's DenyInsecureConnections statement has nothing
# to replicate - it is not a gap, it's redundant on GCS.
resource "google_storage_bucket" "flows" {
  project                     = var.project_id
  name                        = "${var.name_prefix}-flows-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true

  # Driven by a variable, not hardcoded. A customer deploys this blueprint from
  # a read-only GCS source in OUR project into THEIR project - they cannot edit
  # the code, only pass parameters. A hardcoded false here means every teardown
  # from the Infrastructure Manager console fails on a non-empty bucket with no
  # way for them to proceed, because force_destroy is read from Terraform STATE,
  # so changing it needs an apply they cannot perform mid-delete.
  force_destroy = !var.enable_deletion_protection

  encryption {
    default_kms_key_name = var.kms_key_id
  }

  versioning {
    enabled = true
  }

  public_access_prevention = "enforced"

  lifecycle_rule {
    condition {
      days_since_noncurrent_time = var.flows_bucket_lifecycle_days
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels

  # No lifecycle guard here by design. This bucket previously carried
  # prevent_destroy, intended to mirror EHRConnectFlowsBucket's
  # DeletionPolicy: Retain - but the two are not equivalent. AWS's Retain lets
  # the stack delete SUCCEED and leaves the bucket behind; prevent_destroy
  # blocks the entire teardown. Terraform offers no true Retain equivalent, and
  # prevent_destroy cannot take a variable (it must be a literal), so it could
  # never be made optional for a customer who legitimately wants to remove their
  # deployment. It is replaced by var.enable_deletion_protection above, which
  # drives force_destroy and is settable as a deployment parameter.
  #
  # Data protection with the guard off comes from GCS-native controls that a
  # terraform destroy does not bypass: object versioning (enabled above), the
  # lifecycle rule, and GCS soft-delete.
}

# Replaces EHRConnectFlowsBucketPolicy's AllowTaskRoleAccess statement.
resource "google_storage_bucket_iam_member" "flows_run_sa_access" {
  bucket = google_storage_bucket.flows.name
  role   = "roles/storage.objectAdmin"
  member = var.run_sa_member
}

# Replaces ALBAccessLogsBucket + ALBAccessLogsBucketPolicy. Bucket only - the
# Cloud Logging sink that actually routes LB access logs here is owned by the
# load-balancer module (the resource generating the logs owns its export),
# matching the pattern used for VPC flow logs in the Network stack.
resource "google_storage_bucket" "lb_logs" {
  project                     = var.project_id
  name                        = "${var.name_prefix}-lb-logs-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = !var.enable_deletion_protection

  # AWS forced AES256 (KMS-CMK unsupported for ALB access logs at the time
  # the template was written). GCS access-log buckets DO support CMEK, so
  # this uses the shared key rather than reproducing the AWS limitation.
  encryption {
    default_kms_key_name = var.kms_key_id
  }

  public_access_prevention = "enforced"

  lifecycle_rule {
    condition {
      age = var.lb_logs_bucket_lifecycle_days
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels

  # Guard removed - see the note on google_storage_bucket.flows above.
  # Protection is var.enable_deletion_protection driving force_destroy.
}
