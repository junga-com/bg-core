#!/bin/bash

# Library bg_coreDaemon.sh
# This library provides support for bash scripts that can be controlled as daemons. It is a core library meaning that you do not
# need to explicitly import (aka source) it, however, it only gets loaded if the script declares the daemonDefaultStartLevels variable
# and uses the daemonDeclare API.
# See Also:
#    daemonInvokeOutOfBandSystem : implements the control cui for a deamon script. called by invokeOutOfBandSystem when it
#         detects that the script is a daemon
#    daemonDeclare : used at the top of a daemon script to declare that its a daemon
#    daemonOut : called at the end of a daemon script when its about to exit gracefully

#############################################################################################################################################
### API for use in Daemon Scripts

# stub loader for function daemonDeclare() exists in bg_coreLibsMisc.sh

# usage: daemonDeclare "$@"
# putting this at the top of a script will identify the script as a daemon to the invokeOutOfBandSystem
# It will also initialize these global variables. Right after the call, the script can modify these values.
# but there are reasonable defaults for all of them. The most common variable to change are the descriptions
#     daemonName               : default ="$(basename $0)"
#     daemonShortDesc          : default ="server daemon for $daemonName"
#     daemonDesc               : default ="$daemonShortDesc"
#   SysV start/stop conditions
#     daemonCntrCmds_whileRunning: default ="stop status restart reload auto setDefaultCmdLine waitFor"
#     daemonCntrCmds_whileStopped: default ="start status auto setDefaultCmdLine waitFor"
#     daemonStartDependencies  : default ='$remote_fs $syslog'
#     daemonStopDependencies   : default ='$remote_fs $syslog'
#     daemonDefaultStartLevels : default ="2 3 4 5"
#     daemonDefaultStopLevels  : default ="0 1 6"
#   Upstart start/stop conditions
#	  daemonStartDepsUpstart   : default ="filesystem"
#	  daemonStopDepsUpstart    : default ="shutdown"
function daemonDeclare()
{
	declare -g daemonName="$(basename $0)"
	while [[ "$1" =~ ^- ]]; do case $1 in
		--stub) ;;
        -N) daemonName="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	declare -g daemonShortDesc="server daemon for (TODO:)"
	declare -g daemonDesc="(TODO:) see man ${0##*/}"

	# SysV start/stop conditions
	declare -g daemonStartDependencies='$remote_fs $syslog'
	declare -g daemonStopDependencies='$remote_fs $syslog'
	declare -g daemonDefaultStartLevels="2 3 4 5"
	declare -g daemonDefaultStopLevels="0 1 6"

	# Upstart start/stop conditions
	declare -g daemonStartDepsUpstart="filesystem"
	declare -g daemonStopDepsUpstart="shutdown"

	declare -g daemonCntrCmds_whileRunning="stop status restart reload auto waitFor"
	declare -g daemonCntrCmds_whileStopped="start status auto waitFor"


	declare -g daemonLogFile="/var/log/$daemonName"
	declare -g daemonErrorFile="$daemonLogFile"
}

# usage: daemonOut
# this is typically the last line in a daemon script.
# it signals that the daemon has shutdown gracefully
function daemonOut()
{
	echo "" > "/var/run/$daemonName.pid"
}

# usage: daemonLogSetup [-q] [-v] [--verbosity=<level>]
# this sets or modifies the daemonVerbosity and (eventually) other things that effect what happens when daemonLog is called.
function daemonLogSetup()
{
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q) ((daemonVerbosity--)) ;;
		-v) ((daemonVerbosity++)) ;;
		--verbosity*) daemonVerbosity="$(bgetopt "$@")" && shift ;;
		-H*|--headerFormat*)  bgOptionGetOpt val: daemonLogHeaderFormat "$@" && shift ;;
	esac; shift; done
}

# usage: daemonLog [-f<format>] [--pipe] [-v <logLevel>] ...
# similar to echo/printf but it adds some formating that makes the output appropriate for a daemon's log file
# It outputs to stdout because daemon scripts created with this library write to stdout which
# will be redirected to the daemons log file when its ran as a daemon
# Options:
#     -f <formatStr> : If specified, it will be used as the format string to printf and the positional parameters in the cmdline.
#                      The argumets passed must match the %s terms in the format string.
#     -v|--reqVerbosity=<reqVerbosity> : the log message will only be sent if the current daemonVerbosity is set to <reqVerbosity> or higher.
#                         the default is 1 which is the typical starting point which means -q will suppress it
#     --pipe          : If specified, the data to be printed to the log will be read from stdin instead of the cmdline. --pipe and
#                       --format can not be used together
function daemonLog()
{
	local format reqVerbosity=1 pipeFlag
	while [ $# -gt 0 ]; do case $1 in
		-f*|--format*)       bgOptionGetOpt val: format       "$@" && shift ;;
		-v*|--reqVerbosity*) bgOptionGetOpt val: reqVerbosity "$@" && shift ;;
		--pipe)              pipeFlag="--pipe" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ ${reqVerbosity} -le ${daemonVerbosity:-1} ] || return

	# we write to stdout because the daemon that calls this will have stdout redirected to the log file if its running as a daemon

	(
		# note that even if a user is running the daemon attached to a terminal for debugging, we can use the log file as a mutex name
		local lockID; startLock -w5 -u lockID "/var/log/${daemonName:-$(basename $0)}" || bgtrace "daemonLog: timeout (5s) waiting for logFile lock '/var/log/${daemonName:-$(basename $0)}'"

		local header="${daemonLogHeaderFormat:-%Y-%m-%d:%H:%M:%S }"

		if [ "$pipeFlag" ]; then
			gawk -v header="$header"'
				NR==1 {printf(header"%s\n", $0)}
				NR>1 {printf("  | %s\n", $0)}
			'
		elif [ "$format" ]; then
			printf "$header$format" "$@" | awk 'NR==1 {print} NR>1 {print "  | "$0}'
		else
			printf "$header%s" "$*" | awk 'NR==1 {print} NR>1 {print "  | "$0}'
		fi
	)
}


