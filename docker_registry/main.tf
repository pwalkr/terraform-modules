locals {
  registry_hostname = "docker"
  # Prescriptive domain for router
  _registry = "${local.registry_hostname}.${local.ansible_vars.dns_domain}"
  # Derived domain for dependents for automatic link
  registry = "${module.docker_registry.name}.${local.ansible_vars.dns_domain}"

  registry_rootdir = "/var/lib/registry"
}


module "docker_registry" {
  source = "../swarm_service"

  name  = local.registry_hostname
  image = "registry:${local.versions.docker_registry_tag}"

  env = {
    #REGISTRY_LOG_ACCESSLOG_DISABLED           = false  # Debug
    REGISTRY_PROXY_REMOTEURL = "https://registry-1.docker.io"
    #REGISTRY_PROXY_TTL                        = "730h"  # Unrecognized
    REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY = local.registry_rootdir
  }

  nfs_mounts = [{
    name    = "docker-registry"
    target  = local.registry_rootdir
    device  = ":/${local.shared.zpool_primary}/docker-registry"
    options = "addr=${local.ansible.hostvars.stratos.ansible_host},rw,noatime"
  }]

  labels = {
    "traefik.enable"                                          = "true"
    "traefik.http.routers.registry.entryPoints"               = "websecure"
    "traefik.http.routers.registry.rule"                      = "Host(`${local._registry}`)"
    "traefik.http.routers.registry.tls.certResolver"          = local.traefik_certsresolver
    "traefik.http.services.registry.loadbalancer.server.port" = "5000"
  }

  networks = [
    docker_network.traefik,
  ]

  ports = [{
    internal = "5000"
    external = local.ansible_vars.cluster_ports.docker
  }]

  log_driver = local.loki_log_driver
}
