output "notification_channel_id" {
  value = var.alert_email != "" ? google_monitoring_notification_channel.email[0].id : null
}
