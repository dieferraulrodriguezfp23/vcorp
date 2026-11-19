# Guía completa de VirtualCorp: actividades 1 y 2

Esta guía explica cómo montar desde cero la delegación 22 de VirtualCorp, tanto si eres Diefer como si quieres repetir el procedimiento en otra delegación. Cambia el número de delegación sustituyendo `22` y `10.22` por el valor asignado.

## 1. Qué se construye

### Actividad 1

Cuatro routers MikroTik RouterOS CHR en VirtualBox:

- `router0`: enlace a Internet, DMZ y salida NAT.
- `router1`: enlace con `router0`, `router2`, planta baja y zona privada.
- `router2`: enlace con `router1`, `router3`, planta 1 y planta 2.
- `router3`: enlace con `router2`, planta 3 y zona de dirección.

Redes internas usadas:

```text
dmz
privada
pl0
pl1
pl2
pl3
pl3_direccio
rt0_1
rt1_2
rt2_3
```

### Actividad 2

- Template **Debian Server** para servidores, bases de datos, ficheros, web DMZ e impresoras.
- Template **Debian Desktop** con LXQt, LightDM y Falkon para usuarios, expositores, conserjería, desarrollo, corporativos y dirección.
- `pve01` con Proxmox VE 9.2-1 instalado de forma desatendida.
- Equipamiento desplegado mediante clones enlazados de los templates.

---

## 2. Requisitos

En Linux:

- Git.
- GNU Make.
- VirtualBox con `VBoxManage` en `PATH`.
- Cliente OpenSSH.
- `curl`, `sha256sum`, `openssl`, `bash`, `python3`, `tar`, `zstd`.
- Virtualización por hardware activada en BIOS/UEFI.

Comprobación rápida:

```bash
uname -a
git --version
make --version
VBoxManage --version
curl --version
openssl version
grep -E -m1 'vmx|svm' /proc/cpuinfo || echo 'CPU sin VMX/SVM visible'
```

Para Proxmox en VirtualBox, el host debe soportar virtualización anidada. Si falta, `pve01` se instalará pero no hará bien KVM.

---

## 3. Preparar el repositorio

### Clonar el repositorio inicial

```bash
git clone git@github.com:cbarahon/VirtualCorp-student.git
cd VirtualCorp-student
```

### Crear tu propio repo en GitHub

En GitHub crea un repositorio vacío, por ejemplo `vcorp`, sin README, `.gitignore` ni licencia.

```bash
git remote rename origin upstream
git remote add origin git@github.com:tu_usuario/vcorp.git
git push -u origin main
```

Si el repo se llama distinto, usa la URL correcta:

```bash
git remote set-url origin git@github.com:tu_usuario/vcorp.git
```

---

## 4. Actividad 1: routers

### Crear `.env`

```bash
cp .env.example .env
```

Ajusta si hace falta:

```bash
PROJECT_ROOT ?= $(CURDIR)
ARTIFACTS_DIR ?= $(PROJECT_ROOT)/artifacts
CONFIGS_DIR ?= $(PROJECT_ROOT)/configs
SSH_PRIVATE_KEY_DIR ?= $(HOME)/.ssh
VBOX_ROOT_GROUP ?= /VirtualCorp
ROUTEROS_VERSION ?= 7.21.4
```

### Generar claves SSH del proyecto

```bash
make ssh-keys
```

Resultado esperado:

- Claves privadas locales: `~/.ssh/vcorp_sysadmin`, `~/.ssh/vcorp_mikrotik`.
- Claves públicas versionadas: `configs/ssh/vcorp_sysadmin.pub`, `configs/ssh/vcorp_mikrotik.pub`.
- Clave del profesor intacta: `configs/ssh/vcorp-auditor.pub`.

No subir claves privadas a Git.

### Adaptar la delegación

Edita `infrastructure/bash/deploy_routers.sh` y cambia todas las IP de la delegación ejemplo o delegación 22 por la tuya. Para delegación 22:

| Router | Puerto NAT temporal | Redes internas | IP |
| --- | ---: | --- | --- |
| `router0` | 2200 | `rt0_1`, `dmz` | `10.22.0.225/30`, `10.22.0.193/27` |
| `router1` | 2201 durante bootstrap | `rt0_1`, `rt1_2`, `pl0`, `privada` | `10.22.0.226/30`, `10.22.0.229/30`, `10.22.0.1/25`, `10.22.0.129/26` |
| `router2` | 2202 durante bootstrap | `rt1_2`, `rt2_3`, `pl1`, `pl2` | `10.22.0.230/30`, `10.22.0.233/30`, `10.22.1.1/24`, `10.22.2.1/24` |
| `router3` | 2203 durante bootstrap | `rt2_3`, `pl3`, `pl3_direccio` | `10.22.0.234/30`, `10.22.3.1/25`, `10.22.3.129/25` |

