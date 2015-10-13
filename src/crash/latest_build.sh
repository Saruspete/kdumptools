#!/bin/bash

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"
declare MYSRCS="$MYPATH/src"

#Require:    wget, gcc, zlib-devel, ncurses-devel, bison
#Recommands: lzo-devel, snappy-devel
#

# Do the build
make -C "$MYSRCS" -j "$(grep -c processor /proc/cpuinfo)"
make -C "$MYSRCS" -j "$(grep -c processor /proc/cpuinfo)" extensions
make -C "$MYSRCS" -j "$(grep -c processor /proc/cpuinfo)" memory_driver

# Copy the version
mkdir -p $MYPATH/build/{bin,lib,kmod}
cp $MYSRCS/crash $MYPATH/build/bin
cp $MYSRCS/memory_driver/crash.ko $MYPATH/build/kmod
cp $MYSRCS/extensions/*.so $MYPATH/build/lib
