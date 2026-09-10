output "hub_id" {
  value = google_network_connectivity_hub.this.id
}

output "hub_name" {
  value = google_network_connectivity_hub.this.name
}

output "main_vpc_spoke_id" {
  value = google_network_connectivity_spoke.main_vpc.id
}

output "hl7_subnet_id" {
  value = google_compute_subnetwork.hl7.id
}

output "hl7_subnet_self_link" {
  value = google_compute_subnetwork.hl7.self_link
}

output "hl7_subnet_name" {
  value = google_compute_subnetwork.hl7.name
}
