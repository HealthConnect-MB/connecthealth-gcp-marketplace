variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "alert_email" {
  description = "Matches CF AlertEmail parameter. Empty string disables the notification channel, matching HasAlertEmail condition."
  type        = string
  default     = ""
}

variable "container_sync_topic_name" {
  type = string
}

variable "firestore_database_name" {
  type = string
}

variable "cpu_threshold_percent" {
  description = "Matches HighCPUAlarm Threshold: 80."
  type        = number
  default     = 80
}

variable "memory_threshold_percent" {
  description = "Matches HighMemoryAlarm Threshold: 80."
  type        = number
  default     = 80
}

variable "lb_response_time_threshold_sec" {
  description = "Matches ALBResponseTimeAlarm Threshold: 1."
  type        = number
  default     = 1
}

variable "lb_5xx_threshold_count" {
  description = "Matches ALBErrorRateAlarm Threshold: 5."
  type        = number
  default     = 5
}

variable "pubsub_backlog_threshold_count" {
  description = "Matches SQSMessagesVisibleAlarm Threshold: 100."
  type        = number
  default     = 100
}

variable "pubsub_oldest_message_age_threshold_sec" {
  description = "Matches SQSOldestMessageAgeAlarm Threshold: 300."
  type        = number
  default     = 300
}

variable "pubsub_send_rate_threshold_count" {
  description = "Matches SQSMessageSendRateAlarm Threshold: 10000."
  type        = number
  default     = 10000
}

variable "firestore_latency_threshold_ms" {
  description = "Matches DynamoDBReadLatencyAlarm/WriteLatencyAlarm/QueryLatencyAlarm Threshold: 100."
  type        = number
  default     = 100
}

# --- GKE scoping for the CPU/memory policies (replaces the Cloud Run service
# names these used to filter on) ---
variable "gke_cluster_name" {
  description = "Cluster whose containers the CPU/memory alert policies watch."
  type        = string
}

variable "gke_namespace" {
  description = "Namespace the application runs in."
  type        = string
  default     = "default"
}

variable "gke_container_name" {
  description = "Container name the CPU/memory policies are scoped to."
  type        = string
  default     = "connecthealth-be"
}
