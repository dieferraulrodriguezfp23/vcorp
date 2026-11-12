#!/bin/bash
set -euo pipefail

# Cargar las funciones de ayuda y las variables de configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Comprobar la disponibilidad de VBoxManage
if [ -z "$VBOXMANAGE_BIN" ]; then
    log_err "VBoxManage no está instalado o no se encuentra en el PATH."
    exit 1
fi

# Función para mostrar la ayuda
show_help() {
    cat << EOF
Uso: $0 [OPCIONES] [NOMBRE_DEL_GRUPO]

Elimina las máquinas virtuales de un grupo de VirtualBox y de todos sus
subgrupos.

Opciones:
  -r, --routers    Elimina el grupo de routers (${VM_ROUTERS_GROUP:-no definido})
  -a, --all        Elimina el grupo raíz (${VBOX_ROOT_GROUP:-no definido})
  -h, --help       Muestra este mensaje de ayuda

Ejemplos:
  $0 /VirtualCorp
  $0 -r
  $0 --all
EOF
}

TARGET_GROUP=""

# Procesamiento de argumentos y opciones
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--routers)
            TARGET_GROUP="${VM_ROUTERS_GROUP:-}"
            shift
            ;;
        -a|--all)
            TARGET_GROUP="${VBOX_ROOT_GROUP:-}"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            log_err "Opción desconocida: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$TARGET_GROUP" ]; then
                TARGET_GROUP="$1"
            else
                log_err "Error: se han especificado varios grupos o parámetros no válidos ('$1')."
                exit 1
            fi
            shift
            ;;
    esac
done

# Validar que se haya definido un grupo
if [ -z "$TARGET_GROUP" ]; then
    log_err "Error: hay que especificar un grupo o utilizar una opción de selección (-r, -a)."
    show_help
    exit 1
fi

# Normalizar el grupo de entrada (empieza por '/' y sin '/' al final)
TARGET_GROUP="/${TARGET_GROUP#/}"
TARGET_GROUP="${TARGET_GROUP%/}"

log_info "Buscando máquinas virtuales en el grupo '$TARGET_GROUP' y sus subgrupos..."

# Recorrer todas las máquinas virtuales por su UUID
VMS=$("$VBOXMANAGE_BIN" list vms | sed -E 's/.*\{([^}]+)\}/\1/')

if [ -z "$VMS" ]; then
    log_warn "No se ha encontrado ninguna máquina virtual."
    exit 0
fi

DELETED_COUNT=0

for UUID in $VMS; do
    # Extraer la información de la máquina virtual
    INFO=$("$VBOXMANAGE_BIN" showvminfo "$UUID" --machinereadable)
    VM_NAME=$(echo "$INFO" | grep '^name=' | cut -d'=' -f2 | tr -d '"')
    GROUPS_LINE=$(echo "$INFO" | grep '^groups=' | cut -d'=' -f2 | tr -d '"')
    VM_STATE=$(echo "$INFO" | grep '^VMState=' | cut -d'=' -f2 | tr -d '"')

    # Una máquina virtual puede pertenecer a varios grupos separados por comas
    IFS=',' read -ra VM_GROUPS <<< "$GROUPS_LINE"
    
    MATCH=false
    for g in "${VM_GROUPS[@]}"; do
        # Normalizar la ruta del grupo de la máquina virtual
        g="/${g#/}"
        g="${g%/}"

        # Coincidencia exacta ($g == /VirtualCorp) o subgrupo ($g empieza por /VirtualCorp/)
        if [ "$g" = "$TARGET_GROUP" ] || [[ "$g" == "$TARGET_GROUP/"* ]]; then
            MATCH=true
            break
        fi
    done

    if [ "$MATCH" = true ]; then
        log_info "-> Encontrada: '$VM_NAME' ($UUID) en '$GROUPS_LINE'"

        # Detener la máquina virtual si está en ejecución antes de eliminarla
        if [ "$VM_STATE" = "running" ] || [ "$VM_STATE" = "paused" ]; then
            log_info "   Apagando la máquina virtual..."
            "$VBOXMANAGE_BIN" controlvm "$UUID" poweroff 2>/dev/null || true
            sleep 2
        fi

        # Desregistrar y eliminar todos los ficheros del disco
        log_info "   Eliminando ficheros y desregistrando la máquina virtual..."
        "$VBOXMANAGE_BIN" unregistervm "$UUID" --delete
        DELETED_COUNT=$((DELETED_COUNT + 1))
    fi
done

log_info "Completado. Se han eliminado $DELETED_COUNT máquinas virtuales."
