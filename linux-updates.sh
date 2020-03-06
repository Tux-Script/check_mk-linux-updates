#!/bin/bash
#################################################################################################################
#                                  CMK-Script for monitoring updates on linux                                   #
#################################################################################################################
# Supported are apt,dnf,yum,zypper on Debian|Ubuntu|Mint|raspbian, Fedora, RHEL|CentOS|OracleLinux, SLES|opensuse
# systemd-platform for distribution detect required
# Version 1.2.2
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
declare -i reboot_warn
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
#require debian-goodies
function apt_checkrestart() {
        nr_reload="`$CHECKRESTART | $GREP restart | $WC -l`"
        rrpkgs_path="/var/run/reboot-required.pkgs"
        restart=""
        nr_packages_restart=0
        if  test -f "$rrpkgs_path" ; then
                nr_reboot="`$CAT $rrpkgs_path | $WC -l`"
                restart="$nr_reboot packages require system reboot"
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
	echo "`$ZYPPER --non-interactive list-patches | $GREP SLE | $WC -l`"
}
function zypper_get_number_of_sec_updates() {
	echo "`$ZYPPER --non-interactive list-patches | $GREP SLE | $GREP security | $WC -l`"
}
function zypper_get_number_of_locks() {
	echo "`$ZYPPER ll | $EGREP "^[0-9]" | $WC -l`"
}
function zypper_get_number_of_sources() {
	echo "`$ZYPPER repos | $EGREP '^[0-9]' | $AWK -F '|' ' { print $2 } '| $WC -l`"
}
function zypper_get_list_all_updates() {
	lines="`$ZYPPER --non-interactive list-updates | $GREP 'SLE' | $AWK -F '|' ' { print $3 } '`"
	list=""
	for line in $lines
	do
		list="$list$line "
	done
	echo $list
}
function zypper_checkrestart() {
        nr_reload="`$ZYPPER ps -s | $EGREP '^[0-9]* ' | $AWK -F '|' ' { print $6 } ' | uniq | $WC -l`"
        nr_reboot="`$ZYPPER ps -s | $GREP -q 'kernel' | $WC -l`"
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
	echo "`$YUM check-update | $EGREP -v '(^(Geladene|Loading| ? |$)|running|installed|Loaded)' | $WC -l`"
}
function yum_get_number_of_sec_updates() {
	echo "`$YUM check-update | $EGREP '^Security' | $EGREP -v '(running|installed)' | $AWK ' { print $2 } ' | $WC -l`"
}
#require package yum-plugin-versionlock
function yum_get_number_of_locks() {
	if yum_check_package "yum-plugin-versionlock"; then
		locks1="`$YUM versionlock list | $EGREP -v '^(Geladene|Loaded|versionlock list done$)' | $WC -l`"
		locks2="`cat /etc/yum.conf /etc/yum.repos.d/*.repo | grep 'exclude' | awk -F '=' ' {  print $2 } ' | wc -w`"
		echo $(($locks1 + $locks2)) 
	else
		echo "`$CAT /etc/yum.conf /etc/yum.repos.d/*.repo | $GREP 'exclude' | $AWK -F '=' ' {  print $2 } ' | $WC -w`"
	fi
}
function yum_get_number_of_sources() {
	echo "`$YUM repolist enabled | $EGREP -v '(Repo-ID|Plugins|repolist)' | $WC -l`"
}
function yum_get_list_all_updates() {
	lines="`$YUM check-update | $EGREP -v '(^(Geladene|Loading| ? |$)|running|installed|Loaded)' | $AWK ' { if ($1=="Security:") { print $2 } else { print $1 } } '`"
	list=""
	for line in $lines
	do
		list="$list$line "
	done
	echo $list
}
#require yum-utils
function yum_checkrestart() {
	if yum_check_package "yum-utils" ; then
		nr_reload="`$NEEDSRESTARTING | $EGREP -v '^1 :' | $EGREP '[0-9]* :' | $WC -l`"
		nr_reboot="`$NEEDSRESTARTING | $EGREP '^1 :' | $WC -l`"
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
		restart="required yum-utils for check restart"
	fi
		
}
function yum_check_package() {
	package="$1"
	if $YUM list installed "$package" > /dev/null 2>$1; then
                true
        else
                false
        fi
}

