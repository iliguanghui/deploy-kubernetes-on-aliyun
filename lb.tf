/* 创建一个nlb用来路由apiserver流量和ingress流量 */
resource "alicloud_nlb_load_balancer" "apiserver" {
  address_ip_version = "Ipv4"
  address_type       = "Internet"
  cross_zone_enabled = true
  load_balancer_name = "ingress-apiserver"
  load_balancer_type = "Network"
  vpc_id             = alicloud_vpc.default.id
  zone_mappings {
    vswitch_id = alicloud_vswitch.public_subnets[var.vpc.public_subnet_cidr_blocks[0]].id
    zone_id    = data.alicloud_zones.all.ids[tonumber(replace(split("/", var.vpc.public_subnet_cidr_blocks[0])[0], ".", "0")) % length(data.alicloud_zones.all.ids)]
  }
  zone_mappings {
    vswitch_id = alicloud_vswitch.public_subnets[var.vpc.public_subnet_cidr_blocks[1]].id
    zone_id    = data.alicloud_zones.all.ids[tonumber(replace(split("/", var.vpc.public_subnet_cidr_blocks[1])[0], ".", "0")) % length(data.alicloud_zones.all.ids)]
  }
}

/* 为创建的slb配置一个自定义域名 */
resource "alicloud_alidns_record" "control-plane" {
  domain_name = var.dns.domain_name
  rr          = var.dns.record_name
  type        = "CNAME"
  value       = alicloud_nlb_load_balancer.apiserver.dns_name
  status      = "ENABLE"
}

/* 为创建的slb配置一个更容易记忆的别名 */
resource "alicloud_alidns_record" "ingress-entrypoint-alias" {
  domain_name = var.dns.domain_name
  # rr是resource record的意思
  rr          = "ingress"
  type        = "CNAME"
  value       = alicloud_nlb_load_balancer.apiserver.dns_name
  status      = "ENABLE"
}

/* apiserver所在的服务器组 */
resource "alicloud_nlb_server_group" "apiserver" {
  resource_group_id          = data.alicloud_resource_manager_resource_groups.librg.ids[0]
  server_group_name          = "apiserver"
  server_group_type          = "Instance"
  vpc_id                     = alicloud_vpc.default.id
  scheduler                  = "Wrr"
  protocol                   = "TCP"
  preserve_client_ip_enabled = true
  health_check {
    health_check_enabled         = true
    health_check_type            = "TCP"
    health_check_connect_port    = 0
    healthy_threshold            = 2
    unhealthy_threshold          = 2
    health_check_connect_timeout = 5
    health_check_interval        = 10
  }
  connection_drain         = true
  connection_drain_timeout = 60
  address_ip_version       = "Ipv4"
}

/* apiserver监听器：接收流量，转发到各apiserver实例上*/
resource "alicloud_nlb_listener" "apiserver" {
  listener_description = "apiserver"
  listener_protocol    = "TCP"
  listener_port        = "6443"
  load_balancer_id     = alicloud_nlb_load_balancer.apiserver.id
  server_group_id      = alicloud_nlb_server_group.apiserver.id
  idle_timeout         = "900"
  cps                  = "1000"
  mss                  = "0"
}

/* 添加创建的公开子网中的第一台ecs实例到apiserver服务器中，剩下的需要手动添加 */
resource "alicloud_nlb_server_group_server_attachment" "apiserver" {
  server_type     = "Ecs"
  server_id       = alicloud_instance.public_instances[0].id
  port            = 6443
  server_group_id = alicloud_nlb_server_group.apiserver.id
  weight          = 100
}


/* ingress controller的https服务所在的服务器组，默认是空的，需要在创建Ingress controller后手动填充 */
resource "alicloud_nlb_server_group" "websecure" {
  resource_group_id          = data.alicloud_resource_manager_resource_groups.librg.ids[0]
  server_group_name          = "websecure"
  server_group_type          = "Instance"
  vpc_id                     = alicloud_vpc.default.id
  scheduler                  = "Wrr"
  protocol                   = "TCP"
  preserve_client_ip_enabled = true
  health_check {
    health_check_enabled         = true
    health_check_type            = "TCP"
    health_check_connect_port    = 0
    healthy_threshold            = 2
    unhealthy_threshold          = 2
    health_check_connect_timeout = 5
    health_check_interval        = 10
  }
  connection_drain         = true
  connection_drain_timeout = 60
  address_ip_version       = "Ipv4"
}


/* ingress controller的http服务所在的服务器组，默认是空的，需要在创建Ingress controller资源后手动填充 */
resource "alicloud_nlb_server_group" "web" {
  resource_group_id          = data.alicloud_resource_manager_resource_groups.librg.ids[0]
  server_group_name          = "web"
  server_group_type          = "Instance"
  vpc_id                     = alicloud_vpc.default.id
  scheduler                  = "Wrr"
  protocol                   = "TCP"
  preserve_client_ip_enabled = true
  health_check {
    health_check_enabled         = true
    health_check_type            = "TCP"
    health_check_connect_port    = 0
    healthy_threshold            = 2
    unhealthy_threshold          = 2
    health_check_connect_timeout = 5
    health_check_interval        = 10
  }
  connection_drain         = true
  connection_drain_timeout = 60
  address_ip_version       = "Ipv4"
}

/* 接受https流量，转发到集群里的ingress controller暴露的NodePort上 */
resource "alicloud_nlb_listener" "websecure" {
  listener_description = "websecure"
  listener_protocol    = "TCP"
  listener_port        = "443"
  load_balancer_id     = alicloud_nlb_load_balancer.apiserver.id
  server_group_id      = alicloud_nlb_server_group.websecure.id
  idle_timeout         = "900"
  cps                  = "1000"
  mss                  = "0"
}
/* 接受http流量，转发到集群里的ingress controller暴露的NodePort上 */
resource "alicloud_nlb_listener" "web" {
  listener_description = "web"
  listener_protocol    = "TCP"
  listener_port        = "80"
  load_balancer_id     = alicloud_nlb_load_balancer.apiserver.id
  server_group_id      = alicloud_nlb_server_group.web.id
  idle_timeout         = "900"
  cps                  = "1000"
  mss                  = "0"
}
