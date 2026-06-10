terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── Key Pair ────────────────────────────────────────────────────────────────

resource "tls_private_key" "mc_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "mc_key" {
  key_name   = "MC-Key"
  public_key = tls_private_key.mc_key.public_key_openssh
}

resource "local_file" "mc_private_key" {
  content         = tls_private_key.mc_key.private_key_pem
  filename        = "${path.module}/../MC-Key.pem"
  file_permission = "0600"
}

# ─── Networking ───────────────────────────────────────────────────────────────

resource "aws_vpc" "mc_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "MC-VPC"
  }
}

resource "aws_internet_gateway" "mc_igw" {
  vpc_id = aws_vpc.mc_vpc.id

  tags = {
    Name = "MC-IGW"
  }
}

resource "aws_subnet" "mc_subnet" {
  vpc_id                  = aws_vpc.mc_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "MC-Subnet"
  }
}

resource "aws_route_table" "mc_rt" {
  vpc_id = aws_vpc.mc_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mc_igw.id
  }

  tags = {
    Name = "MC-RouteTable"
  }
}

resource "aws_route_table_association" "mc_rta" {
  subnet_id      = aws_subnet.mc_subnet.id
  route_table_id = aws_route_table.mc_rt.id
}

# ─── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "mc_sg" {
  name        = "MC-Security-Group"
  description = "Allow SSH and Minecraft traffic"
  vpc_id      = aws_vpc.mc_vpc.id

  # SSH — restricted to your IP
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # Minecraft — open to all players
  ingress {
    description = "Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic allowed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "MC-Security-Group"
  }
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "mc_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.mc_key.key_name
  subnet_id              = aws_subnet.mc_subnet.id
  vpc_security_group_ids = [aws_security_group.mc_sg.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "MC-Server"
  }
}
