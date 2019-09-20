FROM debian:jessie
MAINTAINER https://github.com/helderco/

# replace repository
RUN sed -i "s#[a-z]\+.debian.org#mirrors.163.com#g" /etc/apt/sources.list

# persistent / runtime deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      librecode0 \
      libmysqlclient-dev \
      libsqlite3-0 \
      libxml2

# phpize deps
RUN apt-get install -y --no-install-recommends \
      autoconf \
      file \
      g++ \
      gcc \
      libc-dev \
      make \
      pkg-config \
      re2c

ENV PHP_INI_DIR /usr/local/etc/php
RUN mkdir -p $PHP_INI_DIR/conf.d

ENV GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 0E604491
RUN set -xe \
  && for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done

# compile openssl, otherwise --with-openssl won't work
RUN OPENSSL_VERSION="1.0.2k" \
      && cd /tmp \
      && mkdir openssl \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
      && curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
      && gpg --verify openssl.tar.gz.asc \
      && tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
      && cd /tmp/openssl \
      && ./config && make && make install \
      && rm -rf /tmp/*

ENV PHP_VERSION 5.3.29
ENV PHP_FPM_CONF /usr/local/etc/php-fpm.d/www.conf
ENV PHP_INI_CONF /usr/local/etc/php/conf.d/php.ini

# php 5.3 needs older autoconf
# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
RUN buildDeps=" \
                autoconf2.13 \
                libcurl4-openssl-dev \
                libreadline6-dev \
                librecode-dev \
                libsqlite3-dev \
                libssl-dev \
                libxml2-dev \
                xz-utils \
                libmhash-dev \
      " \
      && set -x \
      && apt-get install -y $buildDeps --no-install-recommends \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz/from/this/mirror" -o php.tar.xz \
      && curl -SL "http://php.net/get/php-$PHP_VERSION.tar.xz.asc/from/this/mirror" -o php.tar.xz.asc \
      && gpg --verify php.tar.xz.asc \
      && mkdir -p /usr/src/php \
      && tar -xof php.tar.xz -C /usr/src/php --strip-components=1 \
      && rm php.tar.xz* \
      && cd /usr/src/php \
      && ./configure \
            --with-config-file-path="$PHP_INI_DIR" \
            --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
            --enable-fpm \
            --with-fpm-user=www-data \
            --with-fpm-group=www-data \
            --disable-cgi \
            --enable-mysqlnd \
            --with-mysql \
            --with-curl \
            --with-openssl=/usr/local/ssl \
            --with-readline \
            --with-recode \
            --with-zlib \
            --with-mhash \
      && make -j"$(nproc)" \
      && make install \
      && { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
      && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
      && make clean

COPY docker-php-* /usr/local/bin/

WORKDIR /var/www/html

ADD . /var/www/html/

# php extensions install
RUN buildDeps=" \
		libfreetype6-dev \
		libpng-dev \
		libjpeg62-turbo-dev \
		libmemcached-dev \
		zlib1g-dev \
		git \
		supervisor \
		libbz2-dev \
		openssl \
		libssl-dev \
		libmcrypt-dev \
		libxslt-dev \
    " \
    && set -ex \
        && apt-get install -y $buildDeps --no-install-recommends \
        && ln -sf /usr/include/freetype2 /usr/include/freetype2/freetype \
        && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
        && docker-php-ext-install gd

# php base extensions install
RUN set -ex \
	&& docker-php-ext-install \
	            bcmath \
	            bz2 \
	            ftp \
	            mbstring \
	            mcrypt \
	            pcntl \
	            pdo_mysql \
	            mysqli \
	            shmop \
	            soap \
	            sockets \
	            sysvsem

# php third party extensions install
RUN set -ex \
	&& cd /tmp \
	&& curl -sL -C - --retry 5 --retry-delay 3 http://pecl.php.net/get/memcache-2.2.5.tgz -o memcache-2.2.5.tgz \
	&& tar -xzf memcache-2.2.5.tgz \
	&& cd /tmp/memcache-2.2.5 \
	&& phpize \
    	&& ./configure && make && make install \
    	&& rm -rf /tmp/memcache-2.2.5* \
    	&& echo 'extension="memcache.so"' >> $PHP_INI_CONF \
	\
	&& cd /tmp \
	&& curl -sL -C - --retry 5 --retry-delay 3 http://pecl.php.net/get/yaf-2.3.4.tgz -o yaf-2.3.4.tgz\
	&& tar -xzf yaf-2.3.4.tgz \
	&& cd /tmp/yaf-2.3.4 \
	&& phpize \
    	&& ./configure && make && make install \
    	&& rm -rf /tmp/yaf-2.3.4* \
    	&& echo 'extension="yaf.so"' >> $PHP_INI_CONF \
	\
	&& cd /tmp \
	&& curl -sL -C - --retry 5 --retry-delay 3 http://pecl.php.net/get/redis-2.2.4.tgz -o redis-2.2.4.tgz \
	&& tar -xzf redis-2.2.4.tgz \
	&& cd /tmp/redis-2.2.4 \
	&& phpize \
    	&& ./configure && make && make install \
    	&& rm -rf /tmp/redis-2.2.4* \
    	&& echo 'extension="redis.so"' >> $PHP_INI_CONF \
	\
	&& cd /tmp \
	&& git clone https://github.com/GXhua/php-connect-pool.git \
	&& cd php-connect-pool \
	&& phpize \
    	&& ./configure && make && make install \
    	&& rm -rf /tmp/php-connect-pool \
    	&& echo 'extension="connect_pool.so"' >> $PHP_INI_CONF \
	\
    	&& cd /tmp \
    	&& mkdir eaccelerator_cache \
	&& chmod 777 eaccelerator_cache \
	&& git clone https://github.com/eaccelerator/eaccelerator.git \
	&& cd eaccelerator \
	&& phpize \
	&& ./configure --enable-eaccelerator=shared --with-php-config=/usr/local/bin/php-config && make && make install \
	&& { \
		echo '[eaccelerator]'; \
        	echo 'extension="eaccelerator.so"'; \
        	echo 'eaccelerator.cache_dir="/tmp/eaccelerator_cache"'; \
        	echo 'eaccelerator.shm_size="0"'; \
        	echo 'eaccelerator.enable="1"'; \
        	echo 'eaccelerator.optimizer="1"'; \
        	echo 'eaccelerator.check_mtime="1"'; \
        	echo 'eaccelerator.debug="0"'; \
        	echo 'eaccelerator.shm_max="0"'; \
        	echo 'eaccelerator.shm_ttl="360"'; \
        	echo 'eaccelerator.shm_prune_period="3600"'; \
        	echo 'eaccelerator.shm_only="0"'; \
        	echo 'eaccelerator.compress="1"'; \
        	echo 'eaccelerator.compress_level="9"'; \
	} | tee $PHP_INI_DIR/conf.d/eaccelerator.ini \
	&& rm -rf /tmp/eaccelerator

# php-fpm configuration
RUN set -ex \
  && cd /usr/local/etc \
  && if [ -d php-fpm.d ]; then \
    # for some reason, upstream's php-fpm.conf.default has "include=NONE/etc/php-fpm.d/*.conf"
    sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
    cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
  else \
    # PHP 5.x don't use "include=" by default, so we'll create our own simple config that mimics PHP 7+ for consistency
    mkdir php-fpm.d; \
    cp php-fpm.conf.default php-fpm.d/www.conf; \
    { \
      echo '[global]'; \
      echo 'daemonize = no'; \
      echo 'error_log = /dev/stderr'; \
      echo 'emergency_restart_threshold = 10'; \
      echo 'emergency_restart_interval = 10m'; \
      echo 'process_control_timeout = 5s'; \
      echo 'include=etc/php-fpm.d/*.conf'; \
    } | tee php-fpm.conf; \
  fi

# fix some weird corruption in this file
RUN set -ex; \
	    sed -i -e "" $PHP_FPM_CONF; \
	    sed -i "s|listen = .*|listen = 9000|" $PHP_FPM_CONF; \
	    sed -i "s|;slowlog = .*|slowlog = /dev/stderr|" $PHP_FPM_CONF; \
	    sed -i "s|;request_slowlog_timeout = .*|request_slowlog_timeout = 20s|" $PHP_FPM_CONF; \
	    sed -i "s|;listen.backlog = .*|listen.backlog = 4096|" $PHP_FPM_CONF; \
	    sed -i "s|;rlimit_files = .*|rlimit_files = 51200|" $PHP_FPM_CONF; \
	    sed -i "s|;rlimit_core = .*|rlimit_core = 0|" $PHP_FPM_CONF; \
	    sed -i "s|pm.max_children = .*|pm.max_children = 14|" $PHP_FPM_CONF; \
	    sed -i "s|pm.start_servers = .*|pm.start_servers = 6|" $PHP_FPM_CONF; \
	    sed -i "s|pm.min_spare_servers = .*|pm.min_spare_servers = 3|" $PHP_FPM_CONF; \
	    sed -i "s|pm.max_spare_servers = .*|pm.max_spare_servers = 10|" $PHP_FPM_CONF; \
	    sed -i "s|;pm.max_requests = .*|pm.max_requests = 512|" $PHP_FPM_CONF; \
	    sed -i "s|;catch_workers_output = yes|catch_workers_output = yes|g" $PHP_FPM_CONF;

# install nginx
RUN apt-get install -y --no-install-recommends \
      nginx-full \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && apt-get clean \
    && rm -r /var/lib/apt/lists/*

# nginx configuration
COPY nginx.conf /etc/nginx/
COPY default.conf /etc/nginx/conf.d/
COPY supervisord.conf /etc/supervisor/

EXPOSE 9000 80

ENTRYPOINT ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
