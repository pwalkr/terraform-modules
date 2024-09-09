terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "celery_command" {
  type = list(string)
  # https://github.com/gramps-project/gramps-web-docs/blob/main/examples/docker-compose-base/docker-compose.yml
  default = ["celery", "--app=gramps_webapi.celery", "worker", "--loglevel=INFO"]
}

variable "constraints" {
  type        = list(string)
  description = "Required - set constraints so all containers run on same node"
}

variable "data_root" {
  type    = string
  default = "/data"
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "grampsweb_command" {
  type = list(string)
  # TODO: use default after https://github.com/gramps-project/gramps-web-api/pull/538 is released
  default = ["gunicorn", "-w=8", "-b=0.0.0.0:5000", "gramps_webapi.wsgi:app", "--timeout=120", "--limit-request-line=8190"]
}

variable "grampsweb_tag" {
  type    = string
  default = "latest"
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "log_driver" {
  type = object({
    name    = string
    options = map(string)
  })
}

variable "mounts" {
  type        = list(any)
  default     = []
  description = "List of general named volumes to mount"
}

variable "mount_nfs" {
  type        = list(any)
  default     = []
  description = "List of nfs volumes to mount (see swarm_service module)"
}

variable "no_tmp" {
  type        = bool
  default     = false
  description = "Do not add /tmp volume (must supply own volume mounted at /tmp for grampsweb<>celery)"
}

variable "name_prefix" {
  type        = string
  default     = "grampsweb"
  description = "Prefix used for each of grampsweb api, celery, and redis services"
}

variable "networks" {
  type = list(object({
    id = string
  }))
  default = []
}

variable "port" {
  type    = number
  default = 5000
}

variable "redis_tag" {
  type    = string
  default = "alpine"
}

variable "secret" {
  type        = string
  default     = null
  sensitive   = true
  description = "The secret key for flask"
}

variable "tree" {
  type    = string
  default = null
  # Refs https://www.grampsweb.org/Configuration/
  description = "The name of the family tree database to use. Set '*' for multi-tree support"
}

variable "user" {
  type    = string
  default = 33 # www-data
}

locals {
  # Grampsweb and celery share /tmp. Inject local volume unless told otherwise
  tmp_volume = "${var.name_prefix}-tmp"
  tmp_mount = var.no_tmp ? {} : {
    target = "/tmp"
    source = local.tmp_volume
  }
  mounts = concat(var.mounts, [local.tmp_mount])

  redis_port = 6379 # default
  redis_host = "${var.name_prefix}-redis"

  env = merge(
    (var.secret == null ? {} : { GRAMPSWEB_SECRET_KEY = var.secret }),
    (var.tree == null ? {} : { GRAMPSWEB_TREE = var.tree }),
    {
      GRAMPSHOME                                  = var.data_root
      GRAMPSWEB_CELERY_CONFIG__broker_url         = "redis://${local.redis_host}:${local.redis_port}/0"
      GRAMPSWEB_CELERY_CONFIG__result_backend     = "redis://${local.redis_host}:${local.redis_port}/0"
      GRAMPSWEB_EXPORT_DIR                        = "${var.data_root}/cache"
      GRAMPSWEB_MEDIA_BASE_DIR                    = "${var.data_root}/media"
      GRAMPSWEB_RATELIMIT_STORAGE_URI             = "redis://${local.redis_host}:${local.redis_port}/1"
      GRAMPSWEB_SEARCH_INDEX_DB_URI               = "sqlite:///${var.data_root}/search_index.db"
      GRAMPSWEB_THUMBNAIL_CACHE_CONFIG__CACHE_DIR = "${var.data_root}/thumbnail_cache"
      GRAMPSWEB_USER_DB_URI                       = "sqlite:///${var.data_root}/users.sqlite"
    },
    var.env
  )
}

data "docker_registry_image" "grampsweb" {
  name = "ghcr.io/gramps-project/grampsweb:${var.grampsweb_tag}"
}

resource "docker_network" "grampsweb" {
  name   = "grampsweb"
  driver = "overlay"
}

module "grampsweb" {
  source = "../swarm_service"

  command     = var.grampsweb_command
  constraints = var.constraints
  env         = local.env
  name        = "${var.name_prefix}-service"
  image       = data.docker_registry_image.grampsweb
  labels      = var.labels
  networks    = concat([docker_network.grampsweb], var.networks)
  log_driver  = var.log_driver
  user        = var.user

  mounts    = local.mounts
  mount_nfs = var.mount_nfs

  ports = [{
    internal = 5000
    external = var.port
  }]

  depends_on = [
    module.redis
  ]
}

module "celery" {
  source = "../swarm_service"

  command     = var.celery_command
  constraints = var.constraints
  env         = local.env
  name        = "${var.name_prefix}-celery"
  image       = data.docker_registry_image.grampsweb
  networks    = [docker_network.grampsweb]
  log_driver  = var.log_driver
  user        = var.user

  mounts    = local.mounts
  mount_nfs = var.mount_nfs

  depends_on = [
    module.redis
  ]
}

module "redis" {
  source = "../swarm_service"

  constraints = var.constraints
  name        = local.redis_host
  image       = "redis:${var.redis_tag}"
  networks    = [docker_network.grampsweb]
  log_driver  = var.log_driver
}
