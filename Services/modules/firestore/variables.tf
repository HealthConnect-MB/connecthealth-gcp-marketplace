variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "run_sa_member" {
  type = string
}

variable "enable_deletion_protection" {
  description = "When true, the Firestore database refuses deletion. False by default so a customer teardown from the Infrastructure Manager console succeeds - point-in-time recovery stays enabled either way."
  type        = bool
  default     = false
}
