module "vpc" {
  source = "./modules/vpc"

  project_id           = var.project_id
  region               = var.region
  name_prefix          = var.name_prefix
  vpc_cidr_block       = var.vpc_cidr_block
  private_subnet_cidr  = var.private_subnet_cidr
  enable_vpc_flow_logs = var.enable_vpc_flow_logs

  project_name = var.project_name
  environment  = var.environment
  labels       = var.labels
}

module "cloud_nat" {
  source = "./modules/cloud_nat"
  count  = var.enable_cloud_nat ? 1 : 0

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  network_id  = module.vpc.network_id
  subnet_ids  = [module.vpc.private_subnet_self_link]
}

module "vpc_flow_logs" {
  source = "./modules/vpc_flow_logs"
  count  = var.enable_vpc_flow_logs ? 1 : 0

  project_id     = var.project_id
  name_prefix    = var.name_prefix
  retention_days = var.flow_logs_sink_bucket_retention_days
  project_name   = var.project_name
  environment    = var.environment
  labels         = var.labels
}

module "vpc_endpoints" {
  source = "./modules/vpc_endpoints"
  count  = var.enable_private_service_connect ? 1 : 0

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  network_id  = module.vpc.network_id
  subnet_id   = module.vpc.private_subnet_id
}

module "firewall" {
  source = "./modules/firewall"

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

# Replaces the HL7ConnectivityEnabled block's TGW/AppHL7NLB-subnet side
# (per-connector stacks are a separate, not-yet-built piece of work - see
# README).
module "connectivity_hub" {
  source = "./modules/connectivity_hub"
  count  = var.enable_hl7_connectivity ? 1 : 0

  project_id        = var.project_id
  region            = var.region
  name_prefix       = var.name_prefix
  network_id        = module.vpc.network_id
  network_self_link = module.vpc.network_self_link
  hl7_subnet_cidr   = var.hl7_subnet_cidr
  labels            = var.labels
}

# Reserved private-services-access range + peering for Filestore (analogous to
# the AWS EFS mount targets living inside PrivateSubnet1/PrivateSubnet2).
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
