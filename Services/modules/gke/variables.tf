variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP Region"
  type        = string
}

variable "name_prefix" {
  description = "Resource naming prefix"
  type        = string
}

variable "network_id" {
  description = "VPC Network ID"
  type        = string
}

variable "subnet_id" {
  description = "Private Subnet ID"
  type        = string
}

variable "pods_range_name" {
  description = "Secondary IP range name for GKE Pods"
  type        = string
}

variable "services_range_name" {
  description = "Secondary IP range name for GKE Services"
  type        = string
}

variable "labels" {
  description = "Labels to apply to GKE resources"
  type        = map(string)
  default     = {}
}

variable "enable_deletion_protection" {
  description = "Set the cluster's Terraform-side deletion_protection guard. False by default so a deployment can be torn down from the Infrastructure Manager console without the customer needing to change anything."
  type        = bool
  default     = false
}
