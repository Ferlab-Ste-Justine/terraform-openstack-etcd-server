variable "name" {
  description = "Name to give to the vm"
  type        = string
  default     = "etcd"
}

variable "image_source" {
  description = "Source of the vm's image"
  type = object({
    image_id = string
    volume_id = string
  })
}

variable "flavor_id" {
  description = "ID of the flavor the etcd instance will run on"
  type        = string
}

variable "network_port" {
  description = "Network port to assign to the node. Should be of type openstack_networking_port_v2"
  type        = any
}

variable "server_group" {
  description = "Server group to assign to the node. Should be of type openstack_compute_servergroup_v2"
  type        = any
}

variable "keypair_name" {
  description = "Name of the keypair that will be used to ssh to the etcd instance"
  type        = string
}

variable "etcd" {
  description = "Etcd parameters"
  type        = object({
    auto_compaction_mode       = string,
    auto_compaction_retention  = string,
    space_quota                = number,
    grpc_gateway_enabled       = bool,
    client_cert_auth           = bool,
  })
  default = {
    auto_compaction_mode      = "revision"
    auto_compaction_retention = "1000"
    space_quota               = 8*1024*1024*1024
    grpc_gateway_enabled      = false
    client_cert_auth          = true
  }
}

variable "authentication_bootstrap" {
  description = "Authentication settings for the node bootstrapping it. Note that root_password is only used if etcd.client_cert_auth setting is set to false"
  type        = object({
    bootstrap     = bool,
    root_password = string,
  })
  default = {
    bootstrap     = false
    root_password = ""
  }
}

variable "cluster" {
  description = "Etcd cluster parameters"
  type        = object({
    is_initializing = bool,
    initial_token   = string,
    initial_members = list(object({
      ip   = string,
      name = string,
    })),
  })
}

variable "tls" {
  description = "Etcd tls parameters"
  type = object({
    ca_cert     = string
    server_cert = string
    server_key  = string
  })
}

variable "chrony" {
  description = "Chrony configuration for ntp. If enabled, chrony is installed and configured, else the default image ntp settings are kept"
  type        = object({
    enabled = bool,
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server
    servers = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool
    pools = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep
    makestep = object({
      threshold = number
      limit = number
    })
  })
  default = {
    enabled = false
    servers = []
    pools = []
    makestep = {
      threshold = 0
      limit = 0
    }
  }
}

variable "fluentbit" {
  description = "Fluent-bit configuration"
  type = object({
    enabled = bool
    etcd_tag = string
    node_exporter_tag = string
    metrics = object({
      enabled = bool
      port    = number
    })
    forward = object({
      domain = string
      port = number
      hostname = string
      shared_key = string
      ca_cert = string
    })
  })
  default = {
    enabled = false
    etcd_tag = ""
    node_exporter_tag = ""
    metrics = {
      enabled = false
      port = 0
    }
    forward = {
      domain = ""
      port = 0
      hostname = ""
      shared_key = ""
      ca_cert = ""
    }
  }
}

variable "fluentbit_dynamic_config" {
  description = "Parameters for fluent-bit dynamic config if it is enabled"
  type = object({
    enabled = bool
    source  = string
    etcd    = object({
      key_prefix     = string
      endpoints      = list(string)
      ca_certificate = string
      client         = object({
        certificate = string
        key         = string
        username    = string
        password    = string
      })
    })
    git     = object({
      repo             = string
      ref              = string
      path             = string
      trusted_gpg_keys = list(string)
      auth             = object({
        client_ssh_key         = string
        server_ssh_fingerprint = string
      })
    })
  })
  default = {
    enabled = false
    source = "etcd"
    etcd = {
      key_prefix     = ""
      endpoints      = []
      ca_certificate = ""
      client         = {
        certificate = ""
        key         = ""
        username    = ""
        password    = ""
      }
    }
    git  = {
      repo             = ""
      ref              = ""
      path             = ""
      trusted_gpg_keys = []
      auth             = {
        client_ssh_key         = ""
        server_ssh_fingerprint = ""
      }
    }
  }

  validation {
    condition     = contains(["etcd", "git"], var.fluentbit_dynamic_config.source)
    error_message = "fluentbit_dynamic_config.source must be 'etcd' or 'git'."
  }
}

variable "install_dependencies" {
  description = "Whether to install all dependencies in cloud-init"
  type = bool
  default = true
}