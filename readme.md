# VirtualCorp — Delegación 22

Proyecto de la delegación 22 de VirtualCorp (`10.22.0.0/16`). El laboratorio se monta con VirtualBox, routers MikroTik RouterOS CHR y scripts Bash que se lanzan con Make.

La idea no es solo que la infraestructura funcione una vez, sino que cualquier persona pueda entenderla, montarla y mantenerla.

## Estado del proyecto

### Actividad 1 — Routers

Terminada:

- Cuatro routers MikroTik RouterOS CHR: `router0`, `router1`, `router2` y `router3`.
- Direcciones de la delegación 22 configuradas.
- Enlaces entre routers con las redes `/30` del enunciado.
- Red `privada` (`10.22.0.128/26`) conectada a `router1`.
- Solo `router0` tiene NAT y sale a Internet.
- RIP configurado entre los cuatro routers.
- Acceso SSH con clave para el alumno y para el profesor.
- Acceso SSH con contraseña desactivado.
- Probada la conectividad, la salida a Internet y el reinicio de los routers.

### Actividad 2 — Templates y equipamiento

En marcha:

- Template **Debian Server**: creado, comprobado y con snapshot `base`.
- Template **Debian Desktop**: la instalación está a medias y guardada en estado `saved`. Falta terminarla y crear el snapshot `base`.
- `pve01` con Proxmox VE 9.2-1: falta instalarlo.
- Clones enlazados del equipamiento: faltan por crear.
- `create_templates` ya funciona. `deploy_equipment` todavía no está terminado.

El detalle del estado, las pruebas y los problemas encontrados está en [`docs/deployment.md`](docs/deployment.md).

## Topología y direcciones

| Router | Puerto SSH | Interfaces y direcciones |
| --- | --- | --- |
| `router0` | `2200` | `ether2` `rt0_1`: `10.22.0.225/30`; `ether3` `dmz`: `10.22.0.193/27` |
| `router1` | — | `ether2` `rt0_1`: `10.22.0.226/30`; `ether3` `rt1_2`: `10.22.0.229/30`; `ether4` `pl0`: `10.22.0.1/25`; `ether5` `privada`: `10.22.0.129/26` |
| `router2` | — | `ether2` `rt1_2`: `10.22.0.230/30`; `ether3` `rt2_3`: `10.22.0.233/30`; `ether4` `pl1`: `10.22.1.1/24`; `ether5` `pl2`: `10.22.2.1/24` |
| `router3` | — | `ether2` `rt2_3`: `10.22.0.234/30`; `ether3` `pl3`: `10.22.3.1/25`; `ether4` `pl3_direccio`: `10.22.3.129/25` |

`router0` es la puerta de enlace a Internet y el único router con NAT. Los routers 1 a 3 tienen una ruta por defecto hacia `router0` y usan redes internas de VirtualBox.

### Subredes de la delegación

| Zona | Subred |
| --- | --- |
| Planta baja general | `10.22.0.0/25` |
| Zona privada / CPD | `10.22.0.128/26` |
| DMZ | `10.22.0.192/27` |
| Planta 1 | `10.22.1.0/24` |
| Planta 2 | `10.22.2.0/24` |
| Planta 3 | `10.22.3.0/24` |
| Dirección | `10.22.3.128/25` |
| Enlace `rt0_1` | `10.22.0.224/30` |
| Enlace `rt1_2` | `10.22.0.228/30` |
| Enlace `rt2_3` | `10.22.0.232/30` |

### Direcciones reservadas

| Equipo | Dirección |
| --- | --- |
| `pve01` | `10.22.0.133/26` |
| `dbsrv` | `10.22.0.134` |
| `infosrv` | `10.22.0.135` |
| `websrv` | `10.22.0.197` |
| `expo1`–`expo4` | `10.22.0.33`–`10.22.0.36` |
| `printer0`–`printer3` | `10.22.0.65`, `10.22.1.65`, `10.22.2.65`, `10.22.3.65` |

## Estructura del repositorio

