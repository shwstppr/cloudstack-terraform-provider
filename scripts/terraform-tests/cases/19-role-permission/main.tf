# Role permission ordering/reconciliation test.
#
# `permission` is an ordered list - rules are evaluated top to bottom.
# Reordering/inserting/removing entries in that list exercises ID/order
# reconciliation, which a single create+destroy can't cover. See
# main.tf.update for the second phase: this initial config just creates the
# role and an ordered 3-rule permission list.

resource "cloudstack_role" "role" {
  name        = "tf-rc-test-role-permission"
  type        = "User"
  description = "TF RC test - role permission ordering"
}

resource "cloudstack_role_permission" "perms" {
  role_id       = cloudstack_role.role.id
  authoritative = true

  permission {
    rule        = "listVirtualMachines"
    permission  = "allow"
    description = "allow list vm"
  }
  permission {
    rule        = "createVirtualMachine"
    permission  = "allow"
    description = "allow create vm"
  }
  permission {
    rule        = "deleteVirtualMachine"
    permission  = "deny"
    description = "deny delete vm"
  }
}

output "role_permission_ids" {
  value = cloudstack_role_permission.perms.permission[*].id
}
