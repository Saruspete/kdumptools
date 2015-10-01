#!/bin/bash

set -u

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
declare KRN_CONFIG=""
declare KRN_VERSION="$(uname -r)"

declare MEM_AVAILABLE="$(sys_getmemtotal)"
declare CPU_AVAILABLE="$(sys_getcputotal)"

declare DMP_LOCATION=""
declare DMP_PAGETYPE=""
declare DMP_BOOTCMD=""
declare DMP_EXECPRE=""
declare DMP_EXECPOST=""

# Show help
function show_help {
	echo "Usage: $0 [options]"
	echo
	echo "Options:"
	echo "  -f|--fix        Fix errors when possible"
	echo "  -q|--quiet      Do not output error"
	echo "  -h|--help       Display this help"
	echo "  -k|--kconf      Path to the kernel .config file"
	echo "  -l|--location   Location where to dump the vmcore"
	echo "     --bootcmd    Args to append to kexec'd kernel"
	echo "     --pagetype   Page types mask to be selected (default 31, see makedumpfile)"
#	echo "     --execpre    Script to execute prior dumping"
#	echo "     --execpost   Script to execute after dumping"
	echo
	echo "Location may be one of :"
	echo 'Filesystem : fstype:<device|label|uuid>@mountpoint'
	echo '             "fstype" can be any FS managed by the kernel'
	echo 'Raw device : raw:device'
	echo 'NFS        : nfs:host/folder'
	echo 'SSH / SCP  : ssh[%local_key_path]:user@host/folder'
	echo
	echo "You can use these variables in the target folder:"
	echo "  %HOST  "
	echo "  %DATE  "
	echo
}

#
# Parse options
#
eval set -- "$(getopt -o vqhfk:b: -l verbose,quiet,help,fix,kconf:,bootcmd: -- "$@")"

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
		--bootcmd)		DMP_BOOTCMD="$2" ; shift 2 ;;
		--pagetype)		DMP_PAGETPE="$2" ; shift 2 ;;
		--execpre)		DMP_EXECPRE="$2" ; shift 2 ;;
		--execpost)		DMP_EXECPOST="$2"; shift 2 ;;
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
	for k in /boot/config-$KRN_VERSION /usr/src/{kernels/$KRN_VERSION,linux-$KRN_VERSION}/.config; do
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
	logerror "Cannot find valid kernel config file. You can use the -k option to specify it manually"
	RET_CODE=RET_CODE+1
fi


#
# Step 2 - bootloader configuration
#


