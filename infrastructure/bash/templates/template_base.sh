#!/usr/bin/env bash

# Funciones auxiliares para la creación de los templates Debian de VirtualCorp.

TEMPLATE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TEMPLATE_BASE_DIR}/../equipment_common.sh"

TEMPLATE_PRESEED_DIR="${PROJECT_ROOT}/configs/preseed"
TEMPLATE_POSTINSTALL_TEMPLATE="${TEMPLATE_PRESEED_DIR}/debian-postinstall.sh.tmpl"

ensure_debian_iso() {
    if [[ ! -f "$DEBIAN_ISO_PATH" ]]; then
        download_file "$DEBIAN_ISO_URL" "$DEBIAN_ISO_PATH" || return 1
    fi
    verify_sha256 "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_SHA256" || return 1
}

template_parameters() {
    local kind="$1"

    case "$kind" in
        server)
            TEMPLATE_NAME="$DEBIAN_SERVER_TEMPLATE"
            TEMPLATE_PRESEED="${TEMPLATE_PRESEED_DIR}/debian-server-preseed.cfg"
            TEMPLATE_PORT="$TEMPLATE_SSH_PORT_SERVER"
            TEMPLATE_MEMORY="$TEMPLATE_SERVER_MEMORY"
            TEMPLATE_CPU="$TEMPLATE_SERVER_CPU"
            TEMPLATE_DISK_MB="$TEMPLATE_SERVER_DISK_MB"
            TEMPLATE_FINAL_NET="privada"
            TEMPLATE_KIND_LABEL="Debian Server"
            ;;
        desktop)
            TEMPLATE_NAME="$DEBIAN_DESKTOP_TEMPLATE"
            TEMPLATE_PRESEED="${TEMPLATE_PRESEED_DIR}/debian-desktop-preseed.cfg"
            TEMPLATE_PORT="$TEMPLATE_SSH_PORT_DESKTOP"
            TEMPLATE_MEMORY="$TEMPLATE_DESKTOP_MEMORY"
            TEMPLATE_CPU="$TEMPLATE_DESKTOP_CPU"
            TEMPLATE_DISK_MB="$TEMPLATE_DESKTOP_DISK_MB"
            TEMPLATE_FINAL_NET="pl0"
            TEMPLATE_KIND_LABEL="Debian Desktop LXQt"
            ;;
        *)
            log_err "Tipo de template desconocido: $kind"
            return 1
            ;;
    esac
}

generate_postinstall_script() {
    local kind="$1"
    local output="$2"
    local target_block

    if [[ "$kind" == "server" ]]; then
        target_block="log_command_in_target systemctl set-default multi-user.target"
    else
        target_block=$'log_command_in_target systemctl set-default graphical.target\nlog_command_in_target systemctl enable lightdm'
    fi

    mkdir -p "$(dirname "$output")"

    python3 - "$TEMPLATE_POSTINSTALL_TEMPLATE" "$output" \
        "$TEMPLATE_AUDITOR_KEY" "$TEMPLATE_SYSADMIN_KEY" "$target_block" <<'PY'
import sys
from pathlib import Path

template, output, auditor, sysadmin, target = sys.argv[1:]
s = Path(template).read_text()
s = s.replace('__AUDITOR_KEY__', Path(auditor).read_text().strip())
s = s.replace('__SYSADMIN_KEY__', Path(sysadmin).read_text().strip())
s = s.replace('__TEMPLATE_TARGET_BLOCK__', target)
Path(output).write_text(s)
PY

    chmod +x "$output"
}

create_template_vm() {
    local name="$1"
    local kind="$2"
    local vm_dir_path
    local disk_path

    if vm_exists "$name"; then
        log_warn "El template '$name' ya existe. Se omite."
        return 1
    fi

    log_info "Creando la máquina virtual del template '$name' ($TEMPLATE_KIND_LABEL)"

    "$VBOXMANAGE_BIN" createvm \
        --name "$name" \
        --ostype Debian13_64 \
        --basefolder "$VBOX_BASEFOLDER" \
        --register \
        --groups "$VM_TEMPLATES_GROUP" || return 1

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --memory "$TEMPLATE_MEMORY" \
        --cpus "$TEMPLATE_CPU" \
        --vram 16 \
        --audio none \
        --usb off \
        --ioapic on \
        --nic1 nat \
        --natpf1 "ssh,tcp,127.0.0.1,${TEMPLATE_PORT},,22" \
        --cableconnected1 on \
        --groups "$VM_TEMPLATES_GROUP" || return 1

    "$VBOXMANAGE_BIN" storagectl "$name" \
        --name "SATA" \
        --add sata \
        --controller IntelAhci \
        --portcount 2 || return 1

    vm_dir_path="$(vm_dir "$name")" || return 1
    disk_path="${vm_dir_path}/${name}.vdi"

    "$VBOXMANAGE_BIN" createmedium disk \
        --filename "$disk_path" \
        --size "$TEMPLATE_DISK_MB" \
        --format VDI || return 1

    "$VBOXMANAGE_BIN" storageattach "$name" \
        --storagectl "SATA" \
        --port 0 \
        --device 0 \
        --type hdd \
        --medium "$disk_path" || return 1

    "$VBOXMANAGE_BIN" storagectl "$name" \
        --name "IDE" \
        --add ide \
        --controller PIIX4 || return 1

    "$VBOXMANAGE_BIN" storageattach "$name" \
        --storagectl "IDE" \
        --port 1 \
        --device 0 \
        --type dvddrive \
        --medium "$DEBIAN_ISO_PATH" || return 1
}

