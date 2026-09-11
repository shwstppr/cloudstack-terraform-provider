# Template data source lookup, verifying the computed metadata fields
# (distinct from case 01, which only checks that auth/connectivity works).

data "cloudstack_template" "tpl" {
  template_filter = var.template_filter

  filter {
    name  = "name"
    value = var.template_name_regex
  }
}

output "template_format" {
  value = data.cloudstack_template.tpl.format
}

output "template_hypervisor" {
  value = data.cloudstack_template.tpl.hypervisor
}

output "template_size" {
  value = data.cloudstack_template.tpl.size
}
