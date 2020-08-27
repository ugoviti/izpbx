(re)start it from systemd:
  systemctl restart docker-compose-izdock-izpbx

status from systemd:
sudo systemctl status docker-compose-izdock-izpbx
● docker-compose-izdock-izpbx.service - docker-compose izdock-izpbx service
     Loaded: loaded (/etc/systemd/system/docker-compose-izdock-izpbx.service; disabled; vendor preset: enabled)
     Active: active (exited) since Wed 2020-08-26 18:36:21 EEST; 5min ago
    Process: 189901 ExecStart=/usr/bin/docker-compose up -d (code=exited, status=0/SUCCESS)
   Main PID: 189901 (code=exited, status=0/SUCCESS)

Αυγ 26 18:36:12 pbx1 systemd[1]: Starting docker-compose izdock-izpbx service...
Αυγ 26 18:36:13 pbx1 docker-compose[189901]: Creating network "izdock-izpbx_izpbx" with the default driver
Αυγ 26 18:36:13 pbx1 docker-compose[189901]: Creating izpbx-db ...
Αυγ 26 18:36:17 pbx1 docker-compose[189901]: [61B blob data]
Αυγ 26 18:36:21 pbx1 docker-compose[189901]: [40B blob data]
Αυγ 26 18:36:21 pbx1 systemd[1]: Finished docker-compose izdock-izpbx service.

make it autostart on boot:
  sudo systemctl enable docker-compose-izdock-izpbx


if you want to see logs from docker-compose:
  cd /home/rber/projects/izdock-izpbx
  docker-compose logs -f -t

if you want a shell in the container:
  docker-compose exec <name> /bin/sh


