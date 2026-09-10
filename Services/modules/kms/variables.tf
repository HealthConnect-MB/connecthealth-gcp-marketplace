variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "rotation_period_seconds" {
  description = "Key rotation period in seconds. AWS ComplianceKMSKey used EnableKeyRotation: true (annual, AWS-managed schedule); GCP requires an explicit period. Default 90 days is a common HIPAA baseline."
  type        = number
  default     = 7776000
}

variable "destroy_scheduled_duration" {
  description = "Analogous to AWS PendingWindowInDays: 30 - how long a key version is held pending destruction before it is actually destroyed."
  type        = string
  default     = "2592000s" # 30 days
}

variable "bindings" {
  description = "List of {role, member} objects granted on the crypto key - replaces the individual Sid statements in AWS ComplianceKMSKey's KeyPolicy (CloudWatch Logs, ECS Tasks, CloudTrail, SNS, CloudWatch/EventBridge)."
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}

variable "labels" {
  type = map(string)
}
