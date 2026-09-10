output "network_id" {
  value = google_compute_network.this.id
}

output "network_name" {
  value = google_compute_network.this.name
}

output "network_self_link" {
  value = google_compute_network.this.self_link
}

# --- Single regional private subnet (spans all zones in the region - see
# main.tf for why this replaces AWS's zonal PrivateSubnet1/PrivateSubnet2) ---
output "private_subnet_id" {
  value       = google_compute_subnetwork.private.id
  description = "Regional private subnet ID - GKE nodes across every zone in the region are allocated from this one subnet."
}

output "private_subnet_self_link" {
  value = google_compute_subnetwork.private.self_link
}

output "private_subnet_cidr" {
  value = google_compute_subnetwork.private.ip_cidr_range
}

output "pods_range_name" {
  value = "${var.name_prefix}-pods"
}

output "services_range_name" {
  value = "${var.name_prefix}-services"
}
