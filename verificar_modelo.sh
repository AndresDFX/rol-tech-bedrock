#!/usr/bin/env bash
# Antes de cada evento: ¿los dos modelos siguen activos, la cuenta puede usarlos y las cuotas dan para un
# auditorio? Revisa lo que ya rompió demos en otras charlas: un modelo que pasa a LEGACY, el acuerdo de la
# cuenta, una cuota de peticiones por minuto muy baja (o en 0) y el tope de ejecuciones simultáneas de Lambda.
# No llama a los modelos: no cuesta nada.
# Uso:  ./verificar_modelo.sh
set -uo pipefail
cd "$(dirname "$0")"
source ./_comun.sh

NECESITA_RPM=60   # unas 200 personas que terminan el test en 3 o 4 minutos, con margen
avisos=0
aviso() { echo "AVISO  $*"; avisos=$((avisos + 1)); }

# revisar PERFIL BASE "NOMBRE DE LA CUOTA" papel   (papel: primero | respaldo)
revisar() {
  local perfil=$1 base=$2 cuota=$3 papel=$4 estado acuerdo rpm
  echo "── $base ($papel)"
  estado=$(aws bedrock get-foundation-model --model-identifier "$base" --query modelDetails.modelLifecycle.status --output text 2>&1)
  if [ "$estado" = "ACTIVE" ]; then echo "OK     está ACTIVE"
  else aviso "está en '$estado': un modelo LEGACY deja de servir en cuentas que no lo usaban"; fi

  [ "$(aws bedrock get-inference-profile --inference-profile-identifier "$perfil" --query status --output text 2>&1)" = "ACTIVE" ] \
    && echo "OK     el perfil $perfil existe en $AWS_REGION" || aviso "el perfil $perfil no está en $AWS_REGION"

  acuerdo=$(aws bedrock get-foundation-model-availability --model-id "$base" --query agreementAvailability.status --output text 2>&1)
  if [ "$acuerdo" = "AVAILABLE" ]; then echo "OK     la cuenta tiene acceso (acuerdo AVAILABLE)"
  else aviso "acuerdo de la cuenta: '$acuerdo'. Haz una primera llamada con TU usuario en el playground de Bedrock antes de desplegar"; fi

  # La CLI aplica --query página por página: se toma el primer valor numérico de todas las páginas.
  rpm=$(aws service-quotas list-service-quotas --service-code bedrock \
    --query "Quotas[?QuotaName=='Cross-region model inference requests per minute for $cuota'].Value" --output text 2>/dev/null |
    tr '\t' '\n' | grep -E '^[0-9]' | head -1)
  rpm=${rpm%.*}
  if [ -z "$rpm" ]; then aviso "no encontré la cuota de peticiones por minuto de '$cuota'"
  elif [ "$rpm" -eq 0 ]; then aviso "cuota en 0: cada llamada da 'is not available for this account'"
  elif [ "$papel" = "primero" ]; then
    echo "OK     cuota: $rpm peticiones por minuto. Las que pasen de ahí las escribe el modelo de respaldo (así está diseñado)"
  elif [ "$rpm" -ge "$NECESITA_RPM" ]; then echo "OK     cuota: $rpm peticiones por minuto (un auditorio de 200 pide unas $NECESITA_RPM)"
  else aviso "cuota: $rpm peticiones por minuto. Con un auditorio, muchos verán el texto de respaldo; pide aumento en Service Quotas"; fi
}

revisar us.anthropic.claude-haiku-4-5-20251001-v1:0 anthropic.claude-haiku-4-5-20251001-v1:0 "Anthropic Claude Haiku 4.5" primero
revisar us.amazon.nova-lite-v1:0 amazon.nova-lite-v1:0 "Amazon Nova Lite" respaldo

echo "── Lambda"
conc=$(aws lambda get-account-settings --query AccountLimit.ConcurrentExecutions --output text 2>/dev/null)
if [ -n "$conc" ] && [ "$conc" -ge 50 ]; then echo "OK     $conc ejecuciones simultáneas en la cuenta"
else aviso "${conc:-?} ejecuciones simultáneas en la cuenta: la 11.ª petición a la vez recibe un 503 y la página reintenta (medido con 50 envíos en el mismo segundo: 42 de 50 con perfil). Pide 100 o más en Service Quotas (Lambda > Concurrent executions) una semana antes"; fi

echo
if [ "$avisos" -eq 0 ]; then echo "QUÉ MIRAR AHORA: todo en orden. Sigue con ./deploy.sh o ./probar.sh."
else echo "QUÉ MIRAR AHORA: $avisos aviso(s) arriba. Ninguno impide desplegar, pero cada uno es un riesgo el día de la charla."; fi
[ "$avisos" -eq 0 ]
