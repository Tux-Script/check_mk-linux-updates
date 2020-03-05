#!/bin/bash
#################################################################################################################
#                                  CMK-Script for monitoring updates on linux                                   #
#################################################################################################################
# Supported are apt,yum,zypper on Debian|Ubuntu|Mint|raspbian, RHEL|CentOS|OracleLinux, SLES|opensuse
# systemd-platform for distribution detect required
# Version 0.9
# Script by Dipl.-Inf. Christoph Pregla

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

#cmk trehsold values / CMK Schwellwerte
declare -i updates_warn=5
declare -i updates_crit=10
declare -i updates_sec_warn=1
declare -i updates_sec_crit=3
declare -i locks_warn=3
declare -i locks_crit=5

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
	echo "`$APT list --upgradable 2> /dev/null | $EGREP -v "(Auflistung|Listing)" | $WC -l`"
}
function apt_get_number_of_sec_updates() {
	echo "`$APT list --upgradable 2> /dev/null | $GREP "/$(lsb_release -cs)-security" | $WC -l`"
}
function apt_get_number_of_locks() {
	echo "`$APTMARK showhold 2> /dev/null | $WC -l`"
}
function apt_get_number_of_sources() {
	echo "`$GREP -r --include '*.list' '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ | $WC -l`"
}
function apt_get_list_all_updates() {

	lines="`$APT list --upgradable 2> /dev/null | $EGREP '(aktualisierbar|upgradable)' | $AWK -F '/' ' { print $1 } '`"
	list=""
	for line in $lines 
	do
		list="$list$line "
	done
	echo $list
}

function zypper_get_number_of_updates() {
	echo "`$ZYPPER --non-interactive list-patches | $GREP SLE | $WC -l`"
}
function zypper_get_number_of_sec_updates() {
	echo "`$ZYPPER --non-interactive list-patches | $GREP SLE | $GREP security | $WC -l`"
}
function zypper_get_number_of_locks() {
	echo "`$ZYPPER ll | $EGREP "^[0-9]" | $WC -l`"
}
function zypper_get_number_of_sources() {
	echo "`$ZYPPER repos | $EGREP "^[0-9]" | $AWK -F '|' ' { print $2 } '| $WC -l`"
}
function zypper_get_list_all_updates() {
	lines="`$ZYPPER --non-interactive list-updates | $GREP SLE | $AWK -F '|' ' { print $3 } '`"
	list=""
	for line in $lines
	do
		list="$list$line "
	done
	echo $list
}

function yum_get_number_of_updates() {
	echo "`$YUM check-update | $EGREP -v '(^(Geladene|Loading| * )|running|available|Loaded)' | $WC -l`"
}
function yum_get_number_of_sec_updates() {
	echo "`$YUM check-update | $EGREP "^Security" | $GREP -v "running" | $AWK ' { print $2 } ' | $WC -l`"
}
#require package yum-plugin-versionlock
function yum_get_number_of_locks() {
	#TODO: check exist yum-plugin-versionlock; yum versionlock list ; check files
	echo "0"
}
function yum_get_number_of_sources() {
	echo "`$YUM repolist enabled | $EGREP -v "(Repo-ID|Plugins|repolist)" | $WC -l`"
}
function yum_get_list_all_updates() {
	lines="`$YUM check-update | $EGREP -v '(^(Geladene|Loading| ? |$)|running|available|Loaded)' | $AWK ' { if ($1=="Security:") { print $2 } else { print $1 } } '`"
	list=""
	for line in $lines
	do
		list="$list$line "
	done
	echo $list
}
function yum_check_package() {
	package="$1"
	#TODO
	echo "false"
}

###############
function apt_check_updates() {
	nr_updates=`apt_get_number_of_updates`
	nr_sec_updates=`apt_get_number_of_sec_updates`
	nr_locks=`apt_get_number_of_locks`
	nr_sources=`apt_get_number_of_sources`
	list_updates=`apt_get_list_all_updates`

	cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit"
	cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, $nr_locks packets are locked, $nr_sources used Paket-Sources"
	cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources"
}

function zypper_check_updates() {
	nr_updates=`zypper_get_number_of_updates`
	nr_sec_updates=`zypper_get_number_of_sec_updates`
	nr_locks=`zypper_get_number_of_locks`
	nr_sources=`zypper_get_number_of_sources`
	list_updates=`zypper_get_list_all_updates`

	cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit"
	cmk_describe="$nr_updates Patches ($list_updates), $nr_sec_updates Security Patches, $nr_locks packets are locked, $nr_sources used Paket-Sources"	
	cmk_describe_long="$nr_updates Patches ($list_updates) \\n$nr_sec_updates Security Patches \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources"	
}

function yum_check_updates() {
	nr_updates=`yum_get_number_of_updates`
	nr_sec_updates=`yum_get_number_of_sec_updates`
	nr_sources=`yum_get_number_of_sources`
	list_updates=`yum_get_list_all_updates`

	#TODO: check yum-plugin-versionlock; create function yum_check_package with Parameter "<packagename>"
	#cpackage=`yum_check_package "yum-plugin-versionlock"`
	#if [ "$cpackage" == "true" ]; then
		nr_locks=`yum_get_number_of_locks`
		cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit"
		cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, $nr_locks packets are locked, $nr_sources used Paket-Sources"
		cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources"
	#else
	#	nr_locks=0
	#	cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, !!package locks required yum-plugin-versionlock!!, $nr_sources used Paket-Sources"
	#	cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n!!package locks required yum-plugin-versionlock!!\\n$nr_sources used Paket-Sources"
	#fi
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

#Check Systemd os-release file
if test -f /etc/os-release ; then
	dist_id=`$CAT /etc/os-release | $EGREP -i "^id=" | $AWK -F '=' ' { print $2 } '`
else
	cmk_describe="Distribution failed to detect - no systemd platform?"
	cmk_describe_long="Distribution failed to detect - no systemd platform?"
	cmk_status=3
	output;
	exit 0;
fi

#choose packagemanager of distribution
case "$dist_id" in
	debian|ubuntu|linuxmint|raspbian)
		apt_check_updates
		;;
	*suse*|*sles*|*opensuse*)
		zypper_check_updates
		;;
	*centos*|*rhel*|*ol*)
		yum_check_updates
		;;
	*)
		cmk_describe="Distribution failed to detect - not on supported list, check for add ID from /etc/os-release to cmk-script."
		cmk_describe_long="Distribution failed to detect - not on supported list,\\ncheck for add ID from /etc/os-release to cmk-script."
		cmk_status=3
		;;
esac
output;
exit 0;
