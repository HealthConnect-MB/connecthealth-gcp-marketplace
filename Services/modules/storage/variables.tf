variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "kms_key_id" {
  type = string
}

variable "run_sa_member" {
  type = string
}

variable "flows_bucket_lifecycle_days" {
  description = "Matches EHRConnectFlowsBucket's NoncurrentVersionExpirationInDays: 2555."
  type        = number
  default     = 2555
}

variable "lb_logs_bucket_lifecycle_days" {
  description = "Matches ALBAccessLogsBucket's ExpirationInDays: 2555."
  type        = number
  default     = 2555
}

variable "labels" {
  type = map(string)
}

variable "enable_deletion_protection" {
  description = "When true, buckets refuse to be destroyed while they still hold objects (force_destroy = false). False by default so a customer can tear down their deployment from the Infrastructure Manager console without editing the blueprint, which they cannot do - the source lives in a read-only bucket."
  type        = bool
  default     = false
}
