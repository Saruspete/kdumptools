#!/bin/bash

set -u

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"

source "$MYPATH/lib/kdump.lib"
source "$MYPATH/lib/os.lib"

declare DBUG_ARCH=""
declare DBUG_VERS=""
declare DBUG_FLAV=""
declare DBUG_PATH=""
declare DBUG_BASE=""
declare SHOW_HELP=""



function show_help {
	echo "Usage: $0 [options] <memory dump>"
	echo
}


eval set -- "$(getopt -o vqha:r:f: -l verbose,quiet,help,arch:,release:,flavor: -- "$@")"

while [[ -n "${1:-}" ]]; do
	case $1 in
		-a|--arch)		DBUG_ARCH="$2"; shift 2 ;;
		-r|--release)	DBUG_VERS="$2"; shift 2 ;;
		-f|--flavor)	DBUG_FLAV="$2";  shift 2 ;;
		-h|--help)		SHOW_HELP=1; shift ;;
		-q|--quiet)		shift ;;
		--)				shift; break ;;
		-?*)			logerror "Unknown option: '$1'"; shift ;;
		*)				break ;;
	esac
done


[[ "$SHOW_HELP" == "1" ]] && {
	show_help
	exit 0
}


