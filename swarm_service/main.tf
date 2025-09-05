terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

variable "name" {
  type = string
}

variable "image" {
  type = any
}

variable "command" {
  type    = list(string)
  default = null
}

variable "args" {
  type    = list(string)
  default = []
}

variable "env" {
  type    = map(string)
  default = {}
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

variable "constraints" {
  type    = list(string)
  default = []
}

variable "configs" {
  type = list(object({
    source = map(string)
    path   = string
    mode   = optional(number, 0444)
  }))
  default = []
}

variable "configs_raw" {
  type = list(object({
    data = string
    path = string
    mode = optional(number, 0444)
  }))
  default = []
}

variable "secrets" {
  type = list(object({
    data = string
    path = string
  }))
  default = []
}

variable "mounts" {
  type = list(object({
    target    = string
    source    = string
    type      = optional(string, "volume")
    read_only = optional(bool, false)
  }))
  default = []
}

variable "nfs_mounts" {
  type = list(object({
    name      = string
    target    = string
    read_only = optional(bool, false)
    device    = string
    options   = string
  }))
  default = []
}

variable "networks" {
  type = list(object({
    id = string
  }))
  default = []
}

variable "ports" {
  type = list(object({
    internal = number
    external = number
    # https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/service#nested-schema-for-endpoint_specports
    mode     = optional(string, "ingress")
    protocol = optional(string, "tcp")
  }))
  default = []
}

variable "user" {
  type    = string
  default = null
}

resource "docker_config" "this" {
  # Convert list to map for for_each iteration - path will be unique
  for_each = {
    for index, config in var.configs_raw : config.path => config
  }

  name = "${var.name}-${md5(each.value.data)}"
  data = base64encode(each.value.data)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_secret" "this" {
  for_each = { for index, secret in var.secrets : secret.path => secret }

  name = "${var.name}-${md5(each.value.data)}"
  data = base64encode(each.value.data)

  lifecycle {
    create_before_destroy = true
  }
}

data "docker_registry_image" "this" {
  count = can(var.image.name) ? 0 : 1

  name = var.image
}

locals {
  image_name   = try(var.image.name, data.docker_registry_image.this[0].name)
  image_digest = try(var.image.sha256_digest, data.docker_registry_image.this[0].sha256_digest)
}

resource "docker_service" "this" {
  name = var.name

  dynamic "labels" {
    for_each = var.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  mode {
    # defaults
    replicated {
      replicas = 1
    }
  }

  task_spec {
    container_spec {
      image   = "${local.image_name}@${local.image_digest}"
      command = var.command
      args    = var.args
      env     = var.env
      user    = var.user

      dynamic "configs" {
        for_each = var.configs
        content {
          config_id   = configs.value.source.id
          config_name = configs.value.source.name
          file_name   = configs.value.path
          file_mode   = configs.value.mode
        }
      }

      dynamic "configs" {
        for_each = var.configs_raw
        content {
          config_id   = docker_config.this[configs.value.path].id
          config_name = docker_config.this[configs.value.path].name
          file_name   = configs.value.path
          file_mode   = configs.value.mode
        }
      }

      dynamic "secrets" {
        for_each = var.secrets
        content {
          secret_id   = docker_secret.this[secrets.value.path].id
          secret_name = docker_secret.this[secrets.value.path].name
          file_name   = secrets.value.path
        }
      }

      dynamic "mounts" {
        for_each = var.mounts
        content {
          source    = mounts.value.source
          target    = mounts.value.target
          type      = mounts.value.type
          read_only = mounts.value.read_only
        }
      }

      dynamic "mounts" {
        for_each = var.nfs_mounts
        content {
          source    = "${mounts.value.name}-${md5(jsonencode(mounts.value))}"
          target    = mounts.value["target"]
          type      = "volume"
          read_only = mounts.value["read_only"]

          volume_options {
            driver_name = "local"
            driver_options = {
              device = mounts.value["device"]
              o      = mounts.value["options"]
              type   = "nfs4"
            }
            no_copy = true
          }
        }
      }

      # defaults
      groups            = []
      read_only         = false
      stop_grace_period = "0s"
      sysctl            = {}
      healthcheck {
        interval     = "0s"
        retries      = 0
        start_period = "0s"
        test         = []
        timeout      = "0s"
      }
    }

    log_driver {
      name    = var.log_driver.name
      options = var.log_driver.options
    }

    restart_policy {
      delay = "5s"
      # defaults
      condition    = "any"
      max_attempts = 0
      window       = "0s"
    }

    placement {
      constraints = var.constraints
      # defaults
      max_replicas = 0
      prefs        = []
      platforms {
        architecture = "amd64"
        os           = "linux"
      }
    }

    dynamic "networks_advanced" {
      for_each = var.networks
      content {
        name = networks_advanced.value.id
      }
    }

    # task_spec defaults
    force_update = 0
    runtime      = "container"
  }

  endpoint_spec {
    dynamic "ports" {
      for_each = var.ports
      content {
        target_port    = ports.value.internal
        published_port = ports.value.external
        publish_mode   = ports.value.mode
        protocol       = ports.value.protocol
      }
    }
    # defaults
    mode = "vip"
  }
}

output "name" {
  value = docker_service.this.name
}

output "port" {
  value = try(docker_service.this.endpoint_spec[0].ports[0].published_port, null)
}
