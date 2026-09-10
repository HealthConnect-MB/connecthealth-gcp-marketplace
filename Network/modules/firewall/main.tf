# Replaces the ~25 numbered PrivateSubnetNACL/PublicSubnetNACL entries plus
# ALBSecurityGroup/ECSTaskSecurityGroup/VPCEndpointSecurityGroup/
# EFSSecurityGroup ingress+egress rules.
#
# Two structural differences from the AWS original, both intentional:
#   1. GCP VPC firewall is STATEFUL (like an AWS security group), not
#      stateless like an AWS NACL - so there is no "ephemeral return traffic"
#      rule to write; return traffic for an allowed connection is automatic.
#   2. Cloud Run has no NIC sitting inside the VPC the way an ECS task does.
#      Only EGRESS from Cloud Run's Direct VPC egress interface is subject to
#      these rules; INGRESS to the Cloud Run service is controlled by the LB
#      attachment + Cloud Run's own --ingress setting (see load-balancer and
#      cloud-run modules), not by VPC firewall - there is no ECSTaskSecurity-
#      Group-style ingress-from-ALB rule to replicate here.
#
# Default GCP behavior is allow-all-egress / deny-all-ingress. To replicate
# AWS's explicit-allow-only egress posture (ECSTaskSecurityGroupEgress* had no
# blanket allow), we add a low-priority deny-all-egress rule and punch narrow
# holes above it.

resource "google_compute_firewall" "deny_all_egress" {
  project   = var.project_id
  name      = "${var.name_prefix}-deny-all-egress"
  network   = var.network_name
  direction = "EGRESS"
  priority  = 65534
  deny {
    protocol = "all"
  }
  destination_ranges = ["0.0.0.0/0"]
}

# Replaces EFSSecurityGroupIngressFromECS / EFSSecurityGroupEgressToECS /
# ECSTaskSecurityGroupEgressToEFS (NFS 2049 between ECS tasks and EFS mount
# targets in PrivateSubnet1/2).
resource "google_compute_firewall" "allow_egress_to_filestore" {
  project   = var.project_id
  name      = "${var.name_prefix}-allow-egress-filestore-nfs"
  network   = var.network_name
  direction = "EGRESS"
  priority  = 1000

  # Filestore Basic/STANDARD serves NFSv3 (the chart mounts with vers=3), which
  # needs more than the data port: 111 is the RPC portmapper the client hits
  # first to locate the other daemons, 2046/2050 are mountd/status and 4045 is
  # the lock manager. Opening only 2049 - correct for NFSv4 - lets the mount
  # hang and fail with DeadlineExceeded rather than being refused outright,
  # because the portmapper call is silently dropped by deny-all-egress.
  allow {
    protocol = "tcp"
    ports    = ["111", "2046", "2049", "2050", "4045"]
  }
  allow {
    protocol = "udp"
    ports    = ["111", "2046", "2049", "2050", "4045"]
  }
  destination_ranges = [var.filestore_reserved_range_cidr]
}

# Replaces ECSTaskSecurityGroupEgressToVPCEndpoint / VPCEndpointSecurityGroup*
# (HTTPS 443 from ECS tasks to the S3 Gateway + Logs Interface VPC Endpoints).
# Here the destination is the PSC "all Google APIs" endpoint IP, which lives
# inside the private subnet's own range.
resource "google_compute_firewall" "allow_egress_to_google_apis_psc" {
  project   = var.project_id
  name      = "${var.name_prefix}-allow-egress-psc-https"
  network   = var.network_name
  direction = "EGRESS"
  priority  = 1000
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  destination_ranges = [var.private_subnet_cidr]
}

# Replaces NACLOutboundHTTPS / PublicNACLOutboundHTTPS (443 to internet via
# NAT for ECR/Secrets Manager/AWS APIs). Only relevant if the cloud-run
# module's VPC egress setting is ALL_TRAFFIC (routes public-internet-bound
# calls through the VPC / Cloud NAT too) rather than the default
# PRIVATE_RANGES_ONLY, where public internet calls bypass the VPC entirely
# and this rule is a no-op safety net.
resource "google_compute_firewall" "allow_egress_https_internet" {
  project   = var.project_id
  name      = "${var.name_prefix}-allow-egress-internet-https"
  network   = var.network_name
  direction = "EGRESS"
  priority  = 1000
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  destination_ranges = ["0.0.0.0/0"]
}

# -----------------------------------------------------------------------
# HL7 CONNECTIVITY (conditional on enable_hl7_connectivity) - replaces
# ECSTaskSGIngressFromConnectors / ECSTaskSGEgressToConnectors /
# ECSTaskSGEgressReturnToConnectors / PrivateNACLInboundConnectorHL7 /
# PrivateNACLInboundConnectorEphemeral / PrivateNACLOutboundConnectorHL7 /
# PrivateNACLOutboundConnectorEphemeral.
#
# Scoped via destination_ranges/source_ranges to the dedicated HL7 subnet
# rather than via network tags: Google's own documentation notes that
# network tags cannot be used to target ingress firewall rules at Cloud Run
# worker pool instances, so CIDR-based scoping (the HL7 subnet is dedicated
# to the worker pool and nothing else) is the reliable mechanism here - not
# a simplification, a deliberate substitute for a targeting method that
# doesn't work for this resource type.
# -----------------------------------------------------------------------

# Replaces ECSTaskSGIngressFromConnectors + PrivateNACLInboundConnectorHL7.
resource "google_compute_firewall" "allow_ingress_hl7_from_connectors" {
  count     = var.enable_hl7_connectivity ? 1 : 0
  project   = var.project_id
  name      = "${var.name_prefix}-allow-ingress-hl7-from-connectors"
  network   = var.network_name
  direction = "INGRESS"
  priority  = 1000
  allow {
    protocol = "tcp"
    ports    = ["2575"]
  }
  source_ranges      = [var.connector_supernet_cidr]
  destination_ranges = [var.hl7_subnet_cidr]
  description        = "Inbound HL7 from any connector NLB. Destination scoped to the dedicated HL7 subnet only."
}

# Replaces ECSTaskSGEgressToConnectors + ECSTaskSGEgressReturnToConnectors +
# PrivateNACLOutboundConnectorHL7/Ephemeral. AWS split this into an
# any-port-outbound rule and a separate ephemeral-return rule because NACLs
# are stateless; one stateful rule covers both here (see the module-level
# comment on why GCP firewall needs no "ephemeral return" counterpart).
resource "google_compute_firewall" "allow_egress_hl7_to_connectors" {
  count     = var.enable_hl7_connectivity ? 1 : 0
  project   = var.project_id
  name      = "${var.name_prefix}-allow-egress-hl7-to-connectors"
  network   = var.network_name
  direction = "EGRESS"
  priority  = 1000
  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }
  destination_ranges = [var.connector_supernet_cidr]
  description        = "Outbound HL7 + reply traffic to any connector NLB."
}
