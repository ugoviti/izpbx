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

# Install

Suggested use docker-compose:

copy **default.env** in **.env** and edit the variables inside:

```
cp default.env .env
```

Start containers with:

```
docker-compose up -d
```

