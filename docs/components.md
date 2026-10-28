# Project components

This page describes the repository's current folders and the files used by the
active router deployment workflow. The lab uses MikroTik RouterOS CHR virtual
machines in VirtualBox.

## Folder structure

```text
.
├── artifacts/
│   └── images/
│       └── chr/
├── automation/
│   ├── ansible/
│   └── scripts/
│       └── bootstrap/
├── configs/
│   └── ssh/
├── docs/
└── infrastructure/
    ├── bash/
    └── terraform/
```

| Folder | Purpose |
| --- | --- |
| `artifacts/images/chr/` | Holds the downloaded RouterOS CHR disk image and other local generated image files. Generated files are ignored by Git; `.gitkeep` preserves the directory when outputs are absent. |
| `automation/ansible/` | Reserved for Ansible automation. It currently contains only `.gitkeep`, with no playbooks or inventory files. |
| `automation/scripts/bootstrap/` | Bootstrap scripts for initial configuration of the virtual environment (before Ansible can be applied). |
| `configs/ssh/` | Public SSH keys used by the bootstrap scripts and router accounts. Private keys are stored locally, usually in `~/.ssh`. |
| `docs/` | Project documentation: assignment statement, component reference, and the delegation 22 deployment report. |
| `infrastructure/bash/` | Bash scripts that create VirtualBox routers, connect their network interfaces, and bootstrap RouterOS. |
| `infrastructure/terraform/` | Reserved for Terraform configuration. It currently contains only `.gitkeep`, with no Terraform configuration files. |

## Main files

### Repository root

| File | Functionality |
| --- | --- |
| `Makefile` | Provides the help, router deployment, deletion, reset, and SSH-key targets used by the setup workflow. It loads local settings from `.env`. |
| `.env.example` | Example Make configuration for project paths, SSH key locations, RouterOS image settings, and VirtualBox groups. Copy it to `.env` and adjust it for the local machine. |
| `.gitignore` | Excludes local settings, private credentials, generated images, VirtualBox data, and temporary files from Git. |
| `readme.md` | Project overview, prerequisites, setup steps, and a basic router connectivity check. |

### `automation/scripts/bootstrap/`

| File | Functionality |
| --- | --- |
| `create_ssh_keys.sh` | Generates the `vcorp_sysadmin` and MikroTik-compatible `vcorp_mikrotik` SSH key pairs. Private keys stay in the local SSH directory; public keys are copied to `configs/ssh/`. The professor's `vcorp_auditor.pub` key is not regenerated. |
| `create_mikrotik_box.sh` | Legacy template-packaging helper. It downloads a CHR image if needed, configures a temporary RouterOS VM, and packages it. The active router deployment workflow does not use this helper. |

### `automation/ansible/` and `infrastructure/terraform/`

Each directory currently contains only a `.gitkeep` placeholder. No Ansible playbooks or Terraform configuration files are present yet.

### `configs/ssh/`

| File | Functionality |
| --- | --- |
| `vcorp_auditor.pub` | Public key for the auditor account. |
| `vcorp_mikrotik.pub` | Public key using the MikroTik-compatible key format. |
| `vcorp_sysadmin.pub` | Public key for the sysadmin account and router bootstrap. |

### `infrastructure/bash/`

| File | Functionality |
| --- | --- |
| `common.sh` | Sets shared VirtualBox, RouterOS, path, and key settings; defines logging helpers and an SSH availability check. |
| `router_base.sh` | Provides functions to download the CHR image, create and configure router VMs and network interfaces, bootstrap RouterOS over SSH, install the student and auditor SSH keys, and apply router configuration. |
| `deploy_routers.sh` | Defines the four lab routers (`router0` through `router3`) for delegation 22 (`10.22.0.0/16`), their internal networks, IP addresses, gateways, and NAT settings, then creates them. |
| `del_vbox_group.sh` | Deletes VirtualBox VMs in a selected group and its subgroups. It supports selecting the router group or the root group. |

### `docs/`

| File | Functionality |
| --- | --- |
| `components.md` | Describes the repository structure and the purpose of its main files. |
| `deployment.md` | Describes the delegation 22 deployment, design decisions, validation results, and incidents. |
| `statement.html` | Contains the assignment scenario, requirements, and project details. |

### `artifacts/images/chr/`

| File | Functionality |
| --- | --- |
| `.gitkeep` | Keeps the output directory in Git when it has no generated images. Downloaded disk images and other generated files are local outputs and are not committed. |

## Typical workflow

1. Copy `.env.example` to `.env` and customize local paths if needed.
2. Run `make ssh-keys` to create the SSH key pairs.
3. Run `make deploy-routers` to download the CHR image when needed and create the lab routers.
4. Use `make delete-routers` or `make reset-routers` to remove or recreate the router group.
