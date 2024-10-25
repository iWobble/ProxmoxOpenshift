terraform {
    required_providers {
        proxmox = {
            source = "bpg/proxmox"
            version = "0.66.1"
        }
        ansible = {
            version = "~> 1.3.0"
            source  = "ansible/ansible"
        }
    }
}

provider "proxmox" {
    endpoint                = var.endpoint
    username                = var.username
    password                = var.password
    insecure                = "true"

    ssh {
        agent    = true
        username = "root"
    }
}


locals {
    vm_settings = {
        "master01"       = { tags = ["ign_master"], size = 100, cores = 4, ram = 16384, mac_addr = "00:0d:b9:5f:ce:10", template_id = resource.proxmox_virtual_environment_vm.redhat_coreos_template.id, vm_id = 700, boot = false, hook = true },
        "master02"       = { tags = ["ign_master"], size = 100, cores = 4, ram = 16384, mac_addr = "00:0d:b9:5f:ce:11", template_id = resource.proxmox_virtual_environment_vm.redhat_coreos_template.id, vm_id = 701, boot = false, hook = true },
        "master03"       = { tags = ["ign_master"], size = 100, cores = 4, ram = 16384, mac_addr = "00:0d:b9:5f:ce:12", template_id = resource.proxmox_virtual_environment_vm.redhat_coreos_template.id, vm_id = 702, boot = false, hook = true },
        "worker01"       = { tags = ["ign_worker"], size = 100, cores = 2, ram = 16384, mac_addr = "00:0d:b9:5f:ce:20", template_id = resource.proxmox_virtual_environment_vm.redhat_coreos_template.id, vm_id = 703, boot = false, hook = true },
        "worker02"       = { tags = ["ign_worker"], size = 100, cores = 2, ram = 16384, mac_addr = "00:0d:b9:5f:ce:21", template_id = resource.proxmox_virtual_environment_vm.redhat_coreos_template.id, vm_id = 704, boot = false, hook = true },
        "worker03"       = { tags = ["ign_worker"], size = 100, cores = 2, ram = 16384, mac_addr = "00:0d:b9:5f:ce:22", template_id = resource.proxmox_virtual_environment_vm.redhat_coreos_template.id, vm_id = 705, boot = false, hook = true },
        "bootstrap"      = { tags = ["ign_bootstrap"], size = 100, cores = 4, ram = 16384, mac_addr = "00:0d:b9:5f:ce:05", template_id = resource.proxmox_virtual_environment_vm.redhat_coreos_template.id, vm_id = 707, boot = false, hook = true }
        "service"        = { tags = ["ign_service"], size = 100, cores = 4, ram = 16384, mac_addr = "00:0d:b9:5f:ce:02", template_id = resource.proxmox_virtual_environment_vm.centos_stream_template.id, vm_id = 709, boot = true, hook = false }
    }
    
    bridge  = "VLAN50"
    lxc_settings = {
    }
}


# Not using right now
#data "proxmox_virtual_environment_datastores" "proxmox_node" {
#    node_name   = "${var.node_name}"
#}

data "local_file" "public_ssh_key" {
  filename = "/home/${var.user}/.ssh/id_rsa.pub"
}


resource "proxmox_virtual_environment_download_file" "redhat_coreos_image" {
    content_type            = "iso"
    datastore_id            = "${var.template_datastore}"
    node_name               = "${var.node_name}"
    url                     = "https://rhcos.mirror.openshift.com/art/storage/prod/streams/${var.rhcos_stream}/builds/${var.rhcos_version}/x86_64/rhcos-${var.rhcos_version}-${var.rhcos_platform}.x86_64.qcow2.gz"
    decompression_algorithm = "zst"
    file_name               = "RedHat-CoreOS-${var.rhcos_version}-${var.rhcos_platform}.x86_64.img"
    overwrite               = false
}

resource "proxmox_virtual_environment_download_file" "centos_cloud_image" {
    content_type = "iso"
    datastore_id = "${var.template_datastore}"
    node_name    = "${var.node_name}"
    url          = "https://cloud.centos.org/centos/${var.centos_stream}-stream/x86_64/images/CentOS-Stream-GenericCloud-${var.centos_stream}-${var.centos_version}.x86_64.qcow2"
    file_name    = "CentOS-Stream-GenericCloud-${var.centos_stream}-${var.centos_version}.img"
    overwrite    = false
}

