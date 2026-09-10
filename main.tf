# ==============================================================================
# ConnectHealth - Google Cloud Marketplace Root Module (main.tf)
# Designed for Google Cloud Infrastructure Manager single-click automated deployment.
# ==============================================================================

# --- 1. Network Foundation ---
module "vpc" {
  source = "./Network/modules/vpc"

  project_id           = var.project_id
  region               = var.region
  name_prefix          = "${var.name_prefix}-net"
  vpc_cidr_block       = var.vpc_cidr_block
  private_subnet_cidr  = var.private_subnet_cidr
  pods_cidr_block      = var.pods_cidr_block
  services_cidr_block  = var.services_cidr_block
  enable_vpc_flow_logs = var.enable_vpc_flow_logs

  project_name = var.project_name
  environment  = var.environment
  labels       = var.labels
}

module "cloud_nat" {
  source = "./Network/modules/cloud_nat"
  count  = var.enable_cloud_nat ? 1 : 0

  project_id  = var.project_id
  region      = var.region
  name_prefix = "${var.name_prefix}-net"
  network_id  = module.vpc.network_id
  subnet_ids  = [module.vpc.private_subnet_self_link]
}

module "firewall" {
  source = "./Network/modules/firewall"

  project_id                    = var.project_id
  name_prefix                   = var.name_prefix
  network_id                    = module.vpc.network_id
  network_name                  = module.vpc.network_name
  private_subnet_cidr           = var.private_subnet_cidr
  filestore_reserved_range_cidr = var.filestore_reserved_range_cidr

  enable_hl7_connectivity = var.enable_hl7_connectivity
  connector_supernet_cidr = var.connector_supernet_cidr
  hl7_subnet_cidr         = var.hl7_subnet_cidr
}

module "connectivity_hub" {
  source = "./Network/modules/connectivity_hub"
  count  = var.enable_hl7_connectivity ? 1 : 0

  project_id        = var.project_id
  region            = var.region
  name_prefix       = var.name_prefix
  network_id        = module.vpc.network_id
  network_self_link = module.vpc.network_self_link
  hl7_subnet_cidr   = var.hl7_subnet_cidr
  labels            = var.labels
}

# Peering range + connection for Filestore
resource "google_compute_global_address" "filestore_range" {
  name          = "${var.name_prefix}-filestore-psa-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = tonumber(split("/", var.filestore_reserved_range_cidr)[1])
  network       = module.vpc.network_id
  address       = split("/", var.filestore_reserved_range_cidr)[0]
}

resource "google_service_networking_connection" "filestore" {
  network                 = module.vpc.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.filestore_range.name]
}

# --- 2. Application Services Layer (GKE-only - see Services/main.tf) ---
module "services" {
  source = "./Services"

  project_id         = var.project_id
  region             = var.region
  zone               = var.zone
  name_prefix        = var.name_prefix
  project_name       = var.project_name
  environment        = var.environment
  enable_audit_trail = var.enable_audit_trail
  enable_cloud_armor = var.enable_cloud_armor

  # Mirrors the AWS template's AdminInitialPassword parameter - surfaced in the
  # Infrastructure Manager / Marketplace deployment form.
  admin_initial_password     = var.admin_initial_password
  alert_email                = var.alert_email
  enable_deletion_protection = var.enable_deletion_protection

  app_domain           = var.app_domain
  ssl_certificate_name = var.ssl_certificate_name
  dns_managed_zone     = var.dns_managed_zone

  labels = var.labels

  # Pass network outputs in-memory (bypasses data.terraform_remote_state for Infrastructure Manager)
  network_id_override          = module.vpc.network_id
  private_subnet_id_override   = module.vpc.private_subnet_id
  pods_range_name_override     = module.vpc.pods_range_name
  services_range_name_override = module.vpc.services_range_name
}
