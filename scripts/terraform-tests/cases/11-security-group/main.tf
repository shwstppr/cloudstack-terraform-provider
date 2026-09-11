# Security group + an ingress rule. Standalone (not attached to a VM) since
# security groups require a SG-enabled zone/network offering to actually
# take effect on an instance.

resource "cloudstack_security_group" "sg" {
  name        = "tf-rc-test-sg"
  description = "TF RC test security group"
}

resource "cloudstack_security_group_rule" "sg_rule" {
  security_group_id = cloudstack_security_group.sg.id

  rule {
    cidr_list = ["0.0.0.0/0"]
    protocol  = "tcp"
    ports     = ["22"]
  }
}

output "security_group_id" {
  value = cloudstack_security_group.sg.id
}