run_unattended_debian() {
    local name="$1"
    local kind="$2"
    local password_file
    local postinstall

    password_file="${PROJECT_ROOT}/artifacts/secrets/${name}-user-password.txt"
    postinstall="${PROJECT_ROOT}/artifacts/preseed/${name}-postinstall.sh"

    ensure_dir "${PROJECT_ROOT}/artifacts/secrets"
    chmod 700 "${PROJECT_ROOT}/artifacts/secrets"
    ensure_dir "${PROJECT_ROOT}/artifacts/preseed"

    if [[ ! -f "$password_file" ]]; then
        openssl rand -hex 16 > "$password_file"
        chmod 600 "$password_file"
    fi

    generate_postinstall_script "$kind" "$postinstall" || return 1

    log_info "Iniciando la instalación desatendida de '$name'"

    "$VBOXMANAGE_BIN" unattended install "$name" \
        --iso="$DEBIAN_ISO_PATH" \
        --user="$TEMPLATE_USER" \
        --user-password-file="$password_file" \
        --full-user-name="VirtualCorp Sysadmin" \
        --hostname="${name}.virtualcorp.local" \
        --locale=en_US \
        --country=US \
        --time-zone=Europe/Madrid \
        --script-template="$TEMPLATE_PRESEED" \
        --post-install-template="$postinstall" \
        --start-vm=headless || return 1
}

verify_template_guest() {
    local name="$1"
    local kind="$2"

    log_info "Verificando '$name' por SSH"

    ssh \
        -i "$SYSADMIN_PRIVATE_KEY_FILE" \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -p "$TEMPLATE_PORT" \
        "${TEMPLATE_USER}@127.0.0.1" \
        'set -e
         test -f /home/sysadmin/.ssh/authorized_keys
         grep -q vcorp_auditor /home/sysadmin/.ssh/authorized_keys
         grep -q vcorp_sysadmin /home/sysadmin/.ssh/authorized_keys
         dpkg -s openssh-server >/dev/null
         systemctl is-enabled ssh >/dev/null
         ip -4 addr show | grep -q "10\.0\.2\."
        ' || return 1

    if [[ "$kind" == "desktop" ]]; then
        ssh \
            -i "$SYSADMIN_PRIVATE_KEY_FILE" \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 \
            -p "$TEMPLATE_PORT" \
            "${TEMPLATE_USER}@127.0.0.1" \
            'set -e
             dpkg -s lxqt >/dev/null
             dpkg -s falkon >/dev/null
             dpkg -s lightdm >/dev/null
            ' || return 1
    fi

    log_ok "Invitado '$name' verificado"
}

finalize_template() {
    local name="$1"
    local kind="$2"

    log_info "Apagando '$name'"
    poweroff_vm "$name" 600 || return 1

    remove_dvd_medium "$name"

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --nic1 intnet \
        --intnet1 "$TEMPLATE_FINAL_NET" \
        --cableconnected1 on \
        --boot1 disk \
        --boot2 none \
        --boot3 none \
        --boot4 none || return 1

    "$VBOXMANAGE_BIN" modifyvm "$name" --natpf1 delete "ssh" 2>/dev/null || true

    "$VBOXMANAGE_BIN" modifyvm "$name" \
        --description "Template ${TEMPLATE_KIND_LABEL} de VirtualCorp. Debian ${DEBIAN_VERSION}." || true

    "$VBOXMANAGE_BIN" snapshot "$name" take "base" \
        --description "Snapshot base para los clones enlazados del equipamiento de VirtualCorp" || return 1

    log_ok "Template '$name' preparado con el snapshot 'base'"
}

create_debian_template() {
    local kind="$1"

    template_parameters "$kind" || return 1

    if vm_exists "$TEMPLATE_NAME"; then
        log_warn "El template '$TEMPLATE_NAME' ya existe. Se omite."
        return 0
    fi

    ensure_debian_iso || return 1
    create_template_vm "$TEMPLATE_NAME" "$kind" || return 1
    run_unattended_debian "$TEMPLATE_NAME" "$kind" || return 1

    log_info "Esperando a que termine la instalación de '$TEMPLATE_NAME'..."

    if ! wait_ssh_key 127.0.0.1 "$TEMPLATE_PORT" "$SYSADMIN_PRIVATE_KEY_FILE" "$TEMPLATE_USER" 1800; then
        log_err "No se ha podido conectar con '$TEMPLATE_NAME' después de la instalación."
        return 1
    fi

    verify_template_guest "$TEMPLATE_NAME" "$kind" || return 1
    finalize_template "$TEMPLATE_NAME" "$kind" || return 1
}
