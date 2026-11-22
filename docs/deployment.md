# Despliegue de la delegación 22

## Qué se despliega

Cuatro routers MikroTik RouterOS CHR para la delegación 22 de VirtualCorp, con el rango `10.22.0.0/16`, conexión entre routers, salida a Internet y acceso SSH para el alumno y el profesor.

## Topología y direcciones

| Router | Interfaz | Red | Dirección |
| --- | --- | --- | --- |
| `router0` | `ether1` | NAT de gestión | DHCP `10.0.2.15/24` |
| `router0` | `ether2` | `rt0_1` | `10.22.0.225/30` |
| `router0` | `ether3` | `dmz` | `10.22.0.193/27` |
| `router1` | `ether1` | Sin NAT | Red interna sin usar |
| `router1` | `ether2` | `rt0_1` | `10.22.0.226/30` |
| `router1` | `ether3` | `rt1_2` | `10.22.0.229/30` |
| `router1` | `ether4` | `pl0` | `10.22.0.1/25` |
| `router1` | `ether5` | `privada` | `10.22.0.129/26` |
| `router2` | `ether1` | Sin NAT | Red interna sin usar |
| `router2` | `ether2` | `rt1_2` | `10.22.0.230/30` |
| `router2` | `ether3` | `rt2_3` | `10.22.0.233/30` |
| `router2` | `ether4` | `pl1` | `10.22.1.1/24` |
| `router2` | `ether5` | `pl2` | `10.22.2.1/24` |
| `router3` | `ether1` | Sin NAT | Red interna sin usar |
| `router3` | `ether2` | `rt2_3` | `10.22.0.234/30` |
| `router3` | `ether3` | `pl3` | `10.22.3.1/25` |
| `router3` | `ether4` | `pl3_direccio` | `10.22.3.129/25` |

Los enlaces entre routers usan las redes punto a punto del enunciado: `10.22.0.224/30`, `10.22.0.228/30` y `10.22.0.232/30`.

## Decisiones de diseño

- **Nombres de los routers**: `router0`, `router1`, `router2` y `router3`, como pide el enunciado.
- **NAT**: solo `router0` tiene NAT y sale a Internet. Los routers 1 a 3 dejan `ether1` en una red interna sin usar y desconectada, como pide la actividad 2.
- **Salida a Internet**: los routers 1 a 3 tienen una ruta por defecto hacia `router0`. Se desactiva la ruta por defecto que podría llegar por DHCP.
- **Encaminamiento**: RIP con la instancia `rip1` y plantillas para las interfaces `ether2`...`etherN`.
- **NAT de salida**: solo `router0` hace `masquerade` por `ether1`.
- **Acceso SSH**: `sysadmin` usa la clave ed25519 del alumno y `vcorp_auditor` la clave pública del profesor. La autenticación por contraseña está desactivada.
- **Contraseñas**: se generan al azar durante el despliegue y no se guardan en el repositorio.
- **Claves**: las privadas solo están en `~/.ssh`. En el repositorio solo hay claves públicas.

## Cómo desplegar

```bash
cp .env.example .env
make ssh-keys
make deploy-routers
```

El despliegue crea las cuatro máquinas en el grupo `/VirtualCorp/Routers`, clona la imagen CHR, hace el bootstrap de RouterOS, instala las claves SSH y aplica direcciones, rutas, RIP y NAT.

## Pruebas

### Máquinas virtuales

```bash
VBoxManage list runningvms
```

Deben aparecer `router0`, `router1`, `router2` y `router3` en ejecución.

### Direcciones

Se comprobó con `/ip address print` en cada router. Las direcciones coinciden con la tabla de arriba.

### Conexión entre routers

Se hicieron pruebas `ping count=3` desde cada router a las direcciones de tránsito de los otros tres. Todas dieron `received=3` y `packet-loss=0%`.

| Origen | Destinos probados | Resultado |
| --- | --- | --- |
| `router0` | `10.22.0.226`, `10.22.0.230`, `10.22.0.234` | 0 % de pérdida |
| `router1` | `10.22.0.225`, `10.22.0.230`, `10.22.0.234` | 0 % de pérdida |
| `router2` | `10.22.0.225`, `10.22.0.226`, `10.22.0.234` | 0 % de pérdida |
| `router3` | `10.22.0.225`, `10.22.0.226`, `10.22.0.230` | 0 % de pérdida |

### Internet y DNS

Desde los cuatro routers:

```text
ping 1.1.1.1 count=3
ping google.com count=2
```

Resultado: `received=3` y `received=2`, con `packet-loss=0%`. Los DNS dinámicos apuntan a `10.0.2.3`, el NAT de VirtualBox.

### Acceso SSH

Administración:

```bash
ssh -i ~/.ssh/vcorp_sysadmin -p 2200 sysadmin@127.0.0.1
```

Profesor:

```bash
ssh -i /ruta/a/vcorp_auditor -p 2200 vcorp_auditor@127.0.0.1
```

La clave del profesor está importada en `router0`. Su huella `SHA256:l4PBUaqvAae9BinLB1rAZ4xd+dEG+9AQNton9AzfICg=` coincide con `configs/ssh/vcorp_auditor.pub`. La autenticación por contraseña está desactivada en todos los routers.

### Reinicio

Se ejecutó `/system reboot` en los cuatro routers. Después del reinicio se mantienen las direcciones, las rutas por defecto, RIP, el NAT de `router0`, las claves SSH y la autenticación por contraseña desactivada.

## Estado de la actividad 2

Actividad 2 terminada y validada en la delegación 22:

