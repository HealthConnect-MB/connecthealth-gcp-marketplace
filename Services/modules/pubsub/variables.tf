variable "project_id" {
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

variable "labels" {
  type = map(string)
}
