#!/bin/bash

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"
declare MYSRCS="$MYPATH/src"

[[ -d "$MYSRCS" ]] || mkdir "$MYSRCS"

if type git >/dev/null 2>&1; then
	if [[ -e "$MYSRCS/.git" ]]; then
		git -C $MYSRCS pull
	else
		if git clone https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git $MYSRCS; then
			echo "Git repo cloned to $MYSRCS"
		else
			echo "Failed to clone repo to $MYSRCS"
		fi
	fi
else
	wget https://kernel.org/pub/linux/utils/kernel/kexec/kexec-tools.tar.gz -O "$MYSRCS/kexec-tools.tar.gz"
	tar -C $MYSRCS -zxf $MYSRCS/kexec-tools.tar.gz
fi

