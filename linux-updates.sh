#!/bin/bash
#################################################################################################################
#                                  CMK-Script for monitoring updates on linux                                   #
#################################################################################################################
# Supported are apt,dnf,yum,zypper on Debian|Ubuntu|Mint|raspbian, Fedora, RHEL|CentOS|OracleLinux, SLES|opensuse
# Version 1.6.3
# Script by Dipl.-Inf. Christoph Pregla
# License: GNU GPL v3
# https://github.com/Tux-Script/check_mk-linux-updates

###########################################
### Declaration var / const /command	###
###########################################

declare -l dist_id
declare cmk_output
declare cmk_status="P"
declare -r cmk_checkname="Linux-Updates"
declare cmk_metrics
declare cmk_describes
declare cmk_describes_long
declare -i nr_updates
declare -i nr_sec_updates
declare -i nr_locks
declare -i nr_sources
declare list_updates
declare -i nr_reload
declare -i nr_reboot
declare restart

#cmk trehsold values / CMK Schwellwerte  
declare -i updates_warn=5
declare -i updates_crit=10
declare -i updates_sec_warn=1
declare -i updates_sec_crit=3
declare -i locks_warn=3
declare -i locks_crit=5
declare  -i reboot_warn
declare -i reboot_crit=1
declare -i reload_warn=1
declare -i reload_crit=10

#tools:
declare -r CAT="/bin/cat"
declare -r GREP="/bin/grep"
declare -r EGREP="/bin/egrep"
declare -r AWK="/usr/bin/awk"
declare -r SED="/bin/sed"
declare -r WC="/usr/bin/wc"

declare -r APT="/usr/bin/apt"
declare -r APTMARK="/usr/bin/apt-mark"
declare -r ZYPPER="/usr/bin/zypper"
declare -r YUM="/usr/bin/yum"
declare -r DNF="/usr/bin/dnf"
declare -r CHECKRESTART="/usr/sbin/checkrestart"
declare -r NEEDRESTARTING="/usr/bin/needs-restarting"

###########################################
### 	Declaration functions		###
###########################################

declare -f apt_check_updates
declare -f zypper_check_updates
declare -f yum_check_updates
declare -f generate_cmk_output
declare -f output

###########################################
###		   Functions		###
###########################################

function apt_get_number_of_updates() {
	echo "$($APT list --upgradable 2> /dev/null | $EGREP -v "(Auflistung|Listing)" | $WC -l)"
}
function apt_get_number_of_sec_updates() {
	echo "$($APT list --upgradable 2> /dev/null | $GREP "/$(lsb_release -cs)-security" | $WC -l)"
}
function apt_get_number_of_locks() {
	echo "$($APTMARK showhold 2> /dev/null | $WC -l)"
}
function apt_get_number_of_sources() {
	echo "$($GREP -r --include '*.list' '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ | $WC -l)"
}
function apt_get_list_all_updates() {
	lines="$($APT list --upgradable 2> /dev/null | $EGREP '(aktualisierbar|upgradable)' | $AWK -F '/' ' { print $1 } ')"
	list=""
	for line in $lines 
	do
		list="$list$line "
	done
	echo $list
}
#require debian-goodies
function apt_checkrestart() {
	rrpkgs_path="/var/run/reboot-required.pkgs"
	restart=""
	if $APT list 2>/dev/null | $GREP 'debian-goodies/' &>/dev/null; then
		nr_reload="$($CHECKRESTART 2>/dev/null| $GREP restart | $EGREP "^s" | $WC -l)"
		if  test -f "$rrpkgs_path" ; then
			nr_reboot="$($CAT $rrpkgs_path | $WC -l)"
			restart="$nr_reboot packages require system reboot"
	fi
	else
		nr_reload=0
       		if  test -f "$rrpkgs_path" ; then
			nr_reboot="$($CAT $rrpkgs_path | $WC -l)"
			restart="$nr_reboot packages require system reboot, package debian-goodies required!!"
		else
			restart="package debian-goodies required!!"
		fi
	fi
	if [ $nr_reload -gt 0 ]; then
		if [ -z "$restart" ]; then
			restart="$nr_reload services required reload"
		else
			restart="$restart, $nr_reload services required reload"
		fi
	fi
}

