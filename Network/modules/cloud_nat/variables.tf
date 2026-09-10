variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnet SELF-LINKS (not internal Terraform ids) Cloud NAT should provide outbound internet access for - the underlying API field requires the fully-qualified self-link."
  type        = list(string)
}
