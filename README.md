kdumptools
==========

The kdumptools is a set of scripts to help you working with Kernel Dumps.
When your system is unresponsive, 

## How to use it / requirements

The scripts should work on any reasonably recent Linux system. 
For kdump to work, there is some requirements (the script `kdump_setup.sh` will check and fix them for you) :
  - Kernel configuration parameters.
  - Between 64 and 256M (according to your quantity of RAM) to be reserved thanks to bootoption `crashkernel`
  - Some packages (kexec-tools mainly) to be installed (if you explicitely accept it)

For the analysis, there is other needs, but it can be done on any computer (not necessarily the one where the dump come from)
  - Crash tool (GDB like) working with pretty much all architectures. `kdump_analyze.sh` will call the required scripts so you can analyze the dump easily.
  - Kernel debuginfos to analyze the dump afterwards. `kdump_getdbg.sh` will retrieve and extract them.
  - For the modification of a live system, `kdump_live.sh` will do the required checks (and bypasses if needed).


## How to contribute
### A few rules
We target mostly modern systems, and should run with all major distribution families.
When adding code, try not to invade the userspace. As it should run on production systems with as few packages as possible, the only allowed tools are :
  - bash4 (http://wiki.bash-hackers.org/bash4) 
  - coreutils (mv, cp, touch, tr, head, tail, uname...)
  - util-linux (su, mkfs, getopt, mount, kill...)

Try to avoid other tools (awk, sed...) as much as possible. They are not available on all systems. 

### Why bash ?
Shell is the most low-level language for sysadmins.
And bash because it's the default shell for most Linux distributions

Perl ? I love it, but most people don't
Awk ? Even fewer people know how to use it
Other script langage ? We're doing sysadmin here. Not a website


## More details about kdump
You can find the slides of the Kernel-Recipes 2015 lightning-talk here : 

### Contact
Author : Adrien Mahieux <adrien.mahieux@gmail.com>  - Sysadmin
