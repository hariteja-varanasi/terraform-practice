# ===================================================================
# EC2 + EBS + ALB + Target Group + Security Groups + Key Pair (us-east-1)
#
# This folder is a SEPARATE Terraform root from the network folder, so it
# cannot reference the VPC/subnet/route-table resources directly. Instead it
# looks up the already-applied network via data sources (tags / CIDR).
# Apply the network folder FIRST. Keep user_data.sh.tftpl in this folder.
# ===================================================================

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    tls = {
      source = "hashicorp/tls"
    }
    local = {
      source = "hashicorp/local"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "my_ip_cidr" {
  description = "Your public IPv4 in CIDR form, e.g. 203.0.113.25/32 (used for SSH on the public SG)"
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0))
    error_message = "Must be a valid CIDR block, e.g. 203.0.113.25/32."
  }
}

# -------------------------------------------------------------------
# Look up the existing network (created by the other folder)
# -------------------------------------------------------------------
data "aws_vpc" "main" {
  tags = {
    Name = "tf-vpc-example-zero"
  }
}

# subnet-0 (10.0.0.0/20, us-east-1a). Looked up by CIDR because both of the
# original subnets share the same Name tag.
data "aws_subnet" "subnet_0" {
  vpc_id     = data.aws_vpc.main.id
  cidr_block = "10.0.0.0/20"
}

data "aws_route_table" "public" {
  vpc_id = data.aws_vpc.main.id

  tags = {
    Name = "tf-rt-public-example-zero"
  }
}

locals {
  instance_count = 3
  instance_type  = "t3.medium" # 2 vCPU, 4 GiB RAM
  root_volume_gb = 8
  data_volume_gb = 20

  common_tags = {
    Environment = "dev"
    Project     = "terraform-practice"
  }

  # Which subnet each of the 3 instances lands in (spread across 2 AZs)
  web_subnet_ids = [
    data.aws_subnet.subnet_0.id,
    aws_subnet.subnet-public-b.id,
    data.aws_subnet.subnet_0.id,
  ]

  web_azs = [
    data.aws_subnet.subnet_0.availability_zone,
    aws_subnet.subnet-public-b.availability_zone,
    data.aws_subnet.subnet_0.availability_zone,
  ]
}

# -------------------------------------------------------------------
# Networking additions
# An ALB needs subnets in at least 2 AZs, and the instances need internet
# access to install nginx. subnet-1 is private (no IGW route, no NAT), so
# this adds a second PUBLIC subnet in us-east-1b.
# -------------------------------------------------------------------
resource "aws_subnet" "subnet-public-b" {
  vpc_id                  = data.aws_vpc.main.id
  cidr_block              = "10.0.32.0/20"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "tf-subnet-public-b-example-zero"
  })
}

resource "aws_route_table_association" "public-subnet-b" {
  subnet_id      = aws_subnet.subnet-public-b.id
  route_table_id = data.aws_route_table.public.id
}

# -------------------------------------------------------------------
# Security groups
#   public  -> attached to the ALB and the EC2 instances
#              SSH from your IP only, HTTP/HTTPS from anywhere (IPv4)
#   private -> created but not attached to anything yet
#              SSH/HTTP/HTTPS only from resources that carry the public SG
# -------------------------------------------------------------------
resource "aws_security_group" "public" {
  name        = "tf-sg-public-example-zero"
  description = "Public SG: SSH from my IP, HTTP/HTTPS from anywhere"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "HTTP from anywhere (IPv4)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere (IPv4)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "tf-sg-public-example-zero"
  })
}

resource "aws_security_group" "private" {
  name        = "tf-sg-private-example-zero"
  description = "Private SG: SSH/HTTP/HTTPS only from the public SG"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "SSH from public SG"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  ingress {
    description     = "HTTP from public SG"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  ingress {
    description     = "HTTPS from public SG"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.public.id]
  }

  # Outbound needed for apt / nginx install
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "tf-sg-private-example-zero"
  })
}

