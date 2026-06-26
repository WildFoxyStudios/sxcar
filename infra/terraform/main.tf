# AMI Ubuntu 24.04 LTS arm64 más reciente (parámetro público SSM de Canonical)
data "aws_ssm_parameter" "ubuntu_2404_arm64" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

# VPC + subred por defecto (lo más barato: sin NAT ni red gestionada extra)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.project}-admin"
  public_key = file(var.ssh_public_key_path)
  tags       = { Project = var.project }
}

resource "aws_security_group" "api" {
  name        = "${var.project}-api-sg"
  description = "proyecto-X API: SSH solo admin, HTTP/HTTPS publico"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (solo admin)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS (para cuando haya dominio)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Todo el trafico saliente"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = var.project }
}

resource "aws_instance" "api" {
  ami                         = data.aws_ssm_parameter.ubuntu_2404_arm64.value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.api.id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/user-data.sh")

  metadata_options {
    http_tokens   = "required" # IMDSv2 obligatorio (hardening)
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  tags = { Name = "${var.project}-api", Project = var.project }
}
