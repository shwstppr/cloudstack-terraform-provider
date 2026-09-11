# Customized disk offering: size chosen at volume/VM creation time
# (disk_size and customized are mutually exclusive).

resource "cloudstack_disk_offering" "do" {
  name         = "tf-rc-test-do-customized"
  display_text = "TF RC test - customized disk offering"
  customized   = true
}

output "disk_offering_id" {
  value = cloudstack_disk_offering.do.id
}
