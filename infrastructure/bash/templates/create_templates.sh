#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"
source "${SCRIPT_DIR}/template_base.sh"

TARGET="${1:-all}"

case "$TARGET" in
    server)
        create_debian_template server
        ;;
    desktop)
        create_debian_template desktop
        ;;
    all)
        create_debian_template server
        create_debian_template desktop
        ;;
    *)
        log_err "Uso: $0 [server|desktop|all]"
        exit 1
        ;;
esac

log_ok "Proceso de templates completado"
