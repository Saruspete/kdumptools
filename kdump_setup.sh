#!/bin/bash

set -u
#set -x

[[ $(id -ru) != 0 ]] && {
	echo "You should run this script as root"
	exit 1
}

declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"

source "$MYPATH/lib/kdump.lib"
source "$MYPATH/lib/os.lib"

declare RET_CODE=0

declare OPT_FIX=0
declare OPT_HELP=0
declare OPT_ERRORS=""

declare KRN_CONFIGFILE=""
declare KRN_VERSION="$(uname -r)"
declare KRN_CMDRUN="$(< /proc/cmdline)"
declare KRN_CMDBOOT=""

#declare MEM_AVAILABLE="$(awk '$1=="MemTotal:"{print $2}' /proc/meminfo)"
declare MEM_AVAILABLE="$(grep -Po '^MemTotal:\s+[0-9]+' /proc/meminfo|grep -Po '[0-9]+')"

# Show help
function show_help {
	echo "Usage: $0 [options]"
	echo
}


# Parse options
eval set -- "$(getopt -o vqhfk: -l verbose,quiet,help,kconf: -- "$@")"

while [[ -n "${1:-}" ]]; do
	case $1 in
		-f|--fix)		OPT_FIX=1 ;		shift ;;
		-q|--quiet)		LOG_LEVEL=0 ;	shift ;;
		-h|--help)		OPT_HELP=1	;	shift ;;
		-k|--kconf)
			[[ ! -e "$2" ]] && OPT_ERRORS="Kernel config file '$2' from option $1 does not exists"
			KRN_CONFIGFILE="$2"
			shift 2
			;;
		# Special cases for getopt
		--)				shift; break ;;
		-?*)			logerror "Unknown option: '$1'"; shift ;;
		*)				break ;;
	esac
done

# Stop on parsing error
[[ -n "$OPT_ERRORS" ]] && {
	logerror "Parsing error: $OPT_ERRORS"
	exit 1
}

# Show help
[[ $OPT_HELP -eq 1 ]] && {
	show_help
	exit 0
}


#
# Step 1 - Kernel configuration
#

# Most accurate kernel config
if [[ -e "/proc/config.gz" ]]; then
	KRN_CONFIG="$(gunzip -c /proc/config.gz)"
else
	for k in /usr/src/{kernels/$KRN_VERSION,linux-$KRN_VERSION}/.config; do
		[[ -e "$k" ]] && {
			loginfo "Using kernel config '$k'"
			KRN_CONFIG="$(<$k)"
		}
	done
fi

# Check the required config parameters
if [[ -n "$KRN_CONFIG" ]]; then
	for opt in KEXEC SYSFS DEBUG_INFO CRASH_DUMP PROC_VMCORE RELOCATABLE; do
		echo "$KRN_CONFIG" | grep "^CONFIG_$opt=y" >/dev/null || {
			logerror "Required kernel config 'CONFIG_$opt' is not enabled"
		}
	done

else
	logerror "Cannot find valid kernel config file"
	logerror "You can use the -k option to specify it manually"
	RET_CODE=10
fi


#
# Step 2 - bootloader configuration
#


# kernel boot argument
declare crashoption="$(echo "$KRN_CMDRUN" | grep -Po 'crashkernel=[^\s]+')"
if [[ -n "$crashoption" ]]; then
	declare crashstring="${crashoption%*=}"
	declare crashselect=""
	declare crashoffset=""

	# Simple crashkernel=auto
	if [[ "$crashstring" == "auto" ]]; then
		# Check for > 2G RAM
		[[ "$MEM_AVAILABLE" -lt "$(normalize_unit "2G")" ]] && {
			logerror "You have less than 2G RAM. crashkernel=auto will not work"
			RET_CODE=12
		}
	else
		# Parsing for multiple selection (512M-2G:64M,2G-:128M)
		for sel in ${crashstring//,/ }; do
			declare memrange="${sel##:*}"
			declare memvalue="${sel%%*:}"
			# Do we have range selection
			if [[ "$memrange" != "$memvalue" ]]; then
				declare memmin="${memrange%-*}"
				declare memmax="${memrange#*-}"
				# From any to upper
				if [[ -z "$memmin" ]]; then
					[[ "$(normalize_unit $memmax)" -gt $MEM_AVAILABLE ]] && {
						crashselect="$memvalue"
					}
				# From lower to infinite
				elif [[ -z "$memmax" ]]; then
					[[ "$(normalize_unit $memmin)" -lt $MEM_AVAILABLE ]] && {
						crashselect="$memvalue"
					}
				else
					logerror "Unable to understand tuple '$sel'. Please check "
				fi
			# Simple crashkernel= match
			else
				crashselect="$memvalue"
			fi
		done

		# Check value
		if [[ -n "$crashselect" ]]; then
			# TODO: Add value validation
			loginfo "Using reservation: $crashselect"
		else
			logerror "Cannot find the value in '$crashstring'"
			RET_CODE=13
		fi
	fi
else
	logwarning "Your system is not started with 'crashkernel=XXX' option."
	logwarning "You'll have to reboot your system once added"
	RET_CODE=11
fi




#
# Step 3 -kdump installation
#
[[ -n "$(bin_find "kexec")" ]] || {
	[[ -n "$PKG_KEXEC" ]] && {
		log_info "We need to install kexec tools (package: $PKG_KEXEC)"
	}
}


#
# Step 4 - kdump configuration
#
[[ -n "$PKG_KDUMP" ]] && {
	os_pkginstall "$PKG_KDUMP"
}


#
# Step 5 - kdump initrd image generation
#



