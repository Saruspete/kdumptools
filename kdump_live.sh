#!/bin/bash
set -u
declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"

#
source "$MYPATH/lib/kdump.lib"

# Step 0 - Basic user requirements
[[ -r /dev/mem ]] && [[ -w /dev/mem ]] || {
	logerror "You must be able to read and write to /dev/mem"
	logerror "Did you run this script as root ?"
	exit 1
}

# Step 1 - System : Check if STRICTMEM is enabled
dd if=/dev/mem of=/dev/null bs=1024 count=2 >/dev/null 2>&1 || {
	loginfo "STRICTMEM restriction in effect. We'll need to workaround"

	# Check if we can load our kretprobe module
	[[ ! -e /proc/modules ]] && {
		logerror "Your system does not seems to have modules enabled. I can't do anything for you"
		exit 1
	}

	# Try to load our kretprobe allow_devmem module
	declare ALLOWMEMPATH="$MYPATH/src/allow_devmem"

	# Check for required tools
	declare compiletools="make gcc000"
	declare missingtools="$(bin_require $compiletools)"
	[[ -n "$missingtools" ]] && {
		if ask_yn "Some require tools are missing ($missingtools). Should I try to install them ?"; then
			os_bininstall $missingtools || {
				logerror "There was an error during installation of $missingtools"
				logerror "Please check logs at : $LOGPATH and fix manually"
				exit 10
			}
		else
			logerror "Please install manually"
		fi
	}
	
}

# Step 2 - Check basic tools
bin_require crash || {
	if ask_yn "I require 'crash' tool to continue. Should I try to install it ?"; then
		os_pkginstall "crash"
	else
		logerror ""
		exit 20
	fi
}

# Step 3 - Check debuginfo



# Step 4 - We're good to go
