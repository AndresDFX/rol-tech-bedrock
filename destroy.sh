#!/usr/bin/env bash
# Borra todo lo que creó deploy.sh y comprueba en AWS que no quede nada (consulta los recursos, no el
# estado de Terraform). Tarda unos 3 min: CloudFront deshabilita la distribución antes de borrarla.
# Uso:  ./destroy.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./_comun.sh
SECONDS=0

comprobar_identidad
terraform_disponible
terraform -chdir="$TF_DIR" init -input=false >/dev/null

# Los nombres antes de borrar: después el estado ya no los tiene.
NOMBRE=$(sed -n '/^variable "nombre"/,/^}/s/^[[:space:]]*default[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "$TF_DIR/variables.tf")
FUNCION=$(salida funcion); FUNCION=${FUNCION:-$NOMBRE-api}
TABLA=$(salida tabla); TABLA=${TABLA:-$NOMBRE-stats}

terraform -chdir="$TF_DIR" destroy -input=false -auto-approve
rm -f "$TF_DIR/deploy.auto.tfvars"

echo
echo "Comprobando en AWS que no quede nada..."
quedan=0
queda() { echo "  QUEDA: $*"; quedan=$((quedan + 1)); }
aws lambda get-function --function-name "$FUNCION" >/dev/null 2>&1 && queda "la Lambda $FUNCION"
estado_tabla=$(aws dynamodb describe-table --table-name "$TABLA" --query Table.TableStatus --output text 2>/dev/null || true)
[ -n "$estado_tabla" ] && [ "$estado_tabla" != "DELETING" ] && queda "la tabla $TABLA ($estado_tabla)"
# Los listados paginados imprimen "None" por cada página sin coincidencias: se descartan.
hay() { tr '\t' '\n' | grep -v -x -E 'None|' | head -1; }
[ -n "$(aws apigatewayv2 get-apis --query "Items[?Name=='$FUNCION'].ApiId" --output text | hay)" ] && queda "el HTTP API $FUNCION"
[ -n "$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '$NOMBRE-web-')].Name" --output text | hay)" ] && queda "el bucket $NOMBRE-web-*"
[ -n "$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Comment, '$NOMBRE - ')].Id" --output text 2>/dev/null | hay)" ] && queda "la distribución de CloudFront"
aws iam get-role --role-name "$FUNCION-role" >/dev/null 2>&1 && queda "el rol $FUNCION-role"

echo
if [ "$quedan" -eq 0 ]; then
  echo "QUÉ MIRAR AHORA: no queda nada en ${SECONDS} s. La cuenta no sigue cobrando por esta app."
else
  echo "QUÉ MIRAR AHORA: quedaron $quedan recurso(s). Repite ./destroy.sh; si siguen, bórralos en la consola."
  exit 1
fi
