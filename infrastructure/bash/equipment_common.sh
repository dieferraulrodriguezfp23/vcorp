#!/usr/bin/env bash

# Funciones auxiliares para los templates Debian y el despliegue del equipamiento.
# Este fichero se carga desde los scripts de templates y de equipamiento.

EQUIPMENT_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${EQUIPMENT_COMMON_DIR}/common.sh"

ensure_dir() {
    mkdir -p "$1"
}

download_file() {
    local url="$1"
    local dest="$2"

    if [[ -f "$dest" ]]; then
        log_info "Ya existe: $dest"
        return 0
    fi

    ensure_dir "$(dirname "$dest")"
    log_info "Descargando: $url"

    curl -k -fL --retry 3 --continue-at - -o "$dest" "$url" || {
        log_err "No se ha podido descargar $url"
        return 1
    }
}

verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual

    if [[ ! -f "$file" ]]; then
        log_err "No existe el fichero: $file"
        return 1
    fi

    actual="$(sha256sum "$file" | awk '{print $1}')"

    if [[ "$actual" != "$expected" ]]; then
        log_err "SHA256 incorrecto para $file"
        log_err "Esperado: $expected"
        log_err "Obtenido: $actual"
        return 1
    fi

    log_ok "SHA256 correcto: $(basename "$file")"
}

vm_exists() {
    "$VBOXMANAGE_BIN" showvminfo "$1" &>/dev/null
}

vm_dir() {
    local name="$1"
    local cfg
    cfg="$("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable | grep '^CfgFile=' | cut -d'"' -f2)"
    [[ -n "$cfg" ]] || return 1
    dirname "$cfg"
}

wait_vm_poweroff() {
    local name="$1"
    local timeout="${2:-3600}"
    local elapsed=0

    while (( elapsed < timeout )); do
        local state
        state="$("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable | grep '^VMState=' | cut -d'"' -f2)"
        if [[ "$state" == "poweroff" ]]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_err "Timeout esperando a que '$name' se apague."
    return 1
}

wait_ssh_key() {
    local ip="$1"
    local port="$2"
    local key="$3"
    local user="${4:-sysadmin}"
    local timeout="${5:-1800}"
    local elapsed=0

    log_info "Esperando SSH con clave en ${user}@${ip}:${port} (máx. ${timeout}s)..."

    while (( elapsed < timeout )); do
        if ssh \
            -i "$key" \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -p "$port" \
            "${user}@${ip}" true >/dev/null 2>&1; then
            log_info "SSH con clave disponible en ${ip}:${port}"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_err "Timeout esperando SSH con clave en ${ip}:${port}"
    return 1
}

remove_dvd_medium() {
    local name="$1"

    "$VBOXMANAGE_BIN" storageattach "$name" \
        --storagectl "IDE" --port 1 --device 0 --type dvddrive --medium none \
        2>/dev/null || true
    "$VBOXMANAGE_BIN" storageattach "$name" \
        --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium none \
        2>/dev/null || true
}

poweroff_vm() {
    local name="$1"
    "$VBOXMANAGE_BIN" controlvm "$name" acpipowerbutton 2>/dev/null || true
    wait_vm_poweroff "$name" "${2:-600}"
}
