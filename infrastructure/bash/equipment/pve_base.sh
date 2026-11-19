#!/usr/bin/env bash

# Proxmox VE unattended installation helpers for pve01.

PVE_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PVE_BASE_DIR}/../equipment_common.sh"

PVE_ANSWER_TEMPLATE="${CONFIGS_DIR}/proxmox/pve01-answer.toml.tmpl"
PVE_ANSWER_FILE="${ARTIFACTS_DIR}/proxmox/pve01-answer.toml"
PVE_ROOT_PASSWORD_FILE="${ARTIFACTS_DIR}/secrets/pve01-root-password.txt"
PVE_MAC="080027220101"

ensure_pve_tools() {
    local tools="$VCORP_TOOLS_DIR"
    local assistant="$tools/pve-assistant/usr/bin/proxmox-auto-install-assistant"
    local xorriso="$tools/xorriso-root/usr/bin/xorriso"

    if [[ -x "$assistant" && -x "$xorriso" ]]; then
        export LD_LIBRARY_PATH="${tools}/xorriso-root/usr/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
        export PATH="${tools}/pve-assistant/usr/bin:${tools}/xorriso-root/usr/bin:${PATH}"
        return 0
    fi

    command -v bsdtar >/dev/null 2>&1 || {
        log_err "Falta bsdtar para extraer las herramientas locales de Proxmox."
        return 1
    }

    ensure_dir "$tools"

    if [[ ! -x "$assistant" ]]; then
        log_info "Descargando proxmox-auto-install-assistant ${PVE_ASSISTANT_VERSION}"
        download_file "$PVE_ASSISTANT_URL" "${tools}/pve-assistant.deb" || return 1
        ensure_dir "${tools}/pve-assistant"
        bsdtar -xf "${tools}/pve-assistant.deb" -C "${tools}/pve-assistant" || return 1
        bsdtar -xf "${tools}/pve-assistant/data.tar.xz" -C "${tools}/pve-assistant" || return 1
    fi

    if [[ ! -x "$xorriso" ]]; then
        log_info "Descargando xorriso y sus librerías para el host"
        ensure_dir "${tools}/pkgs"
        ensure_dir "${tools}/xorriso-root"
        local pkg
        for pkg in \
            "core/os/x86_64/libxcrypt-compat-4.5.2-1-x86_64.pkg.tar.zst" \
            "extra/os/x86_64/libburn-1.5.8-1-x86_64.pkg.tar.zst" \
            "extra/os/x86_64/libisofs-1.5.8.2-2-x86_64.pkg.tar.zst" \
            "extra/os/x86_64/libisoburn-1.5.8.2-1-x86_64.pkg.tar.zst"; do
            local file="${tools}/pkgs/$(basename "$pkg")"
            download_file "https://geo.mirror.pkgbuild.com/${pkg}" "$file" || return 1
            bsdtar -xf "$file" -C "${tools}/xorriso-root" || return 1
        done
    fi

    [[ -x "$assistant" && -x "$xorriso" ]] || return 1
    export LD_LIBRARY_PATH="${tools}/xorriso-root/usr/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export PATH="${tools}/pve-assistant/usr/bin:${tools}/xorriso-root/usr/bin:${PATH}"
}

ensure_proxmox_iso() {
    if [[ ! -f "$PROXMOX_ISO_PATH" ]]; then
        download_file "$PROXMOX_ISO_URL" "$PROXMOX_ISO_PATH" || return 1
    fi
    verify_sha256 "$PROXMOX_ISO_PATH" "$PROXMOX_ISO_SHA256" || return 1
}

generate_pve_answer() {
    local password_hash
    local auditor_key
    local sysadmin_key

    ensure_dir "$(dirname "$PVE_ANSWER_FILE")"
    ensure_dir "$(dirname "$PVE_ROOT_PASSWORD_FILE")"
    chmod 700 "$(dirname "$PVE_ROOT_PASSWORD_FILE")"

    if [[ ! -f "$PVE_ROOT_PASSWORD_FILE" ]]; then
        openssl rand -hex 16 > "$PVE_ROOT_PASSWORD_FILE"
        chmod 600 "$PVE_ROOT_PASSWORD_FILE"
    fi

    password_hash="$(openssl passwd -6 "$(cat "$PVE_ROOT_PASSWORD_FILE")")"
    auditor_key="$(cat "$TEMPLATE_AUDITOR_KEY")"
    sysadmin_key="$(cat "$TEMPLATE_SYSADMIN_KEY")"

    python3 - "$PVE_ANSWER_TEMPLATE" "$PVE_ANSWER_FILE" \
        "$password_hash" "$auditor_key" "$sysadmin_key" \
        "$PVE01_IP" "$PVE01_GATEWAY" "$PVE01_DNS" "$PVE_MAC" <<'PY'
import sys
from pathlib import Path

(template, output, password_hash, auditor, sysadmin,
 cidr, gateway, dns, mac) = sys.argv[1:]
s = Path(template).read_text()
s = s.replace('__ROOT_PASSWORD_HASH__', password_hash)
s = s.replace('__AUDITOR_KEY__', auditor.strip())
s = s.replace('__SYSADMIN_KEY__', sysadmin.strip())
s = s.replace('__PVE01_IP__', cidr)
s = s.replace('__PVE01_GATEWAY__', gateway)
s = s.replace('__PVE01_DNS__', dns)
s = s.replace('__PVE01_MAC__', mac)
Path(output).write_text(s)
PY
    chmod 600 "$PVE_ANSWER_FILE"
}

