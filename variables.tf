variable "name" {
  description = "Base name to give to the vm. The namespace, if present, will be suffixed"
  type = string
  default = "etcd"
}

variable "namespace" {
  description = "Namespace to create the resources under"
  type = string
  default = ""
}

variable "image_id" {
  description = "ID of the image the etcd instance will run on"
  type = string
}

variable "flavor_id" {
  description = "ID of the flavor the etcd instance will run on"
  type = string
}

variable "network_port" {
  description = "Network port to assign to the node. Should be of type openstack_networking_port_v2"
  type = any
}

variable "keypair_name" {
  description = "Name of the keypair that will be used to ssh to the etcd instance"
  type = string
}

variable "etcd_version" {
  description = "Version of etcd to use in the format: vX.Y.Z"
  type = string
  default = "v3.4.15"
}

variable "etcd_auto_compaction_mode" {
  description = "The policy of etcd's auto compaction. Can be either 'periodic' to delete revision older than x or 'revision' to keep at most y revisions"
  type = string
  default = "revision"
}

variable "etcd_auto_compaction_retention" {
  #see for expected format: https://etcd.io/docs/v3.4/op-guide/maintenance/
  description = "Boundary specifying what revisions should be compacted. Can be a time value for 'periodic' or a number in string format for 'revision'"
  type = string
  default = "1000"
}


variable "etcd_space_quota" {
  description = "Maximum disk space that etcd can take before the cluster goes into alarm mode"
  type = number
  #Defaults to 8GB
  default = 8*1024*1024*1024
}

variable "is_initial_cluster" {
  description = "Whether or not this etcd vm is generated as part of a new cluster"
  type = bool
  default = true
}

variable "initial_cluster_token" {
  description = "Initial token given to uniquely identify the new cluster"
  type = string
  default = "etcd-cluster"
}

variable "initial_cluster" {
  description = "List indicating the initial cluster. Each entry in the list should be a map with the following two keys: 'ip' and 'name'. The name should be the same as the 'name' variable passed to each node."
  type = list(map(string))
}

variable "organization" {
  description = "The etcd cluster's certificates' organization"
  type = string
  default = "Ferlab"
}

variable "certificate_validity_period" {
  description = "The etcd cluster's certificate's validity period in hours"
  type = number
  default = 100*365*24
}

variable "certificate_early_renewal_period" {
  description = "The etcd cluster's certificate's early renewal period in hours"
  type = number
  default = 99*365*24
}

variable "ca" {
  description = "The ca that will sign the member's certificate. Should have the following keys: key, key_algorithm, certificate"
  type = any
}

variable "bootstrap_authentication" {
  description = "Whether the node should bootstrap authentication for the cluster: creating an admin root user and enabling authentication"
  type = bool
  default = false
}