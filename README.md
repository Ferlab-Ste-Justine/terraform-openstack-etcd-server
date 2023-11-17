# About

This is a terraform module that provisions a single member of an opensearch cluster.

Given a certificate authority as argument (can be an internal-only self-signed authority), it will generate its own secret key and certificate to communicate with clients and peers in the cluster.

One of the servers can also be set to bootstrap authentication in the cluster: it will generates a passwordless **root** user and enable authentication. You are expected to use your certificate authority to generate a client user certificate for **root** to further configure your etcd cluster. See: https://github.com/Ferlab-Ste-Justine/terraform-tls-client-certificate

# Usage

## Variables

This module takes the following variables as input:

- **name**: This should be a name that uniquely identifies this member in the cluster. 
- **image_source**: Source of the image to provision the bastion on. It takes the following keys (only one of the two fields should be used, the other one should be empty):
  - **image_id**: Id of the image to associate with a vm that has local storage
  - **volume_id**: Id of a volume containing the os to associate with the vm
- **data_volume_id**: Id for an optional separate volume to attach to the vm on etcd's data path
- **flavor_id**: Id of the vm flavor to assign to the instance. See hardware recommendations to make an informed choice: https://etcd.io/docs/v3.4/op-guide/hardware/
- **network_port**: Resource of type **openstack_networking_port_v2** to assign to the vm for network connectivity
- **server_group**: Server group to assign to the node. Should be of type **openstack_compute_servergroup_v2**.
- **keypair_name**: Name of the ssh keypair that will be used to ssh against the vm.
- **etcd**: Etcd configuration. It should be the same on each member of the cluster and have the following keys:
  - **auto_compaction_mode**: The kind of auto compaction to use. Can be **periodic** or **revision** (defaults to **revision**). See: https://etcd.io/docs/v3.4/op-guide/maintenance/
  - **auto_compaction_retention**: Specifies what versions will be preserved during auto compaction given the **auto_compaction_mode**. Defaults to **1000** (if the defaults are kept, the last 1000 revisions will be preserved and all revisions older than that will be fair game for compaction)
  - **space_quota**: The maximum disk space the etcd instance can use before the cluster hits **panic mode** and becomes **read only**. Given that etcd tries to cache all its key values in the memory for performance reasons, it make sense not to make this much greater than the amount of memory you have on the machine (because of fragmentation, a key space that fits in the memory could theoretically take an amount of disk space that is larger than the amount of memory). Defaults to 8GiB.
  - **grpc_gateway_enabled**: If set to true (defaults to false), the legacy REST v3 endpoints are enabled which might be needed if you use a client that isn't up to date. Note that if you set this to true, you need to set **client_cert_auth** to false.
  - **client_cert_auth**: Whether to use client certificate authentication (defaults to true). If set to false, username/password authentication will be used instead.
- **authentication_bootstrap**: Configuration parameter for one (and only one) of the starting node that will create the root user and enabled authentication for the cluster. It has the following keys:
  - **bootstrap**: Whether the node should bootstrap authentication. Defaults to false.
  - **root_password**: Password to assign to the root user if **etcd.client_cert_auth** is set to false.
- **cluster**: Configuration parameter to set on all nodes to indicate whether the cluster is getting initialized and the initialization settings. It has the following keys:
  - **is_initializing**: Set to true if the cluster is getting generated along with the creation of this node.
  - **initial_token**: Initialization token for the cluster.
  - **initial_members**: List of the initial members that are present when the cluster is initially boostraped. It should contain a list of maps, each entry having the following keys: ip, name. The **name** value in each map should be the same as the **name** value that is passed to the corresponding member as a module variable.
- **tls**: Tls authentication parameters for peer-to-peer communication and server-to-client communitcation. It has the following keys.
  - **ca_cert**: CA certificate that will be used to validate the authenticity of peers and clients.
  - **server_cert**: Server certificate that will be used to authentify the server to its peers and to clients. In addition to being signed for all the ips and domains the server will use, it should be signed with the **127.0.0.1** loopback address in order to initialize authentication from one of the servers. Its allowed uses should be both server authentication and client authentication.
  - **server_key**: Server private key that complements its certificate for authentication.
- **chrony**: Optional chrony configuration for when you need a more fine-grained ntp setup on your vm. It is an object with the following fields:
  - **enabled**: If set the false (the default), chrony will not be installed and the vm ntp settings will be left to default.
  - **servers**: List of ntp servers to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server)
  - **pools**: A list of ntp server pools to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool)
  - **makestep**: An object containing remedial instructions if the clock of the vm is significantly out of sync at startup. It is an object containing two properties, **threshold** and **limit** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep)
