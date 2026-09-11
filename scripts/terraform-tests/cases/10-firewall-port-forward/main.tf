# Firewall + port forwarding rules against a VM's own source-NAT IP.
# Self-contained: creates its own offering, network (with a source NAT IP)
# and instance.

resource "cloudstack_service_offering_fixed" "so" {
  name         = "tf-rc-test-fw-so"
  display_text = "TF RC test - firewall/port-forward service offering"
  cpu_number   = 1
  cpu_speed    = 1000
  memory       = 512
}

resource "cloudstack_network" "net" {
  name             = "tf-rc-test-fw-network"
  network_offering = var.network_offering
  zone             = var.zone
  source_nat_ip    = true
}

resource "cloudstack_instance" "vm" {
  name             = "tf-rc-test-fw-instance"
  service_offering = cloudstack_service_offering_fixed.so.id
  template         = var.template_name
  zone             = var.zone
  network_id       = cloudstack_network.net.id
  expunge          = true
}

resource "cloudstack_firewall" "fw" {
  ip_address_id = cloudstack_network.net.source_nat_ip_id

  rule {
    cidr_list = ["0.0.0.0/0"]
    protocol  = "tcp"
    ports     = ["22"]
  }
}

resource "cloudstack_port_forward" "pf" {
  ip_address_id = cloudstack_network.net.source_nat_ip_id

  forward {
    protocol           = "tcp"
    private_port       = 22
    public_port        = 2222
    virtual_machine_id = cloudstack_instance.vm.id
  }
}

output "source_nat_ip" {
  value = cloudstack_network.net.source_nat_ip_address
}
