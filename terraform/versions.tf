# ═════════════════════════════════════════════════════════════
# VERSIONES
#   hashicorp/aws en su mayor actual (6) y hashicorp/archive para empaquetar la Lambda sin bucket de
#   despliegue. El .terraform.lock.hcl fija la versión exacta de cada provider y sus checksums.
# ═════════════════════════════════════════════════════════════
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.region

  # Todo lo que crea Terraform lleva estas etiquetas: así se encuentra (y se borra) sin adivinar.
  default_tags {
    tags = {
      Proyecto      = var.nombre
      GestionadoPor = "terraform"
    }
  }
}
