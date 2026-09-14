# cloudstack_vpc_offering CRUD. internet_protocol and routing_mode are set
# in lowercase deliberately: CloudStack normalizes and returns these as
# "IPv4"/"Static" etc, and there was a fix for a case-mismatch bug that
# caused a perpetual replace loop here. A clean no-drift plan after apply
# is a regression guard for that fix (DiffSuppressFunc using
# strings.EqualFold in resource_cloudstack_vpc_offering.go).

resource "cloudstack_vpc_offering" "off" {
  name         = "tf-rc-test-vpc-offering"
  display_text = "TF RC test - VPC offering"

  supported_services = [
    "Dhcp",
    "Dns",
    "SourceNat",
    "PortForwarding",
    "Lb",
    "UserData",
    "StaticNat",
    "NetworkACL",
  ]

  internet_protocol = "ipv4"
  routing_mode      = "static"
  enable            = true
}

output "vpc_offering_id" {
  value = cloudstack_vpc_offering.off.id
}
