# check_mk-linux-updates
This is a local script for check_mk to monitoring update-state of distributions with apt, zypper, yum or dnf

testet in cee-1.6.0

## Requirements
* systemd-platform (for detect distribution /etc/os-release)
* bash (cat,grep,egrep,wc,awk)
* apt (debian-goodies) or zypper or yum (with yum-plugin-versionlock , yum-utils) or dnf (python3-dnf-plugin-versionlock)
* extends the script by further distributions in section Main (with id from /etc/os-release), default distribution: Debian, Ubuntu, Linux Mint, raspbian, SLES12+, opensuse, Redhat, CentOS, OracleLinux

## Features
* detected number of all updates
* detected number of all security updates
* detected number of services or processes to reload
* detected required system reboot
* detected number of package locks 
* list alle packages to update
* create metrics
* creates status based on the thresholds for the metrics
* (detected number of all used sources)
* detected number of package locks (dnf in progress)

## Use local-check in check_mk
* supportet short output and long output. recommend to use long output. (Edit views for show column with long output)
* use in /usr/lib/check_mk_agent/local/CACHETIME/linux-updates.sh
* cache_time at least 30min
* don't use without cache-time
* in cee use bakery witch custom-checks  "linux-updates/lib/local/1800/linux-updates.sh"
* configure thresholds for all in script on section "Declaration var / const /command" 

## Default thresholds in script
* updates_warn=5
* updates_crit=10
* updates_sec_warn=1
* updates_sec_crit=3
* locks_warn=3
* locks_crit=5
* reboot_warn  (== no warn)
* reboot_crit=1
* reload_warn=1
* reload_crit=10
