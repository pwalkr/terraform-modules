variable "constraints" {
  type    = any
  default = []
}

variable "host" {
  type        = string
  description = "Set to reflect back in url output for ease of use"
}

variable "image_tag" {
  type = string
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "log_driver" {
  type = any
}

variable "name" {
  type    = string
  default = "registry"
}

variable "nfs_mount" {
  type    = any
  default = {}
}

variable "networks" {
  type    = any
  default = []
}

variable "port" {
  type = number
  default = 5000
}

variable "proxy_url" {
  type = string
  default = "https://registry-1.docker.io"
}

variable "root_directory" {
  type        = string
  description = "Ensure this is mounted in as nfs_mount"
}

module "this" {
  source = "../swarm_service"

  name  = var.name
  image = "registry:${var.image_tag}"

  constraints = var.constraints

  env = {
    #REGISTRY_LOG_ACCESSLOG_DISABLED           = false  # Debug
    REGISTRY_PROXY_REMOTEURL = var.proxy_url
    #REGISTRY_PROXY_TTL                        = "730h"  # Unrecognized
    REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY = var.root_directory
  }

  nfs_mounts = [var.nfs_mount]

  labels = var.labels

  networks = var.networks

  ports = [{
    internal = "5000"
    external = var.port
  }]

  log_driver = var.log_driver
}

output "name" {
  value = module.this.name
}

output "url" {
  value = "${var.host}:${module.this.port}"
}
