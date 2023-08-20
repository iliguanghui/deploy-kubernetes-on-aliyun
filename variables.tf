variable "region" {
  type        = string
  description = "aliyun region for all resources"
}

variable "vpc" {
  type = object({
    name                       = string
    cidr                       = string
    public_subnet_cidr_blocks  = list(string)
    private_subnet_cidr_blocks = list(string)
  })
}

variable "ecs" {
  type = object({
    security_group_name  = string
    instance_type        = string
    role_name            = string
    pubkey_file          = string
    system_disk_category = string
  })
}

variable "public_instance_count" {
  type        = number
  description = "number of instances within public subnets"
}

variable "private_instance_count" {
  type        = number
  description = "number of instances within private subnets"
}

variable "dns" {
  type = object({
    domain_name = string
    record_name = string
  })
}