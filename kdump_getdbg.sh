#!/bin/bash

set -u

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"

source "$MYPATH/lib/main.lib"

declare    DBUG_ARCH=""
declare    DBUG_VERS=""
declare    DBUG_BASE="$MYPATH/dbg"
declare    DBUG_TEMP="$DBUG_BASE/tmp"
declare    SHOW_HELP=""
declare -l DIST_NAME=""
declare    REPO_LOCAL=""

function show_help {
	echo "Usage: $0 -a ARCH -r RELEASE -o OSNAME [-l LOCALREPO]"
	echo
	echo "  Options:"
	echo "  OSNAME in:"
	echo "    redhat-redhat"
	echo "    redhat-fedora"
	echo "    redhat-centos"
	echo
	echo "    debian-debian"
	echo "    debian-ubuntu"
	echo
	echo "    "
}


eval set -- "$(getopt -o vqha:r:o:l: -l verbose,quiet,help,arch:,release:,osname:,localrepo: -- "$@")"

while [[ -n "${1:-}" ]]; do
	case $1 in
		-a|--arch)		DBUG_ARCH="$2"; shift 2 ;;
		-r|--release)	DBUG_VERS="$2"; shift 2 ;;
		-o|--osname)	DIST_NAME="$2"; shift 2 ;;
		-l|--localrepo)	REPO_LOCAL="$2"; shift 2 ;;
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
declare misarg=""
[[ -z "$DBUG_ARCH" ]] && { misarg="${misarg}\n '-a|--arch'" ; }
[[ -z "$DBUG_VERS" ]] && { misarg="${misarg}\n '-r|--release'" ; }
[[ -z "$DIST_NAME" ]] && { misarg="${misarg}\n '-o|--osname'" ; }
[[ -n "$misarg" ]] && {
	logerror "Missing arugments: $misarg"
	exit 1
}

# Create target and temp folder
[[ -d "$DBUG_BASE" ]] || mkdir -p "$DBUG_BASE" || exit 2
[[ -d "$DBUG_TEMP" ]] || mkdir -p "$DBUG_TEMP" || exit 2


#
# Extraction of packages
#
function extract_rpm {
	declare src="$1"
	declare dst="$2"

	loginfo "Extracting package '$src' to '$dst'"
	(
		cd "$dst"
		rpm2cpio "$src"|cpio -idm || return 1
	)
	return $?
}

function extract_deb {
	declare src="$1"
	declare dst="$2"
	declare _r=0

	loginfo "Extracting package '$src' to '$dst'"

	# dpkg if available
	if [[ -n "$(bin_find dpkg-deb)" ]]; then
		dpkg-deb -x "$file" "$DBUG_BASE"
		_r=$?

	# ar + tar else
	elif [[ -n "$(bin_find ar)" ]]; then
		ar p "$file" "data.tar.gz" | tar -C "$DBUG_BASE" -zx
		_r=$?

	# Well, now I can't do anything for you
	else
		logerror "You need 'dpkg' or 'ar' + 'tar' to extract debian packages"
		_r=1
	fi

	return $_r
}

function download_redhat {
	declare urlbase="$1"

	declare -i ret=0
	declare arch="$DBUG_ARCH"
	[[ "$arch" == "i386" ]] && arch="i686"

	# Download rpm for kernel and kernel-common-$arch
	declare ext="$DBUG_VERS.$arch.rpm"
	for url in $urlbase/kernel-debuginfo{,-common-$arch}-$ext; do
		loginfo "Downloading '$url' (this may not be the good one)"
		declare fetch="$(file_fetch "$url" "$DBUG_TEMP")"
		[[ -s "$fetch" ]] || { logerror "Unable to download '$url'"; return 1; }
		# Extract it
		extract_rpm "$fetch" "$DBUG_BASE"
		ret=ret+$?
	done

	return $ret
}

function download_suse {
	declare urlbase="$1"

	declare -i ret=0
	declare arch="$DBUG_ARCH"
	[[ "$arch" == "i386" ]] && arch="i686"

	declare flv="${DBUG_VERS##*-}"
	declare ver="${DBUG_VERS%-$flv}"

	# Download packages debuginfo and base-debuginfo
	for url in $urlbase/kernel-$flv-{,base-}debuginfo-$ver.$arch.rpm; do
		loginfo "Downloading '$url'"
		declare fetch="$(file_fetch "$url" "$DBUG_TEMP")"
		[[ -s "$fetch" ]] || { logerror "Unable to download '$url'"; return 1; }
		# Extract it
		extract_rpm "$fetch" "$DBUG_BASE"
		ret=ret+$?
	done
}

