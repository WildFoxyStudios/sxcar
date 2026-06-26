variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "Tipo de instancia EC2 (ARM/Graviton)"
  type        = string
  default     = "t4g.small"
}

variable "project" {
  description = "Prefijo de nombre para los recursos"
  type        = string
  default     = "proyectox"
}

variable "admin_cidr" {
  description = "CIDR autorizado a SSH (tu IP, p.ej. 1.2.3.4/32). Obtén tu IP con: curl ifconfig.me"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr))
    error_message = "admin_cidr debe ser un CIDR válido, p.ej. 1.2.3.4/32."
  }
}

variable "ssh_public_key_path" {
  description = "Ruta a tu clave pública SSH (p.ej. ~/.ssh/id_ed25519.pub)"
  type        = string
}

variable "root_volume_gb" {
  description = "Tamaño del volumen raíz EBS (GiB)"
  type        = number
  default     = 20
}
