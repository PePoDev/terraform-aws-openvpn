output "public_ip" {
  value = module.bastion_instance.public_ip
}

output "public_dns" {
  value = module.bastion_instance.public_dns
}