function zypper_get_number_of_updates() {
	echo "$($ZYPPER --non-interactive list-updates | $GREP SLE | $WC -l)"
}
function zypper_get_number_of_patches() {
	echo "$($ZYPPER --non-interactive list-patches | $GREP SLE | $WC -l)"
}
function zypper_get_number_of_sec_patches() {
	echo "$($ZYPPER --non-interactive list-patches | $GREP SLE | $GREP security | $WC -l)"
}
function zypper_get_number_of_locks() {
	echo "$($ZYPPER ll | $EGREP "^[0-9]" | $WC -l)"
}
function zypper_get_number_of_sources() {
	echo "$($ZYPPER repos | $EGREP '^[0-9]' | $AWK -F '|' ' { print $2 } '| $WC -l)"
}
function zypper_get_list_all_updates() {
	lines="$($ZYPPER --non-interactive list-updates | $GREP SLE | $AWK -F '|' ' { print $3 } ')"
	list=""
	for line in $lines
	do
		list="$list$line "
	done
	echo $list
}
function zypper_checkrestart() {
	nr_reload="$($ZYPPER ps -s | $EGREP '^[0-9]* ' | $AWK -F '|' ' { print $6 } ' | sort -u | $EGREP " [a-zA-Z]" | $WC -l)"
	nr_reboot="$($ZYPPER ps -s | $GREP -q 'kernel' | $WC -l)"
	if [ $nr_reboot -gt 0 ]; then
		restart="system reboot required"
	fi
	if [ $nr_reload -gt 0 ]; then
		if [ -z "$restart" ]; then
			restart="$nr_reload services required reload"
		else
			restart="$restart, $nr_reload services required reload"
		fi
	fi
}

function yum_get_number_of_updates() {
	echo "$($YUM check-update -q | $EGREP -v '(^$|running|installed|Loaded)' | $WC -l)"
}
function yum_get_number_of_sec_updates() {
	echo "$($YUM check-update -q | $EGREP '^Security' | $EGREP -v '(running|installed)' | $AWK ' { print $2 } ' | $WC -l)"
}
#require package yum-plugin-versionlock
function yum_get_number_of_locks() {
	if $YUM list installed "yum-plugin-versionlock" -q &> /dev/null; then
		locks1="$($YUM versionlock list -q | $WC -l)"
		locks2="$($CAT /etc/yum.conf /etc/yum.repos.d/*.repo | $GREP 'exclude' | $AWK -F '=' ' {  print $2 } ' | sort -u | $WC -w)"
		echo $(($locks1 + $locks2)) 
	else
		echo "$($CAT /etc/yum.conf /etc/yum.repos.d/*.repo | $GREP 'exclude' | $AWK -F '=' ' {  print $2 } ' | sort -u | $WC -w)"
	fi
} 
function yum_get_number_of_sources() {
	echo "$($YUM repolist enabled -q | $EGREP -v 'Repo-ID' | $WC -l)"
}
function yum_get_list_all_updates() {
	lines="$($YUM check-update -q | $EGREP -v '(running|installed|Loaded)' | $AWK ' { if ($1=="Security:") { print $2 } else { print $1 } } ')"
	list=""
	for line in $lines
	do
		list="$list$line "
	done
	echo $list
}
#require yum-utils
function yum_checkrestart() {
	if $YUM list installed "yum-utils" -q &> /dev/null; then
		nr_reload="$($NEEDSRESTARTING -s | $WC -l)"
		nr_reboot="$($NEEDSRESTARTING -r | $EGREP "Reboot is required" | $WC -l)"
		if [ $nr_reboot -gt 0 ]; then
			restart="system reboot required"
		fi
		if [ $nr_reload -gt 0 ]; then
			if [ -z "$restart" ]; then
				restart="$nr_reload processes required reload"
			else
				restart="$restart, $nr_reload processes required reload"
			fi
		fi
	else
		nr_reload=0
		nr_reboot=0
		restart="yum-utils are required!"
	fi	
}

function dnf_get_number_of_updates() {
	echo "$($DNF check-update | $EGREP -v '(^(Geladene|Loading|Letzte|Last| * |$)|\.src|Metadaten|metadata|running|available|Loaded)' | $WC -l)" 
}
function dnf_get_number_of_sec_updates() {
	echo "$($DNF check-update | $EGREP '^Security' | $GREP -v 'running' | $AWK ' { print $2 } ' | $WC -l)"
}
function dnf_get_number_of_locks() {
	#TODO
	echo 0
}
function dnf_get_number_of_sources() {
	echo "$($DNF repolist --enabled | $GREP -v "\-ID" | $WC -l)"
}
function dnf_get_list_all_updates() {
	lines="$($DNF check-update | $EGREP -v '(^(Geladene|Loading|Letzte|Last ? |$)|\.src|Metadaten|metadata|running|available|Loaded)' | $AWK ' { if ($1=="Security:") { print $2 } else { print $1 } } ')"
	list=""
	for line in $lines
	do
		list="$list$line "
	done
	echo $list
}
function dnf_checkrestart() {
	nr_reboot="$($DNF needs-restarting -r | $EGREP "Reboot is required" | $WC -l)"
	if [ $nr_reboot -gt 0 ]; then
		restart="system reboot required"
	fi
}

