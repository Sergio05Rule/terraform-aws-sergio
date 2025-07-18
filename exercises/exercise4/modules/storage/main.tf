terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

data "aws_ami" "ubuntu_focal" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

#tfsec:ignore:aws-ec2-enforce-http-token-imds
resource "aws_instance" "mongo" {
  ami                    = data.aws_ami.ubuntu_focal.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.sg_id]
  root_block_device {
    volume_size = 10
    encrypted   = true
  }

  /*
  user_data = << EOF
  #! /bin/bash
  sudo apt-get update
  sudo apt-get install -y nginx
  sudo systemctl start nginx
  sudo systemctl enable nginx
  echo "<h1>CloudAcademy 2021</h1>" | sudo tee /var/www/html/index.html
	EOF
  */

  user_data = filebase64("${path.module}/install.sh")

  tags = {
    Name  = "Mongo"
    Owner = "CloudAcademy"
  }
}
