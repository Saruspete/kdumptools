#!/bin/bash

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"
declare MYSRCS="$MYPATH/src"

[[ -d "$MYSRCS" ]] || mkdir "$MYSRCS"

if type git >/dev/null 2>&1; then
	if [[ -e "$MYSRCS/.git" ]]; then
		git -C $MYSRCS pull
	else
		if git clone https://github.com/chitranshi/makedumpfile.git $MYSRCS; then
			echo "Git repo cloned to $MYSRCS"
		else
			echo "Failed to clone repo to $MYSRCS"
		fi
	fi
else
	wget https://github.com/chitranshi/makedumpfile/archive/master.zip -O "$MYSRCS/master.zip"
	unzip "$MYSRCS/master.zip" -d "$MYSRCS"
fi

