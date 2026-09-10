# ==============================================================================
# ConnectHealth - GKE Cluster Module (main.tf)
# Provisions an Autopilot GKE cluster with Workload Identity and private nodes.
#
# Autopilot only. Standard mode (a gke_autopilot toggle plus a
# google_container_node_pool with machine_type/disk_size/autoscaling) was
# removed: it was never used by any environment, and carrying it meant the
# module advertised knobs - node count, machine type, disk size - that have no
# effect on the mode actually deployed. Autopilot rejects node pool
# configuration outright ("Autopilot node pools cannot be accessed or
# modified"), so those inputs could only ever mislead whoever set them.
#
# Google manages nodes, scaling, security and upgrades; billing is per Pod
# resource request. Vertical Pod Autoscaling is always on.
# ==============================================================================

resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = "${var.name_prefix}-gke-cluster"
  location = var.region

  network    = var.network_id
  subnetwork = var.subnet_id

  # A provider-side guard (not a GKE API setting) that defaults to true and
  # blocks `terraform destroy` - which is exactly what the Infrastructure
  # Manager console runs when a customer deletes their deployment. It is read
  # from Terraform STATE, so a customer cannot change it during a delete; left
  # at the provider default, every teardown is a dead end for them.
  #
  # Note the guard is weaker than it appears anyway: gcloud deletes the cluster
  # regardless, because this only constrains Terraform.
  deletion_protection = var.enable_deletion_protection

  # Not a variable: this module is Autopilot-only. enable_autopilot is also
  # immutable in the API - flipping it would force cluster replacement, which
  # for a live cluster means destroying the workload, so it must not be
  # reachable from an input.
  enable_autopilot = true

  # Workload Identity — secure pod-level GCP API authentication
  # (No static credentials in containers. Autopilot enables this by default)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private Cluster — worker nodes have no external IP addresses
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # Public control plane endpoint for kubectl / CI/CD
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Secondary IP ranges for GKE Pods and Services
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Vertical Pod Autoscaling — required and auto-enabled for Autopilot
  vertical_pod_autoscaling {
    enabled = true
  }

  # REGULAR channel: automatic minor upgrades with stability
  release_channel {
    channel = "REGULAR"
  }

  # Resource labels
  resource_labels = var.labels

  lifecycle {
    ignore_changes = [
      # Autopilot may adjust these fields automatically
      resource_labels,
    ]
  }
}
