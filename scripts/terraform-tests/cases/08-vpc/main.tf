# VPC, referencing a pre-existing VPC offering by name (var.vpc_offering).

resource "cloudstack_vpc" "vpc" {
  name         = "tf-rc-test-vpc"
  cidr         = "10.250.0.0/16"
  vpc_offering = var.vpc_offering
  zone         = var.zone
}

output "vpc_id" {
  value = cloudstack_vpc.vpc.id
}

output "vpc_source_nat_ip" {
  value = cloudstack_vpc.vpc.source_nat_ip
}