# usage: daemonSignalHandler <sigSpec>
# usage: bgtrap 'daemonSignalHandler <sigSpec>'  <sigSpec>
# A script can use this handler to trap a signal when it wants to process signals at a predictable point.
# Typically a daemon would do this and then in its main loop, call if daemonIsSignalPresent SIGx; then ...
# For example if the daemon uses SIGHUP to reload its config file, this makes it so the config won't change
# in the middle of the script performing some action. Once per loop, the script will check and reload the
# config if called for and then the rest of the algorithm knows that the config is stable while it is executing
# Note that bash already provides for signals not interrupting commands
# Param:
#     <sigSpec> : can be any token understood by kill. e.g. (SIGUSR1, USR1, usr1, and 10) all refer to signal 10
# See Also:
#    daemonInvokeOutOfBandSystem   -- sets the traps for the main daemon by calling daemonInstalSdtSignalHandler
#    daemonInstalSdtSignalHandler  -- installs daemonSignalHandler for the common signals (<sigSpec>)
#    daemonSignalHandler           -- called by traps to communicate with this function.
function daemonSignalHandler()
{
	# create the daemonSIGs array on first use
	if ! declare -p daemonSIGs &>/dev/null; then
		declare -gA daemonSIGs
	fi

	local sig; sig=$(signalNorm "$1") || return

	# for INT or TERM,  if there is still an outstanding interrupt that has not yet been consumed, exit the process.
	# If the daemon scipt has a trivial loop that does not call "daemonCheckForSignal INT TERM" then this logic will still allow
	# the user to exit the daemon
	[[ "$sig" =~ ^(INT|TERM)$ ]] && (( daemonSIGs[$sig] > 0 )) && exit 1

	((daemonSIGs[$sig]++))

	# pass on the signal to our children
	kill -$sig $(jobs -p) &>/dev/null

}

# usage: daemonCheckForSignal <sigSpec> [... <sigSpec>]
# Checks to see if any of the specified <sigSpec> have been raised for the current thread since the last time it was checked
# If yes, it returns true(0) and resets or modifies the signal's count according to the -n option.
# If no, it return false(1)
# This function assumes that the current thread has traps installed on the <sigSpecs> that communicate
# with this function. daemonInvokeOutOfBandSystem does that automatically for the main thread by calling
# daemonInstalSdtSignalHandler before passing control onto the script
# Param:
#     <sigSpec> : can be any token understood by kill. e.g. (SIGUSR1, USR1, usr1, and 10) all refer to signal 10
# Options:
#     -n <consumeCount> : this many occurances will be consumed. The default is 'infinite' so that the signal count
#          will be reset to 0 no matter how many times the signal had been caught since the last check. If -n is set to 1
#          this function will return true a number of times equal to the times the signal is caught. If -n is set to 0
#          it will return if the signal has been caught without reseting it
#          Typical values are infinite, 1, and 0. Any non-numeric value or "" is taken as infinite
# See Also:
#    daemonInvokeOutOfBandSystem   -- sets the traps for the main daemon by calling daemonInstalSdtSignalHandler
#    daemonInstalSdtSignalHandler  -- installs daemonSignalHandler for the common signals (<sigSpec>)
#    daemonSignalHandler           -- called by traps to communicate with this function.
function daemonCheckForSignal()
{
	local consumeCount=""
	while [[ "$1" =~ ^- ]]; do case $1 in
		-n) consumeCount="$(bgetopt "$@")" && shift
			# if its not a number, set it to "" which means infinite == reset the count to 0 no matter what its value is
			[ "$consumeCount" != "0" ] && [ ${consumeCount:-0} -eq 0 ] && consumeCount=""
			;;
	esac; shift; done

	# create the daemonSIGs array on first use
	if ! declare -p daemonSIGs &>/dev/null; then
		declare -gA daemonSIGs
	fi

	local result=1
	while [ $# -gt 0 ]; do
		local sig; signalNorm "$1" sig; shift

		if [ ${daemonSIGs[$sig]:-0} -gt 0 ]; then
			result=0
			if [ "$consumeCount" ]; then
				(( ${daemonSIGs[$sig]} -= ${consumeCount} ))
				return $result
			else
				daemonSIGs[$sig]=0
			fi
		fi
	done
	return $result
}


# usage: daemonInstalSdtSignalHandler <sigSpec> [... <sigSpec>]
# installs the standard daemon signal handler for the current thread.
# daemonInvokeOutOfBandSystem does this automatically for the main daemon thread but if your script
# spawns additional long running threads, they should call this.
# The standard handler increments a global var and passes the signal on to all children.
# The main loop of the daemon, can call daemonCheckForSignal to perform an action synchronously
# to its algorithm if a particular signal has been received since the last time it was called.
# Param:
#     <sigSpec> : can be any token understood by kill. e.g. (SIGUSR1, USR1, usr1, and 10) all refer to signal 10
# See Also:
#    daemonInvokeOutOfBandSystem   -- sets the traps for the main daemon by calling daemonInstalSdtSignalHandler
#    daemonInstalSdtSignalHandler  -- installs daemonSignalHandler for the common signals (<sigSpec>)
#    daemonSignalHandler           -- called by traps to communicate with this function.
function daemonInstalSdtSignalHandler()
{
	# create the daemonSIGs array on first use
	if ! declare -p daemonSIGs &>/dev/null; then
		declare -gA daemonSIGs
	fi

	while [ $# -gt 0 ]; do
		local sig; sig=$(signalNorm "$1") || return; shift
		bgtrap "daemonSignalHandler $sig" "$sig"
	done
}






#############################################################################################################################################
### Daemon Control Functions



# usage: daemonCntrIsModernType <daemonName>
# Installing an upstart or systemd script is optional but if its done, all control needs to go through it or the upstart
# process will loose track and two daemons might get started.
# This helper is used in most of the control operations to direct to upstart/systemd if needed.
# The paradigm these functions follow is that if upstart is not installed, daemonCntrStart and daemonCntrStop will
# do the start and stop directly the same whether they are called from the daemon command directly or from
# its /etc/init.d/<daemonName> script. If the upstart script is installed, however, then they will call upstart
# to do those operations regardless of whether they are called from the daemon command directly or from
# its /etc/init.d/<daemonName> script.
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
# Exit Codes:
#    0 : the specified daemon has an upstart script
#    1 : the specified daemon does not have an upstart script
function daemonCntrIsModernType()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift
	[ -f /etc/init/$daemonName.conf ] || [ -f /lib/systemd/system/$daemonName.service ]
}

