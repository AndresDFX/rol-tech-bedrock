#!/usr/bin/env bash
# Crea toda la app en un solo paso, con Terraform. Se puede repetir: si ya está desplegada no cambia nada y
# vuelve a imprimir las URL.
#   1. Comprueba la cuenta, el modelo y las cuotas (verificar_modelo.sh; no cuesta nada).
#   2. Instala Terraform si falta (CloudShell lo borra al cerrar la sesión).
#   3. terraform init y apply, con la caché de providers en /tmp.
#   4. Imprime la URL de la app, la del tablero y qué mirar ahora.
# Uso:  ./deploy.sh
#       EMAIL=tu@correo.com ./deploy.sh    además, un presupuesto mensual de USD 5 que avisa por correo
set -euo pipefail
cd "$(dirname "$0")"
source ./_comun.sh
SECONDS=0

comprobar_identidad
./verificar_modelo.sh || echo "(Sigo con el despliegue; resuelve los avisos antes de la charla.)"
echo
terraform_disponible

if [ -n "${EMAIL:-}" ]; then
  case "$EMAIL" in
    *[!A-Za-z0-9._%+@-]*|*@*@*) echo "ERROR: EMAIL no parece un correo: '$EMAIL'." >&2; exit 1 ;;
    ?*@?*.?*) printf 'email_presupuesto = "%s"\n' "$EMAIL" > "$TF_DIR/deploy.auto.tfvars" ;;
    *) echo "ERROR: EMAIL no parece un correo: '$EMAIL'." >&2; exit 1 ;;
  esac
fi

echo "terraform init (la primera vez descarga el provider de AWS, ~1 min)..."
terraform -chdir="$TF_DIR" init -input=false >/dev/null
terraform -chdir="$TF_DIR" apply -input=false -auto-approve

APP=$(salida url_app)
echo
echo "════════════════════════════════════════════════════════════════"
echo " Listo en ${SECONDS} s"
echo "   App:      $APP"
echo "   Tablero:  $(salida url_tablero)"
echo "   Modelo:   $(salida modelo)"
echo "════════════════════════════════════════════════════════════════"
echo "QUÉ MIRAR AHORA:"
echo "  1. Abre el tablero en el portátil. La primera vez CloudFront tarda de 1 a 2,5 min en publicarse:"
echo "     si no carga, espera y recarga."
echo "  2. Escanea el QR con tu celular, con datos móviles, y haz el test: la barra de tu rol sube."
echo "  3. ./probar.sh revisa la API desde la terminal, sin celular."
echo "  4. El día de la charla, antes de empezar: ./reiniciar_tablero.sh (las pruebas suman al tablero)."
echo "  5. Al terminar: ./destroy.sh (unos 3 min, por CloudFront)."
