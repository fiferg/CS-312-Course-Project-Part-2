output "instance_public_ip" {
  description = "Public IP address of the Minecraft EC2 instance"
  value       = aws_instance.mc_server.public_ip
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.mc_server.id
}

output "ssh_command" {
  description = "SSH command to connect to the instance (for debugging only)"
  value       = "ssh -i ../MC-Key.pem ubuntu@${aws_instance.mc_server.public_ip}"
}

output "nmap_command" {
  description = "nmap command to verify the Minecraft server is running"
  value       = "nmap -sV -Pn -p T:25565 ${aws_instance.mc_server.public_ip}"
}
