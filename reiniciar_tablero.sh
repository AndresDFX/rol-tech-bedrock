#!/usr/bin/env bash
# Deja el tablero en cero: borra las filas del contador. Las pruebas y el ensayo suman, así que se corre
# el día de la charla, antes de empezar.
# Uso:  ./reiniciar_tablero.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./_comun.sh

TABLA=$(salida tabla)
[ -n "$TABLA" ] || { echo "ERROR: no hay nada desplegado (corre ./deploy.sh)." >&2; exit 1; }
borradas=0
for rol in $(aws dynamodb scan --table-name "$TABLA" --query "Items[].rol.S" --output text); do
  [ "$rol" = "None" ] && continue
  aws dynamodb delete-item --table-name "$TABLA" --key "{\"rol\": {\"S\": \"$rol\"}}"
  borradas=$((borradas + 1))
done
echo "Tablero en cero ($borradas rol(es) borrados)."
echo "QUÉ MIRAR AHORA: el tablero del proyector marca 0 en unos 4 s. Haz tú el primer test para despertar la Lambda."
