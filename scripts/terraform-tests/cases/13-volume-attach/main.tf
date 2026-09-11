# Data volume creation + attach to a VM. Self-contained: creates its own
# disk offering, service offering, network and instance.

resource "cloudstack_disk_offering" "do" {
  name         = "tf-rc-test-vol-do"
  display_text = "TF RC test - volume disk offering"
  disk_size    = 5
}

resource "cloudstack_service_offering_fixed" "so" {
  name         = "tf-rc-test-vol-so"
  display_text = "TF RC test - volume service offering"
  cpu_number   = 1
  cpu_speed    = 1000
  memory       = 512
}

resource "cloudstack_network" "net" {
  name             = "tf-rc-test-vol-network"
  network_offering = var.network_offering
  zone             = var.zone
}

resource "cloudstack_instance" "vm" {
  name             = "tf-rc-test-vol-instance"
  service_offering = cloudstack_service_offering_fixed.so.id
  template         = var.template_name
  zone             = var.zone
  network_id       = cloudstack_network.net.id
  expunge          = true
}

resource "cloudstack_volume" "vol" {
  name             = "tf-rc-test-volume"
  disk_offering_id = cloudstack_disk_offering.do.id
  zone_id          = var.zone_id
}

resource "cloudstack_attach_volume" "attach" {
  volume_id           = cloudstack_volume.vol.id
  virtual_machine_id  = cloudstack_instance.vm.id
}

output "volume_id" {
  value = cloudstack_volume.vol.id
}
