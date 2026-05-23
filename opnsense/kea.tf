resource "opnsense_kea_dhcpv4_subnet" "main" {
  for_each = var.kea_subnets

  description = each.value.description
  subnet      = each.value.cidr

  match_client_id = false

  pools = [
    each.value.pool,
  ]

  auto_collect = false
  # These are only auto-applied from UI. Define explicitly to ensure sync
  dns_servers = each.value.dns_servers
  ntp_servers = each.value.ntp_servers
  routers     = each.value.routers
}

resource "opnsense_kea_dhcpv4_reservation" "main" {
  for_each = var.kea_reservations

  subnet_id = opnsense_kea_dhcpv4_subnet.main[each.value.subnet_key].id

  description = each.value.description
  ip_address  = each.value.ip_address
  mac_address = each.value.mac_address
}
