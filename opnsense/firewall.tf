resource "opnsense_firewall_nat_port_forward" "rule" {
  for_each = var.firewall_nat_port_forwards

  description = each.value.description
  enabled     = true
  interface   = each.value.interface
  protocol    = each.value.protocol

  source      = each.value.source
  destination = each.value.destination
  target      = each.value.target
}

resource "opnsense_firewall_filter" "rule" {
  for_each = var.firewall_rules

  sequence    = each.value.sequence
  description = each.value.description

  interface = {
    interface = [each.value.interface]
  }

  filter = each.value.filter
}
