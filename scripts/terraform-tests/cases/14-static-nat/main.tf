# Static NAT between a VM and a dedicated acquired IP (not the network's own
# source-NAT IP - static NAT 1:1 maps a separate public IP to the VM).
# Self-contained: creates its own offering, network and instance.
#
# The network must already have its own source NAT IP (source_nat_ip = true)
# before acquiring the second IP below - otherwise CloudStack designates the
# very first IP ever associated with a new isolated network as its source
# NAT IP, which then can't be used for static NAT.

resource "cloudstack_service_offering_fixed" "so" {
  name         = "tf-rc-test-snat-so"
  display_text = "TF RC test - static NAT service offering"
  cpu_number   = 1
  cpu_speed    = 1000
  memory       = 512
}

resource "cloudstack_network" "net" {
  name             = "tf-rc-test-snat-network"
  network_offering = var.network_offering
  zone             = var.zone
  source_nat_ip    = true
}

resource "cloudstack_instance" "vm" {
  name             = "tf-rc-test-snat-instance"
  service_offering = cloudstack_service_offering_fixed.so.id
  template         = var.template_name
  zone             = var.zone
  network_id       = cloudstack_network.net.id
  expunge          = true
}

resource "cloudstack_ipaddress" "ip" {
  network_id = cloudstack_network.net.id
}

resource "cloudstack_static_nat" "snat" {
  ip_address_id      = cloudstack_ipaddress.ip.id
  virtual_machine_id = cloudstack_instance.vm.id
}

output "static_nat_ip" {
  value = cloudstack_ipaddress.ip.ip_address
}
