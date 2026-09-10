output "security_policy_id" {
  value = google_compute_security_policy.waf.id
}

# GKE's BackendConfig CRD references a Cloud Armor policy by NAME, not by the
# fully-qualified resource id - see the Helm chart's backendconfig.yaml
# (spec.securityPolicy.name) and pass this value into it.
output "security_policy_name" {
  value = google_compute_security_policy.waf.name
}