Reglas:

- `router0` mantiene NAT permanente.
- `router1`, `router2` y `router3` usan NIC1 en una red interna sin usar y sin NAT.
- Cada router declara sus redes en `--intnets` y sus IP en `--ips`, en el mismo orden: la primera IP corresponde a `ether2`, la segunda a `ether3`, etc.

### Desplegar routers

```bash
make deploy-routers
```

El script:

1. Descarga y verifica la imagen CHR.
2. Crea las VMs en `/VirtualCorp/Routers`.
3. Arranca cada router con NAT temporal para SSH.
4. Crea usuarios `sysadmin` y `vcorp_auditor`.
5. Instala claves públicas del profesor y del alumno.
6. Apaga el router.
7. Deja solo `router0` con NAT y los demás en redes internas.
8. Arranca los cuatro routers.

```bash
for vm in router0 router1 router2 router3; do
  VBoxManage startvm "$vm" --type headless
done
```

### Validar actividad 1

SSH solo funciona directamente en `router0`:

```bash
ssh -i ~/.ssh/vcorp_sysadmin -p 2200 sysadmin@127.0.0.1
```

Dentro de `router0`:

```text
ping 10.22.0.226 count=4
ping 10.22.0.230 count=4
ping 10.22.0.234 count=4
ping 1.1.1.1 count=4
ping google.com count=4
```

Si falla un ping entre routers, revisa RIP:

```text
/routing rip instance print
/routing rip interface-template print
/ip route print
```

---

## 5. Actividad 2: templates Debian

### Versiones fijas

```text
Debian 13.7.0 amd64: debian-13.7.0-amd64-netinst.iso
SHA256: a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355
```

Estas variables están en `.env.example` y se copian a `.env`:

```bash
DEBIAN_VERSION=13.7.0
DEBIAN_ISO_FILENAME=debian-13.7.0-amd64-netinst.iso
DEBIAN_ISO_URL=https://cdimage.debian.org/debian-cd/13.7.0/amd64/iso-cd/debian-13.7.0-amd64-netinst.iso
DEBIAN_ISO_SHA256=a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355
```

### Crear templates

```bash
make create_templates
```

Puede tardar bastante. Cada template usa instalación desatendida con preseed y postinstalación.

El target crea:

- `debian-server-template`: mínimo, SSH, `sysadmin`, claves SSH, red interna `privada`, snapshot `base`.
- `debian-desktop-template`: LXQt, LightDM, Falkon, SSH, `sysadmin`, claves SSH, red interna `pl0`, snapshot `base`.

Si un template queda pausado o guardado, continúalo:

```bash
make resume_template TEMPLATE_KIND=server
make resume_template TEMPLATE_KIND=desktop
```

### Comprobar templates

Verifica que existen y tienen snapshot `base`:

```bash
VBoxManage showvminfo debian-server-template | grep -i snapshots
VBoxManage showvminfo debian-desktop-template | grep -i snapshots
```

Para comprobar Debian Desktop en vivo, puedes añadir un NIC NAT temporal solo para validación:

```bash
VBoxManage modifyvm debian-desktop-template --nic2 nat --natpf2 "ssh,tcp,127.0.0.1,2221,,22"
VBoxManage startvm debian-desktop-template --type headless
ssh -i ~/.ssh/vcorp_sysadmin -p 2221 sysadmin@127.0.0.1 'dpkg -s lxqt falkon lightdm'
VBoxManage controlvm debian-desktop-template poweroff
VBoxManage modifyvm debian-desktop-template --nic2 none
```

Al terminar, el template debe quedar sin NAT:

```bash
VBoxManage showvminfo debian-desktop-template --machinereadable | grep '^nic1='
```

---

## 6. Actividad 2: `pve01` con Proxmox VE

### Versiones fijas

```text
Proxmox VE 9.2-1: proxmox-ve_9.2-1.iso
SHA256: 4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c
```

En `.env.example`:

```bash
PROXMOX_VERSION=9.2-1
PROXMOX_ISO_URL=https://download.proxmox.com/iso/proxmox-ve_9.2-1.iso
PROXMOX_ISO_SHA256=4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c
```

### Herramientas necesarias

La instalación desatendida de Proxmox usa `proxmox-auto-install-assistant` y `xorriso`. El script las busca en `artifacts/tools/` y, si faltan, intenta descargarlas.

Si necesitas prepararlas manualmente:

