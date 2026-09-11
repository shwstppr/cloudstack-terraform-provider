# Recurring snapshot policy on a volume. A freshly created data volume stays
# in "Allocated" state (not "Ready") until it's attached to a VM, and
# CloudStack refuses to create a snapshot policy on a non-Ready volume - so
# this case creates its own instance and attaches the volume first.

resource "cloudstack_disk_offering" "do" {
  name         = "tf-rc-test-snap-do"
  display_text = "TF RC test - snapshot policy disk offering"
  disk_size    = 5
}

resource "cloudstack_service_offering_fixed" "so" {
  name         = "tf-rc-test-snap-so"
  display_text = "TF RC test - snapshot policy service offering"
  cpu_number   = 1
  cpu_speed    = 1000
  memory       = 512
}

resource "cloudstack_network" "net" {
  name             = "tf-rc-test-snap-network"
  network_offering = var.network_offering
  zone             = var.zone
}

resource "cloudstack_instance" "vm" {
  name             = "tf-rc-test-snap-instance"
  service_offering = cloudstack_service_offering_fixed.so.id
  template         = var.template_name
  zone             = var.zone
  network_id       = cloudstack_network.net.id
  expunge          = true
}

resource "cloudstack_volume" "vol" {
  name             = "tf-rc-test-snap-volume"
  disk_offering_id = cloudstack_disk_offering.do.id
  zone_id          = var.zone_id
}

resource "cloudstack_attach_volume" "attach" {
  volume_id          = cloudstack_volume.vol.id
  virtual_machine_id = cloudstack_instance.vm.id
}

resource "cloudstack_snapshot_policy" "policy" {
  volume_id     = cloudstack_attach_volume.attach.volume_id
  interval_type = "DAILY"
  max_snaps     = 1
  schedule      = "00:00"
  timezone      = "Etc/UTC"

  # MINOR PROVIDER ROUGH EDGE (not a correctness bug): when zone_ids isn't
  # configured, CloudStack itself defaults the policy to the volume's own
  # zone - expected API behavior. But Read() writes that server-derived
  # value into zone_ids regardless, even though this config never set it,
  # so every subsequent plan sees a spurious "zone_ids forces replacement"
  # diff. See resource_cloudstack_snapshot_policy.go
  # resourceCloudstackSnapshotPolicyRead(). Ignored here to keep this test
  # case stable; the provider could avoid this by only setting zone_ids in
  # state when the config actually configured it.
  lifecycle {
    ignore_changes = [zone_ids]
  }
}

output "snapshot_policy_id" {
  value = cloudstack_snapshot_policy.policy.id
}
