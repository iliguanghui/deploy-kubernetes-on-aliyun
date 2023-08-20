/* find image id of latest centos image */
data "alicloud_images" "images_ds" {
  owners      = "system"
  name_regex  = "^centos_stream_9"
  most_recent = true
}

/* create a new security group */
resource "alicloud_security_group" "libvpc_opensg" {
  name        = var.ecs.security_group_name
  description = "open to the world"
  vpc_id      = alicloud_vpc.default.id
}

/* allow any inbound traffic */
resource "alicloud_security_group_rule" "ingress" {
  type              = "ingress"
  ip_protocol       = "tcp"
  policy            = "accept"
  port_range        = "1/65535"
  priority          = 1
  security_group_id = alicloud_security_group.libvpc_opensg.id
  cidr_ip           = "0.0.0.0/0"
}

resource "alicloud_ecs_key_pair" "lab_keypair" {
  key_pair_name = "lab_keypair"
  public_key    = file(var.ecs.pubkey_file)
}

resource "alicloud_instance" "public_instances" {
  count           = var.public_instance_count
  security_groups = [alicloud_security_group.libvpc_opensg.id]

  vswitch_id = alicloud_vswitch.public_subnets[keys(alicloud_vswitch.public_subnets)[count.index % length(alicloud_vswitch.public_subnets)]].id

  instance_charge_type       = "PostPaid"
  spot_strategy              = "SpotAsPriceGo"
  instance_type              = var.ecs.instance_type
  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = 5

  system_disk_category = var.ecs.system_disk_category
  system_disk_size     = max(20, data.alicloud_images.images_ds.images[0].size)
  image_id             = data.alicloud_images.images_ds.ids[0]
  instance_name        = "public_instance_${count.index}"
  key_name             = alicloud_ecs_key_pair.lab_keypair.id
  role_name            = var.ecs.role_name
  user_data            = <<EOF
#!/bin/bash
yum -y install wget
wget https://gitlab.com/liguanghui/deploy-kubernetes-on-aliyun-with-terraform/-/raw/main/prepare.sh
bash prepare.sh
EOF
}
