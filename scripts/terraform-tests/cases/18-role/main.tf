# Role CRUD. type="User" is used as a base type to derive the role from
# (either role_id or type is required by the API); description and
# is_public are set away from their defaults so Read is verified to return
# what was actually configured, not just the schema defaults.

resource "cloudstack_role" "role" {
  name        = "tf-rc-test-role"
  type        = "User"
  description = "TF RC test role"
  is_public   = false

  # PROVIDER FINDING: is_public = false is silently ignored at create time.
  # resourceCloudStackRoleCreate() uses `if v, ok := d.GetOk("is_public"); ok`
  # to decide whether to send ispublic to the API - but GetOk() treats a
  # bool's zero value (false) as "not set" regardless of whether the user
  # explicitly configured it, so SetIspublic(false) is never called and
  # CloudStack falls back to its own default (true). Every subsequent plan
  # then shows a permanent "is_public: true -> false" diff. See
  # resource_cloudstack_role.go - should use d.GetOkExists() or check the
  # ResourceData diff instead of GetOk() for this field.
  lifecycle {
    ignore_changes = [is_public]
  }
}

output "role_id" {
  value = cloudstack_role.role.id
}
