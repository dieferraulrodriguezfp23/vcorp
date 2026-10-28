# Desplegament de la delegació 22

## Abast

Desplegament automatitzat dels quatre routers MikroTik RouterOS CHR de la
delegació 22 de VirtualCorp, amb l'adreçament `10.22.0.0/16`, connectivitat
entre routers, sortida a Internet i accés SSH per a l'administració i per al
professor.

## Topologia i adreçament

| Router | Interfície | Xarxa | Adreça |
| --- | --- | --- | --- |
| `router0` | `ether1` | NAT de gestió | DHCP `10.0.2.15/24` |
| `router0` | `ether2` | `r0-r1` | `10.22.0.225/30` |
| `router0` | `ether3` | `dmz` | `10.22.0.193/27` |
| `router1` | `ether1` | NAT de gestió | DHCP `10.0.2.15/24` |
| `router1` | `ether2` | `r0-r1` | `10.22.0.226/30` |
| `router1` | `ether3` | `r1-r2` | `10.22.0.229/30` |
| `router1` | `ether4` | `pl0` | `10.22.0.1/25` |
| `router2` | `ether1` | NAT de gestió | DHCP `10.0.2.15/24` |
| `router2` | `ether2` | `r1-r2` | `10.22.0.230/30` |
| `router2` | `ether3` | `r2-r3` | `10.22.0.233/30` |
| `router2` | `ether4` | `pl1` | `10.22.1.1/24` |
| `router2` | `ether5` | `pl2` | `10.22.2.1/24` |
| `router3` | `ether1` | NAT de gestió | DHCP `10.0.2.15/24` |
| `router3` | `ether2` | `r2-r3` | `10.22.0.234/30` |
| `router3` | `ether3` | `pl3` | `10.22.3.1/25` |
| `router3` | `ether4` | `pl3-direccio` | `10.22.3.129/25` |

Els enllaços entre routers utilitzen les xarxes punt a punt definides a
l'enunciat: `10.22.0.224/30`, `10.22.0.228/30` i `10.22.0.232/30`.

## Decisions de disseny

- **Noms dels routers**: s'utilitzen `router0`, `router1`, `router2` i
  `router3`, d'acord amb l'enunciat.
- **NIC1 de gestió**: es conserva en mode NAT a tots els routers. Això manté
  els reenviaments de port `2200`-`2203` i permet l'accés SSH des de l'amfitrió
  i des del professor. La topologia del laboratori va per `ether2` i
  posteriors.
- **Sortida a Internet**: `router0` és la passarel·la. Els routers 1 a 3 tenen
  una ruta per defecte cap a `router0` i se'ls desactiva la ruta per defecte
  que podria arribar pel client DHCP de la NIC de gestió.
- **Encaminament**: RIP amb la instància `rip1` i plantilles d'interfície per a
  les interfícies `ether2`...`etherN` de cada router.
- **NAT**: només `router0` fa `masquerade` per `ether1`.
- **Accés SSH**: l'usuari `sysadmin` té la clau ed25519 de l'estudiant;
  l'usuari `vcorp_auditor` té la clau pública del professor en grup `full`.
  L'autenticació per contrasenya SSH queda desactivada; l'accés és només per
  clau. Les contrasenyes dels usuaris es generen aleatòriament durant el
  desplegament i no es desen al repositori.
- **Claus**: les claus privades només existeixen a `~/.ssh`. Al repositori
  només hi ha claus públiques.

## Desplegament

```bash
cp .env.example .env
make ssh-keys
make deploy-routers
```

El desplegament crea les quatre VMs al grup `/VirtualCorp/Routers`, clona la
imatge CHR, fa el bootstrap de RouterOS, instal·la les claus SSH i aplica la
configuració d'adreces, rutes, RIP i NAT.

## Validació

### VMs

```bash
VBoxManage list runningvms
```

Resultat: `router0`, `router1`, `router2` i `router3` en execució.

### Adreçament

