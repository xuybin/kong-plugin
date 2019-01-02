Kong plugin template
====================

# luarocks upload kong-plugin-myplugin
``` bash
yum install lua luarocks lua-json

luarocks upload kong-plugin-myplugin-0.1.0-1.rockspec --api-key=***  --force
```

# Start Kong
first install docker
``` bash
curl -L https://github.com/docker/compose/releases/download/1.23.2/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
curl -L https://github.com/xuybin/kong-plugin/raw/master/docker-compose.yml -o docker-compose.yml
docker-compose up -d
docker-compose ps
```

# Test Loaded kong-plugin-myplugin 
``` bash
curl -i GET --url http://localhost:8001/plugins/enabled
```