resource "proxmox_virtual_environment_vm" "redhat_coreos_template" {
    name            = "RedHatCoreOS-${var.rhcos_version}-template"
    node_name       = "${var.node_name}"
    description     = <<-EOT
    Cloned from: 
    RedHat CoreOS - ${var.rhcos_version}-${var.rhcos_platform} Template
    - Version:      ${var.rhcos_version} 
    - Platform:     ${var.rhcos_platform}
    - CloudInit:    true
    
    EOT

    vm_id           = "${var.rhcos_vmid}"
    on_boot         = false
    started         = false
    template        = true
    tablet_device   = false
    stop_on_destroy = true
    
    boot_order      = ["scsi0"]
    operating_system {
        type        = "l26"
    }
    
    agent {
        enabled     = true
    }

    cpu {
        cores       = 4
        hotplugged  = 0
        type        = "host"

    }
    
    memory {
        dedicated   = 4096
    }

    network_device {
        model   = "virtio"
    }
    
    initialization {
        datastore_id = "${var.template_datastore}"
        user_account {
            keys        = [trimspace(data.local_file.public_ssh_key.content)]
            username    = "${var.user}"
            password    = "${var.passwd}"
        }
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }

    vga {
        type    = "serial0"
    }

    serial_device {}

    disk {
        interface       = "scsi0"
        datastore_id    = "${var.template_datastore}"
        file_id         = proxmox_virtual_environment_download_file.redhat_coreos_image.id
        size            = 16
    }
        
}

resource "proxmox_virtual_environment_vm" "centos_stream_template" {
    name            = "CentOS-${var.centos_version}-template"
    node_name       = "${var.node_name}"
  
    description     = <<-EOT
    Cloned from: 
    Centos Stream ${var.centos_stream} - ${var.centos_version} Template
    - Version:      ${var.centos_version}
    - CloudInit:    true
    
    EOT

    vm_id           = "${var.centos_vmid}"
    on_boot         = false
    started         = false
    template        = true

    tablet_device   = false
    stop_on_destroy = true
    

    boot_order      = ["scsi0"]
    operating_system {
        type        = "l26"
    }
    
    agent {
        enabled     = true
    }

    cpu {
        cores       = 4
        hotplugged  = 0
        type        = "host"

    }
    
    memory {
        dedicated   = 4096
    }

    network_device {
        model   = "virtio"
    }

    initialization {
        datastore_id    = "${var.template_datastore}"
        user_account {
            keys     = [trimspace(data.local_file.public_ssh_key.content)]
            username = "${var.user}"
            password = "${var.passwd}"
        }
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }

    vga {
        type    = "serial0"
    }

    serial_device {} 

    disk {
        datastore_id = "${var.template_datastore}"
        file_id      = proxmox_virtual_environment_download_file.centos_cloud_image.id
        interface    = "scsi0"
        size         = 10
    }
}

resource "proxmox_virtual_environment_vm" "cloudinit-nodes" {
    for_each        = local.vm_settings
    name            = each.key

    node_name       = var.node_name

    vm_id           = each.value.vm_id

    clone {
        vm_id       = each.value.template_id
        full        = true
    }
    
    on_boot         = each.value.boot
    started         = each.value.boot

    cpu {
        cores       = each.value.cores
        hotplugged  = 0
        type        = "host"
    }
    
    memory {
        dedicated   = each.value.ram
    }

    tags            = each.value.tags

    disk {
        interface    = "scsi0"
        datastore_id = "${var.template_datastore}"
        size         = each.value.size
    }

    network_device {
        bridge      = local.bridge
        mac_address = each.value.mac_addr
    }

    vga {
        type    = "serial0"
    }


    
    hook_script_file_id = each.value.hook == true ? proxmox_virtual_environment_file.hook_rhcos.id : ""
}

resource "proxmox_virtual_environment_file" "hook_rhcos" {
    content_type    = "snippets"
    datastore_id    = "${var.template_datastore}"
    node_name       = var.node_name

    file_mode       = "0700"

    source_file {
        path = "scripts/hook-rhcos.sh"
    }
}

resource "proxmox_virtual_environment_file" "rhcos_base_template" {
    content_type    = "snippets"
    datastore_id    = "${var.template_datastore}"
    node_name       = var.node_name

    source_file {
        path = "scripts/rhcos-base-template.yaml"
    }
}

resource "proxmox_virtual_environment_file" "rhcos_import_template" {
    content_type    = "snippets"
    datastore_id    = "${var.template_datastore}"
    node_name       = var.node_name

    
    source_raw {
        ### Indentation is important
        data = <<EOF
        merge:
          - source: "${var.service_endpoint}/TAG.ign"

        EOF

        file_name = "rhcos-import-template.yaml"
    }
}

