variable "namespace" {}
variable "aws_instance_ami" {}
variable "aws_instance_type" {}
variable "public_ip" {}
variable "ssh_key_name" {}
variable "owner" {}
variable "ttl" {}
variable "user_data" {}
variable "vpc_id" {}

variable "ptfe_subnet_ids" {
  type = "list"
}

variable "alb_subnet_ids" {
  type = "list"
}

variable "vpc_security_group_ids" {}
variable "zone_id" {}
variable "alb_internal" {}
variable "hostname" {}
variable "ssl_certificate_arn" {}
variable "ptfe_bucket_name" {}
variable "kms_key_id" {}
variable "source_bucket_id" {}
variable "create_second_instance" {}
