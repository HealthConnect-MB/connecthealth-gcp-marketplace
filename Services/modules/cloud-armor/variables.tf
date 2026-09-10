variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "rate_limit_threshold_count" {
  description = "Matches WebACL RateLimitRule Limit: 2000 (requests per 5-minute evaluation window, per IP)."
  type        = number
  default     = 2000
}

variable "body_size_limit_bytes" {
  description = "Matches WebACL CustomBodySizeLimit Size: 5242880 (5 MiB)."
  type        = number
  default     = 5242880
}

# Cloud Armor Managed Protection PLUS feature. The standard pay-as-you-go
# tier rejects any policy containing evaluateThreatIntelligence(), so this
# stays off unless the project is known to have a Plus subscription.
variable "enable_threat_intelligence" {
  description = "Enable the known-malicious-IP (Threat Intelligence) rule. REQUIRES a Cloud Armor Managed Protection Plus subscription - the policy fails to create on the standard tier if this is true."
  type        = bool
  default     = false
}
