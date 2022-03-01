resource "tls_private_key" "private_key" {
  algorithm   = "RSA"
  ecdsa_curve = "4096"
}

resource "local_file" "private_key" {
  file_permission   = "0400"
  sensitive_content = tls_private_key.private_key.private_key_pem
  filename          = "${path.module}/ovpn-files/private_key"
}

resource "aws_key_pair" "bastion_private_key" {
  key_name   = "${var.name}-key"
  public_key = tls_private_key.private_key.public_key_openssh
}

data "aws_ami" "ubuntu_ami" {
  most_recent = true
  name_regex  = "ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
  owners      = ["099720109477"]
}

module "bastion_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.3.0"

  name                        = var.name
  ami                         = data.aws_ami.ubuntu_ami.image_id
  instance_type               = var.instance_size
  key_name                    = aws_key_pair.bastion_private_key.key_name
  associate_public_ip_address = true
  monitoring                  = false
  vpc_security_group_ids      = [module.bastion_sg.security_group_id]
  subnet_id                   = var.subnet_id
  tags                        = var.tags
}

module "bastion_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.7.0"

  name   = "${var.name}-sg"
  vpc_id = var.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["all-all"]
  egress_rules        = ["all-all"]
}

resource "null_resource" "openvpn_bootstrap" {
  connection {
    host        = module.bastion_instance.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 1m",
      "curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh",
      "chmod +x openvpn-install.sh",
      <<-EOT
      sudo AUTO_INSTALL=y \
      APPROVE_IP=${module.bastion_instance.public_ip} \
      ENDPOINT=${module.bastion_instance.public_dns} \
      ./openvpn-install.sh
    EOT
      ,
    ]
  }
}

resource "null_resource" "openvpn_update_users_script" {
  depends_on = [null_resource.openvpn_bootstrap]
  triggers = {
    users = join(" ", var.openvpn_users)
  }

  connection {
    host        = module.bastion_instance.public_ip
    user        = "ubuntu"
    private_key = tls_private_key.private_key.private_key_pem
  }

  provisioner "file" {
    source      = "${path.module}/update_users.sh"
    destination = "/home/ubuntu/update_users.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ~ubuntu/update_users.sh",
      "sudo ~ubuntu/update_users.sh ${join(" ", var.openvpn_users)}",
    ]
  }
}

resource "null_resource" "openvpn_download_configurations" {
  depends_on = [null_resource.openvpn_update_users_script]
  triggers = {
    users = join(" ", var.openvpn_users)
  }

  provisioner "local-exec" {
    command = <<-EOF
      mkdir -p ovpn-files
      rm ovpn-files/*.ovpn
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${local_file.private_key.filename} ubuntu@${module.bastion_instance.public_ip}:/home/ubuntu/*.ovpn ${path.module}/ovpn-files
      # ${join("\n", [for s in var.openvpn_users : "echo cat ${path.module}/ovpn-files/${s}.ovpn && cat ${path.module}/ovpn-files/${s}.ovpn"])}
    EOF
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm ${path.module}/ovpn-files/*.ovpn\ntrue"
  }
}
