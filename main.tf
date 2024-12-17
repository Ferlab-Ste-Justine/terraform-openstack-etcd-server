locals {
  fluentbit_updater_etcd = var.fluentbit.enabled && var.fluentbit_dynamic_config.enabled && var.fluentbit_dynamic_config.source == "etcd"
  fluentbit_updater_git = var.fluentbit.enabled && var.fluentbit_dynamic_config.enabled && var.fluentbit_dynamic_config.source == "git"
  block_devices = concat(
    var.image_source.volume_id != "" ? [{
      uuid                  = var.image_source.volume_id
      source_type           = "volume"
      boot_index            = 0
      destination_type      = "volume"
      delete_on_termination = false
    }] : [],
    var.data_volume_id != "" ? [{
      uuid                  = var.data_volume_id
      source_type           = "volume"
      boot_index            = -1
      destination_type      = "volume"
      delete_on_termination = false
    }] : []
  )
}

module "etcd_restore_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//etcd-restore?ref=v0.27.2"
  install_dependencies = var.install_dependencies
  restore = {
    s3 = var.restore.s3
    encryption_key = var.restore.encryption_key
    backup_timestamp = var.restore.backup_timestamp
  }
  etcd_initial_cluster = {
    name    = var.name
    ip      = var.network_port.all_fixed_ips.0
    token   = var.cluster.initial_token
    members = var.cluster.initial_members
  }
}

module "etcd_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//etcd?ref=v0.27.2"
  install_dependencies = var.install_dependencies
  etcd_host = {
    name                     = var.name
    ip                       = var.network_port.all_fixed_ips.0
    bootstrap_authentication = var.authentication_bootstrap.bootstrap
  }
  etcd_cluster = {
    auto_compaction_mode       = var.etcd.auto_compaction_mode
    auto_compaction_retention  = var.etcd.auto_compaction_retention
    space_quota                = var.etcd.space_quota
    grpc_gateway_enabled       = var.etcd.grpc_gateway_enabled
    client_cert_auth           = var.etcd.client_cert_auth
    root_password              = var.authentication_bootstrap.root_password
  }
  etcd_initial_cluster = {
    is_initializing = var.cluster.is_initializing
    token           = var.cluster.initial_token
    members         = var.cluster.initial_members
  }
  tls = var.tls
}

module "prometheus_node_exporter_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//prometheus-node-exporter?ref=v0.27.2"
  install_dependencies = var.install_dependencies
}

module "chrony_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//chrony?ref=v0.27.2"
  install_dependencies = var.install_dependencies
  chrony = {
    servers  = var.chrony.servers
    pools    = var.chrony.pools
    makestep = var.chrony.makestep
  }
}

module "fluentbit_updater_etcd_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//configurations-auto-updater?ref=v0.27.2"
  install_dependencies = var.install_dependencies
  filesystem = {
    path = "/etc/fluent-bit-customization/dynamic-config"
    files_permission = "700"
    directories_permission = "700"
  }
  etcd = {
    key_prefix = var.fluentbit_dynamic_config.etcd.key_prefix
    endpoints = var.fluentbit_dynamic_config.etcd.endpoints
    connection_timeout = "60s"
    request_timeout = "60s"
    retry_interval = "4s"
    retries = 15
    auth = {
      ca_certificate = var.fluentbit_dynamic_config.etcd.ca_certificate
      client_certificate = var.fluentbit_dynamic_config.etcd.client.certificate
      client_key = var.fluentbit_dynamic_config.etcd.client.key
      username = var.fluentbit_dynamic_config.etcd.client.username
      password = var.fluentbit_dynamic_config.etcd.client.password
    }
  }
  notification_command = {
    command = ["/usr/local/bin/reload-fluent-bit-configs"]
    retries = 30
  }
  naming = {
    binary = "fluent-bit-config-updater"
    service = "fluent-bit-config-updater"
  }
  user = "fluentbit"
  vault_agent = {
    etcd_auth = {
        enabled = var.fluentbit_dynamic_config.etcd.vault_agent_secret_path != ""
        secret_path = var.fluentbit_dynamic_config.etcd.vault_agent_secret_path
    }
  }
}