# usage: daemonCntrGetType <daemonName>
# returns the type of start up mechanism installed, if any
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
# Return:
#    none    : no start mechanism is installed
#    sysv    : only the old style /etc/init.d/<name> script is installed
#    upstart : the upstart job in /etc/init/<name>.conf is installed and used
#    systemd : the systemd unit in /lib/systemd/system/<name>.service is installed and used
function daemonCntrGetType()
{
	local daemonName="${1:-$daemonName}"; [ $# -gt 0 ] && shift
	if [ -f /lib/systemd/system/$daemonName.service ]; then
		echo "systemd"
	elif [ -f /etc/init/$daemonName.conf ]; then
		echo "upstart"
	elif [ -f /etc/init.d/$daemonName ]; then
		echo "sysv"
	else
		echo "none"
	fi
}

# usage: daemonCntrIsEnabled [-q] <daemonName>
# returns whether the daemon is currently configured to start automatically
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
# Options:
#    -q  : quiet. no output. only the exit code conveys the result
# Exit Code:
#    0 (enabled)    : the daemon will start automatically.
#    1 (disabled)   : the daemon will not start automatically.
function daemonCntrIsEnabled()
{
	local quietFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q) quietFlag="-q"
	esac; shift; done
	local daemonName="$1"; [ $# -gt 0 ] && shift

	local result="disabled"
	if [ -f /lib/systemd/system/$daemonName.service ]; then
		result="$(systemctl is-enabled $daemonName)"
	elif [ -f /etc/init/$daemonName.conf ]; then
		[ ! -f /etc/init/$daemonName.override ]  && result="enabled"
	elif [ -f /etc/init.d/$daemonName ]; then
		[ "$(find /etc/rc*.d/ -name "S*$daemonName")" ] && result="enabled"
	fi

	[ ! "$quietFlag" ] && echo "$result"
	[ "$result" == "enabled" ]
}


# usage: daemonCntrEnable [-q] <daemonName>
# enable the daemon to automatically start
# The auto mechanism has two states. Whether it is installed using sysv,upstart, or systemd and whether
# the installed mechanism is configured to automatically start.
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
function daemonCntrEnable()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift

	if [ -f /lib/systemd/system/$daemonName.service ]; then
		systemctl enable $daemonName >/dev/null
	elif [ -f /etc/init/$daemonName.conf ]; then
		[ -f /etc/init/$daemonName.override ] && rm -f /etc/init/$daemonName.override
	elif [ -f /etc/init.d/$daemonName ]; then
		update-rc.d -f "$daemonName" defaults >/dev/null
	else
		assertError "no auto mechanism is installed for this daemon. run 'auto install' subcommand"
	fi
}

# usage: daemonCntrDisable <daemonName>
# disable the daemon from automatically starting
# The auto mechanism has two states. Whether it is installed using sysv,upstart, or systemd and whether
# the installed mechanism is configured to automatically start.
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
function daemonCntrDisable()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift

	if [ -f /lib/systemd/system/$daemonName.service ]; then
		systemctl disable $daemonName >/dev/null
	elif [ -f /etc/init/$daemonName.conf ]; then
		echo "manual" > /etc/init/$daemonName.override
	elif [ -f /etc/init.d/$daemonName ]; then
		update-rc.d -f "$daemonName" remove &>/dev/null
	fi
}

# usage: daemonCntrGetDefaultAutoStartType [<retVar>]
# return the prefered type of daemon control mechanism on this host
function daemonCntrGetDefaultAutoStartType()
{
	local autoStartType
	if which start >/dev/null; then
		autoStartType=upstart
	elif which systemctl >/dev/null; then
		autoStartType=systemd
	else
		autoStartType=sysv
	fi
	returnValue "$autoStartType" "$1"
}

# usage: daemonCntrIsAutoStartInstalled <daemonName> [<autoStartType>]
# return true(0) or false(1) to indicate whether this <daemonName> is installed in the specified autoStart mechanism.
# Params:
#     <daemonName>    : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
#     <autoStartType> : one of sysv,upstart,systemd,any "any" will pick the best default for how the host is configured
function daemonCntrIsAutoStartInstalled()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift
	local autoStartType="$1"; [ $# -gt 0 ] && shift

	case ${autoStartType,,} in
		sysv|any)
			[ -f /etc/init.d/$daemonName ] && return 0
			;;&

		upstart|any)
			if which start >/dev/null; then
				[ -f /etc/init/$daemonName.conf ] && return 0
			fi
			;;

		systemd|any)
			[ -f /lib/systemd/system/$daemonName.service ] && return 0
			;;
	esac
	return 1
}


# usage: daemonCntrInstallAutoStart <daemonName> [<autoStartType>]
# install an auto start mechanism for this daemon (sysv,upstart,systemd)
# The auto mechanism has two states. Whether it is installed using sysv,upstart, or systemd and whether
# the installed mechanism is configured to automatically start.
# Params:
#     <daemonName>    : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
#     <autoStartType> : one of sysv,upstart,systemd,any "any" will pick the best default for how the host is configured
function daemonCntrInstallAutoStart()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift
	local autoStartType="$1"; [ $# -gt 0 ] && shift

	# choose the default based on whats installed on this host
	if [ "${autoStartType:-any}" == "any" ]; then
		daemonCntrGetDefaultAutoStartType autoStartType
	fi

	case ${autoStartType,,} in
		sysv)
			# install the sysv init script
			cat <<-EOS > /etc/init.d/$daemonName
				#! /bin/bash
				### BEGIN INIT INFO
				# Provides:          $daemonName
				# Required-Start:    $daemonStartDependencies
				# Required-Stop:     $daemonStopDependencies
				# Default-Start:     ${daemonDefaultStartLevels:-2 3 4 5}
				# Default-Stop:      ${daemonDefaultStopLevels:-0 1 6}
				# Short-Description: $daemonShortDesc
				# Description:       $daemonDesc
				# Usage: /etc/init.d/$daemonName {${daemonCntrCmds_whileRunning// /|}}
				### END INIT INFO

				# This file is generated by '$daemonName auto installSysV'
				# see 'man ${0##*/}' for details

				# daemonLogFile="/var/log/$daemonName"
				# daemonErrorFile="$daemonLogFile"

				export daemonCalledFromInitD="1"
				export TZ=UTC

				$0 -N$daemonName "\$@" "$@"
			EOS
			chmod a+x /etc/init.d/$daemonName
			;;

		upstart)
			which start >/dev/null || assertError "this host does not seem to support the upstart system (no 'start' command)"

			# install the Upstart script if called for.
			cat <<-EOS > /etc/init/$daemonName.conf
				# This file is generated by '$daemonName auto installUpstart'
				# see 'man ${0##*/}' for details

				# daemonLogFile="$daemonLogFile"
				# daemonErrorFile="$daemonErrorFile"

				description "$daemonShortDesc"
				author "$projectName package"
				start on $daemonStartDepsUpstart
				stop on $daemonStopDepsUpstart
				respawn
				respawn limit 2 5
				exec TZ=UTC $0 -FN"$daemonName" "$@" >>$daemonLogFile 2>>$daemonErrorFile </dev/null
			EOS
			;;

		systemd)
			# install the Systemd script if called for.
			cat <<-EOS > /lib/systemd/system/$daemonName.service
				[Unit]
				Description="$daemonShortDesc"
				Documentation=man:${0##*/}(1)

				[Service]
				Type=simple
				ExecStart=$0 -O -D -F -N"$daemonName" "$@"
				#Environment="bgTracingOn=file:"
				Environment="TZ=UTC"
				Restart=on-failure

				[Install]
				WantedBy=multi-user.target
			EOS
			;;
	esac

	daemonCntrEnable $daemonName
}


