# Smoke test: provider init + auth. No resources are created - a successful
# data source read is enough to prove the binary loads and the API
# credentials/endpoint are valid.

data "cloudstack_template" "smoke" {
  template_filter = var.template_filter

  filter {
    name  = "name"
    value = var.template_name_regex
  }
}

output "template_id" {
  value = data.cloudstack_template.smoke.id
}
