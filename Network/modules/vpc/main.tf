# Replaces AWS AppVPC (172.28.0.0/16).
resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# ONE regional private subnet, spanning every zone in the region.
#
# This is the GCP equivalent of AWS's PrivateSubnet1 + PrivateSubnet2 pair,
# not a reduction in availability: an AWS subnet is ZONAL, so multi-AZ there
# requires one subnet per AZ. A GCP subnet is REGIONAL - it inherently spans
# all zones in its region, and a regional GKE cluster (see Services/modules/
# gke, location = region) spreads its nodes across those zones out of this
# single subnet. A second subnet would add no zone coverage whatsoever.
#
# This also carries the secondary ranges GKE needs for Pods and Services.
resource "google_compute_subnetwork" "private" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-private"
  ip_cidr_range            = var.private_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.this.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.name_prefix}-pods"
    ip_cidr_range = var.pods_cidr_block
  }

  secondary_ip_range {
    range_name    = "${var.name_prefix}-services"
    ip_cidr_range = var.services_cidr_block
  }

  dynamic "log_config" {
    for_each = var.enable_vpc_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}
