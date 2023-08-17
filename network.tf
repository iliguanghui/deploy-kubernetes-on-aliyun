data "alicloud_resource_manager_resource_groups" "librg" {
  name_regex = "LabResouceGroup"
}

/* create a vpc */
resource "alicloud_vpc" "default" {
  vpc_name          = var.vpc.name
  cidr_block        = var.vpc.cidr
  resource_group_id = data.alicloud_resource_manager_resource_groups.librg.ids[0]
}

/* create an ipv4 gateway */
resource "alicloud_vpc_ipv4_gateway" "igw" {
  vpc_id            = alicloud_vpc.default.id
  ipv4_gateway_name = var.vpc.name
  resource_group_id = data.alicloud_resource_manager_resource_groups.librg.ids[0]
  enabled           = true
}

/* get all available zones */
data "alicloud_zones" "all" {
  available_resource_creation = "VSwitch"
}

/* create public subnets */
resource "alicloud_vswitch" "public_subnets" {
  for_each = toset(var.vpc.public_subnet_cidr_blocks)

  vswitch_name = "public_subnet_${tonumber(replace(split("/", each.key)[0], ".", "0")) % length(data.alicloud_zones.all.ids)}"
  cidr_block   = each.key
  vpc_id       = alicloud_vpc.default.id
  zone_id      = data.alicloud_zones.all.ids[tonumber(replace(split("/", each.key)[0], ".", "0")) % length(data.alicloud_zones.all.ids)]
}

/* create private subnets */
resource "alicloud_vswitch" "private_subnets" {
  for_each = toset(var.vpc.private_subnet_cidr_blocks)

  vswitch_name = "private_subnet_${tonumber(replace(split("/", each.key)[0], ".", "0")) % length(data.alicloud_zones.all.ids)}"
  cidr_block   = each.key
  vpc_id       = alicloud_vpc.default.id
  zone_id      = data.alicloud_zones.all.ids[tonumber(replace(split("/", each.key)[0], ".", "0")) % length(data.alicloud_zones.all.ids)]
}

/* create public route table */
resource "alicloud_route_table" "public_route_table" {
  vpc_id           = alicloud_vpc.default.id
  route_table_name = "PublicRouteTable"
  associate_type   = "VSwitch"
}

/* create gateway entry in public route table */
resource "alicloud_route_entry" "gateway" {
  route_table_id        = alicloud_route_table.public_route_table.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Ipv4Gateway"
  nexthop_id            = alicloud_vpc_ipv4_gateway.igw.id
}

/* attach public route table with public subnets */
resource "alicloud_route_table_attachment" "public_route_table_attachment" {
  for_each       = toset(var.vpc.public_subnet_cidr_blocks)
  vswitch_id     = alicloud_vswitch.public_subnets[each.key].id
  route_table_id = alicloud_route_table.public_route_table.id
}

/* create private subnets */
resource "alicloud_route_table" "private_route_table" {
  vpc_id           = alicloud_vpc.default.id
  route_table_name = "PrivateRouteTable"
  associate_type   = "VSwitch"
}

/* attach private route table with private subnets */
resource "alicloud_route_table_attachment" "private_route_table_attachment" {
  for_each       = toset(var.vpc.private_subnet_cidr_blocks)
  vswitch_id     = alicloud_vswitch.private_subnets[each.key].id
  route_table_id = alicloud_route_table.private_route_table.id
}
