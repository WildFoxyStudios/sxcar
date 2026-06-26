output "public_ip" {
  description = "IP pública de la instancia API"
  value       = aws_instance.api.public_ip
}

output "public_dns" {
  description = "DNS público de la instancia API"
  value       = aws_instance.api.public_dns
}

output "ssh_command" {
  description = "Comando SSH para administrar la instancia"
  value       = "ssh ubuntu@${aws_instance.api.public_dns}"
}

output "api_http_url" {
  description = "URL HTTP temporal del API (staging, sin TLS hasta tener dominio)"
  value       = "http://${aws_instance.api.public_dns}"
}