# usage: daemonCntrUninstallAutoStart <daemonName> [<autoStartType>]
# uninstall any auto start mechanism for this daemon (sysv,upstart,systemd)
# The auto mechanism has two states. Whether it is installed using sysv,upstart, or systemd and whether
# the installed mechanism is configured to automatically start.
# Params:
#     <daemonName>    : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
#     <autoStartType> : one of sysv,upstart,systemd,any "any" will pick the best default for how the host is configured
function daemonCntrUninstallAutoStart()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift
	local autoStartType="${1:-any}"; [ $# -gt 0 ] && shift

	case ${autoStartType,,} in
		sysv|any)
			if daemonCntrIsAutoStartInstalled sysv; then
				update-rc.d -f "$daemonName" remove &>/dev/null
				rm -f /etc/init.d/$daemonName &>/dev/null
			fi
		;;&

		upstart|any)
			if daemonCntrIsAutoStartInstalled upstart; then
				rm -f /etc/init/$daemonName.conf  &>/dev/null
				rm -f /etc/init/$daemonName.override  &>/dev/null
			fi
		;;&

		systemd|any)
			if daemonCntrIsAutoStartInstalled systemd; then
				systemctl disable $daemonName &>/dev/null
				rm -f /lib/systemd/system/$daemonName.service  &>/dev/null
			fi
		;;&
	esac
}




# usage: daemonCntrIsRunning [-P<pidVarName>] <daemonName>
# A daemon is a singleton process ran as its own session leader (SID) and writes its output to a log file
# A daemon process is identified by its pidFile in /var/run/<daemonName> not its executable name.
# returns true if running, false if not
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
# Options:
#     -P <pidVarName> : the pid of the named daemon will be returned in this variable name if its running
# Exit Codes:
#    0 : running. the specified process is running
#    1 : crashed. the pid is no longer running. If a pidFile was specified, this indicates a crash (non-graceful termination)
#    2 : stopped. the pidFile does not exist or is empty, indicating the proc is in the graceful shutdown state
function daemonCntrIsRunning()
{
	local pidVarName dcir_pidValue dcir_result
	while [[ "$1" =~ ^- ]]; do case $1 in
		-P*) pidVarName="$(bgetopt "$@")" && shift
	esac; shift; done
	local daemonName="$1"; [ $# -gt 0 ] && shift

	local daemonPIDFile="/var/run/$daemonName.pid"

	[ -f "$daemonPIDFile" ] && read -r dcir_pidValue < "$daemonPIDFile"

	case $(daemonCntrGetType "$daemonName") in
		upstart)
			if [[ "$(status "$daemonName")" =~ ^$daemonName\ start/((running)|(starting)|(pre-start)|(spawned)|(post-start)) ]]; then
				dcir_result="0"
			elif [[ "$(status "$daemonName")" =~ ^$daemonName\ start/ ]]; then
				# other start/ states are on the way down
				dcir_result="1"
			else
				dcir_result="2"
			fi
			;;
		systemd)
			# ActiveState=failed|inactive|active|activating|deactivating
			case $(systemctl show --property=ActiveState "$daemonName") in
				*inactive) dcir_result="2" ;;
				*failed)   dcir_result="1" ;;
				*)         dcir_result="0" ;;
			esac
			;;
		sysv|none)
			procIsRunning -f "$daemonPIDFile" -P dcir_pidValue
			dcir_result="$?"
			;;
	esac

	setReturnValue "$pidVarName" "$dcir_pidValue"
	return $dcir_result
}

# usage: daemonCntrStart <daemonName> [ <parameters...> ]
# A daemon is a singleton process ran as its own session leader (SID) and writes its output to a log file
# A daemon is identified by its pidFile in /var/run/<daemonName> not its executable name.
# This will start the daemon if its not already running
# It assumes that the way to create the new daemon process is "$0 -FN<daemonName> $@" -- that is, rerun the current script
# adding the -FN<daemonName> option which is a convention that says the script should run the daemon algorithm loop.
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
# Options:
#     -P <pidVarName> : the pid of the named daemon will be returned in this variable name if its running
# Exit Codes:
#    0 : the specified daemon was started
#    1 : the specified daemon was already running
#    2 : the specified daemon failed to start
function daemonCntrStart()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift

	daemonCntrIsRunning "$daemonName" && return 1

	local daemonType="$(daemonCntrGetType "$daemonName")"
	case $daemonType in
		upstart) start "$daemonName" >/dev/null ;;
		systemd)
			systemctl start "$daemonName"
		 	;;
		sysv|none)
			local daemonPIDFile="/var/run/$daemonName.pid"
			local daemonLogFile="/var/log/$daemonName"

			(echo "" > "$daemonPIDFile") 2>/dev/null || assertError "USER='$USER' can not write to run file '$daemonPIDFile'"

			local daemonErrorFile="$daemonLogFile"

			# re-run with setid (new linux session leader) and redirected std* file and in the background (&)
			local -a originalParams
			daemon_oob_ReadDefaultCmdLineParams "$daemonName" originalParams
			setsid $0 -FN"$daemonName" "${originalParams[@]}" "$@" -D >>$daemonLogFile 2>>$daemonErrorFile </dev/null &
			;;
	esac

	# wait a little to see if it starts. When it starts, it writes its pid to the pidFile
	daemonCntrWaitFor -w5 "$daemonName" start || return 2
}