```text
VirtualCorp-student/
├── Makefile
├── readme.md
├── .env.example
├── automation/
│   ├── scripts/bootstrap/     # Claves SSH y utilidades de arranque
│   └── ansible/               # Reservado para Ansible
├── configs/
│   ├── preseed/               # Preseeds y postinstalación de Debian
│   └── ssh/                   # Claves públicas autorizadas
├── docs/
│   ├── components.md          # Carpetas y ficheros del proyecto
│   ├── deployment.md          # Despliegue y pruebas de los routers
│   └── statement.html         # Enunciado original
└── infrastructure/
    └── bash/
        ├── common.sh
        ├── deploy_routers.sh
        ├── router_base.sh
        ├── equipment_common.sh
        └── templates/         # Creación de los templates Debian
```

## Antes de empezar

- GNU Make.
- VirtualBox con `VBoxManage` en el `PATH`.
- Cliente OpenSSH.
- `curl`, `unzip` y `sha256sum`.
- Virtualización por hardware activada en la BIOS o UEFI.

## Puesta en marcha

### 1. Configurar el entorno

```bash
cp .env.example .env
```

El fichero `.env` guarda las rutas locales, las versiones de las imágenes y los parámetros de despliegue. Git lo ignora.

### 2. Generar las claves SSH

```bash
make ssh-keys
```

Crea `vcorp_sysadmin` y `vcorp_mikrotik` en `~/.ssh` y copia sus claves públicas a `configs/ssh/`. La clave `vcorp_auditor.pub` es la del profesor y no se toca.

### 3. Desplegar los routers

```bash
make deploy-routers
```

Descarga la imagen RouterOS CHR si hace falta y crea `router0` a `router3` en el grupo `/VirtualCorp/Routers` de VirtualBox.

### 4. Comprobar el laboratorio

Arranca los routers:

```bash
for vm in router0 router1 router2 router3; do
  VBoxManage startvm "$vm" --type headless
done
```

Prueba la conexión entre routers y la salida a Internet:

```text
ping 10.22.0.226 count=4
ping 10.22.0.230 count=4
ping 10.22.0.234 count=4
ping 1.1.1.1 count=4
ping google.com count=4
```

### 5. Crear los templates Debian

```bash
make create_templates
```

Crea `debian-server-template` y `debian-desktop-template` con una instalación desatendida de Debian 13.7.0. El proceso descarga y verifica la ISO, aplica el preseed, prepara el acceso SSH y crea el snapshot `base`.

## Acceso SSH

Administración con la clave personal:

```bash
ssh -i ~/.ssh/vcorp_sysadmin -p 2200 sysadmin@127.0.0.1
```

Acceso del profesor con su clave privada:

```bash
ssh -i /ruta/a/vcorp_auditor -p 2200 vcorp_auditor@127.0.0.1
```

La autenticación por contraseña está desactivada. Solo se puede entrar con clave pública.

## Targets disponibles

```bash
make                   # muestra la ayuda
make deploy-routers    # crea y configura los routers
make delete-routers    # borra el grupo de routers
make reset-routers     # borra y vuelve a desplegar los routers
make ssh-keys          # genera las claves SSH
make routeros-box      # crea la caja de Vagrant de RouterOS (utilidad antigua)
make create_templates  # crea los templates Debian
make deploy_equipment  # previsto para desplegar el equipamiento
make delete_equipment  # previsto para borrar el equipamiento
```

## Documentación

La documentación se limita a lo necesario para montar, probar y mantener el laboratorio.

- [`docs/deployment.md`](docs/deployment.md): despliegue, direcciones y pruebas de los routers.
- [`docs/components.md`](docs/components.md): estructura y finalidad de los ficheros.
- [`docs/statement.html`](docs/statement.html): enunciado original.

## Seguridad

- Las claves privadas no se suben nunca al repositorio.
- Las contraseñas de los templates se guardan en `artifacts/secrets/`, fuera de Git.
- `.env`, las ISO, los discos de VirtualBox y las copias de seguridad tampoco se suben.
- En Git solo hay scripts, configuraciones sin secretos, claves públicas y documentación.

## Próximos pasos

1. Terminar el template Debian Desktop y crear su snapshot `base`.
2. Instalar `pve01` con Proxmox VE 9.2-1 de forma desatendida.
3. Completar `deploy_equipment` con los clones enlazados del inventario.
4. Probar redes, claves SSH, clones enlazados y virtualización anidada.
5. Actualizar la documentación y publicar el tag `deploy_equipment`.
