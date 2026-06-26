terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# Credenciales AWS: NO van aquí. Se toman de la cadena estándar del provider
# (variables de entorno AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY o `aws configure`).
provider "aws" {
  region = var.aws_region
}