- **fluentbit**: Optional fluent-bit configuration to securely route logs to a fluend/fluent-bit node using the forward plugin. Alternatively, configuration can be 100% dynamic by specifying the parameters of an etcd store or git repo to fetch the configuration from. It has the following keys:
  - **enabled**: If set the false (the default), fluent-bit will not be installed.
  - **metrics**: Configuration for metrics fluentbit exposes.
    - **enabled**: Whether to enable the metrics or not
    - **port**: Port to expose the metrics on
  - **etcd_tag**: Tag to assign to logs coming from etcd
  - **node_exporter_tag** Tag to assign to logs coming from the prometheus node exporter
  - **forward**: Configuration for the forward plugin that will talk to the external fluend/fluent-bit node. It has the following keys:
    - **domain**: Ip or domain name of the remote fluend node.
    - **port**: Port the remote fluend node listens on
    - **hostname**: Unique hostname identifier for the vm
    - **shared_key**: Secret shared key with the remote fluentd node to authentify the client
    - **ca_cert**: CA certificate that signed the remote fluentd node's server certificate (used to authentify it)
- **fluentbit_dynamic_config**: Optional configuration to update fluent-bit configuration dynamically either from an etcd key prefix or a path in a git repo.
  - **enabled**: Boolean flag to indicate whether dynamic configuration is enabled at all. If set to true, configurations will be set dynamically. The default configurations can still be referenced as needed by the dynamic configuration. They are at the following paths:
    - **Global Service Configs**: /etc/fluent-bit-customization/default-config/service.conf
    - **Default Variables**: /etc/fluent-bit-customization/default-config/default-variables.conf
    - **Systemd Inputs**: /etc/fluent-bit-customization/default-config/inputs.conf
    - **Forward Output For All Inputs**: /etc/fluent-bit-customization/default-config/output-all.conf
    - **Forward Output For Default Inputs Only**: /etc/fluent-bit-customization/default-config/output-default-sources.conf
  - **source**: Indicates the source of the dynamic config. Can be either **etcd** or **git**.
  - **etcd**: Parameters to fetch fluent-bit configurations dynamically from an etcd cluster. It has the following keys:
    - **key_prefix**: Etcd key prefix to search for fluent-bit configuration
    - **endpoints**: Endpoints of the etcd cluster. Endpoints should have the format `<ip>:<port>`
    - **ca_certificate**: CA certificate against which the server certificates of the etcd cluster will be verified for authenticity
    - **client**: Client authentication. It takes the following keys:
      - **certificate**: Client tls certificate to authentify with. To be used for certificate authentication.
      - **key**: Client private tls key to authentify with. To be used for certificate authentication.
      - **username**: Client's username. To be used for username/password authentication.
      - **password**: Client's password. To be used for username/password authentication.
  - **git**: Parameters to fetch fluent-bit configurations dynamically from an git repo. It has the following keys:
    - **repo**: Url of the git repository. It should have the ssh format.
    - **ref**: Git reference (usually branch) to checkout in the repository
    - **path**: Path to sync from in the git repository. If the empty string is passed, syncing will happen from the root of the repository.
    - **trusted_gpg_keys**: List of trusted gpp keys to verify the signature of the top commit. If an empty list is passed, the commit signature will not be verified.
    - **auth**: Authentication to the git server. It should have the following keys:
      - **client_ssh_key** Private client ssh key to authentication to the server.
      - **server_ssh_fingerprint**: Public ssh fingerprint of the server that will be used to authentify it.
- **install_dependencies**: Whether cloud-init should install external dependencies (should be set to false if you already provide an image with the external dependencies built-in).

# Current Limitations

## Restoring From Backup

Bootstraping a fresh cluster from a backup when recovering from a disaster needs to be done when a cluster is initially created with etcd: https://etcd.io/docs/v3.4/op-guide/recovery/

In our case, given that our backups will be in ceph, we'll need to be able to support passing connection information to an s3 object (containing the backup) to restore from when a machine is created (as an optional argument).

This is something that will be implemented and validated once we have actual etcd backups to test against.

# Gotcha

To safeguard against potential outages and loss of data, changes to the server's user data will be ignored without reprovisioning.

To change most parameters in etcd, you should explicitly reprovision the nodes.