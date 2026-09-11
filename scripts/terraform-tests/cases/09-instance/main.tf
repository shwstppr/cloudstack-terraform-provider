# VM lifecycle: creates its own service offering, network and keypair so it
# can run independently of the other cases.

resource "cloudstack_service_offering_fixed" "instance_so" {
  name         = "tf-rc-test-instance-so"
  display_text = "TF RC test - instance service offering"
  cpu_number   = 1
  cpu_speed    = 1000
  memory       = 512
}

resource "cloudstack_network" "instance_net" {
  name             = "tf-rc-test-instance-network"
  network_offering = var.network_offering
  zone             = var.zone
}

resource "cloudstack_ssh_keypair" "instance_kp" {
  name = "tf-rc-test-instance-keypair"
}

resource "cloudstack_instance" "vm" {
  name              = "tf-rc-test-instance"
  service_offering  = cloudstack_service_offering_fixed.instance_so.id
  template          = var.template_name
  zone              = var.zone
  network_id        = cloudstack_network.instance_net.id
  keypair           = cloudstack_ssh_keypair.instance_kp.name
  expunge           = true
}

output "instance_id" {
  value = cloudstack_instance.vm.id
}

output "instance_ip_address" {
  value = cloudstack_instance.vm.ip_address
}
