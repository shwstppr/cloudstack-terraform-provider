variable "cloudstack_api_url" {
  description = "CloudStack API endpoint, e.g. http://localhost:8080/client/api"
  type        = string
}

variable "cloudstack_api_key" {
  description = "CloudStack API key"
  type        = string
  sensitive   = true
}

variable "cloudstack_secret_key" {
  description = "CloudStack API secret key"
  type        = string
  sensitive   = true
}

variable "zone" {
  description = "Name or ID of an existing zone. Used by resources that accept a name-or-id string (cloudstack_instance, cloudstack_vpc, cloudstack_kubernetes_cluster)."
  type        = string
}

variable "zone_id" {
  description = "ID of an existing zone. cloudstack_volume requires the ID specifically, not a name."
  type        = string
}

variable "network_offering" {
  description = "Name or ID of an existing network offering, used by cloudstack_network."
  type        = string
}

variable "vpc_offering" {
  description = "Name or ID of an existing VPC offering, used by cloudstack_vpc."
  type        = string
}

variable "template_filter" {
  description = "Filter passed to data.cloudstack_template (e.g. executable, self, featured)."
  type        = string
  default     = "executable"
}

variable "template_name_regex" {
  description = "Regex matching an existing template's name, used by the data.cloudstack_template lookup."
  type        = string
}

variable "template_name" {
  description = "Exact name (or ID) of an existing template, used by resources that take a name-or-id string directly (cloudstack_instance, cloudstack_kubernetes_cluster) rather than a regex lookup."
  type        = string
}

variable "kubernetes_version" {
  description = "Name or ID of an existing Kubernetes ISO/version. Only used by the optional kubernetes-cluster case; leave empty (default) to make that case a no-op."
  type        = string
  default     = ""
}
