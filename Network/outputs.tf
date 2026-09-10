output "network_id" {
  value       = module.vpc.network_id
  description = "VPC network self-link/ID."
}

output "network_name" {
  value       = module.vpc.network_name
  description = "VPC network name."
}

output "vpc_cidr_block" {
  value       = var.vpc_cidr_block
  description = "VPC CIDR block."
}

output "private_subnet_id" {
  value       = module.vpc.private_subnet_id
  description = "Private subnet ID (Cloud Run Direct VPC egress + Filestore attach here)."
}

output "private_subnet_self_link" {
  value       = module.vpc.private_subnet_self_link
  description = "Private subnet self-link, consumed by Services stack's Cloud Run VPC access config."
}

output "private_subnet_cidr" {
  value       = var.private_subnet_cidr
  description = "Private subnet CIDR block."
}

# --- GKE secondary range names, consumed by the Services stack ---
# These MUST be published here. Services/main.tf reads them from this stack's
# remote state to tell GKE which secondary ranges to use for Pods and
# Services. They were previously missing, and Services' `try(...)` fallback
# silently substituted "${services name_prefix}-pods" - which resolves to a
# DIFFERENT name than the range this stack actually creates (Network's
# name_prefix carries a "-network" suffix). The result was a cluster create
# failing with 'Pod secondary range "connecthealth-dev-pods" not found'.
output "pods_range_name" {
  value       = module.vpc.pods_range_name
  description = "Name of the subnet's secondary IP range for GKE Pods."
}

output "services_range_name" {
  value       = module.vpc.services_range_name
  description = "Name of the subnet's secondary IP range for GKE Services."
}

output "filestore_private_service_connection" {
  value       = google_service_networking_connection.filestore.network
  description = "Confirms the private-services-access peering used by Filestore is established."
}

output "psc_endpoint_ip" {
  value       = var.enable_private_service_connect ? module.vpc_endpoints[0].psc_endpoint_ip : null
  description = "Private Service Connect endpoint IP for Google APIs (replaces AWS S3 Gateway + Logs Interface VPC Endpoints)."
}

output "cloud_nat_name" {
  value       = var.enable_cloud_nat ? module.cloud_nat[0].nat_name : null
  description = "Cloud NAT name (replaces AWS NATGateway1)."
}

output "flow_logs_sink_bucket" {
  value       = var.enable_vpc_flow_logs ? module.vpc_flow_logs[0].sink_bucket_name : null
  description = "GCS bucket flow logs are routed to for long-term retention."
}

# --- HL7 Connectivity outputs (only present when enabled) ---
output "hl7_connectivity_enabled" {
  value       = var.enable_hl7_connectivity
  description = "Whether the HL7-connectivity layer was created. Matches AWS HL7ConnectivityEnabledOut."
}

output "connectivity_hub_id" {
  value       = var.enable_hl7_connectivity ? module.connectivity_hub[0].hub_id : null
  description = "NCC hub ID - future per-connector stacks attach here as additional spokes. Replaces AWS TransitGatewayId output."
}

output "connectivity_hub_main_vpc_spoke_id" {
  value       = var.enable_hl7_connectivity ? module.connectivity_hub[0].main_vpc_spoke_id : null
  description = "Replaces AWS VPCAttachmentId output."
}

output "hl7_subnet_id" {
  value       = var.enable_hl7_connectivity ? module.connectivity_hub[0].hl7_subnet_id : null
  description = "Dedicated subnet for the HL7 Cloud Run worker pool's Direct VPC ingress."
}

output "hl7_subnet_self_link" {
  value       = var.enable_hl7_connectivity ? module.connectivity_hub[0].hl7_subnet_self_link : null
  description = "Consumed by the Services stack's hl7-worker module."
}

output "connector_supernet_cidr" {
  value       = var.enable_hl7_connectivity ? var.connector_supernet_cidr : null
  description = "Replaces AWS ConnectorSupernetOut output."
}
