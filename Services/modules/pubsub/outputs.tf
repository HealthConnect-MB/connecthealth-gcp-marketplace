output "alerts_topic_id" {
  value = google_pubsub_topic.alerts.id
}

output "alerts_topic_name" {
  value = google_pubsub_topic.alerts.name
}

output "container_sync_topic_id" {
  value = google_pubsub_topic.container_sync.id
}

output "container_sync_topic_name" {
  value = google_pubsub_topic.container_sync.name
}
