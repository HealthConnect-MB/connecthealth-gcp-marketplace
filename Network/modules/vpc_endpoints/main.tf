# Replaces AWS S3VPCEndpoint (Gateway) + LogsVPCEndpoint (Interface) +
# VPCEndpointSecurityGroup combined. A single Private Service Connect
# endpoint targeting Google's "all APIs" bundle covers private access to GCS,
# Firestore, Pub/Sub, Secret Manager, KMS, and Cloud Logging simultaneously -
# where AWS needed one endpoint resource per service family.
resource "google_compute_global_address" "psc_endpoint_ip" {
  project      = var.project_id
  name         = "${var.name_prefix}-psc-google-apis-ip"
  address_type = "INTERNAL"
  purpose      = "PRIVATE_SERVICE_CONNECT"
  network      = var.network_id
  # Unlike a regional internal address, GCP does NOT auto-assign an address
  # for a global PRIVATE_SERVICE_CONNECT address - omitting it sends an
  # empty string and the API rejects it ("Invalid value for field
  # 'resource.address'"). Must be explicit. Chosen outside every
  # subnet/secondary range this VPC uses in any environment (dev
  # 172.29.0.0/16, prod 172.28.0.0/16, GKE pods 10.4.0.0/14, GKE services
  # 10.8.0.0/20) - it's a global PSC VIP, not tied to a subnet's L2/L3
  # segment, so it just needs to be a stable, unused RFC1918 address.
  address = "10.255.255.5"
}

resource "google_compute_global_forwarding_rule" "psc_endpoint" {
  project = var.project_id
  # PSC "all-apis" forwarding rule names have a much stricter constraint than
  # normal GCE resources: 1-20 characters, lowercase letters/numbers only, no
  # hyphens, must start with a letter. "${name_prefix}-psc-google-apis" (e.g.
  # "connecthealth-dev-network-psc-google-apis") is both too long and has
  # hyphens. md5() output is lowercase hex (letters+digits only, no
  # hyphens), so hashing name_prefix gives a compliant, deterministic,
  # per-environment-unique name instead.
  name                  = "psc${substr(md5(var.name_prefix), 0, 17)}"
  target                = "all-apis"
  network               = var.network_id
  ip_address            = google_compute_global_address.psc_endpoint_ip.id
  load_balancing_scheme = ""
}
