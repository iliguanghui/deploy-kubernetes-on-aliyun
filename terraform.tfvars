vpc = {
  name = "LabVPC"
  cidr = "192.168.0.0/16"
  /* few public subnets */
  public_subnet_cidr_blocks = [
    "192.168.10.0/24",
    "192.168.20.0/24",
    "192.168.30.0/24"
  ]
  /* many private subnets */
  private_subnet_cidr_blocks = [
    "192.168.110.0/24",
    "192.168.120.0/24",
    "192.168.130.0/24"
  ]
}
ecs = {
  security_group_name = "OpenSG"
  instance_type       = "ecs.u1-c1m2.large"
}

public_instance_count  = 1
private_instance_count = 0
