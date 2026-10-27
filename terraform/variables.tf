# ═════════════════════════════════════════════════════════════
# VARIABLES
#   Los valores por defecto son los verificados en AWS el 26-oct-2026. Se cambian con -var o con un
#   archivo terraform.tfvars (deploy.sh escribe deploy.auto.tfvars con lo que le pases).
# ═════════════════════════════════════════════════════════════

variable "region" {
  description = "Región de todo el despliegue. El perfil us. de Nova Lite sale de aquí hacia us-east-1, us-east-2 y us-west-2"
  type        = string
  default     = "us-east-1"
}

variable "nombre" {
  description = "Prefijo de los recursos (tabla, Lambda, API, bucket y distribución)"
  type        = string
  default     = "rol-tech"
}

# Dos modelos, por la cuota. En la cuenta de laboratorio, el 26-oct-2026: Claude Haiku 4.5 aceptaba 10
# peticiones por minuto (igual que Sonnet 4.6), Nova 2 Lite 20 y Nova Lite 200. Un auditorio de 200 personas
# que termina el test en tres o cuatro minutos pide unas 50 por minuto. Haiku es el que mejor actúa el
# PERSONAJE (con el narrador de fútbol grita "¡GOOOL!"; Nova Lite apenas lo nota), así que escribe primero, y
# cuando frena por cuota responde Nova Lite. verificar_modelo.sh revisa los dos en tu cuenta.
variable "model_id" {
  description = "Perfil de inferencia del modelo que escribe primero"
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "foundation_model_id" {
  description = "Modelo base de ese perfil: IAM autoriza el perfil Y el modelo base en cada región de destino"
  type        = string
  default     = "anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "model_id_respaldo" {
  description = "Perfil del modelo que responde si el primero frena por cuota o falla (vacío: sin respaldo)"
  type        = string
  default     = "us.amazon.nova-lite-v1:0"
}

variable "foundation_model_id_respaldo" {
  description = "Modelo base del perfil de respaldo"
  type        = string
  default     = "amazon.nova-lite-v1:0"
}

variable "personaje" {
  description = "Cómo habla la IA. Cambiarlo en la consola de Lambda es la demo en vivo"
  type        = string
  default     = "un mentor tech divertido"
}

variable "limite_por_segundo" {
  description = "Freno del HTTP API: peticiones por segundo sostenidas (la URL se proyecta en una sala)"
  type        = number
  default     = 20
}

variable "rafaga" {
  description = "Freno del HTTP API: ráfaga máxima"
  type        = number
  default     = 40
}

variable "email_presupuesto" {
  description = "Si lo pones, se crea un presupuesto mensual en AWS Budgets que te avisa por correo (vacío: no se crea)"
  type        = string
  default     = ""
}

variable "presupuesto_usd" {
  description = "Monto del presupuesto mensual, en dólares"
  type        = number
  default     = 5
}
