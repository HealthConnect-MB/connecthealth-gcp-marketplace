variable "project_id" {
  description = "GCP project ID the network stack is deployed into."
  type        = string
}

variable "region" {
  description = "Primary GCP region for the network stack."
  type        = string
  default     = "us-east1"
}

variable "name_prefix" {
  description = "Name prefix for network resources (mirrors AWS ProjectName-StackName)."
  type        = string
  default     = "connecthealth-network"
}

variable "project_name" {
  description = "Project name used in resource labels. GCP-side branding (AWS CF's ProjectName parameter is fixed to 'ehrconnect')."
  type        = string
  default     = "connecthealth"
}

variable "environment" {
  description = "Environment name used in resource labels. CF template only ever allows 'production'."
  type        = string
  default     = "production"
}

# --- VPC / Subnet CIDRs (same addressing as Connecthealth-CF-0.3.71-Prod.yaml AppVPC) ---
variable "vpc_cidr_block" {
  description = "CIDR block for the VPC. Matches AWS AppVPC 172.28.0.0/16."
  type        = string
  default     = "172.28.0.0/16"
}

variable "private_subnet_cidr" {
  description = "Regional private subnet CIDR for Cloud Run Direct VPC egress + Filestore mount. A single GCP regional subnet already spans all zones, unlike AWS's per-AZ PrivateSubnet1/PrivateSubnet2, so one subnet replaces both."
  type        = string
  default     = "172.28.1.0/24"
}

variable "filestore_reserved_range_cidr" {
  description = "Reserved /29+ CIDR for Filestore's private services access peering range (analogous to the EFS mount targets sitting inside PrivateSubnet1/2)."
  type        = string
  default     = "172.28.5.0/24"
}

# --- Cloud NAT (replaces the single-AZ AWS NATGateway1 - deployed per-region here) ---
variable "enable_cloud_nat" {
  description = "Enable Cloud Router + Cloud NAT for the private subnet's outbound internet access (ECR/Artifact Registry pulls, external API calls)."
  type        = bool
  default     = true
}

# --- Flow Logs (replaces VPCFlowLogsS3Bucket / EnableVPCFlowLogs condition) ---
variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs on the private subnet. GCP flow logs are a native subnet attribute (no IAM role/log-delivery pipeline needed, unlike AWS's VPCFlowLogsRole)."
  type        = bool
  default     = true
}

variable "flow_logs_sink_bucket_retention_days" {
  description = "Retention (days) for the GCS bucket flow logs are exported to via the vpc_flow_logs module's log sink."
  type        = number
  default     = 365
}

# --- Private Google Access / PSC endpoint (replaces S3 Gateway + Logs Interface VPC Endpoints) ---
variable "enable_private_service_connect" {
  description = "Create a Private Service Connect endpoint for the private-google-apis bundle, giving the private subnet a private IP to reach GCS/Firestore/Pub-Sub/Secret Manager/KMS/Logging without traversing the internet."
  type        = bool
  default     = true
}

# --- HL7 Connectivity (replaces EnableHL7Connectivity / ConnectorSupernet /
# AppHL7NLBIPAz1 / AppHL7NLBIPAz2 - renamed from EnableClientConnectivity /
# ClientConnectivityEnabled as of CF template 0.3.72). false = normal
# ConnectHealth app only. true = also create the HL7-connectivity foundation
# (NCC hub/spoke + dedicated HL7 subnet + connector-supernet firewall rules)
# that per-connector stacks attach to later. The per-connector stack itself
# (AWS's Connecthealth-CF-Connector template) is a SEPARATE, not-yet-built
# piece of work - this flag only stands up the main-stack side, matching the
# AWS HL7ConnectivityEnabled condition's scope exactly. ---
variable "enable_hl7_connectivity" {
  type    = bool
  default = false
}

variable "connector_supernet_cidr" {
  description = "Supernet covering ALL per-connector VPCs. Matches AWS ConnectorSupernet default 100.64.0.0/12."
  type        = string
  default     = "100.64.0.0/12"
}

variable "hl7_subnet_cidr" {
  description = "Dedicated subnet for the HL7 Cloud Run worker pool's Direct VPC ingress. Kept separate from private_subnet_cidr so connector-supernet firewall rules can be scoped narrowly to just this subnet (destination_ranges) rather than opening the whole private subnet to connector traffic."
  type        = string
  default     = "172.28.6.0/27"
}

variable "labels" {
  description = "Common labels for network resources (GCP label keys must be lowercase)."
  type        = map(string)
  default = {
    environment = "production"
    project     = "connecthealth"
    layer       = "network"
    compliance  = "hipaa-gdpr-soc2"
  }
}
