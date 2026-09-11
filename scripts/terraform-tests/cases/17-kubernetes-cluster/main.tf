# Kubernetes cluster - optional and environment-dependent (needs a
# Kubernetes ISO/version registered in CloudStack). Creates 0 instances
# (a safe no-op) when var.kubernetes_version is left empty.

resource "cloudstack_service_offering_fixed" "k8s_so" {
  count        = var.kubernetes_version == "" ? 0 : 1
  name         = "tf-rc-test-k8s-so"
  display_text = "TF RC test - kubernetes service offering"
  cpu_number   = 2
  cpu_speed    = 1000
  memory       = 2048
}

resource "cloudstack_network" "k8s_net" {
  count            = var.kubernetes_version == "" ? 0 : 1
  name             = "tf-rc-test-k8s-network"
  network_offering = var.network_offering
  zone             = var.zone
}

resource "cloudstack_kubernetes_cluster" "cluster" {
  count              = var.kubernetes_version == "" ? 0 : 1
  name               = "tf-rc-test-k8s-cluster"
  zone               = var.zone
  kubernetes_version = var.kubernetes_version
  service_offering   = cloudstack_service_offering_fixed.k8s_so[0].id
  network_id         = cloudstack_network.k8s_net[0].id
  size               = 1
}

output "kubernetes_cluster_id" {
  value = var.kubernetes_version == "" ? "skipped (kubernetes_version not set)" : cloudstack_kubernetes_cluster.cluster[0].id
}
