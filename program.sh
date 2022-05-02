#!/usr/bin/bash

# Ref. http://aerostitch.github.io/linux_and_unix/RedHat/build_sample_rpm.html

PKG_NAME=dummy_package
PKG_DIR=/tmp/${PKG_NAME}
mkdir -p ${PKG_DIR}

cat << __EOF__ > ${PKG_DIR}/hello_world.c
#include <stdio.h>
int main(){
  printf("Hello world!\n");
  return 0;
}
__EOF__

pushd ${PKG_DIR}/..
tar czvf ${PKG_NAME}.tar.gz ${PKG_NAME}
popd 
