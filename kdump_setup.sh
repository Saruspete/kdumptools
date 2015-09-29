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

declare -i RET_CODE=0

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
	echo "Options:"
	echo "  -f|--fix       Fix errors when possible"
	echo "  -q|--quiet     Do not output error"
	echo "  -h|--help      Display this help"
	echo "  -k|--kconf     Path to the kernel .config file"
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

if [[ -n "$KRN_CONFIGFILE" ]]; then
	if [[ -e "$KRN_CONFIGFILE" ]]; then
		loginfo "Using user-specified kernel config file '$KRN_CONFIGFILE'"
		KRN_CONFIG="$(<$KRN_CONFIGFILE)"
	else
		logerror "Bad user-specified kernel config file: '$KRN_CONFIGFILE'"
	fi

# Most accurate kernel config
elif [[ -e "/proc/config.gz" ]]; then
	KRN_CONFIG="$(gunzip -c /proc/config.gz)"

# Usual .config locations
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
	for opt in KEXEC SYSFS CRASH_DUMP PROC_VMCORE; do
		echo "$KRN_CONFIG" | grep "^CONFIG_$opt=y" >/dev/null || {
			logerror "Required kernel config 'CONFIG_$opt' is not enabled"
			RET_CODE=RET_CODE+1
		}
	done
	for opt in DEBUG_INFO RELOCATABLE; do
		echo "$KRN_CONFIG" | grep "^CONFIG_$opt=y" >/dev/null || {
			logwarning "Recommended kernel config 'CONFIG_$opt' is not enabled"
			RET_CODE=RET_CODE+1
		}
	done

else
	logerror "Cannot find valid kernel config file"
	logerror "You can use the -k option to specify it manually"
	RET_CODE=RET_CODE+1
fi


#
# Step 2 - bootloader configuration
#


# kernel boot argument
declare bootchange=""
declare crashoption="$(echo "$KRN_CMDRUN" | grep -Po 'crashkernel=[^\s]+')"
if [[ -n "$crashoption" ]]; then
	declare crashstring="${crashoption%*=}"
	declare crashselect=""
	declare crashoffset=""

	# Simple crashkernel=auto
	if [[ "$crashstring" == "auto" ]]; then
		# Check for > 2G RAM
		[[ "$MEM_AVAILABLE" -lt "$(normalize_unit "2G")" ]] && {
			logerror "You have less than 2G RAM, crashkernel=auto will not work"
			RET_CODE=RET_CODE+1
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
					RET_CODE=RET_CODE+1
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
			RET_CODE=RET_CODE+1
		fi
	fi
else
	logwarning "Your system is not started with 'crashkernel=XXX' option."
	logwarning "You'll have to reboot your system once added"
	RET_CODE=RET_CODE+1
fi

# Change bootloader conf
if [[ -z "$crashoption" ]] || [[ -n "$bootchange" ]]; then
	# Default param
	# TODO: check for < 2G RAM
	[[ -z "$bootchange" ]] && bootchange="crashkernel=auto"

fi

#
# Step 3 -kdump installation
#

# Kexec
[[ -z "$(bin_find "kexec")" ]] || {
	if [[ "$OPT_FIX" -eq 1 ]] && [[ -n "$PKG_KEXEC" ]]; then
		loginfo "Need to install kexec tools (package: $PKG_KEXEC)"
		if ask_yn "Proceed with installation"; then
			os_pkginstall "$PKG_KEXEC" || {
				logerror "Error during installation of the package"
				RET_CODE=RET_CODE+1
			}
		else
			logerror "kexec tool is required"
			RET_CODE=RET_CODE+1
		fi
	else
		logerror "Cannot find executable 'kexec' in \$PATH, and the script"
		logerror "doesn't know the package name for your distribution"
		RET_CODE=RET_CODE+1
	fi
}

# kdump package
if [[ -n "$PKG_KDUMP" ]]; then

	# Is package installed
	! os_pkginstalled "$PKG_KDUMP" && {
		if [[ "$OPT_FIX" -eq 1 ]]; then
			loginfo "Need to install kdump tools (package: $PKG_KDUMP)"
			if ask_yn "Proceed with installation"; then
				os_pkginstall "$PKG_KDUMP" || {
					logerror "Error during installation of the package"
					RET_CODE=RET_CODE+1
				}
			else
				logerror "kdump tool is required"
				RET_CODE=RET_CODE+1
			fi
		else
			logerror "Package $PKG_KDUMP must be installed"
			RET_CODE=RET_CODE+1
		fi
	}

	# Service must be started
	os_svcenabled "kdump" || {
		loginfo "Need to enable the service"
	}
else
	# TODO: Use a custom made generic kdump script
	logwarning "The variable \$PKG_KDUMP is not set for your distribution"
	logwarning "I cannot check if it is installed or not."
	RET_CODE=RET_CODE+1
fi

#
# Step 4 - kdump configuration
#
[[ -e "/etc/kdump.conf" ]] && {
	:
}


#
# Step 5 - kdump initrd image generation
#



