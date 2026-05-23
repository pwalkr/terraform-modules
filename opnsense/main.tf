terraform {
  required_providers {
    opnsense = {
      source = "browningluke/opnsense"
    }
  }
}

variable "kea_subnets" {
  description = "DHCPv4 subnets keyed by stable id."
  type = map(object({
    description = string
    cidr        = string
    pool        = string
    dns_servers = list(string)
    ntp_servers = list(string)
    routers     = list(string)
  }))
  default = {}
}

variable "kea_reservations" {
  description = "DHCPv4 reservations keyed by hostname. subnet_key must match a key in kea_subnets."
  type = map(object({
    subnet_key  = string
    description = string
    ip_address  = string
    mac_address = string
  }))
  default = {}
}

variable "firewall_rules" {
  description = "Firewall filter rules keyed by stable id. Values are passed through to opnsense_firewall_filter."
  type        = any
  default     = {}
}

variable "firewall_nat_port_forwards" {
  description = "NAT port-forward rules keyed by stable id. Values are passed through to opnsense_firewall_nat_port_forward."
  type        = any
  default     = {}
}
