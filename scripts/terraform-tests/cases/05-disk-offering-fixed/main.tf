# Fixed-size disk offering (disk_size and customized are mutually exclusive).

resource "cloudstack_disk_offering" "do" {
  name         = "tf-rc-test-do-fixed"
  display_text = "TF RC test - fixed disk offering"
  disk_size    = 5
}

output "disk_offering_id" {
  value = cloudstack_disk_offering.do.id
}