function dnf_get_number_of_updates() {
	echo "`$DNF check-update | $EGREP -v '(^(Geladene|Loading| * )|Metadaten|metadata|running|available|Loaded)' | $WC -l`" 
}
function dnf_get_number_of_sec_updates() {
	echo "`$DNF check-update | $EGREP '^Security' | $GREP -v 'running' | $AWK ' { print $2 } ' | $WC -l`"
}
function dnf_get_number_of_locks() {
	#TODO
	echo 0
}
function dnf_get_number_of_sources() {
	echo "`$DNF repolist --enabled | $GREP -v "\-ID" | $WC -l`"
}
function dnf_get_list_all_updates() {
	lines="`$DNF check-update | $EGREP -v '(^(Geladene|Loading| ? |$)|Metadaten|metadata|running|available|Loaded)' | $AWK ' { if ($1=="Security:") { print $2 } else { print $1 } } '`"
	list=""
	for line in $lines
	do
		list="$list$line "
	done
	echo $list
}
###############
function apt_check_updates() {
	nr_updates=`apt_get_number_of_updates`
	nr_sec_updates=`apt_get_number_of_sec_updates`
	nr_locks=`apt_get_number_of_locks`
	nr_sources=`apt_get_number_of_sources`
	list_updates=`apt_get_list_all_updates`

	apt_checkrestart

        cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit|Reboot=$nr_reboot;$reboot_warn;$reboot_crit|Reload=$nr_reload;$reload_warn;$reload_crit"
        cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, $nr_locks packets are locked, $nr_sources used Paket-Sources, $restart"
        cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources \\$restart"	
}

function zypper_check_updates() {
	nr_updates=`zypper_get_number_of_updates`
	nr_sec_updates=`zypper_get_number_of_sec_updates`
	nr_locks=`zypper_get_number_of_locks`
	nr_sources=`zypper_get_number_of_sources`
	list_updates=`zypper_get_list_all_updates`

	zypper_checkrestart

        cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit|Reboot=$nr_reboot;$reboot_warn;$reboot_crit|Reload=$nr_reload;$reload_warn;$reload_crit"
        cmk_describe="$nr_updates Patches ($list_updates), $nr_sec_updates Security Patches, $nr_locks packets are locked, $nr_sources used Paket-Sources, $restart"
        cmk_describe_long="$nr_updates Patches ($list_updates) \\n$nr_sec_updates Security Patches \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources \\n$restart"
}

function yum_check_updates() {
	nr_updates=`yum_get_number_of_updates`
	nr_sec_updates=`yum_get_number_of_sec_updates`
	nr_sources=`yum_get_number_of_sources`
	list_updates=`yum_get_list_all_updates`

	yum_checkrestart

        #TODO: check yum-plugin-versionlock; create function yum_check_package with Parameter "<packagename>"
        #cpackage=`yum_check_package "yum-plugin-versionlock"`
        #if [ "$cpackage" == "true" ]; then
                nr_locks=`yum_get_number_of_locks`
                cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit|Reboot=$nr_reboot;$reboot_warn;$reboot_crit|Reload=$nr_reload;$reload_warn;$reload_crit"
                cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, $nr_locks packets are locked, $nr_sources used Paket-Sources, $restart"
                cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources \\n$restart"
        #else
        #       nr_locks=0
        #       cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, !!package locks required yum-plugin-versionlock!!, $nr_sources used Paket-Sources"
        #       cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n!!package locks required yum-plugin-versionlock!!\\n$nr_sources used Paket-Sources"
        #fi
}

function dnf_check_updates() {
	nr_updates=`dnf_get_number_of_updates`
	nr_sec_updates=`dnf_get_number_of_sec_updates`
	nr_locks=`dnf_get_number_of_locks`
	nr_sources=`dnf_get_number_of_sources`
	list_updates=`dnf_get_list_all_updates`

	cmk_metrics="updates=$nr_updates;$updates_warn;$updates_crit|sec_updates=$nr_sec_updates;$updates_sec_warn;$updates_sec_crit|Sources=$nr_sources|Locks=$nr_locks;$locks_warn;$locks_crit"
	cmk_describe="$nr_updates Updates ($list_updates), $nr_sec_updates Security Updates, $nr_locks packets are locked, $nr_sources used Paket-Sources"
	cmk_describe_long="$nr_updates Updates ($list_updates) \\n$nr_sec_updates Security Updates \\n$nr_locks packets are locked \\n$nr_sources used Paket-Sources"
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
	dist_id=`$CAT /etc/os-release | $EGREP -i '^id=' | $AWK -F '=' ' { print $2 } '`
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
	*fedora*)
		dnf_check_updates
		;;
	*)
		cmk_describe="Distribution failed to detect - not on supported list, check for add ID from /etc/os-release to cmk-script."
		cmk_describe_long="Distribution failed to detect - not on supported list,\\ncheck for add ID from /etc/os-release to cmk-script."
		cmk_status=3
		;;
esac
output;
exit 0;
