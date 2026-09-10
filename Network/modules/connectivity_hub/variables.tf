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

variable "network_self_link" {
  type = string
}

variable "hl7_subnet_cidr" {
  type = string
}

variable "labels" {
  type = map(string)
}
