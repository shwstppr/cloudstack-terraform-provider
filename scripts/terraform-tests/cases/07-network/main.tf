# Isolated network. cidr/gateway/startip/endip are left unset so CloudStack
# auto-assigns them from the zone's guest CIDR pool (normal for an isolated,
# non-specifyipranges network offering).

resource "cloudstack_network" "net" {
  name             = "tf-rc-test-network"
  network_offering = var.network_offering
  zone             = var.zone
}

output "network_id" {
  value = cloudstack_network.net.id
}

output "network_cidr" {
  value = cloudstack_network.net.cidr
}
