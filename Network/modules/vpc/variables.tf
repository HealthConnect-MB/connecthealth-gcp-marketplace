variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "vpc_cidr_block" {
  description = "Reference only - GCP custom-mode VPCs are not CIDR-scoped at the network level, subnets carry the CIDR. Kept for parity with AWS AppVPC (172.28.0.0/16)."
  type        = string
  default     = "172.28.0.0/16"
}

variable "private_subnet_cidr" {
  description = "CIDR for the single regional private subnet. Regional in GCP means it already spans every zone in the region - this one subnet replaces AWS's zonal PrivateSubnet1 + PrivateSubnet2 pair (172.28.1.0/24 + 172.28.2.0/24)."
  type        = string
  default     = "172.28.1.0/24"
}

variable "enable_vpc_flow_logs" {
  type = bool
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "labels" {
  type = map(string)
}

variable "pods_cidr_block" {
  description = "Secondary CIDR block for GKE Pods"
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr_block" {
  description = "Secondary CIDR block for GKE Services"
  type        = string
  default     = "10.8.0.0/20"
}
