# Name
izPBX Cloud Native Telephony System

# Description
(TESTING PHASE) izPBX is a Cloud Native Telephony System powered by Asterisk Engine and FreePBX Management GUI

# Supported tags
* `16.9.X-BUILD, 16.9, 16, latest`
* `17.3.X-BUILD, 17.3, 17`

Where **X** is the patch version number, and **BUILD** is the build number (look into project [Tags](/repository/docker/izdock/httpd/tags/) page to discover the latest versions)

# Features
- CentOS 8 powered
- Small image footprint
- Built from scratch Asterisk engine
- FreePBX Engine as Web Management GUI
- Persistent storage for configuration data
- Automatic HTTPS Certificate management via Let's Encrypt service
- Send out emails via local postfix smtp daemon
- Security and bruteforce SIP attacks detection managed by fail2ban service
- First automatic installation managed when deploing the izpbx, subsequent updates managed by FreePBX Version Upgrade
- All Bootstrap configurations made via single `.env` file
- Many customizable variables to use (look inside `default.env` file)
- Two containers setup:
  - izpbx-asterisk (Asterisk Engine + FreePBX Frontend)
  - mariadb (Database Backend)

# How to use this image

Using docker-compose is the suggested method:

1. Clone GIT repository:

```
git clone https://github.com/ugoviti/izdock-izpbx.git
```

3. Create file: `/etc/docker/daemon.json`

```
{
  "userland-proxy": false
}
```

3. Restart Docker Engine: `systemctl restart docker`

4. Copy **default.env** in **.env** and edit the variables inside:

```
cp default.env .env
```

5. Start izpbx deploy with:

```
docker-compose up -d
```

# Environment default variables
TODO:

# Quick reference

- **Where to get help**:
  [InitZero Corporate Support](https://www.initzero.it/)

- **Where to file issues**:
  [https://github.com/ugoviti/izdock-izpbx/issues](https://github.com/ugoviti/izdock-izpbx/issues)

- **Maintained by**:
  [Ugo Viti](https://github.com/ugoviti)

- **Supported architectures**:
  [`amd64`]

- **Supported Docker versions**:
  [the latest release](https://github.com/docker/docker-ce/releases/latest) (down to 1.6 on a best-effort basis)
