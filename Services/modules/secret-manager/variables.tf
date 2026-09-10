variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "run_sa_member" {
  type = string
}

variable "admin_initial_password" {
  description = "Initial password for the built-in 'administrator' account, mirroring the AWS template's AdminInitialPassword parameter. Leave empty to have Terraform generate a strong random one instead; either way the value is readable from the Secret Manager secret named by the default_password_secret output. Must be changed at first login - the application forces a reset."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    # Matches the AWS parameter's MinLength: 8.
    condition     = var.admin_initial_password == "" || length(var.admin_initial_password) >= 8
    error_message = "admin_initial_password must be at least 8 characters (matching the AWS template's MinLength), or empty to auto-generate."
  }
}
