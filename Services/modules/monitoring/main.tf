# =============================================================================
# ConnectHealth alerting - GCP equivalent of the AWS template's 12 CloudWatch
# alarms (ECS CPU/memory, ALB latency + 5xx, 3x SQS, 5x DynamoDB).
#
# THREE MONITORING API CONSTRAINTS ARE BAKED IN HERE. Each was found by an
# apply failing, so changing any of them back will break the apply again:
#
# 1. COMPARISON_GE IS NOT SUPPORTED. The API accepts only COMPARISON_LT and
#    COMPARISON_GT. The AWS alarms these replace use
#    GreaterThanOrEqualToThreshold, so the ">=" semantics are approximated
#    with ">" - immaterial at these thresholds.
#
# 2. FIRESTORE'S MONITORED RESOURCE IS "firestore.googleapis.com/Database",
#    not "firestore_database". The latter is rejected with "unknown resource
#    type".
#
# 3. document/read_count AND document/write_count REPORT ONLY AGAINST THE
#    LEGACY "firestore_instance" RESOURCE, which carries a project_id label
#    and nothing else - there is no way to scope those metrics to a single
#    database. The *_ops_count variants report against
#    firestore.googleapis.com/Database, which has database_id, so those are
#    used instead.
#
# Verified against the Monitoring API's own metric and monitored-resource
# descriptors for this project, not inferred.
# =============================================================================

# Replaces SNSTopic + SNSEmailSubscription + SQSAlarmTopic +
# SQSAlarmEmailSubscription's DELIVERY role. Cloud Monitoring alerting
# policies talk to notification channels directly rather than an SNS
# topic + subscription pair, so both AWS email subscriptions collapse into
# one channel here.
resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "${var.name_prefix}-alert-email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

locals {
  channels = var.alert_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
}

