# Constrained compute offering: customizable within a min/max CPU+memory range.

resource "cloudstack_service_offering_constrained" "so" {
  name         = "tf-rc-test-so-constrained"
  display_text = "TF RC test - constrained offering"

  cpu_speed      = 1000
  min_cpu_number = 1
  max_cpu_number = 2
  min_memory     = 512
  max_memory     = 1024
}

output "service_offering_id" {
  value = cloudstack_service_offering_constrained.so.id
}
