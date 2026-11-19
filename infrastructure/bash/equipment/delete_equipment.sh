#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

for group in "$VM_SERVERS_GROUP" "$VM_PRINTERS_GROUP" "$VM_DESKTOPS_GROUP" "$VM_DIRECTION_GROUP"; do
    log_info "Eliminando el grupo '$group'"
    "${SCRIPT_DIR}/../del_vbox_group.sh" "$group" || true
done

log_ok "Equipamiento eliminado"
