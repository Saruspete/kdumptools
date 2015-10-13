#!/bin/bash

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"
declare MYSRCS="$MYPATH/src"

#Require :
# wget, gcc, zlib-devel, ncurses-devel, bison

# Do the build
(
	cd "$MYSRCS"
	./bootstrap && ./configure && make -j "$(grep -c processor /proc/cpuinfo)"
)

# Copy the version
cp -r $MYSRCS/build $MYPATH/
