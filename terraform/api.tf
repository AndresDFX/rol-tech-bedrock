# ═════════════════════════════════════════════════════════════
# LA API: HTTP API -> Lambda. CloudFront la llama en /api/* desde el mismo dominio de la página,
# así que no hace falta CORS (la versión 1 lo necesitaba y fallaba con el tablero abierto con doble clic).
# ═════════════════════════════════════════════════════════════

resource "aws_apigatewayv2_api" "api" {
  name          = local.funcion
  protocol_type = "HTTP"
  description   = "API de ¿Qué rol tech eres? (la llama CloudFront en /api/*)"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

# Las rutas llevan /api delante porque CloudFront pasa la ruta completa.
resource "aws_apigatewayv2_route" "rol" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /api/rol"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "stats" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /api/stats"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  # El freno de una URL que se proyecta en una sala: lo que pase de aquí recibe un 429 y la página
  # reintenta. El límite real suele ser otro: la concurrencia de Lambda de la cuenta (10 en una cuenta
  # nueva; ver verificar_modelo.sh).
  default_route_settings {
    throttling_rate_limit  = var.limite_por_segundo
    throttling_burst_limit = var.rafaga
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "PermitirHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/api/*"
}
