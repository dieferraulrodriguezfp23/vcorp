ifeq ($(wildcard .env),)
$(error Falta .env; créalo a partir de .env.example con: cp .env.example .env)
endif

include .env

export PROJECT_ROOT ARTIFACTS_DIR CONFIGS_DIR SSH_PUBLIC_KEY_DIR SSH_PRIVATE_KEY_DIR
export ROUTEROS_VERSION ROUTEROS_VDI_FILENAME ROUTEROS_VDI_PATH ROUTEROS_BOX_NAME ROUTEROS_BOX_FILE
export VBOX_ROOT_GROUP VM_ROUTERS_GROUP VM_TEMPLATES_GROUP VBOXMANAGE_BIN
export DEBIAN_VERSION DEBIAN_ISO_FILENAME DEBIAN_ISO_URL DEBIAN_ISO_SHA256 DEBIAN_ISO_PATH
export PROXMOX_VERSION PROXMOX_ISO_FILENAME PROXMOX_ISO_URL PROXMOX_ISO_SHA256 PROXMOX_ISO_PATH PROXMOX_AUTO_ISO_PATH
export VCORP_TOOLS_DIR PVE_ASSISTANT_VERSION PVE_ASSISTANT_URL
export DEBIAN_SERVER_TEMPLATE DEBIAN_DESKTOP_TEMPLATE TEMPLATE_SSH_PORT_SERVER TEMPLATE_SSH_PORT_DESKTOP TEMPLATE_USER
export TEMPLATE_SERVER_CPU TEMPLATE_SERVER_MEMORY TEMPLATE_SERVER_DISK_MB TEMPLATE_DESKTOP_CPU TEMPLATE_DESKTOP_MEMORY TEMPLATE_DESKTOP_DISK_MB
export VBOX_BASEFOLDER VM_SERVERS_GROUP VM_PRINTERS_GROUP VM_DESKTOPS_GROUP VM_DIRECTION_GROUP EQUIPMENT_INVENTORY
export PVE01_NAME PVE01_CPU PVE01_MEMORY PVE01_DISK_MB PVE01_IP PVE01_GATEWAY PVE01_DNS PVE01_NETWORK PVE01_TEMP_SSH_PORT
export TEMPLATE_AUDITOR_KEY TEMPLATE_SYSADMIN_KEY

BASH_DIR := $(PROJECT_ROOT)/infrastructure/bash
BOOTSTRAP_DIR := $(PROJECT_ROOT)/automation/scripts/bootstrap

.PHONY: help deploy-routers delete-routers reset-routers reset_routers ssh-keys routeros-box create_templates deploy_equipment delete_equipment

help:
	@printf '%s\n' \
	  'Targets disponibles:' \
	  '  deploy-routers   Crear y configurar las máquinas virtuales de los routers' \
	  '  delete-routers   Eliminar el grupo de máquinas virtuales de los routers' \
	  '  reset-routers    Eliminar y volver a desplegar los routers' \
	  '  ssh-keys         Generar las claves SSH del proyecto' \
	  '  routeros-box     Crear la caja de Vagrant de RouterOS' \
	  '  create_templates Crear los templates Debian Server y Desktop' \
	  '  deploy_equipment Desplegar todo el equipamiento de VirtualCorp' \
	  '  delete_equipment Eliminar el grupo de máquinas virtuales del equipamiento'

deploy-routers:
	"$(BASH_DIR)/deploy_routers.sh"

delete-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers

reset-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers
	"$(BASH_DIR)/deploy_routers.sh"

# Mantener el nombre original del target para los scripts existentes.
reset_routers: reset-routers

ssh-keys:
	"$(BOOTSTRAP_DIR)/create_ssh_keys.sh"

routeros-box:
	"$(BOOTSTRAP_DIR)/create_mikrotik_box.sh"

create_templates:
	"$(BASH_DIR)/templates/create_templates.sh" $(TEMPLATE_KIND)

deploy_equipment:
	"$(BASH_DIR)/equipment/deploy_equipment.sh"

delete_equipment:
	"$(BASH_DIR)/equipment/delete_equipment.sh"
