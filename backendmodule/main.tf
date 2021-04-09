resource "ibm_is_instance" "backend-server" {
  count   = var.backend_count
  name    = "${var.unique_id}-backend-vsi-${count.index + 1}"
  image   = var.ibm_is_image_id
  profile = var.profile

  primary_network_interface {
    subnet          = var.subnet_ids[count.index]
    security_groups = [ibm_is_security_group.backend.id]
  }

  vpc            = var.ibm_is_vpc_id
  zone           = "${var.ibm_region}-${count.index % 3 + 1}"
  resource_group = var.ibm_is_resource_group_id
  keys           = [var.ibm_is_ssh_key_id]
  user_data      = data.template_cloudinit_config.app_userdata.rendered
  tags           = ["schematics:group:backend"]
}

resource "ibm_is_security_group" "backend" {
  name           = "${var.unique_id}-backend-sg"
  vpc            = var.ibm_is_vpc_id
  resource_group = var.ibm_is_resource_group_id
}

locals {
  sg_keys = ["direction", "remote", "type", "port_min", "port_max"]
  sg_rules = [
    ["inbound", var.bastion_remote_sg_id, "tcp", 22, 22],
    ["inbound", var.app_frontend_sg_id, "tcp", 27017, 27017],
    ["outbound", "161.26.0.0/24", "tcp", 443, 443],
    ["outbound", "161.26.0.0/24", "tcp", 80, 80],
    ["outbound", "161.26.0.0/24", "udp", 53, 53],
    ["outbound", var.pub_repo_egress_cidr, "tcp", 443, 443],
    ["inbound", "0.0.0.0/0", "tcp", 80, 80]
  ]

  sg_mappedrules = [
    for entry in local.sg_rules :
    merge(zipmap(local.sg_keys, entry))
  ]
}


resource "ibm_is_security_group_rule" "backend_access" {
  count     = length(local.sg_mappedrules)
  group     = ibm_is_security_group.backend.id
  direction = (local.sg_mappedrules[count.index]).direction
  remote    = (local.sg_mappedrules[count.index]).remote
  dynamic "tcp" {
    for_each = local.sg_mappedrules[count.index].type == "tcp" ? [
      {
        port_max = local.sg_mappedrules[count.index].port_max
        port_min = local.sg_mappedrules[count.index].port_min
      }
    ] : []
    content {
      port_max = tcp.value.port_max
      port_min = tcp.value.port_min

    }
  }
  dynamic "udp" {
    for_each = local.sg_mappedrules[count.index].type == "udp" ? [
      {
        port_max = local.sg_mappedrules[count.index].port_max
        port_min = local.sg_mappedrules[count.index].port_min
      }
    ] : []
    content {
      port_max = udp.value.port_max
      port_min = udp.value.port_min
    }
  }
  dynamic "icmp" {
    for_each = local.sg_mappedrules[count.index].type == "icmp" ? [
      {
        type = local.sg_mappedrules[count.index].port_max
        code = local.sg_mappedrules[count.index].port_min
      }
    ] : []
    content {
      type = icmp.value.type
      code = icmp.value.code
    }
  }
}




