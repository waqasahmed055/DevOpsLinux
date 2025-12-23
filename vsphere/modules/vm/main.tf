# modules/vm/main.tf

# Data source to get datacenter
data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

# Data source to get datastore
data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Data source to get compute cluster
data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Data source to get network
data "vsphere_network" "network" {
  name          = var.network_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Data source to get template
data "vsphere_virtual_machine" "template" {
  name          = var.template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Create the Virtual Machine
resource "vsphere_virtual_machine" "vm" {
  name             = "${var.server_name}-${var.environment}"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vm_folder

  num_cpus = var.num_cpus
  memory   = var.memory
  guest_id = data.vsphere_virtual_machine.template.guest_id

  # Network interface
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # Disk configuration
  disk {
    label            = "disk0"
    size             = var.disk_size != null ? var.disk_size : data.vsphere_virtual_machine.template.disks[0].size
    thin_provisioned = var.thin_provisioned
  }

  # Clone from template
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = "${var.server_name}-${var.environment}"
        domain    = var.domain
      }

      network_interface {
        ipv4_address = var.ipv4_address
        ipv4_netmask = var.ipv4_netmask
      }

      ipv4_gateway    = var.ipv4_gateway
      dns_server_list = var.dns_servers
    }
  }

  # Wait for guest operations
  wait_for_guest_net_timeout  = var.wait_for_guest_net_timeout
  wait_for_guest_ip_timeout   = var.wait_for_guest_ip_timeout
  wait_for_guest_net_routable = var.wait_for_guest_net_routable

  # Tags
  tags = var.tags
}