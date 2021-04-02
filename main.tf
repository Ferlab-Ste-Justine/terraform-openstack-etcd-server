locals {
  self_name = var.namespace != "" ? "${var.name}-${var.namespace}" : var.name
  processed_initial_cluster = [
    for elem in var.initial_cluster: {
      name = var.namespace != "" ? "${elem["name"]}-${var.namespace}" : elem["name"]
      ip = elem["ip"]
    }
  ]
}


data "template_cloudinit_config" "etcd_config" {
  gzip = true
  base64_encode = true
  part {
    content_type = "text/cloud-config"
    content = templatefile(
      "${path.module}/files/cloud_config.yaml.tpl", 
      {
        etcd_version = var.etcd_version
        etcd_space_quota = var.etcd_space_quota
        etcd_auto_compaction_mode = var.etcd_auto_compaction_mode
        etcd_auto_compaction_retention = var.etcd_auto_compaction_retention
        etcd_initial_cluster_token = var.initial_cluster_token
        self_ip = var.network_port.all_fixed_ips.0
        etcd_initial_cluster_state = var.is_initial_cluster ? "new" : "existing"
        etcd_name = local.self_name
        etcd_cluster = join(
          ",",
          [
            for elem in local.processed_initial_cluster: "${elem["name"]}=https://${elem["ip"]}:2380"
          ]
        )
        ca_cert = var.ca.certificate
        cert = tls_locally_signed_cert.certificate.cert_pem
        key = tls_private_key.key.private_key_pem
        bootstrap_authentication = var.bootstrap_authentication
        root_key = module.root_certificate.key
        root_cert = module.root_certificate.certificate
      }
    )
  }
}

resource "openstack_compute_instance_v2" "etcd_member" {
  name      = local.self_name
  image_id  = var.image_id
  flavor_id = var.flavor_id
  key_pair  = var.keypair_name
  user_data = data.template_cloudinit_config.etcd_config.rendered

  network {
    port = var.network_port.id
  }
}