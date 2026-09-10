output "deny_all_egress_rule" {
  value = google_compute_firewall.deny_all_egress.name
}
