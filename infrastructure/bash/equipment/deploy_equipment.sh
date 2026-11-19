#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"
source "${SCRIPT_DIR}/../equipment_common.sh"
source "${SCRIPT_DIR}/pve_base.sh"

check_template() {
    local name="$1"

    if ! vm_exists "$name"; then
        log_err "Falta el template '$name'. Ejecuta 'make create_templates'."
        return 1
    fi

    if ! "$VBOXMANAGE_BIN" snapshot "$name" list 2>/dev/null | grep -q 'Name: base'; then
        log_err "El template '$name' no tiene el snapshot 'base'."
        return 1
    fi
}

group_path() {
    case "$1" in
        servers) echo "$VM_SERVERS_GROUP" ;;
        printers) echo "$VM_PRINTERS_GROUP" ;;
        desktops) echo "$VM_DESKTOPS_GROUP" ;;
        direction) echo "$VM_DIRECTION_GROUP" ;;
        *) log_err "Grupo desconocido: $1"; return 1 ;;
    esac
}

template_name() {
    case "$1" in
        server) echo "$DEBIAN_SERVER_TEMPLATE" ;;
        desktop) echo "$DEBIAN_DESKTOP_TEMPLATE" ;;
        *) log_err "Template desconocido: $1"; return 1 ;;
    esac
}

deploy_equipment() {
    local line
    local name
    local template_kind
    local group_kind
    local network
    local memory
    local cpus
    local template
    local group
    local count=0

    check_template "$DEBIAN_SERVER_TEMPLATE" || return 1
    check_template "$DEBIAN_DESKTOP_TEMPLATE" || return 1

    deploy_pve01 || return 1

    if [[ ! -f "$EQUIPMENT_INVENTORY" ]]; then
        log_err "No existe el inventario: $EQUIPMENT_INVENTORY"
        return 1
    fi

    while IFS=, read -r name template_kind group_kind network memory cpus; do
        [[ -z "$name" || "$name" == "name" || "$name" == \#* ]] && continue

        template="$(template_name "$template_kind")" || return 1
        group="$(group_path "$group_kind")" || return 1

        if vm_exists "$name"; then
            log_warn "'$name' ya existe. Se omite."
            continue
        fi

        log_info "Creando clon enlazado '$name' desde '$template' en '$network'"

        "$VBOXMANAGE_BIN" clonevm "$template" \
            --name "$name" \
            --options link \
            --snapshot base \
            --basefolder "$VBOX_BASEFOLDER" \
            --register || return 1

        "$VBOXMANAGE_BIN" modifyvm "$name" \
            --groups "$group" \
            --memory "$memory" \
            --cpus "$cpus" \
            --nic1 intnet \
            --intnet1 "$network" \
            --cableconnected1 on \
            --boot1 disk \
            --boot2 none \
            --boot3 none \
            --boot4 none || return 1

        "$VBOXMANAGE_BIN" modifyvm "$name" --natpf1 delete "ssh" 2>/dev/null || true

        count=$((count + 1))
    done < "$EQUIPMENT_INVENTORY"

    log_ok "Equipamiento desplegado. Clones nuevos: $count"
}

deploy_equipment
