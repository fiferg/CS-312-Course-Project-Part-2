variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation (e.g. 203.0.113.5/32) — used to restrict SSH access"
  type        = string
}
