terraform {
  required_providers {
    adguard = {
      source = "gmichels/adguard"
    }
  }
}

variable "config" {
  description = "Complete AdGuard Home configuration in one map: adguard_config arguments (blocked_services_pause_schedule, dns, querylog, stats, dhcp), rewrites (domain => answer), and clients (adguard_client arguments keyed by name)."
  type        = any
}

resource "adguard_config" "main" {
  blocked_services_pause_schedule = var.config.blocked_services_pause_schedule
  dns                             = var.config.dns
  querylog                        = var.config.querylog
  stats                           = var.config.stats
  dhcp                            = var.config.dhcp
}

resource "adguard_rewrite" "dns" {
  for_each = var.config.rewrites

  domain = each.key
  answer = each.value
}

resource "adguard_client" "list" {
  for_each = var.config.clients

  name = each.value.name
  ids  = each.value.ids

  use_global_blocked_services = each.value.use_global_blocked_services
  blocked_services            = each.value.blocked_services
}