function download_debian {
	declare urlbase="$1"

	declare -i ret=0
	declare arch="$DBUG_ARCH"
	[[ "$arch" == "x86_64" ]] && arch="amd64"

	# Fetch the full index
	loginfo "Getting file index from $urlbase"
	declare fileidx="$(file_fetch "$urlbase/" "$DBUG_TEMP/idxdeb_$DBUG_VERS.$arch.html")"
	[[ -s "$fileidx" ]] || { logerror "Unable to download index of '$urlbase'"; return 1; }
	declare url="$urlbase/$(grep -oP "linux-image-$DBUG_VERS-dbg(.+?)_$arch.d?deb" "$fileidx"|tail -1)"
	declare dst="$DBUG_TEMP/linux-image-$DBUG_VERS-dbg.$arch.deb"

	# Fetch the target file
	loginfo "Downloading '$url' to '$dst'"
	declare file="$(file_fetch "$url" "$dst")"
	[[ -s "$file" ]] || { logerror "Unable to download '$url'"; return 1; }

	extract_deb "$file" "$DBUG_BASE"
}


declare -i retcode=0

case $DIST_NAME in
	#
	# Test for all RPM based systems
	#
	redhat-*|opensuse-*)
		[[ -z "$(bin_find "rpm2cpio")" ]] && {
			logerror "Missing rpm2cpio tool. If you're not on a rpm-based system, you need this tool"
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
		download_redhat "http://fedora.mirrors.ovh.net/linux/updates/$rel/$DBUG_ARCH/debug/k" "$ext" || {
			retcode=$?
			logerror "Unable to download your release. Fedora updates are quick, try to keep them up !"
		}
		;;

	redhat-centos)
		declare arch="$DBUG_ARCH"
		declare rel="${DBUG_VERS#*.el}"
		        rel="${rel%%.*}"

		download_redhat "http://debuginfo.centos.org/$rel/$DBUG_ARCH"
		retcode="$?"
		;;

	redhat-redhat)
		logerror "Redhat doesn't provide public repositories. See https://access.redhat.com/solutions/9907"
		retcode=99
		;;

	#
	# test for all DEB based systems
	#
	debian-*)
		[[ -z "$(bin_find "dpkg-deb")$(bin_find "ar")" ]] && {
			logerror "You need at least 'dpkg-deb' or 'ar' to extract .deb"
			exit 1
		}
		;;&
	
	debian-debian)
		# http://ftp.us.debian.org/debian/pool/main/l/linux/linux-image-4.2.0-1-amd64-dbg_4.2.1-2_amd64.deb
		download_debian "http://ftp.us.debian.org/debian/pool/main/l/linux"
		retcode=$?
		;;

	debian-ubuntu)
		# http://ddebs.ubuntu.com/pool/main/l/linux/linux-image-4.2.0-14-generic-dbgsym_4.2.0-14.16_amd64.ddeb
		download_debian "http://ddebs.ubuntu.com/pool/main/l/linux"
		retcode=$?
		;;

	#
	# SuSE
	#
	opensuse-opensuse)
		# http://download.opensuse.org/debug/distribution/13.2/repo/oss/suse/x86_64/kernel-default-debuginfo-3.16.6-2.1.x86_64.rpm
		# http://download.opensuse.org/debug/distribution/13.2/repo/oss/suse/x86_64/kernel-default-base-debuginfo-3.16.6-2.1.x86_64.rpm
		declare rel="13.1"
		case $DBUG_VERS in
			4.1.8-*)  rel="leap/42.1-Current" ;;
			4.1.6-*)  rel="leap/42.1-Beta1" ;;
			3.16.*)	rel="13.2" ;;
			3.11.*) rel="13.1" ;;
			3.7.*)  rel="12.3" ;;
		esac
		download_suse "http://download.opensuse.org/debug/distribution/$rel/repo/oss/suse/$DBUG_ARCH"
		retcode=$?
		;;
	#
	# Unknown distribution
	#
	*)
		logerror "Unknown distribution name : '$DIST_NAME'"
		exit 1
		;;

esac

exit $retcode
