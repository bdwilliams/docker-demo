#!/bin/sh

/etc/init.d/nginx restart
/usr/local/bin/consul-template -log-level debug -consul=$CONSUL_URL -template="/opt/nginx.template:/etc/nginx/sites-enabled/default:/etc/init.d/nginx reload"