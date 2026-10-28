# VirtualCorp

VirtualCorp is a virtual networking lab for designing and deploying a branch office network. This repository deploys **delegation 22** (`10.22.0.0/16`) with four MikroTik RouterOS CHR virtual machines on VirtualBox. The deployment is automated with shell scripts and Make.

Read the [full project statement](docs/statement.html) for the scenario, requirements, and detailed assignment.

## Lab layout

| Router | SSH port | Links and addresses |
| --- | --- | --- |
| `router0` | `2200` | `r0-r1`: `10.22.0.225/30`, `dmz`: `10.22.0.193/27` |
| `router1` | `2201` | `r0-r1`: `10.22.0.226/30`, `r1-r2`: `10.22.0.229/30`, `pl0`: `10.22.0.1/25` |
| `router2` | `2202` | `r1-r2`: `10.22.0.230/30`, `r2-r3`: `10.22.0.233/30`, `pl1`: `10.22.1.1/24`, `pl2`: `10.22.2.1/24` |
| `router3` | `2203` | `r2-r3`: `10.22.0.234/30`, `pl3`: `10.22.3.1/25`, `pl3-direccio`: `10.22.3.129/25` |

`router0` is the Internet gateway. Every VM keeps NIC1 on VirtualBox NAT as an out-of-band management interface, so SSH port forwarding remains available. The lab topology uses NIC2 and later interfaces (`ether2`...). Routers 1 to 3 use `router0` as their default gateway.

## Getting started

### 1. Install prerequisites

Install GNU Make, VirtualBox with `VBoxManage`, `curl`, `unzip`, and the OpenSSH client. Make sure hardware virtualization is enabled on the host.

### 2. Adapt the environment

From the project root, create the local Make configuration and edit it for your machine:

```bash
cp .env.example .env
```

Update paths such as `PROJECT_ROOT`, `ARTIFACTS_DIR`, `CONFIGS_DIR`, and the SSH key directories as needed. The `.env` file uses GNU Make assignments and is ignored by Git.

### 3. Create the SSH keys

```bash
make ssh-keys
```

This generates the local private keys `~/.ssh/vcorp_sysadmin` and `~/.ssh/vcorp_mikrotik`, and copies their public keys to `configs/ssh/`.

`configs/ssh/vcorp_auditor.pub` is the professor's public key. It must not be overwritten or replaced; the bootstrap installs it on every router.

### 4. Create the routers

```bash
make deploy-routers
```

The deployment downloads the RouterOS CHR disk image when it is missing and creates `router0` through `router3` in VirtualBox under the `/VirtualCorp/Routers` group.

### 5. Check the lab

Confirm that all four VMs appear in VirtualBox. Start them if needed:

```bash
for vm in router0 router1 router2 router3; do
  VBoxManage startvm "$vm" --type headless
done
```

From each router, ping the other routers' transit addresses. For example, from `router0`:

```text
ping 10.22.0.226 count=4
ping 10.22.0.230 count=4
ping 10.22.0.234 count=4
```

Check Internet connectivity and DNS from each router:

```text
ping 1.1.1.1 count=4
ping google.com count=4
```

### 6. SSH access

Student administration key:

```bash
ssh -i ~/.ssh/vcorp_sysadmin -p 2200 sysadmin@127.0.0.1
ssh -i ~/.ssh/vcorp_sysadmin -p 2201 sysadmin@127.0.0.1
ssh -i ~/.ssh/vcorp_sysadmin -p 2202 sysadmin@127.0.0.1
ssh -i ~/.ssh/vcorp_sysadmin -p 2203 sysadmin@127.0.0.1
```

Password authentication is disabled; SSH access uses keys only. Professor/auditor access uses the private key that matches `configs/ssh/vcorp_auditor.pub`:

```bash
ssh -i /path/to/vcorp_auditor -p 2200 vcorp_auditor@127.0.0.1
```

The lab is ready when all four routers can reach one another, each can reach the Internet, and both SSH access methods work.

## Useful Make targets

```bash
make                 # show available targets
make deploy-routers  # create and configure the router VMs
make delete-routers  # delete the router VM group
make reset-routers   # delete and redeploy the router VMs
make ssh-keys        # generate the project SSH keys
```