# usage: daemonCntrStop <daemonName>
# A daemon is a singleton process ran as its own session leader (SID) and writes its output to a log file
# A daemon is identified by its pidFile in /var/run/<daemonName> not its executable name.
# This will stop the daemon if its running
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
# Options:
#     -P <pidVarName> : the pid of the named daemon will be returned in this variable name if its running
# Exit Codes:
#    0 : the specified daemon is now stopped (regardless of whether is was running or not)
#    1 : the specified daemon could not be stopped and is still running
function daemonCntrStop()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift
	local daemonPIDFile="/var/run/$daemonName.pid"
	local daemonPID

	# if its already stopped, make sure the PID file is cleaned up and then we are done
	# This has the effect that if it crached, calling stop will clear the failed state.
	if ! daemonCntrIsRunning -P daemonPID "$daemonName"; then
		echo "" > $daemonPIDFile
		return 0
	fi

	case $(daemonCntrGetType "$daemonName") in
		upstart) stop "$daemonName" >/dev/null ;;
		systemd) systemctl stop "$daemonName" >/dev/null ;;
		sysv|none)
			kill "$daemonPID" &>/dev/null || sudo kill "$daemonPID"

			# wait a little to see if it stops. If not, try killing it with -9
			if ! daemonCntrWaitFor -w5 "$daemonName" stop; then
				kill -9 "$daemonPID" &>/dev/null || sudo kill -9 "$daemonPID"
				daemonCntrWaitFor -w2 "$daemonName" stop || return 1
			fi
			;;
	esac

	daemonCntrWaitFor -w5 "$daemonName" stop || return 1
	return 0
}


# usage: daemonCntrTailLog <selectVerbosity>
# This is a helper function for the interactive control commands (start,stop,restart,reload,status)
# that lets them all implement the feature that -v,-vv,-vvv will tail some log information after the
# work they do.
# Params:
#     <selectVerbosity> : specifies what to do. Corresponds to the verbosity controlled by -v and -q
#           1 : tail 3 lines, intended. do not follow
#           2 : tail and follow the daemon log file
#           3 : tail and follow the control log (like systemd/upstart messages
#           default : do nothing
function daemonCntrTailLog()
{
	local selectVerbosity="$1"; [ $# -gt 0 ] && shift
	case ${selectVerbosity:-0} in
		1|2)
			if [ ! -f "$daemonLogFile" ]; then
				echo "the daemon has not yet created the log file '$daemonLogFile'"
				return
			fi
			;;&
		1) 	tail -n3 "$daemonLogFile" | awk '{print "   > "$0}' ;;
		2) 	printf "\n${CSI}${cBold}%s${CSI}${cNorm}\n" "tail -f $daemonLogFile"
			tail -f $daemonLogFile
			;;
		3) 	case $(daemonCntrGetType "$daemonName") in
				systemd)
					printf "\n${CSI}${cBold}%s${CSI}${cNorm}\n" "journalctl -f -n20 --unit=${daemonName}.service"
					journalctl -f -n20 --unit=${daemonName}.service
					;;
				upstart)
					echo "FIX ME: -vvv not implemented for upstart configs. have not spent time to figure out where the upstart messages are yet in a good way"
					;;
			esac
			;;
	esac
}


# usage: daemonCntrWaitFor [-w<timeout>] <daemonName> start|stop
# A daemon is a singleton process ran as its own session leader (SID) and writes its output to a log file
# A daemon is identified by its pidFile in /var/run/<daemonName> not its executable name.
# This will wait until the daemon enters the specified state or the timeout is reached.
# Params:
#     <daemonName> : specifies the name of the daemon. Must be unique in /var/run/<daemonName>
#     start|stop   : specifies which daemon state to wait for.
# Options:
#     -w <timeout> : the number of seconds to wait for the daemon to enter the specified state
# Exit Codes:
#    0 : the daemon is in the specified state
#    1 : the daemon is NOT in the specified state because timeout was reached
function daemonCntrWaitFor()
{
	local timeout
	while [[ "$1" =~ ^- ]]; do case $1 in
		-w*) timeout="$(bgetopt "$@")" && shift
			timeout="${timeout//[.]}"
			[[ "$timeout" =~ ^[0-9]*$ ]] || timeout=""
			;;
	esac; shift; done

	local daemonName="$1"; [ $# -gt 0 ] && shift
	local targetState="$1"; [ $# -gt 0 ] && shift

	local daemonPIDFile="/var/run/$daemonName.pid"
	local daemonPID
	local pollPeriod="0.5"

	# loop until either the timeout has elapsed or the daemon in in the specified state
	local i; for ((i=1; i>0; i++)); do
		procIsRunning -f "$daemonPIDFile" -P daemonPID
		local state="$?"
		case $state:$targetState in
			0:start) return 0 ;;
			0:stop)  : ;;
			*:stop)  return 0 ;;
		esac
		[ "$timeout" ] && bgFloatCond "(${pollPeriod:-0.5} * ${i:-0} ) > ${timeout:-5}"  && return 1
		sleep ${pollPeriod:-0.5}
	done
	return 0
}

# usage: cr_daemonRunningStateIs <daemonName> on|off
DeclareCreqClass cr_daemonRunningStateIs
function cr_daemonRunningStateIs::check() {
	daemonName="$1"; shift
	targetState="${1,,}"
	[[ "$targetState" =~ ^(on|off)$ ]] || assertError "the second argument should be 'on' or 'off' (case insensitive)"
	if [ "$targetState" == "on" ]; then
		daemonCntrIsRunning "$daemonName"
	else
		! daemonCntrIsRunning "$daemonName"
	fi
}
function cr_daemonRunningStateIs::apply() {
	if [ "$targetState" == "on" ]; then
		daemonCntrStart "$daemonName"
	else
		daemonCntrStop "$daemonName"
	fi
}


# usage: cr_daemonAutoStartIsSetTo <daemonName> sysv|upstart|systemd|none|any|default  enabled|disabled
# declare that the daemon auto start is enabled or disabled
# Apply will install the specified type of control file and set it to the specified enabled/disabled state
DeclareCreqClass cr_daemonAutoStartIsSetTo
function cr_daemonAutoStartIsSetTo::check() {
	daemonName="$1"
	targetType="${2:-any}"
	targetState="${3:-disabled}"
	assertNotEmpty daemonName
	[ "$targetType" == "default" ] && daemonCntrGetDefaultAutoStartType targetType
	[[ "$targetType" =~ ^(sysv|upstart|systemd|none|any)$ ]] || assertError "targetType should be one of sysv|upstart|systemd|none|any"
	{ [ "$targetType" != "none" ] && [[ ! "$targetState" =~ ^(enabled|disabled)$ ]]; } && assertError "targetState should be one of enabled|disabled"

	local curType="$(daemonCntrGetType $daemonName)"
	local curAutoState="$(daemonCntrIsEnabled $daemonName)"

	if [ "$targetType" == "any" ]; then
		[ "$curType" != "none" ] && [ "$targetState" == "$curAutoState" ]
	else
		[ "${targetType,,}" == "${curType,,}" ] && [ "$targetState" == "$curAutoState" ]
	fi
}
function cr_daemonAutoStartIsSetTo::apply() {
	case $targetType in
		sysv)
			$daemonName auto installSysV
			$daemonName auto uninstallSystemd
			$daemonName auto uninstallUpstart
			$daemonName auto "${targetState:0:-1}"
			;;
		upstart)
			$daemonName auto installUpstart
			$daemonName auto uninstallSystemd
			$daemonName auto uninstallSysV
			$daemonName auto "${targetState:0:-1}"
			;;
		systemd)
			$daemonName auto installSystemd
			$daemonName auto uninstallUpstart
			$daemonName auto uninstallSysV
			$daemonName auto "${targetState:0:-1}"
			;;
		none)
			$daemonName auto uninstall
			;;
		any)
			$daemonName auto install
			$daemonName auto "${targetState:0:-1}"
			;;
	esac
}












