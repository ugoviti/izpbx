# Multi-Tenant deploy examples

Many izPBX instances on a single docker host. Every izPBX gets its own LAN IP address on a **macvlan** network, so SIP, RTP, HTTP and the other ports never collide between instances and there is no NAT between the phones and Asterisk.

Two layouts:
- [Dedicated database for every izPBX](#multi-tenant-voip-pbx-with-dedicated-databases): one directory and one `compose.yml` for every izPBX
- [Shared global database](#multi-tenant-voip-pbx-with-shared-global-database-and-single-composeyml-file): one directory and one `compose.yml` for all izPBX

## Common requirements

### One macvlan network for all izPBX instances

Docker allows only **one macvlan network for each parent interface**: a `compose.yml` that declares its own macvlan network on `eth0` works for the first izPBX only, the second one fails with `network ... is already using parent interface eth0`. Create the macvlan network once, outside compose, and use it from every izPBX as an `external` network:

```
docker network create -d macvlan \
  -o parent=eth0 \
  --subnet 10.1.1.0/24 \
  --gateway 10.1.1.1 \
  --ip-range 10.1.1.224/28 \
  izpbx-ext
```

Change according to your environment:
- `parent`: the ethernet card of the docker host connected to the LAN
- `--subnet` and `--gateway`: the LAN network range and its router (without `--gateway` docker uses the first address of the subnet)
- `--ip-range`: a block of LAN addresses reserved to izPBX, outside the range of the DHCP server of the LAN (`10.1.1.224/28` is 10.1.1.224-10.1.1.239). Every izPBX gets a fixed address from this block (`ipv4_address:`), different for every izPBX

### Default route through the LAN

Every izPBX is connected to the macvlan network (LAN) and to a bridge network (database). The default route of the container must be the LAN one, otherwise the SIP and RTP traffic leaves through the bridge with NAT. The examples set `gw_priority: 1` on the macvlan network (Docker Engine 28 or newer, Docker Compose 2.33 or newer); with an older docker remove `gw_priority`: docker then takes the default route from the network whose name comes first alphabetically, so keep the macvlan network name before the bridge one (`izpbx-ext` before `izpbx-int`, `izpbx1-db`, ...).

### Things to know about macvlan

- The docker host cannot reach the izPBX addresses on the macvlan network (and the izPBX cannot reach the host LAN address): this is how macvlan works, not an izPBX issue. Open the web interface and register the phones from another LAN host.
- All the izPBX are on the same LAN: they can reach each other on their LAN addresses, as any LAN host can. If the tenants must not see each other, filter the traffic on the LAN (VLAN, firewall), or use a VLAN sub-interface (for example `parent=eth0.100`) and a macvlan network for every tenant.
- Ports are not published (`ports:` is not needed): every izPBX service listens on its own LAN address.

## Multi-Tenant VoIP PBX with dedicated Databases

### Objective
- Many izPBX instances on a single docker host, each with its own LAN IP address
- A dedicated database container for every izPBX instance

### Configuration
Create the [macvlan network](#one-macvlan-network-for-all-izpbx-instances) (once), then a directory for every izPBX with a `compose.yml` and a `.env` file:

```
mkdir yourgreatpbx
cd yourgreatpbx
docker run --rm --pull always -v "$PWD:/deploy" docker.io/izdock/izpbx-asterisk:22.17 izpbx-deploy init
vim compose.yml
vim .env
```

`izpbx-deploy init` writes `compose.yml` and `.env` (see [izpbx-deploy](izpbx-deploy.md)); `izpbx-deploy upgrade` updates them later and keeps the changes below (local edits of `compose.yml` are merged).

Modify `compose.yml` according to your environment needs:
- `ipv4_address:` (a different LAN address for every izPBX, inside the `--ip-range` of the macvlan network)

Modify `.env` according to your environment needs:
- `MYSQL_SERVER=db` (the database container: `localhost` or `127.0.0.1` don't work here)
- `MYSQL_PASSWORD` and `MYSQL_ROOT_PASSWORD` (different for every izPBX)

```yaml
networks:
  izpbx-ext:
    external: true
  izpbx-int:
    driver: bridge

services:
  db:
    image: docker.io/mariadb:${MARIADB_VERSION:?set MARIADB_VERSION in .env}
    ## WARNING: if you upgrade image tag enter the container and run mariadb-upgrade:
    ## source .env ; docker compose exec db mariadb-upgrade -u root -p$MYSQL_ROOT_PASSWORD
    command: --sql-mode=ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION --log-warnings=1 --expire-logs-days=0
    restart: unless-stopped
    env_file:
    - .env
    volumes:
    - ./data/db:/var/lib/mysql
    networks:
      izpbx-int:

  izpbx:
    #hostname: ${APP_FQDN}
    image: docker.io/izdock/izpbx-asterisk:${IZPBX_VERSION:?set IZPBX_VERSION in .env}
    restart: unless-stopped
    depends_on:
    - db
    env_file:
    - .env
    volumes:
    - ./data/izpbx:/data
    ## fail2ban need privileged mode to manage iptables
    cap_add:
    - NET_ADMIN
    security_opt:
    - apparmor=unconfined
    privileged: true
    ulimits:
      nofile:
        soft: 8192
        hard: 32768
    networks:
      izpbx-ext:
        ipv4_address: 10.1.1.225
        gw_priority: 1
      izpbx-int:
```

With `MYSQL_ROOT_PASSWORD` set, izPBX creates its databases (`MYSQL_DATABASE`, `MYSQL_DATABASE_CDR`) and the user `MYSQL_USER` at the first start.

Repeat the procedure for every izPBX you want to deploy, in a dedicated directory: the directory name is the compose project name, so the containers and the `izpbx-int` network of every izPBX are separate (`yourgreatpbx-db-1`, `yourgreatpbx-izpbx-1`, `yourgreatpbx_izpbx-int`).

### Deploy
Enter every directory containing configuration files and run:
- `docker compose up -d`

## Multi-Tenant VoIP PBX with shared global Database and single compose.yml file

### Objective
- Many izPBX instances on a single docker host, each with its own LAN IP address
- A single global database container used by all izPBX instances

### Configuration
Create the [macvlan network](#one-macvlan-network-for-all-izpbx-instances) (once), then a directory with a `compose.yml`, a `db.env` file for the database and a `PBXNAME.env` file for every izPBX:

```
mkdir izpbx
cd izpbx
vim compose.yml
vim db.env
for n in 1 2 3; do docker run --rm --pull always -v "$PWD:/deploy" docker.io/izdock/izpbx-asterisk:22.17 izpbx-deploy init --only env --env-file izpbx$n.env; done
vim izpbx1.env
vim izpbx2.env
vim izpbx3.env
```
etc...

`db.env` (database container only):
```
TZ=Europe/Rome
MYSQL_ROOT_PASSWORD=YourRootPasswordV3ryS3cur3
```

Every `PBXNAME.env` is a [default.env](../izpbx-asterisk/rootfs/usr/local/share/izpbx/deploy/default.env) (written by `izpbx-deploy init --only env --env-file PBXNAME.env`, updated by `izpbx-deploy upgrade --only env --env-file PBXNAME.env`: this `compose.yml` is your own) with its own database, user and password (for best security use a different password for every izPBX), example for `izpbx1.env`:
```
MYSQL_SERVER=db
MYSQL_DATABASE=izpbx1_asterisk
MYSQL_DATABASE_CDR=izpbx1_asteriskcdrdb
MYSQL_USER=izpbx1_asterisk
MYSQL_PASSWORD=izpbx1_AsteriskPasswordV3ryS3cur3
MYSQL_ROOT_PASSWORD=
```

Leave `MYSQL_ROOT_PASSWORD` empty in the `PBXNAME.env` files: the root password of the shared database gives access to the databases of all the tenants. Without it izPBX does not create its databases, so create them before the first start of every izPBX (same statements izPBX runs when it has the root password):

```
docker compose up -d db
docker compose exec -T db mariadb -u root -p'YourRootPasswordV3ryS3cur3' <<'EOF'
CREATE USER IF NOT EXISTS 'izpbx1_asterisk'@'%' IDENTIFIED BY 'izpbx1_AsteriskPasswordV3ryS3cur3';
CREATE DATABASE IF NOT EXISTS `izpbx1_asterisk`;
GRANT ALL PRIVILEGES ON `izpbx1_asterisk`.* TO 'izpbx1_asterisk'@'%' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS `izpbx1_asteriskcdrdb`;
GRANT ALL PRIVILEGES ON `izpbx1_asteriskcdrdb`.* TO 'izpbx1_asterisk'@'%' WITH GRANT OPTION;
EOF
```
Repeat for `izpbx2`, `izpbx3`, etc. (If all the izPBX are yours and the isolation between them does not matter, you can instead set `MYSQL_ROOT_PASSWORD` in every `PBXNAME.env` to the value of `db.env`, and izPBX creates its databases by itself.)

Modify `compose.yml` according to your environment needs:
- `ipv4_address:` (a different LAN address for every izPBX, inside the `--ip-range` of the macvlan network)

Every izPBX has its own bridge network to the database (`izpbx1-db`, `izpbx2-db`, ...): the izPBX don't reach each other through docker networks, only the database container is connected to all of them.

```yaml
networks:
  izpbx-ext:
    external: true
  izpbx1-db:
    driver: bridge
  izpbx2-db:
    driver: bridge
  izpbx3-db:
    driver: bridge

x-izpbx: &izpbx
  #hostname: ${APP_FQDN}
  ## the series tag follows every 22.17.x release: an exact tag (22.17.N, the IZPBX_VERSION of the PBXNAME.env files) chooses when to update
  image: docker.io/izdock/izpbx-asterisk:22.17
  restart: unless-stopped
  depends_on:
  - db
  ## fail2ban need privileged mode to manage iptables
  cap_add:
  - NET_ADMIN
  security_opt:
  - apparmor=unconfined
  privileged: true
  ulimits:
    nofile:
      soft: 8192
      hard: 32768

services:
  db:
    image: docker.io/mariadb:10.11
    ## WARNING: if you upgrade image tag enter the container and run mariadb-upgrade:
    ## docker compose exec db mariadb-upgrade -u root -p
    command: --sql-mode=ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION --log-warnings=1 --expire-logs-days=0
    restart: unless-stopped
    ## only env_file here: an "environment:" list without values (- MYSQL_ROOT_PASSWORD)
    ## would override db.env with empty values, there is no .env file in this directory
    env_file:
    - db.env
    volumes:
    - ./data/db:/var/lib/mysql
    networks:
      izpbx1-db:
      izpbx2-db:
      izpbx3-db:

  izpbx1:
    <<: *izpbx
    env_file:
    - izpbx1.env
    volumes:
    - ./data/izpbx1:/data
    networks:
      izpbx-ext:
        ipv4_address: 10.1.1.225
        gw_priority: 1
      izpbx1-db:

  izpbx2:
    <<: *izpbx
    env_file:
    - izpbx2.env
    volumes:
    - ./data/izpbx2:/data
    networks:
      izpbx-ext:
        ipv4_address: 10.1.1.226
        gw_priority: 1
      izpbx2-db:

  izpbx3:
    <<: *izpbx
    env_file:
    - izpbx3.env
    volumes:
    - ./data/izpbx3:/data
    networks:
      izpbx-ext:
        ipv4_address: 10.1.1.227
        gw_priority: 1
      izpbx3-db:
```

### Deploy
Enter the directory containing configuration files and run:
- `docker compose up -d`

To add a tenant: create its `PBXNAME.env` and its databases, add its bridge network, its service and the network to the `db` service, then run `docker compose up -d` again.
