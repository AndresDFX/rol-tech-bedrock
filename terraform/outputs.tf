# ═════════════════════════════════════════════════════════════
# PRESUPUESTO (opcional) Y SALIDAS
# ═════════════════════════════════════════════════════════════

# Un presupuesto mensual de USD 5 que avisa por correo.
# Solo se crea si pasas un correo: EMAIL=tu@correo.com ./deploy.sh
resource "aws_budgets_budget" "mensual" {
  count        = var.email_presupuesto == "" ? 0 : 1
  name         = "${var.nombre}-presupuesto"
  budget_type  = "COST"
  limit_amount = tostring(var.presupuesto_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.email_presupuesto]
  }
}

output "url_app" {
  description = "La app: el QR del tablero apunta aquí"
  value       = "https://${aws_cloudfront_distribution.web.domain_name}/"
}

output "url_tablero" {
  description = "El tablero del proyector (QR y barras en vivo)"
  value       = "https://${aws_cloudfront_distribution.web.domain_name}/tablero.html"
}

output "api_directa" {
  description = "La API sin CloudFront, para probar con curl si la distribución todavía se propaga"
  value       = aws_apigatewayv2_api.api.api_endpoint
}

output "consola_personaje" {
  description = "Momento 2 de la demo: la Lambda en la consola, en sus variables de entorno (PERSONAJE)"
  value       = "https://${var.region}.console.aws.amazon.com/lambda/home?region=${var.region}#/functions/${aws_lambda_function.api.function_name}?tab=configure&subtab=envVars"
}

output "consola_monitor" {
  description = "Momento 3 de la demo: métricas de la Lambda y el botón de Live Tail"
  value       = "https://${var.region}.console.aws.amazon.com/lambda/home?region=${var.region}#/functions/${aws_lambda_function.api.function_name}?tab=monitoring"
}

output "funcion" {
  value = aws_lambda_function.api.function_name
}

output "tabla" {
  value = aws_dynamodb_table.stats.name
}

output "log_group" {
  value = aws_cloudwatch_log_group.api.name
}

output "region" {
  value = var.region
}

output "modelo" {
  value = var.model_id_respaldo == "" ? var.model_id : "${var.model_id} (y si frena por cuota, ${var.model_id_respaldo})"
}
