# main.tf
provider "aws" {
  region = "us-east-1"
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "allow_http_https_ssh" {
  name        = "allow_http_https_ssh"
  description = "Allow HTTP, HTTPS, and SSH traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Additional ports for Jenkins
  ingress {
    description = "Allow Jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Additional ports for Kubernetes
  ingress {
    description = "Allow K3s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow-http-https-ssh"
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Role Policy for ECR access
resource "aws_iam_role_policy" "ecr_policy" {
  name = "ecr_policy"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"
  role = aws_iam_role.ec2_role.name
}

# ECR Repository
resource "aws_ecr_repository" "main" {
  name                 = "main-repository"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Kubernetes Instance
resource "aws_instance" "kubernetes_instance" {
  ami                    = "ami-005fc0f236362e99f"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.allow_http_https_ssh.id]
  subnet_id              = aws_subnet.public.id
  key_name               = "key-pair"
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update -y
              sudo apt-get install -y curl
              curl -sfL https://get.k3s.io | sh -
              EOF

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }

  tags = {
    Name = "kubernetes-instance"
  }
}

# Jenkins Instance
resource "aws_instance" "jenkins_instance" {
  ami                    = "ami-005fc0f236362e99f"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.allow_http_https_ssh.id]
  subnet_id              = aws_subnet.public.id
  key_name               = "key-pair"
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name


  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }

  tags = {
    Name = "jenkins-instance"
  }
}

# Output values
output "kubernetes_instance_public_ip" {
  value = aws_instance.kubernetes_instance.public_ip
}

output "jenkins_instance_public_ip" {
  value = aws_instance.jenkins_instance.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.main.repository_url
}
