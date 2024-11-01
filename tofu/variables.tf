variable "endpoint" {
    description     = "Proxmox Endpoint URL"
    default         = "https://pve.iwobble.com:8006/api2/json"
}

variable "username" {
    description     = "Proxmox Username of the account to use"
    default         = "root@pam"
}
variable "user" {
    description     = "CloudInit Username"
}

variable "passwd" {
    description     = "CloudInit Password"
    type            = string
    sensitive       = true
}

variable "password" {
    description     = "Proxmox Password for the user - defined elsewhere"
    type            = string
    sensitive       = true
}

variable "service_endpoint" {
    description     = "Service URL"
    default         = "http://service.ocp4.iwobble.com:8080"
}

variable "node_name" {
    description     = "Proxmox Node Name to be deployed to."
    default         = "pve"
}

variable "template_datastore" {
    description     = "Proxmox Storage ID"
    default         = "local"
}

variable "template_id" {
    description     = "Red Hat CoreOS Template ID"
    default         = "912"
}

variable "rhcos_version" {
    description     = "Red Hat CoreOS Version"
    default         = "417.94.202410090854-0"
}

variable "rhcos_platform" {
    description     = "Red Hat CoreOS Platform"
    default         = "qemu"
}

variable "rhcos_vmid" {
    description     = "Red Hat CoresOS VMID"
    default         = "943" 
}

variable "rhcos_stream" {
    description     = "Red Hat CoreOS Stream"
    default         = "4.17-9.4"
}

variable "centos_version" {
    description     = "CentOS Stream Version"
    default         = "latest"
}

variable "centos_stream" {
    description     = "CentOS Stream ID"
    default         = 9 
}

variable "centos_vmid" {
    description     = "CentOS Stream VMID"
    default         = 901
}

variable "install_type" {
    description     = "Single or Mult Node Cluster"
    default         = "multi_node"
}
