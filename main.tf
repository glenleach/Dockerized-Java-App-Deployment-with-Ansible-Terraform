provider "aws" {
  region = "eu-west-2"
}

variable "vpc_cidr_block" {}
variable "subnet_cidr_block" {}
variable "avail_zone" {}
variable "env_prefix" {}
variable "my_ip" {}
variable "instance_type" {}

resource "tls_private_key" "generated" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

variable "image_name" {
  description = "The name pattern for the AMI to use"
  type        = string
}

resource "aws_vpc" "myapp-vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_hostnames = true
  tags = {
    Name: "${var.env_prefix}-vpc"
  }
}

resource "aws_subnet" "myapp-subnet-1" {
  vpc_id = aws_vpc.myapp-vpc.id
  cidr_block = var.subnet_cidr_block
  availability_zone = var.avail_zone
    tags = {
    Name: "${var.env_prefix}-subnet-1"
  }
}

resource "aws_internet_gateway" "myapp-igw" {
  vpc_id = aws_vpc.myapp-vpc.id
  tags = {
    Name: "${var.env_prefix}-igw"
  }
}

resource "aws_default_route_table" "main-rtb" {
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myapp-igw.id
  }
  tags = {
    Name: "${var.env_prefix}-main-rtb"
  }
}

resource "aws_default_security_group" "default-sg" {
  vpc_id = aws_vpc.myapp-vpc.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "TCP"
    cidr_blocks = [var.my_ip]
  }

  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name: "${var.env_prefix}-default-sg"
  }
}

data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners = ["amazon"]
  filter {
    name = "name" 
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
}

output "aws-ami_id" {
  value = data.aws_ami.latest-amazon-linux-image.id
}

output "ec2-public_ip_1" {
  value = aws_instance.myapp-server-one.public_ip
}

output "ec2-public_ip_2" {
  value = aws_instance.myapp-server-two.public_ip
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "server-key"
  public_key = tls_private_key.generated.public_key_openssh
}

output "private_key_pem" {
  value     = tls_private_key.generated.private_key_pem
  sensitive = true
}

resource "local_file" "private_key_pem" {
  content         = tls_private_key.generated.private_key_pem
  filename        = "${path.module}/server-key.pem"
  file_permission = "0600"
}

resource "aws_instance" "myapp-server-one" {
  ami = data.aws_ami.latest-amazon-linux-image.id
  instance_type = var.instance_type

  subnet_id = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids = [aws_default_security_group.default-sg.id]
  availability_zone = var.avail_zone

  associate_public_ip_address = true
  key_name = aws_key_pair.ssh-key.key_name

  tags = {
    Name: "${var.env_prefix}-server-1"
  }
}

resource "aws_instance" "myapp-server-two" {
  ami = data.aws_ami.latest-amazon-linux-image.id
  instance_type = var.instance_type

  subnet_id = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids = [aws_default_security_group.default-sg.id]
  availability_zone = var.avail_zone

  associate_public_ip_address = true
  key_name = aws_key_pair.ssh-key.key_name

  tags = {
    Name: "${var.env_prefix}-server-2"
  }
}

data "template_file" "ansible_hosts" {
  template = <<EOF
# BEGIN ANSIBLE MANAGED BLOCK
[docker_server]
${aws_instance.myapp-server-one.public_ip} ansible_python_interpreter=/usr/bin/python3.9
${aws_instance.myapp-server-two.public_ip} ansible_python_interpreter=/usr/bin/python3.9

[docker_server:vars]
ansible_ssh_private_key_file=server-key.pem
ansible_user=ec2-user
# END ANSIBLE MANAGED BLOCK
EOF
}

resource "local_file" "ansible_hosts" {
  content  = data.template_file.ansible_hosts.rendered
  filename = "${path.module}/hosts"
}
