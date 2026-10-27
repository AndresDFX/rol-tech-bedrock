# ¿Qué rol tech eres? · el código

La app de la charla, para la Universidad de San Buenaventura (Cali, 2026): el público hace un test de 8 preguntas
en el celular, una IA en Amazon Bedrock le escribe un perfil y un tablero en el proyector muestra en vivo qué rol
gana. Todo se crea con `./deploy.sh` y se borra con `./destroy.sh`.

```
celular ─► CloudFront (https://xxxx.cloudfront.net)
             /*      ─► S3 privado: index.html, tablero.html y preguntas.json
             /api/*  ─► API Gateway (HTTP API, freno 20/40) ─► Lambda (Python 3.13, arm64)
                                                                  ├─► Bedrock: Claude Haiku 4.5
                                                                  │     └─ si frena por cuota: Amazon Nova Lite
                                                                  └─► DynamoDB: +1 al rol (el tablero)
```

Verificado en AWS el 26-oct-2026: despliegue, test desde el celular, tablero, ráfagas de 50 envíos y borrado.

## Antes de desplegar (una vez por cuenta)

1. **La primera llamada a Claude la hace una persona, no la Lambda.** En la consola de Bedrock, abre Claude
   Haiku 4.5 en el playground y escribe "hola": activa la suscripción de Marketplace (y, la primera vez, el
   formulario de caso de uso de Anthropic). Si la Lambda va primero, la suscripción falla.
2. `./verificar_modelo.sh` (no cuesta nada): los dos modelos `ACTIVE`, el acceso de la cuenta, las cuotas y la
   concurrencia de Lambda.
3. **Pide concurrencia de Lambda** si la cuenta tiene 10 (cuentas nuevas): Service Quotas → AWS Lambda →
   *Concurrent executions* → 100 o más. Una semana antes: no siempre es inmediato.

## Desplegar

Lo más simple es **AWS CloudShell** (trae la CLI y las credenciales; Terraform lo instala el script):

```bash
git clone https://github.com/AndresDFX/rol-tech-bedrock.git && cd rol-tech-bedrock
./deploy.sh        # EMAIL=tu@correo.com ./deploy.sh: además, un presupuesto de USD 5
```

Desde tu computador: Terraform ≥ 1.5 y la AWS CLI con credenciales, en Git Bash, Linux o macOS. **No lo
corras desde una carpeta de Google Drive**: el provider de AWS pesa unos 800 MB y el estado de Terraform no debe
sincronizarse.

`deploy.sh` imprime la URL de la app y la del tablero. La primera vez, CloudFront tarda de 1 a 2,5 min en
responder: si no carga, espera y recarga. En la verificación, el despliegue completo tardó 113 s (con la
descarga del provider).

## Probar y operar la demo

| Para qué | Cómo |
|---|---|
| Probar sin celular (1 llamada a Bedrock) | `./probar.sh` |
| El tablero del proyector | La `url_tablero` que imprime `deploy.sh` (nunca con doble clic) |
| Dejar el tablero en cero antes de empezar | `./reiniciar_tablero.sh` |
| Momento 2 de la demo: cambiar cómo habla la IA | Consola de Lambda → `rol-tech-api` → Configuration → Environment variables → `PERSONAJE`. Plan B: `./cambiar_personaje.sh "un narrador de fútbol colombiano muy emocionado"`, y sin argumento vuelve a «un mentor tech divertido» |
| Momento 3: logs en vivo | Lambda → Monitor → *Open CloudWatch Live Tail*; en la terminal (CLI v2), `aws logs tail /aws/lambda/rol-tech-api --follow` |
| Ver qué modelo respondió | Cada línea de log trae `"modelo"`; el celular lo dice en "Así viajó tu respuesta" |

Si alguien cambia `PERSONAJE` en la consola, el siguiente `terraform apply` lo devuelve al valor de
`variables.tf`.

## Borrar

```bash
./destroy.sh
```

Unos 4 minutos (236 s en la verificación): CloudFront deshabilita la distribución antes de borrarla. Al final
consulta en AWS que no quede la Lambda, la tabla, el API, el bucket, la distribución ni el rol.

## Costos (medidos el 26-oct-2026)

| Qué | Costo |
|---|---|
| Un perfil con Claude Haiku 4.5 (~314 tokens de entrada y ~266 de salida, USD 1,10 y 5,50 por millón) | USD 0,0018 |
| Un perfil con Amazon Nova Lite (~269 y ~132 tokens, USD 0,06 y 0,24 por millón) | USD 0,00005 |
| Una charla de 200 personas con dos rondas del test (400 perfiles), aunque todos los escribiera Haiku | menos de USD 0,75 |
| La app desplegada sin uso | prácticamente USD 0 (todo es por petición; S3 guarda tres archivos pequeños) |

Lambda, CloudFront y DynamoDB on-demand caen en sus capas gratuitas con este uso; API Gateway y S3 cobran
centavos. Bedrock no tiene capa gratuita.

## Archivos

| Archivo | Qué es |
|---|---|
| `backend/lambda_function.py` | La API: valida, calcula el rol, la cadena Haiku → Nova Lite → texto de respaldo y el contador |
| `frontend/index.html` | La app del celular: el test, el perfil y «Así viajó tu respuesta», con la API en el mismo dominio y reintentos |
| `frontend/tablero.html` | El tablero del proyector: QR y barras cada 4 s, solo con la pestaña visible |
| `frontend/preguntas.json` | Las 8 preguntas y los 6 roles: lo leen la página y la Lambda |
| `terraform/` | `main.tf` (tabla, logs, IAM, Lambda), `api.tf`, `web.tf` (S3 y CloudFront), `outputs.tf` (presupuesto y salidas), `variables.tf`, `versions.tf` |
| `deploy.sh` · `destroy.sh` | Crear y borrar todo; cada script dice al final qué mirar |
| `verificar_modelo.sh` · `probar.sh` · `reiniciar_tablero.sh` · `cambiar_personaje.sh` | Las comprobaciones y los controles de la demo |
