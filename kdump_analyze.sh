#!/bin/bash

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"

source "$MYPATH/lib/kdump.lib"
source "$MYPATH/lib/os.lib"

declare CORE_ARCH=""
declare CORE_VERS=""
declare CORE_PATH=""
declare DBUG_PATH=""
declare DBUG_BASE=""
declare CRSH_BIN="$(bin_find crash)"
declare CRSH_OPTS=""

while getopts ":a:r:" opt; do
	case $opt in
		a) CORE_ARCH="$OPTARG" ;;
		r) CORE_VERS="$OPTARG" ;;
	esac
done

declare OIFS=$IFS
IFS="\n"
for word in $(head -n1 $CORE_PATH|strings); do
	[[ -z "$CORE_VERS" ]] && [[ "$word" =~ ^[0-9\.\-]{3,} ]] && CORE_VERS="$word"
	[[ -z "$CORE_ARCH" ]] && [[ "$word" =~ ^[xi][0-9_]+$ ]]  && CORE_ARCH="$word"
done
IFS=$OIFS

# Remove additionnal arch version
CORE_KERNPATH="$CORE_VERS"
CORE_VERS="${CORe_VERS%%.$CORE_ARCH}"

# Display results
loginfo "Guessed kernel $CORE_VERS arch $CORE_ARCH"

declare DBUG_PATH="$DBUG_BASE/$CORE_ARCH/usr/lib/debug/lib/modules/$CORE_VERS/vmlinux"

# Check for debuginfo
[[ ! -e "$DBUG_PATH" ]] && {
	if ask_yn "Should I launch 'kdump_retrieve.sh' to get debuginfo files?"; then
		$MYPATH/kdump_retrieve.sh -v "$CORE_VERS" -a "$CORE_ARCH" -f "centos"
	else
		logerror "Couldn't find the debuginfo file in $DBUG_PATH"
		exit 1
	fi
}

$CRSH_BIN $CRSH_OPTS "$DBUG_PATH" "$CORE_PATH"
