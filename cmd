#!/usr/bin/bash

set -e

VERSION=1.2.4
PG_VERSION=13

rm -f example/*.rpm
#sudo rpm -e my_package_name 2>/dev/null || true
bundle exec exe/qrpm $@ --force -C example VERSION=$VERSION PG_VERSION=$PG_VERSION qrpm.yml 
#sudo rpm -i example/my_package_name-1.2.3-4.x86_64.rpm

