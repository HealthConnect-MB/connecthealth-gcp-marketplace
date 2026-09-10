# Replaces SNSTopic (alerts) - used here only as an optional programmatic
# fanout channel. Actual CloudWatch-alarm-style email delivery is wired
# through Cloud Monitoring alerting policies + a notification channel in the
# monitoring module directly, NOT through this topic - GCP alerting talks to
# notification channels, not Pub/Sub, so AWS's "one SNS topic serves both
# AlarmActions and an email subscription" dual role splits into two GCP
# mechanisms.
resource "google_pubsub_topic" "alerts" {
  project = var.project_id
  name    = "${var.name_prefix}-alerts"

  kms_key_name = var.kms_key_id

  labels = var.labels
}

# Replaces ContainerSyncTopic + the dynamic per-container SQS queues the app
# creates/deletes at runtime (naming convention connecthealth-<container-id>).
# Only the TOPIC is Terraform-managed; SUBSCRIPTIONS are created dynamically
# by the app itself (mirrors AWS granting sqs:CreateQueue/DeleteQueue rather
# than Terraform pre-creating fixed queues) - the scoped custom role below
# grants that runtime create/delete/manage capability.
resource "google_pubsub_topic" "container_sync" {
  project = var.project_id
  name    = "${var.name_prefix}-container-sync"

  kms_key_name = var.kms_key_id

  labels = var.labels
}

resource "google_pubsub_topic_iam_member" "alerts_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.alerts.name
  role    = "roles/pubsub.publisher"
  member  = var.run_sa_member
}

# Replaces TaskRole's ContainerSyncAccess statement (sns:Publish/
# GetTopicAttributes on ContainerSyncTopic + sqs:CreateQueue/DeleteQueue/
# GetQueueUrl/GetQueueAttributes/SetQueueAttributes/ReceiveMessage/
# DeleteMessage/SendMessage/PurgeQueue scoped to arn:aws:sqs:...${ProjectName}-*
# + sns:Subscribe/Unsubscribe).
resource "google_project_iam_custom_role" "pubsub_scoped" {
  project     = var.project_id
  role_id     = replace("${var.name_prefix}_pubsub_scoped", "-", "_")
  title       = "ConnectHealth scoped Pub/Sub container-sync admin"
  description = "Publish to the container-sync topic and fully manage its own dynamically created subscriptions - mirrors AWS TaskRole's ContainerSyncAccess."
  permissions = [
    "pubsub.topics.get",
    "pubsub.topics.publish",
    "pubsub.topics.attachSubscription",
    "pubsub.subscriptions.create",
    "pubsub.subscriptions.delete",
    "pubsub.subscriptions.get",
    "pubsub.subscriptions.list",
    "pubsub.subscriptions.update",
    "pubsub.subscriptions.consume",
  ]
}

resource "google_pubsub_topic_iam_member" "container_sync_scoped_binding" {
  project = var.project_id
  topic   = google_pubsub_topic.container_sync.name
  role    = google_project_iam_custom_role.pubsub_scoped.id
  member  = var.run_sa_member
}

# Subscription create/delete/manage is project-scoped in GCP (no
# subscription-name-prefix IAM condition equivalent to AWS's
# arn:aws:sqs:${Region}:${AccountId}:${ProjectName}-* Resource match), so the
# custom role above is bound at the project level rather than a single
# subscription resource.
resource "google_project_iam_member" "pubsub_scoped_project_binding" {
  project = var.project_id
  role    = google_project_iam_custom_role.pubsub_scoped.id
  member  = var.run_sa_member
}
