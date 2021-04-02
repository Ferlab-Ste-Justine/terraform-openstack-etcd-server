#cloud-config
users:
  - default
  - name: node-exporter
    system: true
    lock_passwd: true
  - name: etcd
    system: true
    lock_passwd: true
write_files:
  #Prometheus node exporter systemd configuration
  - path: /etc/systemd/system/node-exporter.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Prometheus Node Exporter"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      User=node-exporter
      Group=node-exporter
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/usr/local/bin/node_exporter

      [Install]
      WantedBy=multi-user.target
  #Etcd tls Certificates
  - path: /opt/ca-cert.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, ca_cert)}
  - path: /opt/cert.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, cert)}
  - path: /opt/key
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, key)}
  #Etcd bootstrap authentication if node is responsible for it
%{ if bootstrap_authentication ~}
  - path: /opt/root_cert.pem
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, root_cert)}
  - path: /opt/root_key
    owner: root:root
    permissions: "0400"
    content: |
      ${indent(6, root_key)}
  - path: /opt/bootstrap_auth.sh
    owner: root:root
    permissions: "0555"
    content: |
      #!/bin/bash
      ROOT_USER=""
      while [ "$ROOT_USER" != "root" ]; do
          sleep 1
          etcdctl user add --no-password --cacert=/etc/etcd/tls/ca-cert.pem --endpoints=https://127.0.0.1:2379 --insecure-transport=false --cert=/opt/root_cert.pem --key=/opt/root_key root
          ROOT_USER=$(etcdctl user list --cacert=/etc/etcd/tls/ca-cert.pem --endpoints=https://127.0.0.1:2379 --insecure-transport=false --cert=/opt/root_cert.pem --key=/opt/root_key | grep root)
      done
      ROOT_ROLES=""
      while [ -z "$ROOT_ROLES" ]; do
          sleep 1
          etcdctl user grant-role --cacert=/etc/etcd/tls/ca-cert.pem --endpoints=https://127.0.0.1:2379 --insecure-transport=false --cert=/opt/root_cert.pem --key=/opt/root_key root root
          ROOT_ROLES=$(etcdctl user get --cacert=/etc/etcd/tls/ca-cert.pem --endpoints=https://127.0.0.1:2379 --insecure-transport=false --cert=/opt/root_cert.pem --key=/opt/root_key root | grep "Roles: root")
      done
      etcdctl auth enable --cacert=/etc/etcd/tls/ca-cert.pem --endpoints=https://127.0.0.1:2379 --insecure-transport=false --cert=/opt/root_cert.pem --key=/opt/root_key
      while [ $? -ne 0 ]; do
          sleep 1
          etcdctl auth enable --cacert=/etc/etcd/tls/ca-cert.pem --endpoints=https://127.0.0.1:2379 --insecure-transport=false --cert=/opt/root_cert.pem --key=/opt/root_key
      done
%{ endif ~}
  #Etcd configuration file
  - path: /opt/conf.yml
    owner: root:root
    permissions: "0400"
    content: |
      data-dir: /var/lib/etcd
      quota-backend-bytes: ${etcd_space_quota}
      auto-compaction-mode: ${etcd_auto_compaction_mode}
      auto-compaction-retention: "${etcd_auto_compaction_retention}"
      name: ${etcd_name}
      initial-cluster-token: ${etcd_initial_cluster_token}
      initial-advertise-peer-urls: https://${self_ip}:2380
      listen-peer-urls: https://${self_ip}:2380
      listen-client-urls: https://${self_ip}:2379,https://127.0.0.1:2379
      advertise-client-urls: https://${self_ip}:2379
      initial-cluster-state: ${etcd_initial_cluster_state}
      initial-cluster: ${etcd_cluster}
      peer-transport-security:
        trusted-ca-file: /etc/etcd/tls/ca-cert.pem
        cert-file: /etc/etcd/tls/cert.pem
        key-file: /etc/etcd/tls/key
        client-cert-auth: true
      client-transport-security:
        trusted-ca-file: /etc/etcd/tls/ca-cert.pem
        cert-file: /etc/etcd/tls/cert.pem
        key-file: /etc/etcd/tls/key
        client-cert-auth: true
  #Etcd systemd configuration
  - path: /etc/systemd/system/etcd.service
    owner: root:root
    permissions: "0444"
    content: |
      [Unit]
      Description="Etcd Service"
      Wants=network-online.target
      After=network-online.target
      StartLimitIntervalSec=0

      [Service]
      Environment="ETCD_CONFIG_FILE=/etc/etcd/conf.yml"
      User=etcd
      Group=etcd
      Type=simple
      Restart=always
      RestartSec=1
      ExecStart=/usr/local/bin/etcd

      [Install]
      WantedBy=multi-user.target
      
runcmd:
  #Move etcd tls related files and configuration file in correct directory
  - mkdir -p /etc/etcd/tls
  - mv /opt/ca-cert.pem /opt/cert.pem /opt/key /etc/etcd/tls/
  - mv /opt/conf.yml /etc/etcd/conf.yml
  - chown etcd:etcd -R /etc/etcd
  #Install etcd service binaries
  - wget -O /opt/etcd-${etcd_version}-linux-amd64.tar.gz https://storage.googleapis.com/etcd/${etcd_version}/etcd-${etcd_version}-linux-amd64.tar.gz
  - mkdir -p /opt/etcd
  - tar xzvf /opt/etcd-${etcd_version}-linux-amd64.tar.gz -C /opt/etcd
  - cp /opt/etcd/etcd-${etcd_version}-linux-amd64/etcd /usr/local/bin/etcd
  - cp /opt/etcd/etcd-${etcd_version}-linux-amd64/etcdctl /usr/local/bin/etcdctl
  - rm -f /opt/etcd-${etcd_version}-linux-amd64.tar.gz
  - rm -rf /opt/etcd
  #Create etcd service data directory
  - mkdir -p /var/lib/etcd
  - chown etcd:etcd /var/lib/etcd
  - chmod 0700 /var/lib/etcd
  #State etcd service
  - systemctl enable etcd
  - systemctl start etcd
  #Install prometheus node exporter as a binary managed as a systemd service
  - wget -O /opt/node_exporter.tar.gz https://github.com/prometheus/node_exporter/releases/download/v1.0.1/node_exporter-1.0.1.linux-amd64.tar.gz
  - mkdir -p /opt/node_exporter
  - tar zxvf /opt/node_exporter.tar.gz -C /opt/node_exporter
  - cp /opt/node_exporter/node_exporter-1.0.1.linux-amd64/node_exporter /usr/local/bin/node_exporter
  - chown node-exporter:node-exporter /usr/local/bin/node_exporter
  - rm -r /opt/node_exporter && rm /opt/node_exporter.tar.gz
  - systemctl enable node-exporter
  - systemctl start node-exporter
  #Setup etcd authentication if node selected for that role 
%{ if bootstrap_authentication ~}
  - /opt/bootstrap_auth.sh
  - rm /opt/root_cert.pem
  - rm /opt/root_key
%{ endif ~}