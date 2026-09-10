output "key_id" {
  value = google_kms_crypto_key.compliance.id
}

output "key_ring_id" {
  value = google_kms_key_ring.this.id
}

output "key_name" {
  value = google_kms_crypto_key.compliance.name
}
