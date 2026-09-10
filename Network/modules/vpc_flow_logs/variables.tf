variable "project_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "retention_days" {
  type = number
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