Comprovat amb `/ip address print` a cada router. Les adreces coincideixen amb
la taula anterior.

### Connectivitat entre routers

Proves `ping count=3` des de cada router cap a les adreces transit dels altres
tres. Totes les proves han retornat `received=3` i `packet-loss=0%`.

| Origen | Destins provats | Resultat |
| --- | --- | --- |
| `router0` | `10.22.0.226`, `10.22.0.230`, `10.22.0.234` | 0% de pèrdua |
| `router1` | `10.22.0.225`, `10.22.0.230`, `10.22.0.234` | 0% de pèrdua |
| `router2` | `10.22.0.225`, `10.22.0.226`, `10.22.0.234` | 0% de pèrdua |
| `router3` | `10.22.0.225`, `10.22.0.226`, `10.22.0.230` | 0% de pèrdua |

### Sortida a Internet i DNS

Des dels quatre routers:

```text
ping 1.1.1.1 count=3
ping google.com count=2
```

Resultat: `received=3` i `received=2` respectivament, amb `packet-loss=0%`.
Els servidors DNS dinàmics apunten a `10.0.2.3` (NAT de VirtualBox).

### Accés SSH

Accés d'administració:

```bash
ssh -i ~/.ssh/vcorp_sysadmin -p 2200 sysadmin@127.0.0.1
ssh -i ~/.ssh/vcorp_sysadmin -p 2201 sysadmin@127.0.0.1
ssh -i ~/.ssh/vcorp_sysadmin -p 2202 sysadmin@127.0.0.1
ssh -i ~/.ssh/vcorp_sysadmin -p 2203 sysadmin@127.0.0.1
```

Accés del professor (amb la clau privada corresponent):

```bash
ssh -i /path/to/vcorp_auditor -p 2200 vcorp_auditor@127.0.0.1
```

La clau del professor està importada als quatre routers. La petjada
`SHA256:l4PBUaqvAae9BinLB1rAZ4xd+dEG+9AQNton9AzfICg=` coincideix amb
`configs/ssh/vcorp_auditor.pub`. L'autenticació per contrasenya està
desactivada a tots els routers (`password-authentication: no`).

### Persistència

S'ha executat `/system reboot` als quatre routers. Després del reinici es
mantenen les adreces IP, les rutes per defecte, la configuració RIP, el NAT de
`router0`, les claus SSH de `sysadmin` i `vcorp_auditor` i la desactivació de
l'autenticació per contrasenya.

## Problemes trobats i resolts

1. **La clau del professor es podia sobrescriure**: `create_ssh_keys.sh`
   generava una clau `vcorp_auditor` i la copiava a `configs/ssh`, substituint
   la clau publicada pel professor. S'ha comentat la generació d'aquesta clau i
   s'ha conservat el fitxer original.
2. **Accés SSH als routers 1-3 després del desplegament**: el guió canviava la
   NIC1 de NAT a `intnet`, cosa que eliminava els reenviaments de port. S'ha
   modificat `configure_final_network()` per conservar la NIC1 en NAT com a
   interfície de gestió.
3. **Ruta per defecte duplicada**: els routers 1-3 podien rebre una ruta per
   defecte pel DHCP de la NIC de gestió. S'ha desactivat `add-default-route` i
   s'ha deixat `router0` com a única sortida a Internet.
4. **Noms dels routers**: s'han adaptat a `router0`...`router3` per complir
   l'enunciat.
5. **RouterOS exigeix contrasenya en crear usuaris**: s'ha detectat durant una
   prova de redesplegament. Els usuaris es creen amb una contrasenya aleatòria
   generada en temps d'execució i, un cop importades les claus, es desactiva
   l'autenticació per contrasenya.

## Reproducció

```bash
make delete-routers
make deploy-routers
for vm in router0 router1 router2 router3; do
  VBoxManage startvm "$vm" --type headless
done
```

No s'han de versionar mai `.env`, les claus privades, les imatges `.vdi` ni els
fitxers `.box`.
