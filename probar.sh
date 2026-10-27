#!/usr/bin/env bash
# Prueba la app desde la terminal, sin celular: GET /api/stats y un POST /api/rol con las 8 respuestas.
# Va por CloudFront, como un celular; si la distribución todavía se propaga, usa la API directa.
# Cada ejecución es UNA llamada a Bedrock (con Nova Lite, una fracción de centavo).
# Uso:  ./probar.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./_comun.sh

APP=$(salida url_app)
[ -n "$APP" ] || { echo "ERROR: no hay nada desplegado (corre ./deploy.sh)." >&2; exit 1; }
BASE="${APP}api"
if [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/stats")" != "200" ]; then
  echo "CloudFront todavía no responde; pruebo la API directa."
  BASE="$(salida api_directa)/api"
fi

echo "GET  /api/stats  -> $(curl -s "$BASE/stats" | head -c 160)"
respuesta=$(curl -s -X POST "$BASE/rol" -H "Content-Type: application/json" \
  -d '{"nombre":"Prueba","respuestas":[0,1,2,3,0,1,2,3]}')
echo "$respuesta" | "$PY" -c '
import json, sys
d = json.load(sys.stdin)
print("POST /api/rol    -> rol:", d["rolNombre"], "| fuente:", d["fuente"], "| IA:", d["tiempos"]["ia_ms"], "ms")
print("                    apodo:", d["perfil"]["titulo"])
'
echo
echo "QUÉ MIRAR AHORA:"
echo "  - fuente: bedrock es lo esperado. Si dice respaldo, el error está en los logs:"
echo "      aws logs tail $(salida log_group) --since 10m"
echo "  - La prueba sumó 1 al tablero. Antes de la charla: ./reiniciar_tablero.sh"
