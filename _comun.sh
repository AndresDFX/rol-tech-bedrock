# Lo que comparten los scripts (se carga con: source ./_comun.sh).
# Región por defecto us-east-1; en CloudShell la fija la consola en AWS_REGION y aquí se respeta.
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
# El provider aws pesa ~800 MB: la caché va en /tmp, no en el GB de $HOME de CloudShell.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-/tmp/terraform-plugins}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"
TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/terraform" && pwd)"
# El primer Python que de verdad se ejecuta (en Windows, "python3" puede ser el atajo de la Microsoft Store).
PY=""
for candidato in python3 python; do
  if "$candidato" -c "import sys" >/dev/null 2>&1; then PY="$candidato"; break; fi
done

# Terraform en el PATH; en CloudShell (Amazon Linux) lo instala con los comandos oficiales de HashiCorp.
terraform_disponible() {
  command -v terraform >/dev/null 2>&1 && return 0
  if command -v yum >/dev/null 2>&1; then
    echo "Instalando Terraform (CloudShell lo borra al cerrar la sesión; tarda ~45 s)..."
    sudo yum install -y -q yum-utils shadow-utils >/dev/null
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo >/dev/null
    sudo yum -y -q install terraform >/dev/null
    return 0
  fi
  echo "ERROR: falta Terraform. Instálalo (https://developer.hashicorp.com/terraform/install) o usa CloudShell." >&2
  return 1
}

# Una salida de Terraform (vacía si no hay nada desplegado).
salida() { terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null || true; }

comprobar_identidad() {
  local arn
  if ! arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
    echo "ERROR: esta terminal no tiene credenciales de AWS (aws sts get-caller-identity falló)." >&2
    return 1
  fi
  # El ID de la cuenta no se imprime: la pantalla puede estar proyectada.
  echo "Cuenta: $(echo "$arn" | sed -E 's/[0-9]{12}/<cuenta>/') · región $AWS_REGION"
}