# kernel boot argument
declare bootchange=""
declare crashoption="$(boot_getopt "crashkernel")"
if [[ -n "$crashoption" ]]; then
	declare crashstring="${crashoption%*=}"
	declare crashselect=""
	declare crashoffset=""

	# Simple crashkernel=auto
	if [[ "$crashstring" == "auto" ]]; then
		# Check for > 2G RAM
		[[ "$MEM_AVAILABLE" -lt "$(normalize_unit "2G")" ]] && {
			logerror "You have less than 2G RAM, crashkernel=auto will not work"
			bootchange="$(boot_getbestmemsize)"
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
	logerror "Your system is not started with 'crashkernel=XXX' option. You'll have to reboot your system once added"
	RET_CODE=RET_CODE+1
fi

# Change bootloader conf
if [[ -z "$crashoption" ]] || [[ -n "$bootchange" ]]; then
	# Default param
	# TODO: check for < 2G RAM
	[[ -z "$bootchange" ]] && bootchange="$(boot_getbestmemsize)"

	if [[ "$OPT_FIX" == "1" ]] && ask_yn "Set the bootparam 'crashkernel' to '$bootchange'"; then
		boot_setopt "crashkernel" "$bootchange" || {
			logerror "Unable to set bootparam. Please check manually"
			RET_CODE=RET_CODE+1
		}
	else
		logerror "The bootparam 'crashkernel' should be set to '$bootchange'"
		RET_CODE=RET_CODE+1
	fi
fi

#
# Step 3 -kdump installation
#

# Kexec
[[ -z "$(bin_find "kexec")" ]] && {
	if [[ -n "$PKG_KEXEC" ]]; then
		loginfo "Need to install kexec tools (package: $PKG_KEXEC)"
		if [[ "$OPT_FIX" == "1" ]] && ask_yn "Proceed with installation"; then
			os_pkginstall "$PKG_KEXEC" || {
				logerror "Error during installation of the package"
				RET_CODE=RET_CODE+1
			}
		else
			logerror "kexec tool is required"
			RET_CODE=RET_CODE+1
		fi
	else
		logerror "Cannot find executable 'kexec' in \$PATH, and the script doesn't know the package name for your distribution"
		RET_CODE=RET_CODE+1
	fi
}

# kdump package
if [[ -n "$PKG_KDUMP" ]]; then

	# Is package installed
	! os_pkginstalled "$PKG_KDUMP" && {
		if [[ "$OPT_FIX" == "1" ]]; then
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

	# Other checks when package is installed
	os_pkginstalled "$PKG_KDUMP" && {
		if os_svcexists "kdump"; then
			os_svcenabled "kdump" || {
				loginfo "Need to enable 'kdump' service"
				if [[ "$OPT_FIX" == "1" ]] && ask_yn "Enable 'kdump' service"; then
					os_svcenable "kdump" || {
						logerror "Error during activation of the service"
						RET_CODE=RET_CODE+1
					}
				else
					logerror "The service kdump must be enabled on boot"
					RET_CODE=RET_CODE+1
				fi
			}
		else
			logerror "Seems there is no kdump service in your distribution. Thats strange..."
			RET_CODE=RET_CODE+1
		fi

		# Check kexec is started
		if [[ -e "/sys/kernel/kexec_crash_loaded" ]]; then
			os_pkginstalled "$PKG_KDUMP" && [[ "$(</sys/kernel/kexec_crash_loaded)" == "0" ]] && {
				loginfo "Need to start 'kdump' service"
				if [[ "$OPT_FIX" == "1" ]] && ask_yn "Start 'kdump' service"; then
					os_svcstart "kdump" || {
						logerror "Error during start of the service"
						RET_CODE=RET_CODE+1
					}
				else
					logerror "The service kdump must be started"
					RET_CODE=RET_CODE+1
				fi
			}
		else
			logerror "Your kernel is missing SYSFS support"
			RET_CODE=RET_CODE+1
		fi
	}
else
	# TODO: Use a custom made generic kdump script
	logwarning "The variable \$PKG_KDUMP is not set for your distribution. I cannot check if it is installed or not."
	RET_CODE=RET_CODE+1
fi

#
# Step 4 - kdump configuration
#
declare kdumpconf="/etc/kdump.conf"
[[ -e "$kdumpconf" ]] && {

	loginfo "Configuring kdump.conf"

	declare kdconf="$(<$kdumpconf)"

	#
	# Dump location configuration
	#

	# Discard all fs types and fs
	declare lfsrgx=""
	declare ftypes="$(grep -oP '[^\s]+$' /proc/filesystems)"
	for ft in path raw nfs ssh $ftypes; do
		[[ -n "$lfsrgx" ]] && lfsrgx="$lfsrgx|"
		lfsrgx="$lfsrgx$ft"
	done
	declare fsrgx="$lfsrgx|path|raw|nfs|ssh"

	kdconf="$(echo "$kdconf"|grep -vP '^\s*'$fsrgx)"
	
	# Add the requested ones
	if [[ -n "$DMP_LOCATION" ]]; then
		declare ft="${DMP_LOCATION%%:*}"
		declare arg="${DMP_LOCATION#*:}"
		declare path="/var/crash/%HOST-%DATE"
		# 
		case $ft in
			$lfsrgx)
				declare fstype="$ft"

				;;

			# ssh%/root/id_dsa.key:user@host:/remote/path/
			ssh|ssh%*)
				declare keyf="${ft%ssh%}"
				declare user="${arg%%@*}"
				declare host="${arg}"
				
				[[ "$keyf" != "ssh" ]] && {
					kdconf="$kdconf\nsshkey $keyf"
				}
				
				kdconf="$kdconf\nssh ${host}:${arg}"
				;;

			# nfs:host:/remote/path
			nfs) 
				declare host="${arg%%/*}"
				declare mnt="${arg#*/}"
				kdconf="$kdconf\nnfs $host:$mnt"
				;;

			# raw:/dev/device
			raw)
				declare dev="${arg}"
				if [[ -b "$dev" ]]; then
					kdconf="$kdconf\nraw $dev"
				else
					logerror "kconf: raw device '$dev' is not available"
				fi
				;;
		esac

		kdconf="$kdconf\npath $path"

	# Default value: root path & /var/crash
	else
		kdconf="$kdconf\npath /var/crash"
	fi

	#
	# core_collector
	#

	#core_collector makedumpfile -l --message-level 1 -d 31

	#
	# Script
	#
	#kdump_pre
	#kdump_post


	mv "$kdumpconf" "$kdumpconf.bak"
	echo -e "$kdconf" > "$kdumpconf"
}


#
# Step 5 - kdump initrd image generation
#



exit $RET_CODE
