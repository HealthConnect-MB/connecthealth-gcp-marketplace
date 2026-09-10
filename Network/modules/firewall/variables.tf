variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "network_id" {
  type = string
}

variable "network_name" {
  type = string
}

variable "private_subnet_cidr" {
  type = string
}

variable "filestore_reserved_range_cidr" {
  type = string
}

variable "enable_hl7_connectivity" {
  type = bool
}

variable "connector_supernet_cidr" {
  type = string
}

variable "hl7_subnet_cidr" {
  type = string
}