###############################################################################
### Daemon Script Out of band (OOB) Implemenation
# These functions are called from the invokeOutOfBandSystem function when
# a call to 'daemonDeclare' is included at the top of the script
# They implement the standard control cmds and BC for those commands
# They respect the oob_ functions that a daemon script defines for its own purposes
# and define a new oob_daemonCntr function that a script can define to extend the
# control functions.

# usage: daemon_oob_getRequiredUserAndGroup "$@"
# This function is called from the invokeOutOfBandSystem function when a call to 'daemonDeclare' is included at the top of the script
# This handles the oob_getRequiredUserAndGroup for the standard daemon command line syntax.
# If the script's oob_getRequiredUserAndGroup returns a value it will override the one this function returns
function daemon_oob_getRequiredUserAndGroup()
{
	bgCmdlineParse "hN:FvDqO" "$@"; shift "${options["shiftCount"]}"
	# this sets the required user for the real daemon proc invocation
	if [ "${options[-F]}" ]; then
		if [ "$(type -t oob_getRequiredUserAndGroup)" ]; then
			oob_getRequiredUserAndGroup "$@"
		fi
		return
	fi

	local daemonName="${options["-N"]:-${0##*/}}"
	local daemonType="$(daemonCntrGetType "$daemonName")"

	local cntrCmd="$1"; shift

	# the -N option can be to the script or to the cntrCmd so check the options again.
	bgCmdlineParse "hN:vqO" "$@"; shift "${options["shiftCount"]}"
	local daemonName="${options["-N"]:-$daemonName}"

	# this sets the required user for the control commands
	# Note that type 'none' still needs root even if the daemon does not b/c we need to write to the pid and log files in the
	# system folders
	case $daemonType:$cntrCmd in
		# This daemon requires the user to be root to start,stop, or reload it
		*:start|*:stop|*:reload|*:setDefaultCmdLine)
			echo "root"
			return
			;;
		*:auto)
			case ${posWords[2]} in
				enable|disable|install|installSysV|installUpstart|installSystemd|uninstallSysV|uninstallUpstart|uninstallSystemd|uninstall)
					echo "root"
					return
					;;
			esac
			;;
	esac
}


# usage: daemon_oob_printBashCompletion "$@"
# This function is called from the invokeOutOfBandSystem function when a call to 'daemonDeclare' is included at the top of the script
# This handles the oob_printBashCompletion for the standard daemon command line syntax.
# The script's oob_printBashCompletion will be called after this and can add to suggestions
function daemon_oob_printBashCompletion()
{
	bgBCParse "hN:FvDqO" "$@"; set -- "${posWords[@]:1}"

	# if the user is running in the foreground for testing, don't complete on the control cmds
	if [[ "${optWords[@]}" =~ -[F] ]]; then
		exit
	fi

	cntrCmd="$1"

	case $cntrCmd:$posCwords in
		*:1)
			daemonCntrIsRunning "$daemonName"
			local runState=$?
			case $runState in
				# running
				0) echo "<running> ${daemonCntrCmds_whileRunning[@]}" ;;
				# crashed
				1) echo "<crashed>  restart ${daemonCntrCmds_whileStopped[@]}" ;;
				# stopped
				2) echo "<stopped> ${daemonCntrCmds_whileStopped[@]}" ;;
				*) echo "<unknown_run_state> ${daemonCntrCmds_whileRunning[@]} ${daemonCntrCmds_whileStopped[@]}"
			esac
			;;
		auto:2)
			local installState="$(daemonCntrGetType "$daemonName")"
			case $installState in
				none) echo "<no_auto_config_installed> installSysV installUpstart installSystemd install status" ;;
				*)
					local enabledState="$(daemonCntrIsEnabled $daemonName)"
					case $enabledState in
						enabled)  echo "<${installState}_${enabledState}> disable uninstall status" ;;
						disabled) echo "<${installState}_${enabledState}> enable uninstall status" ;;
					esac
					;;
			esac
			;;
	esac
}

# usage: daemon_oob_printOptBashCompletion "$@"
# This function is called from the invokeOutOfBandSystem function when a call to 'daemonDeclare' is included at the top of the script
# This handles the oob_printOptBashCompletion for the standard daemon command line syntax.
# The script's oob_printOptBashCompletion can add to suggestions
function daemon_oob_printOptBashCompletion()
{
	local opt="$1"
	local cur="$2"
	case $opt in
		N) echo "> <daemonName> $(basename $0)"
	esac
}