```bash
mkdir -p artifacts/tools
curl -fL -o artifacts/tools/pve-assistant.deb \
  https://aptly.lf.net/nightly/debian-13-proxmox/pool/pve-no-subscription/p/proxmox-installer/proxmox-auto-install-assistant_9.2.1_amd64.deb

mkdir -p artifacts/tools/pve-assistant
bsdtar -xf artifacts/tools/pve-assistant.deb -C artifacts/tools/pve-assistant
bsdtar -xf artifacts/tools/pve-assistant/data.tar.xz -C artifacts/tools/pve-assistant

mkdir -p artifacts/tools/xorriso-root
for pkg in \
  core/os/x86_64/libxcrypt-compat-4.5.2-1-x86_64.pkg.tar.zst \
  extra/os/x86_64/libburn-1.5.8-1-x86_64.pkg.tar.zst \
  extra/os/x86_64/libisofs-1.5.8.2-2-x86_64.pkg.tar.zst \
  extra/os/x86_64/libisoburn-1.5.8.2-1-x86_64.pkg.tar.zst; do
  curl -fL -o artifacts/tools/$(basename "$pkg") "https://geo.mirror.pkgbuild.com/$pkg"
  bsdtar -xf artifacts/tools/$(basename "$pkg") -C artifacts/tools/xorriso-root
done
```

### Parámetros de `pve01`

Para delegación 22:

```bash
PVE01_NAME=pve01
PVE01_CPU=4
PVE01_MEMORY=8192
PVE01_DISK_MB=65536
PVE01_IP=10.22.0.133/26
PVE01_GATEWAY=10.22.0.129
PVE01_DNS=1.1.1.1
PVE01_NETWORK=privada
PVE01_TEMP_SSH_PORT=2222
```

Ajusta `PVE01_IP`, `PVE01_GATEWAY` y el rango si cambias de delegación.

### Instalar `pve01`

```bash
make deploy_pve01
```

El procedimiento:

1. Verifica la ISO de Proxmox.
2. Genera `artifacts/proxmox/pve01-answer.toml`.
3. Prepara una ISO autoinstalable.
4. Crea la VM `pve01` con 4 vCPU, 8 GB RAM, 64 GB de disco, `nested-hw-virt on` y NIC en `privada`.
5. Instala sin intervención.
6. Valida por SSH con un salto temporal por `router0`.
7. Comprueba Proxmox, KVM, IP, enrutamiento y ping a routers/Internet.
8. Apaga `pve01`, quita el ISO y elimina el NAT temporal.
9. Crea snapshot `installed`.

### Comprobar virtualización anidada

```bash
make deploy_equipment
ssh -i ~/.ssh/vcorp_sysadmin -p 2222 root@127.0.0.1 '
  pveversion -v | head
  egrep -c "(vmx|svm)" /proc/cpuinfo
  ls -l /dev/kvm
  lsmod | grep kvm
  qm list
'
```

Durante la validación del script se usan port-forwarding y reglas NAT temporales en `router0`. Si te quedas con la sesión abierta, revisa que al terminar no queden:

```bash
VBoxManage showvminfo router0 --machinereadable | grep 'Forwarding'
ssh -i ~/.ssh/vcorp_sysadmin -p 2200 sysadmin@127.0.0.1 '/ip firewall nat print terse'
```

Solo debe quedar el masquerade normal de `router0`.

---

## 7. Actividad 2: equipamiento

### Inventario

El fichero `configs/inventory/equipment.csv` define las máquinas. Columnas:

```text
name,template,group,network,memory,cpus
```

Ejemplos:

```text
dbsrv,server,servers,privada,1024,1
websrv,server,servers,dmz,1024,1
printer0,server,printers,pl0,512,1
expo1,desktop,desktops,pl0,2048,2
conserge1,desktop,desktops,pl0,2048,2
dev-pl1-01,desktop,desktops,pl1,2048,2
corp-pl3-01,desktop,desktops,pl3,2048,2
dir-pl3-01,desktop,direction,pl3_direccio,2048,2
```

Para otra delegación, cambia IPs y redes según tu diseño, pero mantén las redes exactas si el enunciado lo pide.

### Desplegar equipamiento

```bash
make deploy_equipment
```

Esto:

- Revisa que existan ambos templates con snapshot `base`.
- Ejecuta `deploy_pve01` si `pve01` no existe.
- Crea clones enlazados con:
  ```bash
  VBoxManage clonevm <template> --name <vm> --options link --snapshot base --basefolder <path> --register
  ```
- Ajusta RAM, CPU, grupo y NIC interna.
- Quita NAT de los clones.

### Comprobar clonación enlazada

```bash
VBoxManage list hdds | grep -A5 dbsrv
VBoxManage list hdds | grep -A5 expo1
```

El disco de cada clon debe tener un `Parent UUID` que apunte al disco base del template. Si aparece `Parent UUID: base`, no es un clon enlazado.

### Comprobar redes y NAT

