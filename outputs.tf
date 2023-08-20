output "first_server_ip" {
  value = alicloud_instance.public_instances[0].public_ip
}