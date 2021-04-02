# About

This is a terraform module that provisions a single member of an etcd cluster.

Given a certificate authority as argument (can be an internal-only self-signed authority), it will generate its own secret key and certificate to communicate with clients and peers in the cluster.

One of the servers can also be set to bootstrap authentication in the cluster: it will generates a passwordless **root** user and enable authentication. You are expected to use your certificate authority to generate a client user certificate for **root** to further configure your etcd cluster. See: https://github.com/Ferlab-Ste-Justine/openstack-etcd-client-certificate

# Usage

## Variables

This module takes the following variables as input:

- name: This should be a name that uniquely identifies this member in the cluster. If a namespace is given, it will become ```<name>-<namespace>```.
- namespace: Unique namespacing suffix that will be used to ensure the resources provisioned by this module will be uniquely named across your openstack
- image_id: Id of the vm image that the machine will boot from. This module has been validated against a recent version of Ubuntu Server. Your mileage may vary with other distributions.
- flavor_id: Id of the vm flavor to assign to the instance. See hardware recommendations to make an informed choice: https://etcd.io/docs/v3.4/op-guide/hardware/
- network_port: Resource of type **openstack_networking_port_v2** to assign to the vm for network connectivity
- keypair_name: Name of the ssh keypair that will be used to ssh against the vm.
- etcd_version: Version of etcd that should be install. Defaults to **v3.4.15** and this is the version this module was validated against. Your mileage may vary with other versions.
- etcd_auto_compaction_mode: The kind of auto compaction to use. Can be **periodic** or **revision** (defaults to **revision**). See: https://etcd.io/docs/v3.4/op-guide/maintenance/
- etcd_auto_compaction_retention: Specifies what versions will be preserved during auto compaction given the **etcd_auto_compaction_mode**. Defaults to **1000** (if the defaults are kept, the last 1000 revisions will be preserved and all revisions older than that will be fair game for compaction)
- etcd_space_quota: The maximum disk space the etcd instance can use before the cluster hits **panic mode** and becomes **read only**. Given that etcd tries to cache all its key values in the memory for performance reasons, it make sense not to make this much greater than the amount of memory you have on the machine (because of fragmentation, a key space that fits in the memory could theoretically take an amount of disk space that is larger than the amount of memory)
- is_initial_cluster: Set this to **true** if the machine is created as part of the initial cluster creation. If the machine is created to join an existing cluster, then set this to **false**
- initial_cluster_token: Token to uniquely identify the cluster during the initial cluster bootstraping phase. Defaults to **etcd-cluster**
- initial_cluster: List indicating the initial cluster to join. It should contain a list of maps, each entry having the following keys: ip, name. The **name** value in each map should be the same as the **name** value that is passed to the corresponding member as a module variable. Will be used when the vm is initially created and ignored after that. See: https://etcd.io/docs/v3.4/op-guide/clustering/
- organization: Organization that will be used in the etcd member's certificate
- certificate_validity_period: Validity period of the member's certificate in hours. Defaults to 100 years.
- certificate_early_renewal_period: Period after which Terraform will try to reprovision the member's certificate in hours. Defaults to 99 years.
- ca: Certificate authority that will be used to sign the member's certificat. It is expected to contain the following keys: key, key_algorithm, certificate
- bootstrap_authentication: See to **true** on **one** (and only one) member to boostrap authentication when you initially create the etcd cluster. 

## Example

```
module "etcd_security_groups" {
  source = "git::https://github.com/Ferlab-Ste-Justine/openstack-etcd-security-groups.git"
  namespace = "dev"
}

resource "openstack_compute_keypair_v2" "etcd" {
  name = "etcd-dev-external-keypair"
}

resource "openstack_networking_port_v2" "etcd" {
  count          = 3
  name           = "etcd-dev-${count.index + 1}"
  network_id     = module.reference_infra.networks.internal.id
  security_group_ids = [module.etcd_security_groups.groups.member.id]
  admin_state_up = true
}

module "etcd_ca" {
  source = "./ca"
}

locals {
  etcd_ips = [for network_port in openstack_networking_port_v2.etcd: network_port.all_fixed_ips.0]
  initial_cluster = [
    {
      ip = openstack_networking_port_v2.etcd_dev.0.all_fixed_ips.0
      name = "etcd-1"
    },
    {
      ip = openstack_networking_port_v2.etcd_dev.1.all_fixed_ips.0
      name = "etcd-2"
    },
    {
      ip = openstack_networking_port_v2.etcd_dev.2.all_fixed_ips.0
      name = "etcd-3"
    }
  ]
}

module "etcd_member_one" {
  source = "git::https://github.com/Ferlab-Ste-Justine/openstack-etcd-server.git"
  name = "etcd-1"
  namespace = "dev"
  image_id = data.openstack_images_image_v2.ubuntu.id
  flavor_id = module.reference_infra.flavors.micro.id
  network_port = openstack_networking_port_v2.etcd.0
  keypair_name = openstack_compute_keypair_v2.etcd.name
  initial_cluster = local.initial_cluster
  ca = module.etcd_ca
  bootstrap_authentication = true
}

module "etcd_member_two" {
  source = "git::https://github.com/Ferlab-Ste-Justine/openstack-etcd-server.git"
  name = "etcd-2"
  namespace = "dev"
  image_id = data.openstack_images_image_v2.ubuntu.id
  flavor_id = module.reference_infra.flavors.micro.id
  network_port = openstack_networking_port_v2.etcd.1
  keypair_name = openstack_compute_keypair_v2.etcd.name
  initial_cluster = local.initial_cluster
  ca = module.etcd_ca
}

module "etcd_member_three" {
  source = "git::https://github.com/Ferlab-Ste-Justine/openstack-etcd-server.git"
  name = "etcd-3"
  namespace = "dev"
  image_id = data.openstack_images_image_v2.ubuntu
  flavor_id = module.reference_infra.flavors.micro.id
  network_port = openstack_networking_port_v2.etcd.2
  keypair_name = openstack_compute_keypair_v2.etcd.name
  initial_cluster = local.initial_cluster
  ca = module.etcd_ca
}
```

# Concerning Architectural Choices

The etcd resources we provision are more decoupled across several modules than most of our other openstack resources, exposing more complexity that needs to be managed outside the modules.

This choice is for three reasons:
- Etcd is a distributed data store. It is stateful so during update, you can't simply provision a fresh etcd cluster to replace the old one and switch dns pointers without propagating the state.
- When we update nodes in the etcd cluster, we should preferably do it one node at a time which will allow us to both maximize uptime and keep our state without having to save/restore from backups (given the limited amount of **volume** space we have in our Openstack).
- To translate the more **hands on** update flow described in the etcd documentation into a gitops flow (if the updates can't initially be simplified into a one step process, at least they can be made auditable in the git history and follow a more quality controlled git-flow with the code... fewer butter fingers): https://etcd.io/docs/v3.4/op-guide/runtime-configuration/

# Current Limitations

## Runtime Reconfiguration

The recommended etcd cluster update flow has two steps: Changing the etcd configuration and then destroying/creating the machine.

Currently, we still don't have an automated way to change the cluster configuration prior to destroying/creating the machines. This is something that we'll probably have to tackle separately from this project.

## Restoring From Backup

Bootstraping a fresh cluster from a backup when recovering from a disaster needs to be done when a cluster is initially created with etcd: https://etcd.io/docs/v3.4/op-guide/recovery/

In our case, given that our backups will be in ceph, we'll need to be able to support passing connection information to an s3 object (containing the backup) to restore from when a machine is created (as an optional argument).

This is something that will be implemented and validated once we have actual etcd backups to test against.
