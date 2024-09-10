terraform {
  required_providers {
    docker = {
      source = "kreuzwerker/docker"
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

variable "mounts" {
  type = list(object({
    target    = string
    source    = string
    type      = optional(string, "volume")
    read_only = optional(bool, false)
  }))
  default = []
}

variable "mount_nfs" {
  type = list(object({
    name      = string
    target    = string
    read_only = optional(bool, false)
    device    = string
    addr      = string
    options   = optional(string, null)
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

variable "secrets" {
  type = list(object({
    path   = string
    data   = optional(string, null)
    source = optional(any, null)
  }))
  default     = []
  description = "List of secrets, either raw with data+path or resource as source+path"
}

variable "user" {
  type    = string
  default = null
}

# To reduce docker pulls, reuse data.docker_registry_image between services
data "docker_registry_image" "main" {
  count = can(var.image.name) ? 0 : 1

  name = var.image
}

# Generate a secret resource for any "raw" incoming
resource "docker_secret" "main" {
  for_each = {
    for s in var.secrets : s.path => s.data if s.source == null
  }

  data = base64encode(each.value)

  # Hashing name allows new secret to be created and bound before old is deleted
  name = "${var.name}-${md5(nonsensitive(each.value))}"
  lifecycle {
    create_before_destroy = true
  }
}

locals {
  image_name   = try(var.image.name, data.docker_registry_image.main[0].name)
  image_digest = try(var.image.sha256_digest, data.docker_registry_image.main[0].sha256_digest)
}

resource "docker_service" "main" {
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
      env     = var.env
      user    = var.user

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
        for_each = var.mount_nfs
        content {
          source    = "${mounts.value.name}-${md5(jsonencode(mounts.value))}"
          target    = mounts.value["target"]
          type      = "volume"
          read_only = mounts.value["read_only"]

          volume_options {
            driver_name = "local"
            driver_options = {
              device = mounts.value["device"]
              # addr=$addr,$options
              o    = join(",", compact(["addr=${mounts.value["addr"]}", mounts.value["options"]]))
              type = "nfs4"
            }
            no_copy = true
          }
        }
      }

      dynamic "secrets" {
        for_each = [
          for s in var.secrets : {
            path   = s.path
            source = coalesce(s.source, docker_secret.main[s.path])
          }
        ]

        content {
          secret_id   = secrets.value.source.id
          secret_name = secrets.value.source.name
          file_name   = secrets.value.path
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
  value = docker_service.main.name
}
