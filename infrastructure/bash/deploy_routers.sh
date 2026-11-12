#!/usr/bin/env bash

set -e

# Cargar las funciones de ayuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/router_base.sh"


check_prerequisites

# Crear la plantilla del router
# create_router_template

# Despliegue de router0
create_router "router0" 2200 \
  --intnets "rt0_1" "dmz" \
  --ips "10.22.0.225/30" "10.22.0.193/27" \
  --nat

# Despliegue de router1
create_router "router1" 2201 \
  --intnets "rt0_1" "rt1_2" "pl0" "privada" \
  --ips "10.22.0.226/30" "10.22.0.229/30" "10.22.0.1/25" "10.22.0.129/26" \
  --gateway "10.22.0.225"

# Despliegue de router2
create_router "router2" 2202 \
  --intnets "rt1_2" "rt2_3" "pl1" "pl2" \
  --ips "10.22.0.230/30" "10.22.0.233/30" "10.22.1.1/24" "10.22.2.1/24" \
  --gateway "10.22.0.229"

# Despliegue de router3
create_router "router3" 2203 \
  --intnets "rt2_3" "pl3" "pl3_direccio" \
  --ips "10.22.0.234/30" "10.22.3.1/25" "10.22.3.129/25" \
  --gateway "10.22.0.233"

log_info "=========================================="
log_info "[+] Routers desplegados correctamente."
log_info "=========================================="
