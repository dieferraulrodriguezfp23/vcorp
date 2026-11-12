#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Configuración
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../../../" && pwd)}"

PUBLIC_KEY_DIR="${SSH_PUBLIC_KEY_DIR:-${CONFIGS_DIR:-${PROJECT_ROOT}/configs}/ssh}"
PRIVATE_KEY_DIR="${SSH_PRIVATE_KEY_DIR:-${HOME}/.ssh}"

FORCE=false

###############################################################################
# Funciones
###############################################################################

usage() {
    cat <<EOF
Generador de claves SSH de VirtualCorp

Genera las claves SSH del laboratorio VirtualCorp:
  - vcorp_sysadmin
  - vcorp_mikrotik

La clave vcorp_auditor.pub es la del profesor y no se regenera.

Opciones:
  -f    Fuerza la regeneración (borra las claves existentes)
  -h    Muestra la ayuda

Ejemplos:
  $(basename "$0")
  $(basename "$0") -f
EOF
}

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

###############################################################################
# SEGURIDAD: evitar secretos en el repositorio
###############################################################################

check_repo_for_private_keys() {
    log_info "Comprobando que no hay claves privadas en el repositorio..."

    local found
    found=$(find "${PROJECT_ROOT}" -type f \( -name "*.key" -o -name "id_*" -o -name "*.pem" \) 2>/dev/null || true)

    if [[ -n "${found}" ]]; then
        echo
        log_err "¡Se han detectado posibles claves privadas dentro del repositorio!"
        echo "${found}"
        echo
        log_err "Se rechaza continuar por seguridad."
        exit 1
    fi

    log_ok "No se han detectado secretos en el repositorio."
}

###############################################################################
# Generación de claves
###############################################################################

generate_key() {
    local key_name="$1"

    local private_key="${PRIVATE_KEY_DIR}/${key_name}"
    local public_key_repo="${PUBLIC_KEY_DIR}/${key_name}.pub"

    if [[ -f "${private_key}" || -f "${private_key}.pub" ]]; then
        if [[ "${FORCE}" != "true" ]]; then
            log_warn "La clave '${key_name}' ya existe. Se omite (usa -f para regenerar)."
            return
        fi

        log_warn "Regenerando '${key_name}' (FORZADO)"

        rm -f \
            "${private_key}" \
            "${private_key}.pub" \
            "${public_key_repo}"
    fi

    log_info "Generando la clave '${key_name}'..."

    ssh-keygen \
        -q \
        -t ed25519 \
        -a 100 \
        -N "" \
        -C "${key_name}@virtualcorp" \
        -f "${private_key}"

    cp "${private_key}.pub" "${public_key_repo}"

    chmod 600 "${private_key}"
    chmod 644 "${private_key}.pub"
    chmod 644 "${public_key_repo}"

    log_ok "Clave '${key_name}' creada"
}

generate_mikrotik_key() {
    # MikroTik no es compatible con los algoritmos de las claves SSH modernas.
    # Se genera un par de claves específico en formato RSA/PEM para MikroTik.
    local key_name=vcorp_mikrotik

    local private_key="${PRIVATE_KEY_DIR}/${key_name}"
    local public_key_repo="${PUBLIC_KEY_DIR}/${key_name}.pub"

    if [[ -f "${private_key}" || -f "${private_key}.pub" ]]; then
        if [[ "${FORCE}" != "true" ]]; then
            log_warn "La clave '${key_name}' ya existe. Se omite (usa -f para regenerar)."
            return
        fi

        log_warn "Regenerando '${key_name}' (FORZADO)"

        rm -f \
            "${private_key}" \
            "${private_key}.pub" \
            "${public_key_repo}"
    fi

    log_info "Generando la clave '${key_name}'..."

    ssh-keygen \
        -q \
        -t rsa \
        -m pem \
        -b 2048 \
        -N "" \
        -C "${key_name}@virtualcorp" \
        -f "${private_key}"

    cp "${private_key}.pub" "${public_key_repo}"

    chmod 600 "${private_key}"
    chmod 644 "${private_key}.pub"
    chmod 644 "${public_key_repo}"

    log_ok "Clave '${key_name}' creada"
}



###############################################################################
# CLI
###############################################################################

while getopts ":fh" opt; do
    case "${opt}" in
        f)
            FORCE=true
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            log_err "Opción inválida: -${OPTARG}"
            usage
            exit 1
            ;;
    esac
done

###############################################################################
# Ejecución
###############################################################################

if ! command -v ssh-keygen >/dev/null 2>&1; then
    log_err "ssh-keygen no está instalado"
    exit 1
fi

mkdir -p "${PRIVATE_KEY_DIR}"
mkdir -p "${PUBLIC_KEY_DIR}"

check_repo_for_private_keys

# vcorp_auditor.pub es la clave pública del profesor: nunca se regenera ni se
# sobrescribe desde este script.
#generate_key "vcorp_auditor"
generate_key "vcorp_sysadmin"
generate_mikrotik_key

###############################################################################
# Resumen final
###############################################################################

cat <<EOF

==================================================
Claves SSH de VirtualCorp generadas correctamente
==================================================

Privadas (LOCAL):
  ${PRIVATE_KEY_DIR}/vcorp_sysadmin
  ${PRIVATE_KEY_DIR}/vcorp_mikrotik

Públicas (REPO):
  ${PUBLIC_KEY_DIR}/vcorp_sysadmin.pub
  ${PUBLIC_KEY_DIR}/vcorp_mikrotik.pub
  ${PUBLIC_KEY_DIR}/vcorp_auditor.pub  (clave del profesor, no generada)

Reglas del laboratorio:
  - No subir nunca claves privadas a GitHub
  - vcorp_sysadmin → administración + Ansible
  - vcorp_mikrotik → alternativa RSA compatible con RouterOS
  - vcorp_auditor → acceso profesor / auditoría

==================================================
EOF