# Replaces HighCPUAlarm (AWS/ECS CPUUtilization, dimensions ServiceName +
# ClusterName). Alerts on either Cloud Run service (backend or frontend).
resource "google_monitoring_alert_policy" "high_cpu" {
  project      = var.project_id
  display_name = "${var.name_prefix}-high-cpu"
  combiner     = "OR"

  conditions {
    display_name = "Container CPU utilization > ${var.cpu_threshold_percent}% of limit"
    condition_threshold {
      # GKE container CPU as a ratio of the pod's CPU *limit*. Replaces AWS
      # HighCPUAlarm (AWS/ECS CPUUtilization > 80%). Scoped to this app's
      # containers rather than the whole cluster so unrelated workloads on the
      # same nodes cannot trip it.
      filter          = "resource.type = \"k8s_container\" AND metric.type = \"kubernetes.io/container/cpu/limit_utilization\" AND resource.label.cluster_name = \"${var.gke_cluster_name}\" AND resource.label.namespace_name = \"${var.gke_namespace}\" AND resource.label.container_name = \"${var.gke_container_name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.cpu_threshold_percent / 100
      duration        = "600s" # matches EvaluationPeriods 2 x Period 300s
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces HighMemoryAlarm.
resource "google_monitoring_alert_policy" "high_memory" {
  project      = var.project_id
  display_name = "${var.name_prefix}-high-memory"
  combiner     = "OR"

  conditions {
    display_name = "Container memory utilization > ${var.memory_threshold_percent}% of limit"
    condition_threshold {
      # Replaces AWS HighMemoryAlarm (AWS/ECS MemoryUtilization > 80%).
      # limit_utilization is the right metric here because the chart sets a
      # memory limit well above its request - measuring against the request
      # would alert constantly under normal operation.
      filter          = "resource.type = \"k8s_container\" AND metric.type = \"kubernetes.io/container/memory/limit_utilization\" AND resource.label.cluster_name = \"${var.gke_cluster_name}\" AND resource.label.namespace_name = \"${var.gke_namespace}\" AND resource.label.container_name = \"${var.gke_container_name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.memory_threshold_percent / 100
      duration        = "600s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces ALBResponseTimeAlarm.
resource "google_monitoring_alert_policy" "lb_response_time" {
  project      = var.project_id
  display_name = "${var.name_prefix}-lb-high-response-time"
  combiner     = "OR"

  conditions {
    display_name = "LB backend latency > ${var.lb_response_time_threshold_sec}s"
    condition_threshold {
      # Replaces AWS ALBResponseTimeAlarm (TargetResponseTime > 1s).
      # NOTE: the URL map is created by the GKE INGRESS CONTROLLER, not by
      # Terraform, so its name is not knowable at plan time. This matches every
      # external HTTPS LB in the project instead. If a second Ingress is ever
      # added, narrow this with resource.label.url_map_name.
      filter          = "resource.type = \"https_lb_rule\" AND metric.type = \"loadbalancing.googleapis.com/https/backend_latencies\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.lb_response_time_threshold_sec * 1000 # metric is in ms
      duration        = "600s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces ALBErrorRateAlarm.
resource "google_monitoring_alert_policy" "lb_5xx_errors" {
  project      = var.project_id
  display_name = "${var.name_prefix}-lb-high-5xx-rate"
  combiner     = "OR"

  conditions {
    display_name = "LB 5xx responses > ${var.lb_5xx_threshold_count} in 5 min"
    condition_threshold {
      # Replaces AWS ALBErrorRateAlarm (HTTPCode_ELB_5XX_Count > 5 in 5 min).
      # Same URL-map caveat as the latency policy above.
      filter          = "resource.type = \"https_lb_rule\" AND metric.type = \"loadbalancing.googleapis.com/https/request_count\" AND metric.label.response_code_class = \"500\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.lb_5xx_threshold_count
      duration        = "600s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces SQSMessagesVisibleAlarm. Dimensions intentionally omitted (matches
# AWS comment "monitor all queues in the account") - Pub/Sub subscriptions
# are dynamic/app-created, so this aggregates across the container-sync
# topic's subscriptions rather than naming one.
resource "google_monitoring_alert_policy" "pubsub_backlog" {
  project      = var.project_id
  display_name = "${var.name_prefix}-pubsub-high-backlog"
  combiner     = "OR"

  conditions {
    display_name = "Undelivered messages >= ${var.pubsub_backlog_threshold_count}"
    condition_threshold {
      # NOT scoped to a topic, deliberately. The pubsub_subscription
      # monitored resource exposes only project_id and subscription_id -
      # there is no topic_id label, and these metrics carry no metric
      # labels either, so subscription metrics CANNOT be filtered by topic.
      # (The send-rate policy below can, because it reads pubsub_topic.)
      # Alerting across every subscription in the project is the correct
      # scope anyway: each deployment owns its project, and the app creates
      # its subscriptions dynamically at "<prefix>-<containerId>", so a
      # name filter would couple this alert to an app config value.
      filter          = "resource.type = \"pubsub_subscription\" AND metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.pubsub_backlog_threshold_count
      duration        = "600s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_MAX"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces SQSOldestMessageAgeAlarm.
resource "google_monitoring_alert_policy" "pubsub_oldest_message_age" {
  project      = var.project_id
  display_name = "${var.name_prefix}-pubsub-oldest-message-age"
  combiner     = "OR"

  conditions {
    display_name = "Oldest unacked message age >= ${var.pubsub_oldest_message_age_threshold_sec}s"
    condition_threshold {
      # Same topic-scoping limitation as the backlog policy above.
      filter          = "resource.type = \"pubsub_subscription\" AND metric.type = \"pubsub.googleapis.com/subscription/oldest_unacked_message_age\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.pubsub_oldest_message_age_threshold_sec
      duration        = "600s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_MAX"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces SQSMessageSendRateAlarm.
resource "google_monitoring_alert_policy" "pubsub_send_rate_spike" {
  project      = var.project_id
  display_name = "${var.name_prefix}-pubsub-high-send-rate"
  combiner     = "OR"

  conditions {
    display_name = "Messages published >= ${var.pubsub_send_rate_threshold_count} in 5 min"
    condition_threshold {
      filter          = "resource.type = \"pubsub_topic\" AND metric.type = \"pubsub.googleapis.com/topic/send_message_operation_count\" AND resource.label.topic_id = \"${var.container_sync_topic_name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.pubsub_send_rate_threshold_count
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces DynamoDBReadLatencyAlarm/WriteLatencyAlarm/QueryLatencyAlarm (3
# alarms collapse to one, since Firestore's latency metric is not split by
# GetItem/PutItem/Query operation dimension the way DynamoDB's is).
resource "google_monitoring_alert_policy" "firestore_latency" {
  project      = var.project_id
  display_name = "${var.name_prefix}-firestore-high-latency"
  combiner     = "OR"

  conditions {
    display_name = "Firestore API request latency > ${var.firestore_latency_threshold_ms}ms"
    condition_threshold {
      filter          = "resource.type = \"firestore.googleapis.com/Database\" AND resource.label.database_id = \"${var.firestore_database_name}\" AND metric.type = \"firestore.googleapis.com/api/request_latencies\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.firestore_latency_threshold_ms
      duration        = "600s"
      aggregations {
        alignment_period = "300s"
        # request_latencies is a DISTRIBUTION. Comparing one to a
        # scalar threshold is rejected outright - it must first be
        # reduced with an explicit percentile aligner. p95 chosen so a
        # handful of slow calls does not mask a broadly degraded database.
        per_series_aligner = "ALIGN_PERCENTILE_95"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces DynamoDBReadCapacityAlarm + DynamoDBWriteCapacityAlarm. Firestore
# Native mode bills per document-operation, not RCU/WCU, so "capacity" is
# adapted to read/write OPERATION COUNT rather than consumed capacity units -
# this is a deliberate metric-model adaptation, not a 1:1 threshold port.
resource "google_monitoring_alert_policy" "firestore_read_volume" {
  project      = var.project_id
  display_name = "${var.name_prefix}-firestore-high-read-volume"
  combiner     = "OR"

  conditions {
    display_name = "Firestore document reads - sustained spike"
    condition_threshold {
      filter          = "resource.type = \"firestore.googleapis.com/Database\" AND resource.label.database_id = \"${var.firestore_database_name}\" AND metric.type = \"firestore.googleapis.com/document/read_ops_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 6000
      duration        = "600s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "firestore_write_volume" {
  project      = var.project_id
  display_name = "${var.name_prefix}-firestore-high-write-volume"
  combiner     = "OR"

  conditions {
    display_name = "Firestore document writes - sustained spike"
    condition_threshold {
      filter          = "resource.type = \"firestore.googleapis.com/Database\" AND resource.label.database_id = \"${var.firestore_database_name}\" AND metric.type = \"firestore.googleapis.com/document/write_ops_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 3000
      duration        = "600s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}

# Replaces SQSQueueCreationRule + AlertTopicsEventBridgePolicy. AWS bridged
# CloudTrail's CreateQueue API event through EventBridge's InputTransformer
# straight to an SNS topic - no Lambda involved, because EventBridge can
# target SNS directly with a reshaped payload. GCP's Eventarc has no
# equivalent "reshape and forward to Pub/Sub" target; the idiomatic
# GCP-native substitute is a log-based metric matched against the Cloud Audit
# Log entry for Pub/Sub's CreateSubscription call, alerted on directly -
# same outcome (email whenever a new container-sync subscription is
# created), no custom Cloud Function required.
resource "google_logging_metric" "subscription_created" {
  project = var.project_id
  name    = "${var.name_prefix}-pubsub-subscription-created"
  filter  = "resource.type=\"audited_resource\" AND protoPayload.serviceName=\"pubsub.googleapis.com\" AND protoPayload.methodName=\"google.pubsub.v1.Subscriber.CreateSubscription\" AND protoPayload.resourceName:\"${var.container_sync_topic_name}\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

# Cloud Monitoring indexes a new log-based metric's DESCRIPTOR asynchronously,
# and an alert policy cannot reference a metric type the descriptor index has not
# caught up to yet. Terraform already creates the metric first - the policy
# interpolates its name - but "created" and "queryable" are different moments, so
# ordering alone is not enough. The apply fails with:
#
#   Error 404: Cannot find metric(s) that match type =
#   "logging.googleapis.com/user/<prefix>-pubsub-subscription-created".
#   If a metric was created recently, it could take up to 10 minutes...
#
# 10 minutes is Google's own stated worst case. Descriptors usually appear within
# a minute or two, so this is nearly always waiting longer than needed - which is
# the right trade for a blueprint customers run unattended. A failed apply leaves
# a half-built stack and a person who does not know it just needs re-running;
# ten idle minutes inside a deployment that already takes twenty-five does not.
resource "time_sleep" "metric_descriptor_propagation" {
  depends_on      = [google_logging_metric.subscription_created]
  create_duration = "10m"
}

resource "google_monitoring_alert_policy" "subscription_created" {
  depends_on = [time_sleep.metric_descriptor_propagation]

  project      = var.project_id
  display_name = "${var.name_prefix}-new-pubsub-subscription-created"
  combiner     = "OR"

  conditions {
    display_name = "New container-sync subscription created"
    condition_threshold {
      filter          = "resource.type = \"audited_resource\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.subscription_created.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }

  notification_channels = local.channels
  alert_strategy {
    auto_close = "1800s"
  }
}
