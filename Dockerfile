FROM debian:jessie

## Change apt sources to available archives
RUN echo "deb http://archive.debian.org/debian jessie main"                                             > /etc/apt/sources.list \
&&  echo "deb http://snapshot.debian.org/archive/debian/20210326T030000Z jessie main"                  >> /etc/apt/sources.list \
&&  echo "deb http://snapshot.debian.org/archive/debian-security/20210326T030000Z jessie/updates main" >> /etc/apt/sources.list \
&&  echo "deb http://snapshot.debian.org/archive/debian/20210326T030000Z jessie-updates main"          >> /etc/apt/sources.list

# persistent / runtime deps
RUN apt-get update \
&&  apt-get install -y --no-install-recommends --force-yes \
        ca-certificates \
        curl \
        librecode0 \
        libmysqlclient-dev \
        libsqlite3-0 \
        libxml2 \
&&  apt-get clean \
&&  rm -r /var/lib/apt/lists/*

# phpize deps
RUN apt-get update \
&&  apt-get install -y --no-install-recommends --force-yes \
        autoconf \
        file \
        g++ \
        gcc \
        libc-dev \
        make \
        pkg-config \
        re2c \
&&  apt-get clean \
&&  rm -r /var/lib/apt/lists/*

#<apache2>#
RUN apt-get update \
&&  apt-get install -y --no-install-recommends --force-yes \
        apache2-bin \
        apache2-dev \
        apache2.2-common \
&&  rm -rf /var/lib/apt/lists/*

RUN rm -rf /var/www/html \
&&  mkdir -p \
        /var/lock/apache2 \
        /var/run/apache2 \
        /var/log/apache2 \
        /var/www/html \
&&  chown -R www-data:www-data \
        /var/lock/apache2 \
        /var/run/apache2 \
        /var/log/apache2 \
        /var/www/html

# Apache + PHP requires preforking Apache for best results
RUN a2dismod mpm_event && a2enmod mpm_prefork

RUN mv /etc/apache2/apache2.conf /etc/apache2/apache2.conf.dist
COPY apache2.conf /etc/apache2/apache2.conf
#</apache2>#

ENV PHP_INI_DIR /etc/php5/apache2
RUN mkdir -p $PHP_INI_DIR/conf.d

## ENV GPG_KEYS 0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7 0E604491
## RUN set -xe \
##  &&  for key in $GPG_KEYS; do \
##     gpg --keyserver keys.gnupg.net --recv-keys "$key"; \
##   done

# compile openssl, otherwise --with-openssl won't work
## RUN CFLAGS="-fPIC"&&  OPENSSL_VERSION="1.0.2d" \
## &&  cd /tmp \
## &&  mkdir openssl \
## &&  curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz" -o openssl.tar.gz \
## &&  curl -sL "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz.asc" -o openssl.tar.gz.asc \
## &&  gpg --verify openssl.tar.gz.asc \
## &&  tar -xzf openssl.tar.gz -C openssl --strip-components=1 \
## &&  cd /tmp/openssl \
## &&  ./config -fPIC&&  make&&  make install \
## &&  rm -rf /tmp/*

ENV PHP_VERSION 5.4.45

# php 5.3 needs older autoconf
# --enable-mysqlnd is included below because it's harder to compile after the fact the extensions are (since it's a plugin for several extensions, not an extension in itself)
ENV buildDeps=" \
    apache2-dev \
    autoconf2.13 \
    libcurl4-openssl-dev \
    libreadline6-dev \
    librecode-dev \
    libsqlite3-dev \
##    libssl-dev \
    libxml2-dev \
    libpng-dev \
    xz-utils"

RUN set -x \
&&  apt-get update \
&&  apt-get install -y --no-install-recommends --force-yes \
        $buildDeps \
&&  rm -rf /var/lib/apt/lists/* \
&&  curl -SL "https://www.php.net/distributions/php-$PHP_VERSION.tar.gz" -o php.tar.gz \
&&  mkdir -p /usr/src/php \
&&  tar -xvxf php.tar.gz -C /usr/src/php --strip-components=1 \
&&  rm php.tar.gz \
&&  cd /usr/src/php \
&&  ./configure --disable-cgi \
        $(command -v apxs2 > /dev/null 2>&1&&  echo '--with-apxs2=/usr/bin/apxs2' || true) \
        --with-config-file-path="$PHP_INI_DIR" \
        --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
        --enable-ftp \
        --enable-mbstring \
        --enable-mysqlnd \
        --with-mysql \
        --with-mysqli \
        --with-pdo-mysql \
        --with-curl \
##        --with-openssl=/usr/local/ssl \
        --enable-soap \
        --with-png \
        --with-gd \
        --with-readline \
        --with-recode \
        --with-zlib \
&&  make -j"$(nproc)" \
&&  make install \
&&  { find /usr/local/bin /usr/local/sbin -type f -executable -exec strip --strip-all '{}' + || true; } \
&&  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
&&  make clean

RUN echo "default_charset = " > $PHP_INI_DIR/php.ini \
&&  echo "date.timezone = America/Toronto" >> $PHP_INI_DIR/php.ini

COPY docker-php-* /usr/local/bin/
COPY apache2-foreground /usr/local/bin/

WORKDIR /var/www/html

EXPOSE 80
CMD ["apache2-foreground"]
