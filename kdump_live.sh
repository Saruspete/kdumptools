#!/bin/bash
set -u
declare MYSELF="$(readlink -f $0)"
declare MYPATH="${MYSELF%/*}"


source "$MYPATH/lib/kdump.lib"

# Step 0 - Basic user requirements
[[ -r /dev/mem ]] && [[ -w /dev/mem ]] || {
	logerror "You must be able to read and write to /dev/mem"
	logerror "Did you run this script as root ?"
	exit 1
}

# Step 1 - System : Check if STRICTMEM is enabled
dd if=/dev/mem of=/dev/null bs=1024 count=2048 >/dev/null 2>&1 || {
	loginfo "STRICTMEM restriction in effect. We'll need to workaround"

	# Check if we can load our kretprobe module
	[[ ! -e /proc/modules ]] && {
		logerror "Your system does not seems to have modules enabled. I can't do anything for you"
		exit 1
	}

	# Try to load our kretprobe allow_devmem module
	declare ALLOWMEMPATH="$MYPATH/src/allow_devmem"

	# Check for required tools
	declare compiletools="make gcc"
	declare missingtools="$(bin_require $compiletools)"
	[[ -n "$missingtools" ]] && {
		if ask_yn "Some required tools are missing ($missingtools). Should I try to install them ?"; then
			os_bininstall $missingtools || {
				logerror "There was an error during installation of $missingtools"
				logerror "Please check logs at : $LOGPATH and fix manually"
				exit 10
			}
		else
			logerror "Please install these packages manually"
		fi
	}

	# Check for module presency
	grep '^allow_devmem ' /proc/modules >/dev/null && {
		logerror "Module allow_devmem is loaded but I can't access /dev/mem..."
		logerror "This is a bug, and should be reported"
		exit 1
	}
	
	# Target module
	declare memkmod_src="$ALLOWMEMPATH/allow_devmem.ko"
	declare memkmod_tgt="$ALLOWMEMPATH/allow_devmem-$(uname -r).ko"
		
	# Compile the module if needed
	[[ -e "$memkmod_tgt" ]] || {
		make -C $ALLOWMEMPATH
		if [[ -e "$memkmod_src" ]]; then
			mv "$memkmod_src" "$memkmod_tgt"
		else
			logerror "Error during compilation of '$memkmod_src'. Please check logs"
			exit 11
		fi
	}

	if [[ -e "$memkmod_tgt" ]]; then
		declare bin_insmod="$(bin_find "insmod")"
		if [[ -n "$bin_insmod" ]]; then
			$bin_insmod "$memkmod_tgt" || {
				logerror "Error during load of $memkmod_tgt. Please check logs"
				exit 12
			}
		else
			logerror "Cannot find bin 'insmod'. Required for loading modules"
			exit 13
		fi
	else
		logerror "Can't find module ($memkmod_tgt)."
		exit 10
	fi
	
}

# Check if we're called from kdump analyze, or directly
grep "kdump_analyze.sh" "/proc/$PPID/comm" >/dev/null 2>&1 || {
	$MYPATH/kdump_analyze.sh -l
}
