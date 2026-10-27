# ═════════════════════════════════════════════════════════════
# LA PÁGINA: bucket S3 PRIVADO servido por CloudFront (HTTPS), con la API en el mismo dominio.
#   La versión 1 usaba un bucket público con sitio web estático: solo HTTP (el celular avisa
#   "No seguro") y la API en otro dominio (CORS).
#     /*      -> S3 (Origin Access Control: solo esta distribución lee el bucket)
#     /api/*  -> HTTP API, sin caché
# ═════════════════════════════════════════════════════════════

locals {
  web_dir = "${path.module}/../frontend"
  # Tipo de cada archivo según su extensión: el navegador no interpreta un HTML que llega como binario.
  web_tipos = {
    html = "text/html; charset=utf-8"
    json = "application/json; charset=utf-8"
  }
  web_archivos = {
    for f in fileset(local.web_dir, "*.{html,json}") : f => local.web_tipos[reverse(split(".", f))[0]]
  }
}

resource "aws_s3_bucket" "web" {
  bucket_prefix = "${var.nombre}-web-" # nombre único en todo S3, sin el ID de la cuenta
  force_destroy = true                 # el destroy borra también los archivos
}

resource "aws_s3_bucket_ownership_controls" "web" {
  bucket = aws_s3_bucket.web.id
  rule {
    object_ownership = "BucketOwnerEnforced" # sin ACL: manda solo la política del bucket
  }
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# etag = filemd5: si cambias un archivo, Terraform lo vuelve a subir.
# no-cache: el navegador pregunta siempre si hay versión nueva (304 si no la hay).
resource "aws_s3_object" "web" {
  for_each      = local.web_archivos
  bucket        = aws_s3_bucket.web.id
  key           = each.key
  source        = "${local.web_dir}/${each.key}"
  etag          = filemd5("${local.web_dir}/${each.key}")
  content_type  = each.value
  cache_control = "no-cache"
}

# Solo ESTA distribución puede leer el bucket. No es una política pública: por eso convive con el
# bloqueo de acceso público.
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SoloEstaDistribucionLee"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.web.arn }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.web]
}

resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${var.nombre}-oac"
  description                       = "CloudFront firma con SigV4 las lecturas del bucket de la app"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Políticas administradas de AWS: no hace falta escribir las nuestras.
data "aws_cloudfront_cache_policy" "optimizada" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "sin_cache" {
  name = "Managed-CachingDisabled"
}

# Pasa al API todo lo del navegador MENOS el Host: API Gateway necesita ver su propio dominio.
data "aws_cloudfront_origin_request_policy" "todo_menos_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  comment             = "${var.nombre} - ¿Qué rol tech eres?"
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # bordes de América del Norte y Europa: lo más barato
  is_ipv6_enabled     = true

  # El apply no espera a que CloudFront se propague: la página responde 1 a 2,5 min después.
  # El destroy sí espera siempre (unos 3 min): CloudFront deshabilita la distribución antes de borrarla.
  wait_for_deployment = false

  origin {
    origin_id                = "pagina"
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  origin {
    origin_id   = "api"
    domain_name = replace(aws_apigatewayv2_api.api.api_endpoint, "https://", "")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "pagina"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.optimizada.id
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.sin_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.todo_menos_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
