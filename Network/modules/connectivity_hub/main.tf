# Replaces ConnectHealthTransitGateway + ConnectHealthTGWAttachment +
# ConnectHealthTGWRouteTable + ConnectHealthTGWAssoc (the TGW side of
# HL7ConnectivityEnabled, renamed from ClientConnectivityEnabled as of CF
# 0.3.72). Network Connectivity Center (NCC) is GCP's hub-and-spoke
# equivalent of Transit Gateway.
#
# STRUCTURAL DIFFERENCE FROM AWS: AWS TGW requires an explicit
# AWS::EC2::Route in EACH attached VPC's route table pointing traffic at the
# TGW attachment (that's what PrivateRouteToConnectors did in the AWS
# template) - without it, the VPC has no way to know traffic for other
# TGW-reachable CIDRs should go to the TGW ENI. NCC does NOT need this: once
# a VPC is attached as a spoke, NCC exchanges routes with every other spoke
# on the same hub automatically (subject to the export/import range filters
# below) - no manual google_compute_route resource is needed or created
# here. When a per-client connector VPC is later attached as its own spoke
# on this same hub, this main VPC starts learning that connector's routes
# with zero additional Terraform in this stack.
resource "google_network_connectivity_hub" "this" {
  project     = var.project_id
  name        = "${var.name_prefix}-hub"
  description = "ConnectHealth client-connectivity hub - replaces AWS ConnectHealthTransitGateway."
  labels      = var.labels
}

resource "google_network_connectivity_spoke" "main_vpc" {
  project     = var.project_id
  name        = "${var.name_prefix}-main-vpc-spoke"
  location    = "global"
  description = "Main ConnectHealth VPC attached to the hub - replaces ConnectHealthTGWAttachment."
  hub         = google_network_connectivity_hub.this.id

  linked_vpc_network {
    uri = var.network_self_link
    # No exclude/include_export_ranges set: export every subnet in this VPC
    # to other spokes (matches AWS's TGW route table having no filtering -
    # ConnectHealthTGWRouteTable propagated everything it was associated
    # with).
  }

  labels = var.labels
}

# Dedicated subnet for the HL7 Cloud Run worker pool's Direct VPC ingress.
# Kept separate from the app's private_subnet (used by Cloud Run
# services/Filestore) so the connector-supernet firewall rules in
# ../firewall can scope to exactly this range via destination_ranges,
# without opening the whole private subnet to connector traffic.
resource "google_compute_subnetwork" "hl7" {
  project       = var.project_id
  name          = "${var.name_prefix}-hl7"
  ip_cidr_range = var.hl7_subnet_cidr
  region        = var.region
  network       = var.network_id
}
