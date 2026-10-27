# ═════════════════════════════════════════════════════════════
# "¿Qué rol tech eres?": toda la app en un solo apply.
#
#   celular -> CloudFront (https://xxxx.cloudfront.net)
#                /*      -> S3 privado: index.html, tablero.html y preguntas.json      (web.tf)
#                /api/*  -> HTTP API -> Lambda -> Bedrock (el perfil) + DynamoDB (el conteo)
#                                                                         (api.tf y este archivo)
# ═════════════════════════════════════════════════════════════

data "aws_caller_identity" "actual" {}

locals {
  cuenta = data.aws_caller_identity.actual.account_id

  # Los dos modelos de la cadena: el perfil de inferencia y su modelo base.
  modelos = { for m in [
    { perfil = var.model_id, base = var.foundation_model_id },
    { perfil = var.model_id_respaldo, base = var.foundation_model_id_respaldo },
  ] : m.perfil => m.base if m.perfil != "" }

  # Regiones a las que enrutan los perfiles us. de Haiku 4.5 y de Nova Lite desde us-east-1 (las mismas
  # tres para los dos). Comprobado el 26-oct-2026 con:
  #   aws bedrock get-inference-profile --inference-profile-identifier <perfil>
  regiones_del_perfil = ["us-east-1", "us-east-2", "us-west-2"]

  funcion = "${var.nombre}-api"
}

# ─────────────────────────────────────────────────────────────
# 1. El contador del tablero: una fila por rol, on-demand (se paga por petición)
# ─────────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "stats" {
  name         = "${var.nombre}-stats"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "rol"

  attribute {
    name = "rol"
    type = "S"
  }
}

# ─────────────────────────────────────────────────────────────
# 2. Los logs de la Lambda: el grupo lo crea Terraform, con retención, para que el destroy lo borre
# ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/${local.funcion}"
  retention_in_days = 7
}

# ─────────────────────────────────────────────────────────────
# 3. Permisos mínimos: sus logs, su tabla y los dos modelos de la cadena (nunca "Resource": "*")
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "api" {
  name = "${local.funcion}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "api" {
  name = "MinimoPrivilegio"
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SusLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.api.arn}:*"
      },
      {
        Sid      = "ElContador"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem", "dynamodb:Scan"]
        Resource = aws_dynamodb_table.stats.arn
      },
      # Con un perfil de inferencia se autorizan DOS cosas: el perfil y el modelo base en cada región
      # a la que el perfil puede enrutar (y el modelo base, solo cuando la llamada entra por un perfil).
      {
        Sid      = "InvocarPerfiles"
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = [for p in keys(local.modelos) : "arn:aws:bedrock:${var.region}:${local.cuenta}:inference-profile/${p}"]
      },
      {
        Sid    = "InvocarModelosBaseViaPerfil"
        Effect = "Allow"
        Action = "bedrock:InvokeModel"
        Resource = flatten([for base in values(local.modelos) :
        [for r in local.regiones_del_perfil : "arn:aws:bedrock:${r}::foundation-model/${base}"]])
        Condition = {
          StringLike = { "bedrock:InferenceProfileArn" = "arn:aws:bedrock:${var.region}:${local.cuenta}:inference-profile/*" }
        }
      },
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# 4. La Lambda: el código y preguntas.json (el mismo archivo que lee la página)
# ─────────────────────────────────────────────────────────────
data "archive_file" "api" {
  type        = "zip"
  output_path = "${path.module}/.build/api.zip"

  source {
    content  = file("${path.module}/../backend/lambda_function.py")
    filename = "lambda_function.py"
  }
  source {
    content  = file("${path.module}/../frontend/preguntas.json")
    filename = "preguntas.json"
  }
}

resource "aws_lambda_function" "api" {
  function_name    = local.funcion
  role             = aws_iam_role.api.arn
  runtime          = "python3.13"
  architectures    = ["arm64"] # Graviton: más barata por milisegundo
  handler          = "lambda_function.lambda_handler"
  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256
  memory_size      = 256
  timeout          = 30 # la IA puede tardar unos segundos; API Gateway corta a los 30

  environment {
    variables = {
      MODEL_ID          = var.model_id
      MODEL_ID_RESPALDO = var.model_id_respaldo
      TABLE_NAME        = aws_dynamodb_table.stats.name
      PERSONAJE         = var.personaje
    }
  }

  depends_on = [aws_cloudwatch_log_group.api, aws_iam_role_policy.api]
}