# usage: daemon_oob_ReadDefaultCmdLineParams <daemonName> <paramsAryVar>
# this is used by the daemonInvokeOutOfBandSystem to add the default daemon parameters automatically
# no matter how the daemon is invoked. add -D to the command line (along with -F) if you don't  want to
# use the default parameters from  /etc/default/<daemonName>
# This reads the /etc/default/<daemonName> into the array <paramsAryVar>
#   * blank lines and lines starting with # are ignored
#   * lines starting with cmdlineArgs= will add each space separated token to the
#     right as separate parameter. Quotes are not honored
#   * all other lines will be added as one quoted parameter. quotes will be included
#     so typically should not be used in the data
#  TODO: do we need to support /etc/default/<name>? Why not just add the arguments to the Exec line in the sysv,upstart or systemd start files
function daemon_oob_ReadDefaultCmdLineParams()
{
	local daemonName="$1"
	local paramsAryVar="$2"
	local line
	while IFS="" read -r line; do
		[[ "$line" =~ ^[^#]*-N ]] && assertError "-N<name> can not be specified in /etc/default/<daemonName> because -N<daemonName> defines the <daemonName> identifies the default file to use "
		case ${line:=#} in
			'#'*) continue ;;
			cmdlineArgs=*)
				line="${line#cmdlineArgs=}"
				eval $paramsAryVar+='($line)'
				;;
			*) 	eval $paramsAryVar+='("$line")'
		esac
	done < "$(fsExpandFiles -f "/etc/default/$daemonName")"
}

# usage: daemon_oob_SetDefaultCmdLineParams <daemonName> ...
function daemon_oob_SetDefaultCmdLineParams()
{
	local daemonName="$1"; [ $# -gt 0 ] && shift
	cat <<-EOS  > "/etc/default/$daemonName"
		# default cmd line params for ${0##*/} (-N$daemonName)
		# This file is created/overwritten with ${0##*/} setDefaultCmdLine ...
		#   * blank lines and lines starting with # are ignored
		#   * lines starting with cmdlineArgs= can specify multiple params as long as they don't contain spaces
		#          cmdlineArgs=<p1> <p2> <p3>
		#   * all other lines will be added as one quoted parameter to support params with spaces
		# params will be ordered as they are encountered, top to bottom, left to right

	EOS
	local collected=""
	local i; for i in "$@"; do
		local test=($i)
		if [ ${#test[@]} -gt 1 ]; then
			[ "$collected" ] && echo "cmdlineArgs=$collected" >> /etc/default/"$daemonName"
			echo "$i" >> /etc/default/"$daemonName"
			collected=""
		else
			collected+=" $i"
		fi
	done
	[ "$collected" ] && echo "cmdlineArgs=$collected" >> /etc/default/"$daemonName"
}

# usage: daemon_oob_GetDefaultCmdLineParams <daemonName> ...
# The gets the params in one line, with quotes where needed for display purposes.
# in this form, the quoted parsing can not easily and safely be restored so its typically only for display
function daemon_oob_GetDefaultCmdLineParams()
{
	local defaultParams
	daemon_oob_ReadDefaultCmdLineParams "$daemonName" defaultParams
	for i in "${defaultParams[@]}"; do
		local test=($i)
		[ ${#test[@]} -gt 1 ] && i='"'"$i"'"'
		printf "%s " "$i"
	done
	printf "\n"
}


# usage: daemonInvokeOutOfBandSystem [-v] <daemonName> <contrCmd>
# This function is called from the invokeOutOfBandSystem function when a call to 'daemonDeclare' is included at the top of the script
# It implements the standard daemon control commands -- start,stop,reload,restart,status
#
# If invokeOutOfBandSystem returns, the script should proceed to run the daemon processing loop like it would if it were not a daemon
# At that point it may be running in the background with stdout redirected to the log file or it could be running in a terminal like
# any other script which is useful for debugging.
#
# If the Daemon script declares a oob_daemonCntr function it will be called from this function to give it a chance to
# implement new cntr cmds or change/replace the implementation of a stanard daemon contr command
#
# To make a new daemon script that uses this mechanism, create a command with "bg-sp-addCommand -t sh-daemon <commandName>"
#
# Daemon Control Sub Commands:
# These are the base daemon control operations. A script can override one of these operations or add new operations by defining oob_daemonCntr.
#    start     : start the daemon proc
#    stop      : stop the daemon proc
#    restart   : stop if needed and then start the daemon proc
#    reload    : send the SIGHUP signal to the daemon which will invoke it to reload configuration
#    status    : display the status of the daemon proc
#    waitFor start|stop : wait for the daemon to enter the specified state
#    auto  : commands that control the daemon's integration with a daemon management system
#    auto enable   : enable the daemon to start when configured
#    auto disable  : diable the daemon so that it will not automatically start when its configured to
#    auto installSysV   : install an older SysV init script to control this daemon
#    auto installUpstart : install an upstart config script to control this daemon
#    auto installSystemd  : install a systemd config script to control this daemon
#    auto install         : install the default control script based on the host
#    auto uninstallSysV   : unintall...
#    auto uninstallUpstart: unintall...
#    auto uninstallSystemd: unintall...
#    auto uninstall  : unintall which ever type of control script was installed
#    auto status  : show what type of control script if any is installed for this daemon
function daemonInvokeOutOfBandSystem()
{
	local originalParams=("$@")

	local cntrCmd foregrounMode defaultArgsAlreadyConsidered outputRedirectMode
	while [ $# -gt 0 ]; do case $1 in
		-N*) bgOptionGetOpt val: daemonName "$@" && shift ;;
		-F)  foregrounMode="-F" ;;
		--test) foregrounMode="--test" ;;
		-O)  outputRedirectMode="-O" ;;
		-D)  defaultArgsAlreadyConsidered="-D" ;;
		-v)  ((verbosity++)); verboseFlag="$verboseFlag -v" ;;
		-q)  ((verbosity--)); verboseFlag="${verboseFlag/-v}" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local daemonLogFile="/var/log/$daemonName"
	local daemonErrorFile="$daemonLogFile"

	if [ "$foregrounMode" ]; then
		# this signifies that the daemon script is launching as opposed to being called to cntr the background daemon.

		# defaultArgsAlreadyConsidered (-D) means that we should not add the defaults to our command line and re-exec
		# typically, only this code adds -D but the user can specify -D to suppress using the defaults while testing.
		if [ ! "$defaultArgsAlreadyConsidered" ] && [ -s /etc/default/$daemonName ]; then
			originalParams+=(-D)
			daemon_oob_ReadDefaultCmdLineParams "$daemonName" originalParams
			exec $0 "${originalParams[@]}"
		fi

		# at this point, we know that we are the real daemon process starting up. this is the only case that returns control
		# back to the daemon script after the invokeOutOfBandSystem call

		# systemd makes it awkward to redirect the output from its init script so we added this option that we can
		# pass from the systemd ExecStart line that causes the starting daemon pid to redirect its own output
		if [ "$outputRedirectMode" ]; then
			exec >>$daemonLogFile 2>>$daemonErrorFile </dev/null
		fi

		# fail if another copy is already running
		# this uses the lower level procIsRunning b/c in upstart mode, daemonCntrIsRunning will return true because it considers
		# this code already running as the daemon
		local daemonPIDFile="/var/run/$daemonName.pid"
		procIsRunning -f "$daemonPIDFile" && assertError "$daemonName singleton daemon is already running"
		echo $$ > "/var/run/$daemonName.pid"

		# define HOME and USER
		export HOME=~
		export USER="$(id -un)"

		# the standard handler records singal catches in a count variable and resends the signal to any children
		# daemons should use "while ! daemonCheckForSignal SIGTERM SIGINT"; do ... as the main loop so that it will
		# terminate when asked. Typically inside the loop it would also "if daemonCheckForSignal SIGHUP; then reloadConfig ..."
		# this pattern allows the reload to be done synchronously with the algorithm so that it does not change half way
		# through some algorithm
		daemonInstalSdtSignalHandler SIGINT SIGTERM SIGHUP SIGUSR1 SIGUSR2
		return
	fi

	cntrCmd="$1";    [ $# -gt 0 ] && shift

	# options that can be specied for cntr cmds
	while [ $# -gt 0 ]; do case $1 in
		-N) bgOptionGetOpt val: daemonName "$@" && shift ;;
		-v) ((verbosity++)); verboseFlag="$verboseFlag -v" ;;
		-q) ((verbosity--)); verboseFlag="${verboseFlag/-v}" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# if no subcmd and no -F was specified...
	if [ ! "$cntrCmd" ]; then
		if [ "$daemonCalledFromInitD" ]; then
			echo "Usage: /etc/init.d/$daemonName {${daemonCntrCmds_whileStopped// /|}}"
			echo "see 'man ${0##*/}' for details"
		else
			echo "This command is a singleton daemon."
			echo "You can use this command to control the running state of the daemon."
			echo "You can test this daemon in the foreground, by running with the -F option"
		fi
		exit
	fi

	# give the daemon script a chance to override or augment a standard cntr function.
	# note that the $cntrCmd is prefixed with "before_"
	[ "$(type -t oob_daemonCntr)" ] && oob_daemonCntr "before_$cntrCmd" "$@"

	case $cntrCmd in
		start)
			daemonCntrStart  "$daemonName" "$@"
			local sCode=$?;

			case $sCode in
				0) echo "$daemonName has started" ;;
				1) echo "$daemonName singleton daemon is already running" ;;
				2) echo "$daemonName failed to start" ;;
			esac
			daemonCntrTailLog "$verbosity"
			;;

		stop)
			daemonCntrStop   "$daemonName" "$@"
			local sCode=$?;

			case $sCode in
				0) echo "$daemonName is stopped" ;;
				1) echo "$daemonName failed to stop" ;;
			esac
			daemonCntrTailLog "$verbosity"
			;;

		restart)
			daemonCntrStop   "$daemonName" "$@" || assertError "$daemonName failed to stop"
			daemonCntrStart  "$daemonName" "$@"
			local sCode=$?;

			case $sCode in
				0) echo "$daemonName has started" ;;
				1) echo "$daemonName singleton daemon is already running" ;;
				2) echo "$daemonName failed to start" ;;
			esac
			daemonCntrTailLog "$verbosity"
			;;

		reload)
			local sig; sig="$(signalNorm "${1:-SIGHUP}")" || exit
			local daemonPID
			daemonCntrIsRunning -P daemonPID "$daemonName" || assertError "$daemonName is not running"
			kill -s $sig "${daemonPID}"
			daemonCntrTailLog "$verbosity"
			;;

		status)
			local daemonPID
			daemonCntrIsRunning -P daemonPID "$daemonName"
			local sCode=$?;

			case $sCode in
				0) echo "$daemonName is running ($daemonPID)" ;;
				1) echo "$daemonName is crashed" ;;
				2) echo "$daemonName is shutdown" ;;
			esac

			if [ ${verbosity:-0} -eq 1 ]; then
				local type="$(daemonCntrGetType $daemonName)"
				if [ "$type" == "none" ]; then
					echo "no auto start configuration is installed"
				else
					echo "auto start configuration : $type"
					echo "auto start state         : $(daemonCntrIsEnabled $daemonName)"
				fi
				[ "$type" == "systemd" ] && echo "daemon control log (-vvv): 'journalctl -f -n20 --unit=${daemonName}.service'"
				echo "log file            (-vv): $daemonLogFile"
				echo "PID file                 : /var/run/$daemonName.pid"
				echo "last 3 log lines:"
			fi

			daemonCntrTailLog "$verbosity"
			;;

		waitFor) daemonCntrWaitFor  "$daemonName" ${1:-start} || assertError "timed out waiting for daemon $daemonName to ${1:-start}" ;;

		auto)
			subCmd="$1"; [ $# -gt 0 ] && shift
			case ${subCmd:-status} in
				enable)  daemonCntrEnable "$daemonName" ;;
				disable) daemonCntrDisable "$daemonName" ;;

				installSysV)      daemonCntrInstallAutoStart   "$daemonName" sysv ;;
				installUpstart)   daemonCntrInstallAutoStart   "$daemonName" upstart ;;
				installSystemd)   daemonCntrInstallAutoStart   "$daemonName" systemd ;;
				install)          daemonCntrInstallAutoStart   "$daemonName" any ;;

				uninstallSysV)    daemonCntrUninstallAutoStart "$daemonName" sysv ;;
				uninstallUpstart) daemonCntrUninstallAutoStart "$daemonName" upstart ;;
				uninstallSystemd) daemonCntrUninstallAutoStart "$daemonName" systemd ;;
				uninstall)        daemonCntrUninstallAutoStart "$daemonName" any ;;

				# we always display the status after the case so we accept the command but there is
				# nothing to do
				status) : ;;
				*) assertError "unrecognized subcommand auto '$subCmd'"
			esac

			local type="$(daemonCntrGetType $daemonName)"
			if [ "$type" == "none" ]; then
				echo "auto start is not installed, but $daemonName can be started directly"
			else
				echo "auto start is $(daemonCntrIsEnabled $daemonName), installed using '$type'"
			fi
			;;


		setDefaultCmdLine) daemon_oob_SetDefaultCmdLineParams "$daemonName" "$@" ;;
		getDefaultCmdLine) daemon_oob_GetDefaultCmdLineParams "$daemonName" ;;

		*) [ "$(type -t oob_daemonCntr)" ] && oob_daemonCntr "$cntrCmd" "$@" || assertError "unkown daemon control command '$cntrCmd'" ;;
	esac

	# give the daemon script a chance to augment a standard cntr functions after they execute.
	# note that the $cntrCmd is prefixed with "after_"
	[ "$(type -t oob_daemonCntr)" ] && oob_daemonCntr "after_$cntrCmd" "$@"

	# the only case that this function gets called and we want to return to the calling script is
	# handled at the top of this function
	exit
}
