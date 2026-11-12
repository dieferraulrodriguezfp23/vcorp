#!/usr/bin/env bash

# Parámetros globales de configuración
SSH_USER="${SSH_USER:-sysadmin}"

# Cargar funciones y variables de entorno
source "$SCRIPT_DIR/common.sh"

# =========================
# DESCARGA DE CHR
# =========================
download_vdi() {
    if [[ ! -f "$ROUTEROS_VDI_PATH" ]]; then
        local image_dir
        local zip_file
        image_dir="$(dirname "$ROUTEROS_VDI_PATH")"
        mkdir -p "$image_dir"

        log_info "Descargando CHR..."
        zip_file="${image_dir}/chr.zip"

        curl -L "$URL" -o "$zip_file"
        unzip -o "$zip_file" -d "$image_dir"
        rm -f "$zip_file"
    fi
}

# Función para verificar dependencias y ficheros
check_prerequisites() {

    download_vdi

    if [[ ! -f "$ROUTEROS_VDI_PATH" ]]; then
        log_err "No se ha encontrado la imagen de disco base en '$ROUTEROS_VDI_PATH'."
        exit 1
    fi
}


# =========================================================
# CREACIÓN DE LA PLANTILLA (TEMPLATE)
# =========================================================
create_router_template() {
    local template_name="${VM_NAME:-routeros_template}"
    local router_nics="${ROUTER_NICS:-8}"

    # Validación básica
    if ! [[ "$router_nics" =~ ^[1-8]$ ]]; then
        log_err "ROUTER_NICS debe ser un valor entre 1 y 8."
        return 1
    fi

    # Si la plantilla ya existe, se omite su creación
    if "$VBOXMANAGE_BIN" showvminfo "$template_name" &>/dev/null; then
        log_info "La plantilla '$template_name' ya existe. Se omite su creación."
        return 0
    fi

    # =========================
    # CREAR VM
    # =========================

    log_info "Creando la plantilla RouterOS con $router_nics interfaces de red"

    "$VBOXMANAGE_BIN" createvm --name "$VM_NAME" --register \
        --memory "$ROUTER_MEMORY" \
        --cpus "$ROUTER_CPU" \
        --groups "$VM_ROUTERS_GROUP"

    "$VBOXMANAGE_BIN" modifyvm "$VM_NAME" \
        --groups "$VM_ROUTERS_GROUP"

    

    # NIC2..NICN = Internal Network
    #
    # En esta fase no importa qué red interna utilicen.
    # El objetivo es que RouterOS detecte todas las NIC desde el
    # primer arranque de la plantilla.
    for ((nic=2; nic<=router_nics; nic++)); do
        "$VBOXMANAGE_BIN" modifyvm "$VM_NAME" \
            "--nic${nic}" intnet \
            "--intnet${nic}" "routeros-template-unused"
    done

    # SSH temporal de la NIC1 NAT
    "$VBOXMANAGE_BIN" modifyvm "$VM_NAME" \
        --natpf1 "ssh,tcp,127.0.0.1,${SSH_PORT},,22"

    # =========================
    # ALMACENAMIENTO
    # =========================

    "$VBOXMANAGE_BIN" storagectl "$VM_NAME" \
        --name "SATA" \
        --add sata \
        --controller IntelAhci

    VM_DIR=$(dirname "$("$VBOXMANAGE_BIN" showvminfo "$VM_NAME" --machinereadable \
        | grep "CfgFile=" \
        | cut -d'"' -f2)")

    "$VBOXMANAGE_BIN" clonemedium disk \
        "$ROUTEROS_VDI_PATH" \
        "$VM_DIR/$ROUTEROS_VDI_FILENAME"

    "$VBOXMANAGE_BIN" storageattach "$VM_NAME" \
        --storagectl "SATA" \
        --port 0 \
        --device 0 \
        --type hdd \
        --medium "$VM_DIR/$ROUTEROS_VDI_FILENAME"

    # =========================
    # ARRANCAR VM
    # =========================

    log_info "Arrancando la VM"

    "$VBOXMANAGE_BIN" startvm "$VM_NAME" --type headless

    # =========================
    # ESPERAR SSH
    # =========================

    log_info "Limpiando la entrada de known_hosts de SSH"

    ssh-keygen -R "[127.0.0.1]:$SSH_PORT" 2>/dev/null || true

    wait_ssh 127.0.0.1 "$SSH_PORT"

    # =========================
    # APROVISIONAR ROUTEROS
    # =========================

    log_info "Configurando los usuarios de RouterOS y SSH"

    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" \
        admin@127.0.0.1 <<EOF

# habilitar el servicio SSH
/ip service enable ssh

# crear el usuario sysadmin
/user add name=sysadmin group=full password="$(openssl rand -hex 16 2>/dev/null || date +%s%N)" comment="sysadmin user" disabled=no

EOF

    # =========================
    # INSTALAR LA CLAVE DE SYSADMIN
    # =========================

    log_info "Inyectando la clave de sysadmin"

    scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -P "$SSH_PORT" \
        "$SSH_PUBLIC_KEY_DIR/vcorp_sysadmin.pub" \
        admin@127.0.0.1:sysadmin.pub

    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" \
        admin@127.0.0.1 <<EOF

/user ssh-keys import user=sysadmin public-key-file=sysadmin.pub

EOF

    # =========================
    # MOSTRAR INTERFACES
    # =========================

    log_info "Comprobando las interfaces de RouterOS antes de apagar"

    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" \
        admin@127.0.0.1 \
        "/interface print detail"

    # =========================
    # APAGADO
    # =========================

    log_info "Apagando la VM"

    "$VBOXMANAGE_BIN" controlvm "$VM_NAME" acpipowerbutton || true
    sleep 20

    # =========================
    # SNAPSHOT
    # =========================

    log_info "Creando la plantilla RouterOS '$template_name' en el grupo '$TEMPLATE_GROUP'..."

    log_info "Creando el snapshot base de la plantilla para permitir clones enlazados..."

    "$VBOXMANAGE_BIN" snapshot "$template_name" take "BaseSnapshot" \
        --description "Snapshot base para clones enlazados"

    log_ok "Plantilla '$template_name' creada correctamente con $router_nics interfaces."
}

# =========================================================
# VALIDACIONES
# =========================================================

validate_router_nics() {
    local router_nics="$1"

    if ! [[ "$router_nics" =~ ^[1-8]$ ]]; then
        log_err "ROUTER_NICS debe ser un valor entre 1 y 8."
        return 1
    fi
}


router_exists() {
    local name="$1"

    "$VBOXMANAGE_BIN" showvminfo "$name" &>/dev/null
}


validate_router_config() {
    local router_nics="$1"
    local intnets_name="$2"
    local ips_name="$3"

    # Recuperamos los arrays mediante nameref
    local -n ref_intnets="$intnets_name"
    local -n ref_ips="$ips_name"

    # NIC1 queda reservada para la interfaz de management/NAT.
    #
    # Por tanto, como máximo podemos configurar:
    #
    #   ether2 ... etherN
    #
    local max_internal_nics=$((router_nics - 1))

    if (( ${#ref_intnets[@]} > max_internal_nics )); then
        log_err \
            "Se han especificado ${#ref_intnets[@]} redes internas, " \
            "pero solo hay $max_internal_nics NICs disponibles " \
            "(NIC2..NIC${router_nics})."
        return 1
    fi

    if (( ${#ref_intnets[@]} != ${#ref_ips[@]} )); then
        log_err \
            "--intnets y --ips deben tener el mismo número de elementos."
        return 1
    fi

    return 0
}

# =========================================================
# ANÁLISIS DE ARGUMENTOS
# =========================================================

parse_router_args() {
    local -n ref_intnets="$1"
    local -n ref_ips="$2"
    local -n ref_nat="$3"
    local -n ref_gateway="$4"

    shift 4

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --intnets)
                shift
                while [[ $# -gt 0 && "$1" != --* ]]; do
                    ref_intnets+=("$1")
                    shift
                done
                ;;

            --ips)
                shift
                while [[ $# -gt 0 && "$1" != --* ]]; do
                    ref_ips+=("$1")
                    shift
                done
                ;;

            --nat)
                ref_nat=true
                shift
                ;;

            --gateway)
                if [[ $# -lt 2 ]]; then
                    log_err "--gateway requiere un valor."
                    return 1
                fi

                ref_gateway="$2"
                shift 2
                ;;

            *)
                log_err "Opción desconocida: $1"
                return 1
                ;;
        esac
    done
}


# =========================================================
# CREACIÓN DE LA VM
# =========================================================

create_router_vm() {
    local name="$1"
    local router_nics="$2"
    local ssh_port="$3"

    log_info "Creando la VM '$name'"

    "$VBOXMANAGE_BIN" createvm \
        --name "$name" \
        --register

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --memory "$ROUTER_MEMORY" \
        --cpus "$ROUTER_CPU" \
        --groups "$VM_ROUTERS_GROUP" || return 1

    configure_router_nics \
        "$name" \
        "$router_nics" || return 1

    # NIC1 = NAT temporal para poder hacer el bootstrap por SSH
    log_info "Configurando NAT temporal para SSH: localhost:$ssh_port → RouterOS:22"

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --natpf1 "ssh,tcp,127.0.0.1,${ssh_port},,22" || return 1
}


# =========================================================
# CONFIGURACIÓN DE LAS NICs
# =========================================================

configure_router_nics() {
    local name="$1"
    local router_nics="$2"

    log_info "Configurando $router_nics interfaces de red"

    # -----------------------------------------------------
    # NIC1
    # -----------------------------------------------------
    #
    # NAT temporal.
    #
    # Esta NIC es la que permite hacer el bootstrap inicial
    # de RouterOS antes de conectarla a la red definitiva.
    #
    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --nic1 nat \
        --cableconnected1 on || return 1


    # -----------------------------------------------------
    # NIC2..NICN
    # -----------------------------------------------------
    #
    # Inicialmente las dejamos desconectadas.
    #
    # Posteriormente configure_router_internal_networks()
    # las conectará a las redes intnet correspondientes.
    #
    for ((nic=2; nic<=router_nics; nic++)); do

        "$VBOXMANAGE_BIN" modifyvm "$name" \
            "--nic${nic}" intnet \
            "--intnet${nic}" "unused${nic}" \
            "--cableconnected${nic}" off \
            || return 1

    done
}


# =========================================================
# CONFIGURACIÓN DE LAS REDES INTERNAS
# =========================================================

configure_router_internal_networks() {
    local name="$1"
    local intnets_name="$2"

    local -n ref_intnets="$intnets_name"

    local nic_idx=2

    for net in "${ref_intnets[@]}"; do

        log_info "NIC${nic_idx} → red interna '$net'"

        "$VBOXMANAGE_BIN" modifyvm "$name" \
            "--nic${nic_idx}" intnet \
            "--intnet${nic_idx}" "$net" \
            "--cableconnected${nic_idx}" on \
            || return 1

        ((nic_idx++))
    done
}


# =========================================================
# ALMACENAMIENTO
# =========================================================

attach_router_disk() {
    local name="$1"

    local vm_dir
    local disk_path

    log_info "Configurando el almacenamiento"

    "$VBOXMANAGE_BIN" storagectl "$name" \
        --name "SATA" \
        --add sata \
        --controller IntelAhci \
        || return 1

    vm_dir="$(
        "$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable |
            grep '^CfgFile=' |
            cut -d'"' -f2
    )"

    if [[ -z "$vm_dir" ]]; then
        log_err "No se ha podido determinar el directorio de la VM '$name'."
        return 1
    fi

    vm_dir="$(dirname "$vm_dir")"

    disk_path="$vm_dir/$ROUTEROS_VDI_FILENAME"

    log_info "Clonando el VDI de RouterOS → $disk_path"

    "$VBOXMANAGE_BIN" clonemedium disk \
        "$ROUTEROS_VDI_PATH" \
        "$disk_path" \
        || return 1

    "$VBOXMANAGE_BIN" storageattach "$name" \
        --storagectl "SATA" \
        --port 0 \
        --device 0 \
        --type hdd \
        --medium "$disk_path" \
        || return 1
}


# =========================================================
# BOOTSTRAP DE ROUTEROS
# =========================================================

bootstrap_routeros() {
    local name="$1"
    local ssh_port="$2"
    local sysadmin_password
    local auditor_password

    sysadmin_password="$(openssl rand -hex 16 2>/dev/null || date +%s%N)"
    auditor_password="$(openssl rand -hex 16 2>/dev/null || date +%s%N)"

    log_info "Arrancando '$name' para hacer el bootstrap"

    "$VBOXMANAGE_BIN" startvm "$name" --type headless || return 1

    log_info "Esperando SSH de RouterOS en 127.0.0.1:$ssh_port"

    ssh-keygen -R "[127.0.0.1]:$ssh_port" 2>/dev/null || true

    wait_ssh 127.0.0.1 "$ssh_port" || {
        log_err "No se ha podido establecer SSH con '$name'."
        return 1
    }


    # -----------------------------------------------------
    # Crear el usuario sysadmin
    # -----------------------------------------------------

    log_info "Configurando el usuario sysadmin"

    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$ssh_port" \
        admin@127.0.0.1 <<EOF

/ip service enable ssh
/user add name=sysadmin group=full password="$sysadmin_password" comment="sysadmin user" disabled=no

EOF

    if [[ $? -ne 0 ]]; then
        log_err "No se ha podido crear el usuario sysadmin."
        return 1
    fi


    # -----------------------------------------------------
    # Instalar la clave pública
    # -----------------------------------------------------

    log_info "Inyectando la clave SSH de sysadmin"

    scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -P "$ssh_port" \
        "$SSH_PUBLIC_KEY_DIR/vcorp_sysadmin.pub" \
        admin@127.0.0.1:sysadmin.pub \
        || return 1


    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$ssh_port" \
        admin@127.0.0.1 <<'EOF'

/user ssh-keys import user=sysadmin public-key-file=sysadmin.pub

EOF

    if [[ $? -ne 0 ]]; then
        log_err "No se ha podido instalar la clave SSH."
        return 1
    fi


    # -----------------------------------------------------
    # Instalar la clave pública del auditor
    # -----------------------------------------------------

    log_info "Inyectando la clave SSH del auditor"

    scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -P "$ssh_port" \
        "$AUDIT_PUB_KEY_FILE" \
        admin@127.0.0.1:auditor.pub \
        || return 1


    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$ssh_port" \
        admin@127.0.0.1 <<EOF

/user add name=vcorp_auditor group=full password="$auditor_password" comment="auditor user" disabled=no
/user ssh-keys import user=vcorp_auditor public-key-file=auditor.pub

EOF

    if [[ $? -ne 0 ]]; then
        log_err "No se ha podido instalar la clave SSH del auditor."
        return 1
    fi


    # -----------------------------------------------------
    # Validar el acceso por clave y desactivar las contraseñas
    # -----------------------------------------------------

    log_info "Comprobando el acceso con clave de sysadmin"

    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$SYSADMIN_PRIVATE_KEY_FILE" \
        -p "$ssh_port" \
        "$SSH_USER@127.0.0.1" \
        "/system identity print" >/dev/null || {
            log_err "No se ha podido validar el acceso con clave de sysadmin."
            return 1
        }

    log_info "Desactivando la autenticación por contraseña"

    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$SYSADMIN_PRIVATE_KEY_FILE" \
        -p "$ssh_port" \
        "$SSH_USER@127.0.0.1" \
        "/ip ssh set password-authentication=no" \
        || return 1

    log_ok "Bootstrap de '$name' completado"
}


# =========================================================
# GENERACIÓN DE LA CONFIGURACIÓN DE ROUTEROS
# =========================================================

generate_router_config() {
    local rsc_file="$1"
    local gateway="$2"
    local ips_name="$3"
    local nat=$4
    local name=$5

    local -n ref_ips="$ips_name"

    # Empezamos con un fichero vacío
    : > "$rsc_file"

    # -----------------------------------------------------
    # Direcciones IP
    # -----------------------------------------------------

    local idx
    local ether_iface

    for idx in "${!ref_ips[@]}"; do

        ether_iface="ether$((idx + 2))"

        cat >> "$rsc_file" <<EOF
/ip address add address=${ref_ips[$idx]} interface=${ether_iface}
EOF

    done

    # -----------------------------------------------------
    # Puerta de enlace por defecto
    # -----------------------------------------------------

    if [[ -n "$gateway" ]]; then

        cat >> "$rsc_file" <<EOF
:if ([:len [/ip dhcp-client find]] > 0) do={/ip dhcp-client set [find] add-default-route=no}
/ip route add dst-address=0.0.0.0/0 gateway=$gateway
EOF

    fi

    # -----------------------------------------------------
    # RIP y nombre de host
    # -----------------------------------------------------

    cat >> "$rsc_file" <<EOF
/system identity set name="$name"
/routing rip instance add name=rip1 redistribute=connected,rip
EOF

    for idx in "${!ref_ips[@]}"; do

        ether_iface="ether$((idx + 2))"

        cat >> "$rsc_file" <<EOF
/routing rip interface-template add instance=rip1 interfaces=${ether_iface}
EOF

    done

    if [[ "$nat" == true ]]; then
        cat >> "$rsc_file" <<EOF
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade
EOF
    fi

}

# =========================================================
# APLICACIÓN DE LA CONFIGURACIÓN DE ROUTEROS
# =========================================================

apply_router_config() {
    local name="$1"
    local ssh_port="$2"
    local gateway="$3"
    local ips_name="$4"
    local nat="$5"

    local rsc_file="/tmp/${name}_config.rsc"

    log_info "Generando la configuración de RouterOS $name"

    generate_router_config \
        "$rsc_file" \
        "$gateway" \
        "$ips_name" \
        "$nat" \
        "$name" \
        || return 1


    # -----------------------------------------------------
    # Subir la configuración
    # -----------------------------------------------------

    log_info "Subiendo la configuración RSC a '$name'"

    scp \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$SYSADMIN_PRIVATE_KEY_FILE" \
        -P "$ssh_port" \
        "$rsc_file" \
        "$SSH_USER@127.0.0.1:/config.rsc" \
        || {
            rm -f "$rsc_file"
            return 1
        }


    # -----------------------------------------------------
    # Importar la configuración
    # -----------------------------------------------------

    log_info "Aplicando la configuración RSC"

    ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$SYSADMIN_PRIVATE_KEY_FILE" \
        -p "$ssh_port" \
        "$SSH_USER@127.0.0.1" \
        "/import file-name=config.rsc" \
        || {
            rm -f "$rsc_file"
            return 1
        }


    rm -f "$rsc_file"

    log_ok "Configuración de RouterOS aplicada"
}


# =========================================================
# CONFIGURACIÓN FINAL DE LA NIC1
# =========================================================

configure_final_network() {
    local name="$1"
    local nat="$2"
    local intnets_name="$3"

    # Solo router0 puede conservar una interfaz NAT. Los demás routers
    # dejan NIC1 en una red interna no utilizada y desconectada.
    if [[ "$nat" == true ]]; then
        log_info "NIC1 se mantiene en modo NAT en '$name'"
        return 0
    fi

    log_info "NIC1 de '$name' sin NAT (red interna de gestión desconectada)"

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --nic1 intnet \
        --intnet1 "unused" \
        --cableconnected1 off \
        || return 1

    "$VBOXMANAGE_BIN" modifyvm "$name" --natpf1 delete "ssh" 2>/dev/null || true
}


# =========================================================
# CREACIÓN DE UN ROUTER CONCRETO
# =========================================================

create_router() {

    local router_nics="${ROUTER_NICS:-8}"

    local name="$1"
    local ssh_port="$2"

    if [[ -z "$name" || -z "$ssh_port" ]]; then
        log_err "Uso: create_router <name> <ssh_port> [opciones]"
        return 1
    fi

    shift 2


    # -----------------------------------------------------
    # VALIDACIONES
    # -----------------------------------------------------

    validate_router_nics "$router_nics" || return 1


    # -----------------------------------------------------
    # PARÁMETROS DE CONFIGURACIÓN
    # -----------------------------------------------------

    local intnets=()
    local ips=()
    local nat=false
    local gateway=""

    parse_router_args \
        intnets \
        ips \
        nat \
        gateway \
        "$@" \
        || return 1


    validate_router_config \
        "$router_nics" \
        intnets \
        ips \
        || return 1


    # -----------------------------------------------------
    # COMPROBAR SI YA EXISTE
    # -----------------------------------------------------

    if router_exists "$name"; then

        log_warn \
            "El router '$name' ya existe. " \
            "Se omite el despliegue."

        return 0
    fi


    # -----------------------------------------------------
    # INFORMACIÓN
    # -----------------------------------------------------

    log_info "=========================================="
    log_info "Desplegando el router: $name"
    log_info "=========================================="


    # -----------------------------------------------------
    # 1. CREAR VM
    # -----------------------------------------------------

    create_router_vm \
        "$name" \
        "$router_nics" \
        "$ssh_port" \
        || return 1


    # -----------------------------------------------------
    # 2. CONFIGURAR EL ALMACENAMIENTO
    # -----------------------------------------------------

    attach_router_disk \
        "$name" \
        || return 1


    # -----------------------------------------------------
    # 3. CONFIGURAR LAS REDES INTERNAS
    # -----------------------------------------------------

    configure_router_internal_networks \
        "$name" \
        intnets \
        || return 1


    # -----------------------------------------------------
    # 4. BOOTSTRAP ROUTEROS
    # -----------------------------------------------------

    bootstrap_routeros \
        "$name" \
        "$ssh_port" \
        || return 1


    # -----------------------------------------------------
    # 5. CONFIGURACIÓN DE ROUTEROS
    # -----------------------------------------------------

    apply_router_config \
        "$name" \
        "$ssh_port" \
        "$gateway" \
        ips \
        "$nat" \
        || return 1


    # -----------------------------------------------------
    # 6. APAGAR EL ROUTER
    # -----------------------------------------------------

    log_info "Apagando '$name'"

    "$VBOXMANAGE_BIN" controlvm "$name" acpipowerbutton || {
        log_warn "No se ha podido enviar el apagado ACPI a '$name'."
    }


    # -----------------------------------------------------
    # 7. ESPERAR A QUE SE APAGUE
    # -----------------------------------------------------

    log_info "Esperando a que '$name' se apague..."

    while true; do

        local vm_state

        vm_state="$(
            "$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable |
                grep '^VMState=' |
                cut -d'"' -f2
        )"

        if [[ "$vm_state" == "poweroff" ]]; then
            break
        fi

        sleep 2
    done


    # -----------------------------------------------------
    # 8. CONFIGURACIÓN FINAL DE NIC1
    # -----------------------------------------------------

    configure_final_network \
        "$name" \
        "$nat" \
        intnets \
        || return 1


    log_ok \
        "Router '$name' creado y configurado correctamente."
}

