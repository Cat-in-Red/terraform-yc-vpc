### Datasource
data "yandex_client_config" "client" {}



### Locals
locals {
  folder_id                = var.folder_id == null ? data.yandex_client_config.client.folder_id : var.folder_id
  vpc_id                   = var.create_vpc ? yandex_vpc_network.this[0].id : var.vpc_id
  public_route_table_id    = var.create_route_table && var.public_subnets != null  ? yandex_vpc_route_table.public[0].id : var.public_route_table_id
  private_route_table_id   = var.create_route_table && var.private_subnets != null ? yandex_vpc_route_table.private[0].id : var.public_route_table_id
  domain_name              = var.domain_zone_id != "" ? data.yandex_dns_zone.dns_zone[0].zone : var.domain_name

}

data "yandex_dns_zone" "dns_zone" {
  count = var.domain_zone_id != "" ? 1 : 0
  dns_zone_id = var.domain_zone_id
} 

### Network
resource "yandex_vpc_network" "this" {
  count       = var.create_vpc ? 1 : 0
  description = var.network_description
  name        = var.network_name
  labels      = var.labels
  folder_id   = local.folder_id
}

resource "yandex_vpc_subnet" "public" {
  for_each       = try({ for v in var.public_subnets : v.zone => v }, {})
  name           = "public-${var.network_name}-${each.value.zone}"
  description    = "${var.network_name} subnet for zone ${each.value.zone}"
  v4_cidr_blocks = each.value.v4_cidr_blocks
  zone           = each.value.zone
  network_id     = local.vpc_id
  folder_id      = lookup(each.value, "folder_id", local.folder_id)
  route_table_id = try(var.public_route_table_id, null)
  dhcp_options {
    domain_name         = local.domain_name
    domain_name_servers = var.domain_name_servers
    ntp_servers         = var.ntp_servers
  }

  labels = var.labels
}

resource "yandex_vpc_subnet" "private" {
  for_each       = try({ for v in var.private_subnets : v.zone => v }, {})
  name           = "private-${var.network_name}-${each.value.zone}"
  description    = "${var.network_name} subnet for zone ${each.value.zone}"
  v4_cidr_blocks = each.value.v4_cidr_blocks
  zone           = each.value.zone
  network_id     = local.vpc_id
  folder_id      = lookup(each.value, "folder_id", local.folder_id)
  route_table_id = try(var.private_route_table_id, null)
  dhcp_options {
    domain_name         = local.domain_name
    domain_name_servers = var.domain_name_servers
    ntp_servers         = var.ntp_servers
  }

  labels = var.labels
}

## Routes
resource "yandex_vpc_gateway" "egress_gateway" {
  count     = var.create_nat_gw && var.private_subnets != null ? 1 : 0
  name      = "${var.network_name}-egress-gateway"
  folder_id = local.folder_id
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "public" {
  count      = var.create_route_table && var.public_subnets != null ? 1 : 0
  name       = "${var.network_name}-public"
  network_id = local.vpc_id
  folder_id  = local.folder_id

  dynamic "static_route" {
    for_each = var.routes_public_subnets == null ? [] : var.routes_public_subnets
    content {
      destination_prefix = static_route.value["destination_prefix"]
      next_hop_address   = static_route.value["next_hop_address"]
    }
  }

}
resource "yandex_vpc_route_table" "private" {
  count      = var.create_route_table && var.private_subnets != null ? 1 : 0
  name       = "${var.network_name}-private"
  network_id = local.vpc_id
  folder_id  = local.folder_id

  dynamic "static_route" {
    for_each = var.routes_private_subnets == null ? [] : var.routes_private_subnets
    content {
      destination_prefix = static_route.value["destination_prefix"]
      next_hop_address   = static_route.value["next_hop_address"]
    }
  }
  dynamic "static_route" {
    for_each = var.create_nat_gw ? yandex_vpc_gateway.egress_gateway : []
    content {
      destination_prefix = "0.0.0.0/0"
      gateway_id         = yandex_vpc_gateway.egress_gateway[0].id
    }
  }

}

## Default Security Group
resource "yandex_vpc_default_security_group" "default_sg" {
  count       = var.create_vpc && var.create_sg ? 1 : 0
  description = "Default security group"
  network_id  = local.vpc_id
  folder_id   = local.folder_id
  labels      = var.labels

  ingress {
    protocol          = "ANY"
    description       = "Communication inside this SG"
    predefined_target = "self_security_group"

  }
  ingress {
    protocol       = "ANY"
    description    = "ssh"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22

  }
  ingress {
    protocol       = "ANY"
    description    = "RDP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 3389

  }
  ingress {
    protocol       = "ICMP"
    description    = "ICMP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol          = "TCP"
    description       = "NLB health check"
    predefined_target = "loadbalancer_healthchecks"
  }

  egress {
    protocol       = "ANY"
    description    = "To internet"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
