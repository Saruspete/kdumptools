#!/bin/bash

set -u

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"

source "$MYPATH/lib/kdump.lib"

declare    DBUG_ARCH=""
declare    DBUG_VERS=""
declare    DBUG_BASE="$MYPATH/dbg"
declare    DBUG_TEMP="$DBUG_BASE/tmp"
declare    SHOW_HELP=""
declare -l DIST_FAMI=""
declare -l DIST_FLAV=""


function show_help {
	echo "Usage: $0 -a ARCH -r RELEASE -f FAMILY -F FLAVOR"
	echo
	echo "  Options:"
	echo
}


eval set -- "$(getopt -o vqha:r:f:F: -l verbose,quiet,help,arch:,release:,family:,flavor: -- "$@")"

while [[ -n "${1:-}" ]]; do
	case $1 in
		-a|--arch)		DBUG_ARCH="$2"; shift 2 ;;
		-r|--release)	DBUG_VERS="$2"; shift 2 ;;
		-f|--family)	DIST_FAMI="$2"; shift 2 ;;
		-F|--flavor)	DIST_FLAV="$2";  shift 2 ;;
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

# Required arguments
[[ -z "$DBUG_ARCH" ]] && { logerror "Missing argument '-a|--arch'" ; exit 1 ; }
[[ -z "$DBUG_VERS" ]] && { logerror "Missing argument '-r|--release'" ; exit 1 ; }
[[ -z "$DIST_FAMI" ]] && { logerror "Missing argument '-f|--family'" ; exit 1 ; }
[[ -z "$DIST_FLAV" ]] && { logerror "Missing argument '-F|--flavor'" ; exit 1 ; }


# Create target and temp folder
[[ -d "$DBUG_BASE" ]] || mkdir -p "$DBUG_BASE" || exit 2
[[ -d "$DBUG_TEMP" ]] || mkdir -p "$DBUG_TEMP" || exit 2


function download_redhat {
	declare urlbase="$1"

	declare -i ret=0
	declare ext="$DBUG_VERS.rpm"
	declare arch="$DBUG_ARCH"
	[[ "$arch" == "i386" ]] && arch="i686"
	
	# Download rpm for kernel and kernel-common-$arch
	for url in $urlbase/kernel-debuginfo{,-common-$arch}-$ext; do
		declare fetch="$(file_fetch "$url" "$DBUG_TEMP")"
		[[ -s "$fetch" ]] || { logerror "Unable to download '$url'"; exit 1; }
		(
			cd "$DBUG_BASE"
			rpm2cpio "$fetch"|cpio -idm || exit $?
		)
		ret=ret+$?
	done

	return $ret
}



declare -i retcode=0

case $DIST_FAMI-$DIST_FLAV in
	# Test for all RPM based systems
	redhat-*)
		[[ -z "$(bin_find "rpm2cpio")" ]] && {
			logerror "Missing binary rpm2cpio. If you're not on a rpm-based system, you need this tool"
			exit 1
		}
		;;&

	redhat-fedora)
		declare arch="$DBUG_ARCH"
		declare rel="${DBUG_VERS#*.fc}"
		        rel="${rel%%.*}"
		

		#http://fedora.mirrors.ovh.net/linux/releases/21/Everything/x86_64/debug/k/kernel-debuginfo-common-x86_64-3.17.4-301.fc21.x86_64.rpm
		#http://fedora.mirrors.ovh.net/linux/updates/21/x86_64/debug/k/kernel-debuginfo-4.1.7-100.fc21.x86_64.rpm
		declare ext="$DBUG_VERS.rpm"

		# Tries releases and updates
		download_redhat "http://fedora.mirrors.ovh.net/linux/releases/$rel/Everything/$DBUG_ARCH/debug/k" "$ext" || 
		download_redhat "http://fedora.mirrors.ovh.net/linux/updates/$rel/$DBUG_ARCH/debug/k" "$ext"
		retcode=$?
		;;

	redhat-centos)
		declare arch="$DBUG_ARCH"
		declare rel="${DBUG_VERS#*.el}"
		        rel="${rel%%.*}"

		download_redhat "http://debuginfo.centos.org/$rel/$DBUG_ARCH"
		retcode="$?"
		;;

	redhat-rhel)
		logerror "Redhat doesn't provide public repositories. See https://access.redhat.com/solutions/9907"
		retcode=99
		;;

	# test for all DEB based systems
	debian-*)
		
		;;

	*)
		logerror "Unknown distribution type: '$DIST_FAMI-$DIST_FLAV'"
		exit 1
		;;

esac

exit $retcode
