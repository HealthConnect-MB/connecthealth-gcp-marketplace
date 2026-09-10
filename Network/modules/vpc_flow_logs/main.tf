# NOTE ON STRUCTURAL DIFFERENCE FROM AWS:
# In AWS, VPCFlowLog is an independent resource that attaches to a VPC/subnet
# after the fact (modules/vpc_flow_logs owned it in the NAHQ reference, taking
# only a vpc_id as input). In GCP, flow-log emission is a `log_config` block
# nested directly inside `google_compute_subnetwork` - it cannot be created as
# a standalone resource, so the ../vpc module owns *enabling* flow logs
# (see private_subnet.log_config, gated by var.enable_vpc_flow_logs).
#
# This module instead owns what AWS's VPCFlowLogsRole + VPCFlowLogsS3Bucket
# concern was actually about: WHERE flow log records land for long-term
# retention. VPC Flow Logs write to Cloud Logging by default; this module
# exports them to a GCS bucket via a log sink, matching AWS's "flow logs to
# S3, retained N days" pattern - no IAM role required, Cloud Logging's sink
# writer identity is provisioned automatically.

resource "google_storage_bucket" "flow_logs" {
  project                     = var.project_id
  name                        = "${var.name_prefix}-flow-logs-${var.project_id}"
  location                    = "US"
  uniform_bucket_level_access = true
  force_destroy               = false

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
}

resource "google_logging_project_sink" "flow_logs" {
  project                = var.project_id
  name                   = "${var.name_prefix}-flow-logs-sink"
  destination            = "storage.googleapis.com/${google_storage_bucket.flow_logs.name}"
  filter                 = "resource.type=\"gce_subnetwork\" AND logName:\"compute.googleapis.com%2Fvpc_flows\""
  unique_writer_identity = true
}

resource "google_storage_bucket_iam_member" "flow_logs_sink_writer" {
  bucket = google_storage_bucket.flow_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.flow_logs.writer_identity
}