prepare_pve_iso() {
    ensure_pve_tools || return 1
    ensure_proxmox_iso || return 1
    generate_pve_answer || return 1

    log_info "Validando el answer file de Proxmox"
    proxmox-auto-install-assistant validate-answer "$PVE_ANSWER_FILE" || return 1

    log_info "Preparando la ISO autoinstalable de Proxmox"
    proxmox-auto-install-assistant prepare-iso \
        "$PROXMOX_ISO_PATH" \
        --fetch-from iso \
        --answer-file "$PVE_ANSWER_FILE" \
        --output "$PROXMOX_AUTO_ISO_PATH" || return 1
}

create_pve01_vm() {
    local vm_dir_path
    local disk_path

    if vm_exists "$PVE01_NAME"; then
        log_warn "La máquina '$PVE01_NAME' ya existe. Se omite la creación."
        return 1
    fi

    log_info "Creando '$PVE01_NAME' (${PVE01_CPU} vCPU, ${PVE01_MEMORY} MB RAM, ${PVE01_DISK_MB} MB disco)"

    "$VBOXMANAGE_BIN" createvm \
        --name "$PVE01_NAME" \
        --ostype Debian_64 \
        --basefolder "$VBOX_BASEFOLDER" \
        --register \
        --groups "$VM_SERVERS_GROUP" || return 1

    "$VBOXMANAGE_BIN" modifyvm "$PVE01_NAME" \
        --memory "$PVE01_MEMORY" \
        --cpus "$PVE01_CPU" \
        --vram 16 \
        --audio none \
        --usb off \
        --ioapic on \
        --nested-hw-virt on \
        --nic1 intnet \
        --intnet1 "$PVE01_NETWORK" \
        --nictype1 virtio \
        --macaddress1 "$PVE_MAC" \
        --cableconnected1 on \
        --groups "$VM_SERVERS_GROUP" || return 1

    "$VBOXMANAGE_BIN" storagectl "$PVE01_NAME" \
        --name "SATA" \
        --add sata \
        --controller IntelAhci \
        --portcount 2 || return 1

    vm_dir_path="$(vm_dir "$PVE01_NAME")" || return 1
    disk_path="${vm_dir_path}/${PVE01_NAME}.vdi"

    "$VBOXMANAGE_BIN" createmedium disk \
        --filename "$disk_path" \
        --size "$PVE01_DISK_MB" \
        --format VDI || return 1

    "$VBOXMANAGE_BIN" storageattach "$PVE01_NAME" \
        --storagectl "SATA" \
        --port 0 \
        --device 0 \
        --type hdd \
        --medium "$disk_path" || return 1

    "$VBOXMANAGE_BIN" storagectl "$PVE01_NAME" \
        --name "IDE" \
        --add ide \
        --controller PIIX4 || return 1

    "$VBOXMANAGE_BIN" storageattach "$PVE01_NAME" \
        --storagectl "IDE" \
        --port 1 \
        --device 0 \
        --type dvddrive \
        --medium "$PROXMOX_AUTO_ISO_PATH" || return 1

    "$VBOXMANAGE_BIN" modifyvm "$PVE01_NAME" \
        --boot1 dvd --boot2 disk --boot3 none --boot4 none || return 1
}

install_pve01() {
    log_info "Iniciando la instalación desatendida de Proxmox VE"
    "$VBOXMANAGE_BIN" startvm "$PVE01_NAME" --type headless || return 1

    if ! wait_vm_poweroff "$PVE01_NAME" 2400; then
        log_err "Proxmox no se ha apagado al terminar la instalación."
        return 1
    fi

    log_ok "Instalación de Proxmox finalizada"
}

