variable "name" {
  type        = string
  description = "OPEN VPN Name prefix to create resources on AWS"
}

variable "region" {
  type        = string
  description = "AWS Region"
  default     = "ap-southeast-1"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to create security group for bastion"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID to create OpenVPN server (Must be public subnet)"
}

variable "instance_size" {
  type        = string
  description = "Instance size for OpenVPN server"
  default     = "t2.micro"
}

variable "tags" {
  type        = map(string)
  description = "Tags to assign to resource create by Terraform"
  default     = {}
}

variable "openvpn_users" {
  type        = list(string)
  description = "List of OpenVPN users to generate"
  default     = ["client"]
}
