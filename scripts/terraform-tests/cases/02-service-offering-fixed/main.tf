# Fixed compute offering: explicit cpu_number/cpu_speed/memory.

resource "cloudstack_service_offering_fixed" "so" {
  name         = "tf-rc-test-so-fixed"
  display_text = "TF RC test - fixed offering"

  cpu_number = 1
  cpu_speed  = 1000
  memory     = 512
}

output "service_offering_id" {
  value = cloudstack_service_offering_fixed.so.id
}