###############
function apt_check_updates() {
	nr_updates=$(apt_get_number_of_updates)
	nr_sec_updates=$(apt_get_number_of_sec_updates)
	nr_locks=$(apt_get_number_of_locks)
	nr_sources=$(apt_get_number_of_sources)
	list_updates=$(apt_get_list_all_updates)

	apt_checkrestart

	cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit|Reboot=$nr_reboot;$reboot_warn;$reboot_crit|Reload=$nr_reload;$reload_warn;$reload_crit"
	cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, $nr_locks packets are locked, $nr_sources used Paket-Sources, $restart"
	cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources \\$restart"	
}

function zypper_check_updates() {
	nr_package=$(zypper_get_number_of_updates)
	nr_updates=$(zypper_get_number_of_patches)
	nr_sec_updates=$(zypper_get_number_of_sec_patches)
	nr_locks=$(zypper_get_number_of_locks)
	nr_sources=$(zypper_get_number_of_sources)
	list_updates=$(zypper_get_list_all_updates)

	zypper_checkrestart

	cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit|Reboot=$nr_reboot;$reboot_warn;$reboot_crit|Reload=$nr_reload;$reload_warn;$reload_crit"
	cmk_describe="$nr_updates Patches [$nr_package pkgs] ($list_updates), $nr_sec_updates Security Patches, $nr_locks packets are locked, $nr_sources used Paket-Sources, $restart"
	cmk_describe_long="$nr_updates Patches [$nr_package pkgs] ($list_updates) \\n$nr_sec_updates Security Patches \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources \\n$restart"
}

function yum_check_updates() {
	nr_updates=$(yum_get_number_of_updates)
	nr_sec_updates=$(yum_get_number_of_sec_updates)
	nr_sources=$(yum_get_number_of_sources)
	list_updates=$(yum_get_list_all_updates)

	yum_checkrestart

	if $YUM list installed "yum-plugin-versionlock" -q &> /dev/null; then
		nr_locks=$(yum_get_number_of_locks)
		cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit|Reboot=$nr_reboot;$reboot_warn;$reboot_crit|Reload=$nr_reload;$reload_warn;$reload_crit"
		cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, $nr_locks packets are locked, $nr_sources used Paket-Sources, $restart"
		cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources \\n$restart"
	else
		nr_locks=0
		cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit|Reboot=$nr_reboot;$reboot_warn;$reboot_crit|Reload=$nr_reload;$reload_warn;$reload_crit"
		cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, !!package locks required yum-plugin-versionlock!!, $nr_sources used Paket-Sources"
		cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n!!package locks required yum-plugin-versionlock!!\\n$nr_sources used Paket-Sources"
	fi
}

function dnf_check_updates() {
	nr_updates=$(dnf_get_number_of_updates)
	nr_sec_updates=$(dnf_get_number_of_sec_updates)
	nr_locks=$(dnf_get_number_of_locks)
	nr_sources=$(dnf_get_number_of_sources)
	list_updates=$(dnf_get_list_all_updates)

	dnf_checkrestart

	cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit|Reboot=$nr_reboot;$reboot_warn;$reboot_crit"
	cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, $nr_locks packets are locked, $nr_sources used Paket-Sources, $restart"
	cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources \\n$restart"
}

function detect_pkg_manager() {
	pkgm="$(which apt 2>/dev/null | awk -F '/' ' { print $NF} '; which zypper 2>/dev/null | awk -F '/' ' { print $NF} '; which dnf 2>/dev/null | awk -F '/' ' { print $NF} '; which yum 2>/dev/null | awk -F '/' ' { print $NF}  ' ; which apt-get 2>/dev/null | awk -F '/' ' { print $NF} ')"

	if [[ -z $pkgm ]]; then
	        pkgm="none"
	else
	        pkgm=(${pkgm[@]})
	        pkgm="${pkgm[0]}"
	fi
	echo "$pkgm"
}
################
function generate_cmk_output() {
	#last "\\n", because cmk append metrics thresholds information at last line
	cmk_output="$cmk_status $cmk_checkname $cmk_metrics $cmk_describe\\n$cmk_describe_long\\n"
}
function output() {
	generate_cmk_output;
	echo "$cmk_output";
}
###################################################
###################################################
###			MAIN			###
###################################################
###################################################

#Check packagemanager
pkgm="$(detect_pkg_manager)"

#Check updates for packagemanager
case "$pkgm" in
	apt)
               	apt_check_updates 
                ;;
        zypper)
                zypper_check_updates
                ;;
        dnf)
                dnf_check_updates
                ;;
        yum)
                yum_check_updates
                ;;
	*)                
		cmk_describe="Packagemanager not detected and not supported."
                cmk_describe="Packagemanager not detected and not supported.\\nsupportet are apt, zypper, yum, dnf"
		cmk_status=3	
                ;;
esac

output;
exit 0;
