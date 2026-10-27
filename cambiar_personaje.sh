#!/usr/bin/env bash
# Plan B del momento 2 de la demo: cambia cómo habla la IA sin abrir la consola (la variable PERSONAJE
# de la Lambda). Sin argumento, vuelve al valor original.
# Uso:  ./cambiar_personaje.sh "un narrador de fútbol colombiano muy emocionado"
#       ./cambiar_personaje.sh                       (vuelve a "un mentor tech divertido")
set -euo pipefail
cd "$(dirname "$0")"
source ./_comun.sh

FUNCION=$(salida funcion)
[ -n "$FUNCION" ] || { echo "ERROR: no hay nada desplegado (corre ./deploy.sh)." >&2; exit 1; }
export NUEVO="${1:-un mentor tech divertido}"

# Se reemplaza solo PERSONAJE: update-function-configuration reescribe TODAS las variables.
nuevas=$(aws lambda get-function-configuration --function-name "$FUNCION" --query Environment.Variables --output json |
  "$PY" -c 'import json, os, sys; v = json.load(sys.stdin); v["PERSONAJE"] = os.environ["NUEVO"][:200]; print(json.dumps({"Variables": v}))')
aws lambda update-function-configuration --function-name "$FUNCION" --environment "$nuevas" >/dev/null
aws lambda wait function-updated --function-name "$FUNCION"
echo "PERSONAJE: $NUEVO"
echo "QUÉ MIRAR AHORA: el siguiente test ya habla así (pide a la sala «Hacer el test otra vez»)."
echo "  Al terminar la demo: ./cambiar_personaje.sh  (sin argumento, vuelve al original)."
