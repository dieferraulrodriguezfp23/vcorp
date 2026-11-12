# Componentes del proyecto

Este documento explica qué hay en cada carpeta y para qué sirve cada fichero importante. El laboratorio usa máquinas de VirtualBox: routers MikroTik RouterOS CHR, templates Debian y, más adelante, el equipamiento de la delegación.

## Carpetas

```text
.
├── artifacts/
│   ├── images/
│   │   ├── chr/
│   │   ├── debian/
│   │   └── proxmox/
│   ├── preseed/
│   ├── secrets/
│   └── tools/
├── automation/
│   ├── ansible/
│   └── scripts/
│       └── bootstrap/
├── configs/
│   ├── preseed/
│   └── ssh/
├── docs/
└── infrastructure/
    ├── bash/
    │   └── templates/
    └── terraform/
```

| Carpeta | Para qué sirve |
| --- | --- |
| `artifacts/images/chr/` | Guarda la imagen de RouterOS CHR y otros ficheros generados. Git no los versiona; `.gitkeep` mantiene la carpeta. |
| `artifacts/images/debian/` | Guarda la ISO de Debian y los ficheros que se crean al hacer los templates. |
| `artifacts/images/proxmox/` | Guarda la ISO de Proxmox VE y la ISO preparada para instalar sin asistente. |
| `artifacts/preseed/` | Scripts de postinstalación generados a partir de `configs/preseed/`. |
| `artifacts/secrets/` | Contraseñas aleatorias de los templates. Git no las versiona. |
| `artifacts/tools/` | Herramientas locales para preparar Proxmox cuando no están en el sistema. |
| `automation/ansible/` | Reservado para Ansible. Ahora solo tiene `.gitkeep`. |
| `automation/scripts/bootstrap/` | Scripts de arranque anteriores a Ansible. |
| `configs/preseed/` | Preseeds de Debian Server y Desktop y plantilla de postinstalación. |
| `configs/ssh/` | Claves públicas que usan los scripts y las cuentas de los equipos. Las privadas están en `~/.ssh`. |
| `docs/` | Documentación: enunciado, componentes y despliegue. |
| `infrastructure/bash/` | Scripts que crean las máquinas, conectan las redes y configuran RouterOS y los templates. |
| `infrastructure/bash/templates/` | Scripts para crear y preparar los templates Debian. |
| `infrastructure/terraform/` | Reservado para Terraform. Ahora solo tiene `.gitkeep`. |

## Ficheros principales

### Raíz del repositorio

| Fichero | Para qué sirve |
| --- | --- |
| `Makefile` | Tiene los targets de ayuda, despliegue, borrado, claves SSH y templates. Carga la configuración de `.env`. |
| `.env.example` | Ejemplo de configuración: rutas, claves, versiones de imágenes, grupos de VirtualBox y parámetros de los templates. Se copia a `.env`. |
| `.gitignore` | Evita subir configuración local, claves privadas, imágenes, datos de VirtualBox, backups y temporales. |
| `readme.md` | Presentación, estado, requisitos, puesta en marcha y pruebas básicas. |

### `automation/scripts/bootstrap/`

| Fichero | Para qué sirve |
| --- | --- |
| `create_ssh_keys.sh` | Crea `vcorp_sysadmin` y `vcorp_mikrotik`. Las privadas se quedan en `~/.ssh` y las públicas se copian a `configs/ssh/`. La clave del profesor no se regenera. |
| `create_mikrotik_box.sh` | Utilidad antigua para empaquetar RouterOS como caja de Vagrant. El despliegue actual no la usa. |

### `automation/ansible/` e `infrastructure/terraform/`

Solo tienen un `.gitkeep`. Todavía no hay playbooks de Ansible ni configuración de Terraform.

### `configs/preseed/`

| Fichero | Para qué sirve |
| --- | --- |
| `debian-server-preseed.cfg` | Respuestas del instalador para Debian Server. Instala lo mínimo y SSH. |
| `debian-desktop-preseed.cfg` | Respuestas del instalador para Debian Desktop. Instala LXQt, LightDM y Falkon. |
| `debian-postinstall.sh.tmpl` | Plantilla de postinstalación basada en la de VirtualBox. Añade las claves SSH, la seguridad de SSH y el target por defecto. |

### `configs/ssh/`

| Fichero | Para qué sirve |
| --- | --- |
| `vcorp-auditor.pub` | Clave pública del profesor con el nombre del enunciado. |
| `vcorp_auditor.pub` | La misma clave, con el nombre que ya tenía el repositorio. |
| `vcorp_mikrotik.pub` | Clave pública compatible con RouterOS. |
| `vcorp_sysadmin.pub` | Clave pública de `sysadmin` y del bootstrap de los routers. |

### `infrastructure/bash/`

| Fichero | Para qué sirve |
| --- | --- |
| `common.sh` | Configuración común de VirtualBox, RouterOS, rutas y claves; funciones de log y de espera de SSH. |
| `router_base.sh` | Descarga CHR, crea las VMs y sus redes, hace el bootstrap por SSH, instala las claves y aplica la configuración. |
| `deploy_routers.sh` | Define los cuatro routers de la delegación 22 con sus redes, direcciones, puertas de enlace y NAT. |
| `equipment_common.sh` | Funciones para descargar y verificar imágenes, comprobar VMs, esperar el apagado y probar SSH con clave. |
| `del_vbox_group.sh` | Borra las VMs de un grupo de VirtualBox y de sus subgrupos. Puede borrar routers o todo el grupo raíz. |

### `infrastructure/bash/templates/`

| Fichero | Para qué sirve |
| --- | --- |
| `template_base.sh` | Crea los templates Debian: descarga y verifica la ISO, crea la VM, instala sin asistente, comprueba, apaga, cambia la red y crea el snapshot `base`. |
| `create_templates.sh` | Punto de entrada de `make create_templates`. Permite crear el de servidor, el de escritorio o los dos. |

### `docs/`

| Fichero | Para qué sirve |
| --- | --- |
| `components.md` | Este documento: estructura y finalidad de los ficheros. |
| `deployment.md` | Despliegue de la delegación 22, decisiones, pruebas y problemas. |
| `statement.html` | Enunciado original del proyecto. |

### `artifacts/images/chr/`

| Fichero | Para qué sirve |
| --- | --- |
| `.gitkeep` | Mantiene la carpeta en Git cuando no hay imágenes. Las imágenes y los discos no se versionan. |

## Flujo de trabajo

1. Copia `.env.example` a `.env` y cambia las rutas si hace falta.
2. Ejecuta `make ssh-keys` para crear las claves.
3. Ejecuta `make deploy-routers` para descargar CHR y crear los routers.
4. Ejecuta `make create_templates` para crear los templates Debian.
5. Usa `make delete-routers` o `make reset-routers` para borrar o rehacer los routers.
6. Completa `make deploy_equipment` para crear los clones del equipamiento.
