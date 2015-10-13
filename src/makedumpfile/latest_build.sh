#!/bin/bash

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"
declare MYSRCS="$MYPATH/src"

# Do the build
make -C "$MYSRCS" -j "$(grep -c processor /proc/cpuinfo)"

# Copy the version
mkdir -p $MYPATH/build/{bin,etc}
cp $MYSRCS/makedumpfile $MYPATH/build/bin
cp $MYSRCS/makedumpfile.conf $MYPATH/build/etc
