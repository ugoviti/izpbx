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
- Build from scratch Asterisk Engine
- FreePBX Engine as Web Management GUI
- Many customizable variables to use
- Two containers setup: 
  - izpbx-asterisk (Asterisk+FreePBX Frontend)
  - mariadb (Database Backend)

# How to use this image

Using docker-compose is the suggested method:

copy **default.env** in **.env** and edit the variables inside:

```
cp default.env .env
```

Start containers with:

```
docker-compose up -d
```

# Environment default variables
TODO:

# Quick reference

- **Where to get help**:
  [InitZero Corporate Support](https://www.initzero.it/)

- **Where to file issues**:
  [https://github.com/ugoviti](https://github.com/ugoviti)

- **Maintained by**:
  [Ugo Viti](https://github.com/ugoviti)

- **Supported architectures**:
  [`amd64`]

- **Supported Docker versions**:
  [the latest release](https://github.com/docker/docker-ce/releases/latest) (down to 1.6 on a best-effort basis)
