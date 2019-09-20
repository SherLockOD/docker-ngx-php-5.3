## docker-ngx-php-5.3 

### Quick start
1. Build Docker images
```
$ docker build -t ngx-php-5.3 . 
```

2. Run the Docker container
```
$ docker run -d --name my-php-5.3 -p 80:80 ngx-php-5.3
```

3. Test the container
```
$ curl -s http://localhost/info.php
```
### About Images

#### PHP
- version: 5.3.29
- extensions:
  - memcache: 2.2.5
  - yaf: 2.3.4
  - redis: 2.2.4
  - php-connect-pool
  - eaccelerator_cache
  - gd
  - mhash
  - mcrypt
  - pdo_mysql
  - mysqli
  - shmop
  - soap
  - sockets
  - sysvsem
  - "..."

#### Nginx
- version: 1.6.2

#### Supervisord
- version: 3.0
