#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIGURACIÓN
# =========================

ROUTEROS_VERSION="${ROUTEROS_VERSION:-7.21.4}"
ROUTEROS_VDI_FILENAME="${ROUTEROS_VDI_FILENAME:-chr-${ROUTEROS_VERSION}.vdi}"
URL="${ROUTEROS_URL:-https://download.mikrotik.com/routeros/${ROUTEROS_VERSION}/${ROUTEROS_VDI_FILENAME}.zip}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts/images/chr}"
CONFIGS_DIR="${CONFIGS_DIR:-${PROJECT_ROOT}/configs}"
SSH_PUBLIC_KEY_DIR="${SSH_PUBLIC_KEY_DIR:-${CONFIGS_DIR}/ssh}"
ROUTEROS_VDI_PATH="${ROUTEROS_VDI_PATH:-${ARTIFACTS_DIR}/${ROUTEROS_VDI_FILENAME}}"

VM_NAME="${ROUTEROS_VM_NAME:-routeros_template}"
BOX_NAME="${ROUTEROS_BOX_NAME:-routeros-base}"
BOX_FILE="${ROUTEROS_BOX_FILE:-${ARTIFACTS_DIR}/${BOX_NAME}.box}"

SSH_PORT=2222

AUDIT_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_auditor.pub"
SYSADMIN_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_sysadmin.pub"
VBOXMANAGE_BIN="${VBOXMANAGE_BIN:-$(command -v VBoxManage 2>/dev/null || command -v vboxmanage 2>/dev/null || true)}"

# Colores ANSI
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # Sin color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

log_err() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# =========================
# DEPENDENCIAS
# =========================

command -v vagrant >/dev/null 2>&1 || { log_err "Falta Vagrant"; exit 1; }
[[ -n "$VBOXMANAGE_BIN" ]] || { log_err "Falta VirtualBox"; exit 1; }

# =========================
# AYUDA
# =========================

usage() {
cat <<EOF
Uso: $0 [-f]

-f Fuerza la reconstrucción
EOF
}

FORCE=false
while getopts "fh" opt; do
  case $opt in
    f) FORCE=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# =========================
# LIMPIEZA
# =========================

if [[ "$FORCE" == true ]]; then
  log_info "Limpieza forzada"

  # 1. Apagar la VM si está en ejecución
  if VBoxManage list runningvms | grep -q "$VM_NAME"; then
    log_info "La VM está en ejecución -> apagando"
    VBoxManage controlvm "$VM_NAME" poweroff || true
    sleep 3
  fi

  # 2. Intentar apagado normal (si existe pero no está en ejecución)
  VBoxManage controlvm "$VM_NAME" acpipowerbutton 2>/dev/null || true
  sleep 5

  # 3. Forzar estado inconsistente
  VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true

  # 4. Si queda una carpeta residual (IMPORTANTE)
  rm -rf "$HOME/VirtualBox VMs/$VM_NAME" || true

  # 5. Limpieza del box
  vagrant box remove "$BOX_NAME" --force 2>/dev/null || true

  # 6. Fichero box local
  rm -f "$BOX_FILE" || true

  log_ok "Limpieza completada"
fi

# =========================
# COMPROBAR SI EL BOX YA EXISTE
# =========================

if vagrant box list | grep -q "$BOX_NAME" && [[ "$FORCE" == false ]]; then
  log_ok "El box ya existe"
  exit 0
fi

mkdir -p "$ARTIFACTS_DIR"

# =========================
# DESCARGAR CHR
# =========================

if [[ ! -f "$ROUTEROS_VDI_PATH" ]]; then
  log_info "Descargando CHR..."
  ZIP_FILE="${ARTIFACTS_DIR}/chr.zip"

  curl -L "$URL" -o "$ZIP_FILE"
  unzip -o "$ZIP_FILE" -d "$ARTIFACTS_DIR"
  rm -f "$ZIP_FILE"
fi

# =========================
# CREAR VM
# =========================

log_info "Creando la VM"

"$VBOXMANAGE_BIN" createvm --name "$VM_NAME" --register

"$VBOXMANAGE_BIN" modifyvm "$VM_NAME" \
  --memory 256 \
  --cpus 1 \
  --nic1 nat

"$VBOXMANAGE_BIN" modifyvm "$VM_NAME" --natpf1 "ssh,tcp,127.0.0.1,${SSH_PORT},,22"


"$VBOXMANAGE_BIN" storagectl "$VM_NAME" \
  --name "SATA" \
  --add sata \
  --controller IntelAhci

"$VBOXMANAGE_BIN" storageattach "$VM_NAME" \
  --storagectl "SATA" \
  --port 0 \
  --device 0 \
  --type hdd \
  --medium "$ROUTEROS_VDI_PATH"

# =========================
# ARRANCAR VM
# =========================

log_info "Arrancando la VM"
"$VBOXMANAGE_BIN" startvm "$VM_NAME" --type headless

# =========================
# ESPERAR SSH
# =========================

log_info "Limpiando la entrada known_hosts de SSH"

ssh-keygen -R "[127.0.0.1]:$SSH_PORT" 2>/dev/null || true

log_info "Esperando SSH..."

until ssh -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -p "$SSH_PORT" \
  admin@127.0.0.1 " /system identity print " \
  >/dev/null 2>&1
do
  log_info "Esperando SSH..."
  sleep 5
done

# =========================
# APROVISIONAR ROUTEROS
# =========================

log_info "Configurando los usuarios de RouterOS y SSH"

ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
     -p "$SSH_PORT" admin@127.0.0.1 <<EOF

# habilitar el servicio SSH
/ip service enable ssh

# asegurar que existe el usuario vagrant (crítico para el ciclo de vida de Vagrant)
/user add name=vagrant group=full password="vagrant" comment="Vagrant user" disabled=no

EOF


# =========================
# INSTALAR LA CLAVE DE VAGRANT
# =========================

log_info "Inyectando la clave insegura de Vagrant"

scp -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -P "$SSH_PORT" \
    "$SYSADMIN_PUB_KEY_FILE" \
    admin@127.0.0.1:vagrant.pub

ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p "$SSH_PORT" \
    admin@127.0.0.1 <<EOF

/user ssh-keys import user=vagrant public-key-file=vagrant.pub

EOF

# =========================
# APAGADO
# =========================

log_info "Apagando la VM"

"$VBOXMANAGE_BIN" controlvm "$VM_NAME" acpipowerbutton || true
sleep 20

# =========================
# EMPAQUETAR EL BOX
# =========================

log_info "Empaquetando el box"

vagrant package \
  --base "$VM_NAME" \
  --output "$BOX_FILE"

vagrant box add "$BOX_NAME" "$BOX_FILE" --force

# =========================
# LIMPIEZA
# =========================

"$VBOXMANAGE_BIN" unregistervm "$VM_NAME" --delete || true

log_ok "Box listo: $BOX_NAME"
