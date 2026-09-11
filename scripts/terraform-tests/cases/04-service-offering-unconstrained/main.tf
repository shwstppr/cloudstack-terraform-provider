# Unconstrained compute offering: no cpu/memory fields at all - fully
# customizable at VM-deploy time.

resource "cloudstack_service_offering_unconstrained" "so" {
  name         = "tf-rc-test-so-unconstrained"
  display_text = "TF RC test - unconstrained offering"
}

output "service_offering_id" {
  value = cloudstack_service_offering_unconstrained.so.id
}