- **Template Debian Server**: creado con `VBoxManage unattended install`, SSH, claves del profesor y del alumno, `pkgsel/run_tasksel boolean false` para no instalar GNOME por defecto y snapshot `base`.
- **Template Debian Desktop**: instalado con LXQt, LightDM y Falkon. Se corrigió el conflicto entre GDM y LightDM, se purgaron Firefox/LibreOffice/GNOME innecesario y se creó el snapshot `base`.
- **`pve01`**: instalado desatendidamente con Proxmox VE 9.2-1 mediante `proxmox-auto-install-assistant prepare-iso --fetch-from iso`. Tiene IP estática `10.22.0.133/26`, gateway `10.22.0.129`, virtualización anidada (`nested-hw-virt on`, `/dev/kvm`, `kvm_amd`) y snapshot `installed`.
- **Equipamiento**: `deploy_equipment` crea 28 máquinas Debian con clonación enlazada desde los templates, sin NAT y con las redes internas exactas del enunciado.
- **Validación**: todos los clones arrancan, los discos enlazados tienen `Parent UUID` correcto, solo `router0` conserva NAT y `pve01` hace ping a los cuatro routers y a una IP pública.

La guía completa para recrear las actividades 1 y 2 está en [`guia-actividades-1-2.md`](guia-actividades-1-2.md).

## Estado de la actividad 3

Actividad 3 terminada y validada:

- Ansible está instalado en el nodo de control y gestiona las VMs con `VBoxManage`.
- `automation/ansible/playbooks/start_routers.yml` arranca `router0`-`router3`.
- `automation/ansible/playbooks/stop_routers.yml` los apaga ordenadamente con ACPI.
- Los playbooks son idempotentes: una segunda ejecución no reinicia routers ya encendidos ni apaga routers ya apagados.
- `automation/ansible/playbooks/configure_wireguard.yml` crea o corrige en `router0`:
  - interfaz WireGuard `wg1`,
  - dirección túnel `10.22.10.1/24`,
  - peer del cliente `10.22.10.2/32`,
  - reglas de firewall para UDP 51820 y forward restringido,
  - plantilla RIP para que las rutas de retorno se propaguen.
- El cliente se genera en `artifacts/vpn/`, fuera de Git.
- La validación con `pve01` como cliente temporal muestra handshake y ping correcto a `10.22.10.1` y a los cuatro routers internos.
- El playbook de prueba abre SSH temporal hacia `pve01` mediante un salto NAT por `router0` y lo limpia al terminar.

## Problemas encontrados y soluciones

1. **La clave del profesor se podía sobrescribir**: `create_ssh_keys.sh` generaba una clave `vcorp_auditor` y podía sustituir la del profesor. Se comentó esa generación y se conservó el fichero original.
2. **No se podía entrar por SSH a los routers 1-3 después del despliegue**: el script cambiaba la NIC1 de NAT a `intnet` y perdía el reenvío de puerto. Se cambió `configure_final_network()` para dejar NAT solo en `router0`.
3. **Ruta por defecto duplicada**: los routers 1-3 podían recibir otra ruta por DHCP. Se desactivó `add-default-route` y `router0` quedó como única salida a Internet.
4. **Nombres de los routers**: se adaptaron a `router0`...`router3` para cumplir el enunciado.
5. **RouterOS pide contraseña al crear usuarios**: se crean con una contraseña aleatoria y, cuando las claves ya están importadas, se desactiva el acceso por contraseña.
6. **El instalador de Debian Desktop arrastraba GNOME y Firefox**: el preseed no desactivaba tasksel y metía `task-gnome-desktop`. Se añadió `pkgsel/run_tasksel boolean false` y la postinstalación purga `firefox-esr`, `gdm3`, `gnome`, `gnome-core` y `task-gnome-desktop`.
7. **LightDM fallaba al habilitarse porque GDM ya existía**: se elimina el symlink de `display-manager.service` antes de habilitar LightDM.
8. **La validación de `pve01` no era accesible desde el host porque el enunciado prohíbe NAT en todas menos `router0`**: se validó con un reenvío temporal en `router0` y reglas NAT locales en el router, eliminándolas después. El script usa ahora ese salto temporal automatizado y lo limpia al terminar.
9. **El snapshot de los templates se comprobaba con una búsqueda demasiado estricta**: el parseo de `VBoxManage snapshot list` usa ahora `Name: base` en lugar de `"base"`.
10. **`community.routeros.command` colgaba consultando `routerboard print` en CHR**: para tareas de RouterOS en este host se usa SSH controlado desde Ansible con `ansible.builtin.command`, manteniendo comprobaciones previas para ser idempotente.
11. **RouterOS rechaza claves base64 sin comillas en `private-key` y `public-key`**: las órdenes de alta de interfaz y peer ahora entrecomillan las claves.
12. **El cliente interno de prueba perdía el acceso SSH por routing loop**: se ajustaron `AllowedIPs` del cliente interno para no enrutar por la VPN la red de tránsito usada como endpoint.

## Copias de seguridad

Hay que proteger `.env`, las claves de `SSH-keys/`, las contraseñas de `artifacts/secrets/`, las ISO y los discos de las máquinas virtuales. La copia se guarda fuera del repositorio, junto con un archivo comprimido del proyecto.

Para restaurar:

1. Copia el proyecto y las claves a `~/.ssh` con permisos `600`.
2. Revisa las rutas absolutas de `.env`.
3. Registra las máquinas con `VBoxManage registervm`.
4. Comprueba el acceso SSH y arranca los routers.

No subas a Git las copias de seguridad, las claves privadas ni los discos de VirtualBox.

## Repetir el despliegue

```bash
make delete-routers
make deploy-routers
for vm in router0 router1 router2 router3; do
  VBoxManage startvm "$vm" --type headless
done
```

No subas nunca a Git `.env`, las claves privadas, las imágenes `.vdi` ni los ficheros `.box`.
