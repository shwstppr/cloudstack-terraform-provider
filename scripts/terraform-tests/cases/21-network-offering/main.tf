# cloudstack_network_offering CRUD. See main.tf.update for the Update-path
# regression guard (a prior bug left the offering's ID unset when updating,
# so the update silently didn't target the right resource).

resource "cloudstack_network_offering" "off" {
  name          = "tf-rc-test-network-offering"
  display_text  = "TF RC test - network offering"
  guest_ip_type = "Isolated"
  traffic_type  = "Guest"
  conserve_mode = true
  enable        = true

  supported_services = [
    "Dhcp",
    "Dns",
    "SourceNat",
    "PortForwarding",
    "Firewall",
    "Lb",
    "UserData",
    "StaticNat",
  ]
}

output "network_offering_id" {
  value = cloudstack_network_offering.off.id
}