```bash
for vm in dbsrv infosrv websrv printer0 expo1 dev-pl1-01 corp-pl3-01 dir-pl3-01; do
  echo "== $vm =="
  VBoxManage showvminfo "$vm" --machinereadable | grep -E '^nic1=|^intnet1=|="nat"'
done

for vm in router0 router1 router2 router3; do
  echo "== $vm =="
  VBoxManage showvminfo "$vm" --machinereadable | grep -E '^nic[1-5]=|^intnet[1-5]='
done
```

Resultado esperado:

- Ningún clon tiene `nic="nat"`.
- `router0` tiene `nic1="nat"`.
- `router1`, `router2` y `router3` no tienen NAT permanente.
- Cada equipo está en la red correspondiente.

### Arrancar y apagar pruebas

```bash
while IFS=, read -r name template group network memory cpus; do
  [[ "$name" == "name" || -z "$name" ]] && continue
  VBoxManage startvm "$name" --type headless
  sleep 3
  VBoxManage showvminfo "$name" --machinereadable | grep VMState
  VBoxManage controlvm "$name" poweroff
  sleep 1
done < configs/inventory/equipment.csv
```

---

## 8. Validación final recomendada

### Routers

```bash
for vm in router0 router1 router2 router3; do
  VBoxManage showvminfo "$vm" --machinereadable | grep '^VMState='
done
```

SSH a `router0`:

```bash
ssh -i ~/.ssh/vcorp_sysadmin -p 2200 sysadmin@127.0.0.1
```

Comandos dentro de RouterOS:

```text
/system identity print
/ip address print
/ip route print
/routing rip instance print
/ip firewall nat print
```

### Proxmox

SSH temporal o mediante el proceso de validación:

```bash
ssh -i ~/.ssh/vcorp_sysadmin -p 2222 root@127.0.0.1 '
  pveversion -v
  ls -l /dev/kvm
  egrep -c "(vmx|svm)" /proc/cpuinfo
  ip -4 addr show vmbr0
  ip route
  ping -c 2 10.22.0.129
  ping -c 2 10.22.0.225
  ping -c 2 1.1.1.1
'
```

### Equipamiento

```bash
VBoxManage list vms | sort
VBoxManage list hdds | grep -B3 -A6 'Parent UUID: 0b93\|Parent UUID: 0c4a'
```

---

## 9. Borrar y rehacer

### Borrar solo equipamiento

```bash
make delete_equipment
```

Esto borra grupos de equipamiento, no templates ni routers.

### Borrar y rehacer routers

```bash
make reset-routers
```

### Borrar y rehacer templates

Si quieres rehacer templates limpios:

```bash
VBoxManage unregistervm debian-server-template --delete
VBoxManage unregistervm debian-desktop-template --delete
make create_templates
```

### Borrar `pve01`

```bash
VBoxManage unregistervm pve01 --delete
make deploy_pve01
```

---

## 10. Errores frecuentes

| Problema | Causa | Solución |
| --- | --- | --- |
| `VBoxManage` no encontrado | VirtualBox no está instalado o no está en PATH | Instala VirtualBox y revisa `VBoxManage --version` |
| Faltan herramientas ISO o SSH | No están `curl`, `openssl`, `sha256sum`, `python3`, etc. | Instala las dependencias |
| `pve01` instalado pero KVM no funciona | No hay virtualización anidada | Activar VT-x/AMD-V, VirtualBox con nested, y revisar `egrep` y `/dev/kvm` |
| Debian Desktop arranca GDM/Firefox | Tasksel instala GNOME por defecto | Mantener `pkgsel/run_tasksel boolean false` y purga de GNOME/Firefox en postinstalación |
| LightDM no habilita | GDM dejó `/etc/systemd/system/display-manager.service` | Borrar el symlink y habilitar LightDM |
| SSH a `router1` no funciona | La NIC1 pasa a intnet sin NAT, según el enunciado | Usar consola de VirtualBox, `router0` como salto o validación temporal automatizada |
| Clones no arrancan | Snapshot `base` del template corrupto | Regenerar template y snapshot `base` |
| `deploy_equipment` no existe el script | No estaba implementado | Esta guía lo añade: `infrastructure/bash/equipment/deploy_equipment.sh` |

---

## 11. Criterios de entrega

Antes de entregar:

- GitHub actualizado con los scripts y la documentación.
- Actividad 1: cuatro routers operativos, pings entre routers, salida a Internet y claves SSH.
- Actividad 2: templates Debian creados, `pve01` con Proxmox y virtualización anidada, clones enlazados y validación documentada.
- Tag:

```bash
git tag -a deploy_equipment -m "Lliurament activitat 2: deploy_equipment"
git push origin main
git push origin deploy_equipment
```

- Comprobar que no se suben `.env`, ISOs, discos VDI, backups, claves privadas ni contraseñas.