# -------------------------------------------------------------------
# Ubuntu 26.04 LTS AMI (resolved from Canonical's public SSM parameter)
# -------------------------------------------------------------------
data "aws_ssm_parameter" "ubuntu_2604" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# -------------------------------------------------------------------
# SSH key pair (RSA 4096). Terraform generates the key, registers the
# public half in AWS, and writes the private half as a .pem next to
# your .tf files on the machine where you run `terraform apply`.
# -------------------------------------------------------------------
resource "tls_private_key" "web" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "web" {
  key_name   = "tf-key-example-zero"
  public_key = tls_private_key.web.public_key_openssh

  tags = merge(local.common_tags, {
    Name = "tf-key-example-zero"
  })
}

resource "local_file" "web_pem" {
  content         = tls_private_key.web.private_key_pem
  filename        = "${path.module}/tf-key-example-zero.pem"
  file_permission = "0400"
}

# -------------------------------------------------------------------
# EBS data volumes (20 GB gp3, one per instance, same AZ as its instance)
# -------------------------------------------------------------------
resource "aws_ebs_volume" "data" {
  count = local.instance_count

  availability_zone = local.web_azs[count.index]
  size              = local.data_volume_gb
  type              = "gp3"

  tags = merge(local.common_tags, {
    Name = "tf-ebs-example-${count.index + 1}"
  })
}

# -------------------------------------------------------------------
# EC2 instances (public SG)
# -------------------------------------------------------------------
resource "aws_instance" "web" {
  count = local.instance_count

  ami                         = nonsensitive(data.aws_ssm_parameter.ubuntu_2604.value)
  instance_type               = local.instance_type
  subnet_id                   = local.web_subnet_ids[count.index]
  vpc_security_group_ids      = [aws_security_group.public.id]
  key_name                    = aws_key_pair.web.key_name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  root_block_device {
    volume_size           = local.root_volume_gb
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    instance_name    = "tf-ec2-example-${count.index + 1}"
    volume_id_nodash = replace(aws_ebs_volume.data[count.index].id, "-", "")
  })
  user_data_replace_on_change = true

  # subnet-0's internet route already exists (network folder); make sure the
  # new subnet has its route before first boot
  depends_on = [aws_route_table_association.public-subnet-b]

  lifecycle {
    # Canonical's "current" AMI moves over time; don't rebuild instances for that
    ignore_changes = [ami]
  }

  tags = merge(local.common_tags, {
    Name = "tf-ec2-example-${count.index + 1}"
  })
}

# Attach each EBS volume to its instance
resource "aws_volume_attachment" "data" {
  count = local.instance_count

  device_name = "/dev/sdf" # shows up as /dev/nvme1n1 on Nitro instances
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = aws_instance.web[count.index].id

  # Let instance termination handle the detach on destroy (avoids hangs
  # with a mounted filesystem)
  skip_destroy = true
}

# -------------------------------------------------------------------
# Application Load Balancer (public SG) + target group + listener
# -------------------------------------------------------------------
resource "aws_lb" "web" {
  name               = "tf-alb-example-zero"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.public.id]
  subnets            = [data.aws_subnet.subnet_0.id, aws_subnet.subnet-public-b.id]

  tags = merge(local.common_tags, {
    Name = "tf-alb-example-zero"
  })
}

resource "aws_lb_target_group" "web" {
  name        = "tf-tg-example-zero"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "tf-tg-example-zero"
  })
}

resource "aws_lb_target_group_attachment" "web" {
  count = local.instance_count

  target_group_arn = aws_lb_target_group.web.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# -------------------------------------------------------------------
# Outputs
# -------------------------------------------------------------------
output "alb_dns_name" {
  description = "Open this in a browser and refresh to see the instances rotate"
  value       = "http://${aws_lb.web.dns_name}"
}

output "instance_ids" {
  value = aws_instance.web[*].id
}

output "instance_public_ips" {
  value = aws_instance.web[*].public_ip
}

output "ssh_command_example" {
  description = "Replace <ip> with one of the instance public IPs"
  value       = "ssh -i ${local_file.web_pem.filename} ubuntu@<ip>"
}
