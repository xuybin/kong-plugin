Kong plugin template
====================

This repository contains a very simple Kong plugin template to get you
up and running quickly for developing your own plugins.

This template was designed to work with the `kong-vagrant`
[development environment](https://github.com/Mashape/kong-vagrant). Please
check out that repo's `README` for usage instructions.

# centos luarocks upload

``` bash
yum install lua luarocks lua-json

luarocks upload kong-plugin-myplugin-0.1.0-1.rockspec --api-key=***  --force
```