module "fluentbit_updater_git_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//gitsync?ref=v0.27.2"
  install_dependencies = var.install_dependencies
  filesystem = {
    path = "/etc/fluent-bit-customization/dynamic-config"
    files_permission = "700"
    directories_permission = "700"
  }
  git = var.fluentbit_dynamic_config.git
  notification_command = {
    command = ["/usr/local/bin/reload-fluent-bit-configs"]
    retries = 30
  }
  naming = {
    binary = "fluent-bit-config-updater"
    service = "fluent-bit-config-updater"
  }
  user = "fluentbit"
}

module "fluentbit_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//fluent-bit?ref=v0.27.2"
  install_dependencies = var.install_dependencies
  fluentbit = {
    metrics = var.fluentbit.metrics
    systemd_services = [
      {
        tag     = var.fluentbit.etcd_tag
        service = "etcd.service"
      },
      {
        tag     = var.fluentbit.node_exporter_tag
        service = "node-exporter.service"
      }
    ]
    forward = var.fluentbit.forward
  }
  dynamic_config = {
    enabled = var.fluentbit_dynamic_config.enabled
    entrypoint_path = "/etc/fluent-bit-customization/dynamic-config/index.conf"
  }
}


module "vault_agent_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//vault-agent?ref=v0.27.2"
  install_dependencies = var.install_dependencies
  vault_agent = {
    auth_method = var.vault_agent.auth_method
    vault_address = var.vault_agent.vault_address
    vault_ca_cert = var.vault_agent.vault_ca_cert
    extra_config = ""
  }
}

module "data_volume_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//data-volumes?ref=v0.27.2"
  volumes = [{
    label         = "etcd_data"
    device        = "vdb"
    filesystem    = "ext4"
    mount_path    = "/var/lib/etcd"
    mount_options = "defaults"
  }]
}

locals {
  cloudinit_templates = concat(
    var.restore.enabled ? [{
      filename     = "etcd_restore.cfg"
      content_type = "text/cloud-config"
      content      = module.etcd_restore_configs.configuration
    }] : [],
    [
      {
        filename     = "base.cfg"
        content_type = "text/cloud-config"
        content = templatefile(
          "${path.module}/files/user_data.yaml.tpl", 
          {
            hostname = var.name
            install_dependencies = var.install_dependencies
          }
        )
      },
      {
        filename     = "node_exporter.cfg"
        content_type = "text/cloud-config"
        content      = module.prometheus_node_exporter_configs.configuration
      },
      {
        filename     = "etcd.cfg"
        content_type = "text/cloud-config"
        content      = module.etcd_configs.configuration
      }
    ],
    var.chrony.enabled ? [{
      filename     = "chrony.cfg"
      content_type = "text/cloud-config"
      content      = module.chrony_configs.configuration
    }] : [],
    local.fluentbit_updater_etcd ? [{
      filename     = "fluent_bit_updater.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_updater_etcd_configs.configuration
    }] : [],
    local.fluentbit_updater_git ? [{
      filename     = "fluent_bit_updater.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_updater_git_configs.configuration
    }] : [],
    var.fluentbit.enabled ? [{
      filename     = "fluent_bit.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_configs.configuration
    }] : [],
    var.vault_agent.enabled ? [{
      filename     = "vault_agent.cfg"
      content_type = "text/cloud-config"
      content      = module.vault_agent_configs.configuration
    }] : [],
    var.data_volume_id != "" ? [{
      filename     = "data_volume.cfg"
      content_type = "text/cloud-config"
      content      = module.data_volume_configs.configuration
    }]: []
  )
}

data "cloudinit_config" "user_data" {
  gzip = true
  base64_encode = true
  dynamic "part" {
    for_each = local.cloudinit_templates
    content {
      filename     = part.value["filename"]
      content_type = part.value["content_type"]
      content      = part.value["content"]
    }
  }
}

resource "openstack_compute_instance_v2" "etcd_member" {
  name      = var.name
  image_id  = var.image_source.image_id != "" ? var.image_source.image_id : null
  flavor_id = var.flavor_id
  key_pair  = var.keypair_name
  user_data = data.cloudinit_config.user_data.rendered

  network {
    port = var.network_port.id
  }

  dynamic "block_device" {
    for_each = local.block_devices
    content {
      uuid                  = block_device.value["uuid"]
      source_type           = block_device.value["source_type"]
      boot_index            = block_device.value["boot_index"]
      destination_type      = block_device.value["destination_type"]
      delete_on_termination = block_device.value["delete_on_termination"]
    }
  }

  scheduler_hints {
    group = var.server_group.id
  }

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}