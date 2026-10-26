# syntax=docker/dockerfile:1
# P0-13: the FreePBX 17 prototype served by php-fpm instead of mod_php
# (apache mpm_event + proxy_fcgi). max_input_vars, which the admin .htaccess
# sets only under <IfModule php7_module>, is set in the fpm pool.
FROM izpbx-proto/fpbx17:17.0.33
RUN apt-get update \
 && apt-get install -y --no-install-recommends php8.2-fpm \
 && rm -rf /var/lib/apt/lists/* \
 && a2dismod -q php8.2 mpm_prefork \
 && a2enmod -q mpm_event proxy_fcgi setenvif \
 && a2enconf -q php8.2-fpm \
 && sed -i 's/^\(user\|group\|listen.owner\|listen.group\) = .*/\1 = asterisk/' /etc/php/8.2/fpm/pool.d/www.conf \
 && printf '%s\n' 'php_admin_value[max_input_vars] = 5000' >> /etc/php/8.2/fpm/pool.d/www.conf \
 && sed -i 's/^\(upload_max_filesize\|post_max_size\) = .*/\1 = 256M/; s/^memory_limit = .*/memory_limit = 512M/' /etc/php/8.2/fpm/php.ini \
 && mv /usr/local/bin/proto-install.sh /usr/local/bin/proto-install-base.sh
COPY proto-install.sh /usr/local/bin/proto-install.sh