ensure_routers_running() {
    local vm
    local state

    for vm in router0 router1 router2 router3; do
        if ! vm_exists "$vm"; then
            log_err "Falta el router '$vm'."
            return 1
        fi
        state="$("$VBOXMANAGE_BIN" showvminfo "$vm" --machinereadable | grep '^VMState=' | cut -d'"' -f2)"
        if [[ "$state" != "running" ]]; then
            log_info "Arrancando '$vm'"
            "$VBOXMANAGE_BIN" startvm "$vm" --type headless || return 1
        fi
    done
    sleep 15
}

validate_pve01() {
    local output="${ARTIFACTS_DIR}/pve01-validation.txt"
    local router_ssh_port="${ROUTER0_SSH_PORT:-2200}"

    ensure_routers_running || return 1

    log_info "Preparando salto SSH temporal a través de router0"

    "$VBOXMANAGE_BIN" modifyvm "$PVE01_NAME" --nic2 none --natpf2 delete "ssh" 2>/dev/null || true
    "$VBOXMANAGE_BIN" controlvm router0 natpf1 delete "pve-ssh" 2>/dev/null || true
    "$VBOXMANAGE_BIN" controlvm router0 natpf1 "pve-ssh,tcp,127.0.0.1,${PVE01_TEMP_SSH_PORT},,${PVE01_TEMP_SSH_PORT}" || return 1

    ssh -i "$SYSADMIN_PRIVATE_KEY_FILE"         -o BatchMode=yes         -o StrictHostKeyChecking=no         -o UserKnownHostsFile=/dev/null         -o ConnectTimeout=10         -p "$router_ssh_port"         sysadmin@127.0.0.1         '/ip firewall nat remove [find comment="vcorp-pve-ssh"]; /ip firewall nat add chain=dstnat protocol=tcp dst-port=2222 in-interface=ether1 action=dst-nat to-addresses=10.22.0.133 to-ports=22 comment="vcorp-pve-ssh"; /ip firewall nat add chain=srcnat src-address=10.0.2.0/24 dst-address=10.22.0.133 action=masquerade comment="vcorp-pve-ssh"' || return 1

    wait_ssh_key 127.0.0.1 "$PVE01_TEMP_SSH_PORT" "$SYSADMIN_PRIVATE_KEY_FILE" root 1800 || return 1

    {
        echo "== pveversion =="
        ssh -i "$SYSADMIN_PRIVATE_KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$PVE01_TEMP_SSH_PORT" root@127.0.0.1 'pveversion -v'
        echo "== cpu virtualization =="
        ssh -i "$SYSADMIN_PRIVATE_KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$PVE01_TEMP_SSH_PORT" root@127.0.0.1 'egrep -c "(vmx|svm)" /proc/cpuinfo; ls -l /dev/kvm; lsmod | grep kvm || true'
        echo "== network =="
        ssh -i "$SYSADMIN_PRIVATE_KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$PVE01_TEMP_SSH_PORT" root@127.0.0.1 'ip -4 addr show; ip route'
        echo "== qm =="
        ssh -i "$SYSADMIN_PRIVATE_KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$PVE01_TEMP_SSH_PORT" root@127.0.0.1 'qm list'
        echo "== ping routers =="
        ssh -i "$SYSADMIN_PRIVATE_KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$PVE01_TEMP_SSH_PORT" root@127.0.0.1 'for ip in 10.22.0.225 10.22.0.226 10.22.0.230 10.22.0.234; do ping -c 2 "$ip" | tail -2; done; ping -c 2 1.1.1.1 | tail -2'
    } | tee "$output"

    log_info "Apagando pve01"
    ssh -i "$SYSADMIN_PRIVATE_KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$PVE01_TEMP_SSH_PORT" root@127.0.0.1 'poweroff' || true
    wait_vm_poweroff "$PVE01_NAME" 600 || true

    ssh -i "$SYSADMIN_PRIVATE_KEY_FILE"         -o BatchMode=yes         -o StrictHostKeyChecking=no         -o UserKnownHostsFile=/dev/null         -o ConnectTimeout=10         -p "$router_ssh_port"         sysadmin@127.0.0.1         '/ip firewall nat remove [find comment="vcorp-pve-ssh"]' || true

    "$VBOXMANAGE_BIN" controlvm router0 natpf1 delete "pve-ssh" 2>/dev/null || true
    "$VBOXMANAGE_BIN" modifyvm "$PVE01_NAME" --nic2 none --natpf2 delete "ssh" 2>/dev/null || true
}

deploy_pve01() {
    if vm_exists "$PVE01_NAME"; then
        log_warn "'$PVE01_NAME' ya existe. Se omite."
        return 0
    fi

    prepare_pve_iso || return 1
    create_pve01_vm || return 1
    install_pve01 || return 1
    validate_pve01 || return 1

    log_ok "pve01 instalado y validado"
}
