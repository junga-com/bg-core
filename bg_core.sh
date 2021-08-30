#!/bin/bash

# guard against multiple sourcing since this is the only file that does not get sourced with import
[[ "${_importedLibraries@a}" =~ A ]] && [ "${_importedLibraries["lib:bg_coreImport.sh"]}" ] && return 0

set +e

# Library bg_core.sh
# bg_core.sh is the entry point into the bg_* script system. Scripts should source this script in the typical way using its absolute
# path like...
#     source /usr/lib/bg_core.sh
# After that, the facilities of the bg_* script environment are available and any other required libraries should use the import
# syntax instead of source. The import syntax implements idepontency and supports virtual install environments for development.
#     import <libraryName> ;$L1;$L2
#
# This library provides two essential mechanisms. Adding any other mechanisms should be avoided.
#
# Bootstraping:
# This library is just a bootstrap to load the actual library starting at bg_coreImport.sh so that development of the rest of the
# bg_core package can use the development and debugging facilities that other bg_* package enjoy. This file is special because it
# needs to be installed in the actual system path and therefore when multiple versions of the bg_core package exist on a host (for
# example, a stable version installed and a new version being developed) they must share this file. Since ths file only bootstraps
# the bg_coreImport.sh and provides no functions that scripts rely on, it is relatively stable and will not often change between
# versions.
#
# Security:
# Being the entrypoint into script environment puts this file in a unque position to enforce some security constraints. The security
# concept builds upon the linux mechanism that requires privilige (typically root privilege) to modify system files. It requires
# privilege to install scripts into system folder (typically through a package manager system from a trusted repository). The security
# goal of this file therfore is to ensure that scripts written to use this library will not execute a script that is not in a protected
# system folder. This can not ensure that the script author does not violate that constraint so a security review process for accpeting
# scripts into the trusted repository should be implemented. This library can ensure that when a script uses the libraries facitities
# and supported code patterns, that those actions will not result in untrusted execution. Furthermore, script libraries can detect
# when they are being executed by unsecure user scripts on production systems to protect against confused deputy attacks.
#
# When developing scripts, the security constraint should be relaxed to support a good development coding cycle of change -> test
# -> fix -> repeat. This library supports a concept of production modes. A script run on a host in production mode have its mode set
# based on whether the script itself is a secure system script or a user script. Script libraries installed into system folders
# should each start with an entry statement that fails out if they are not sourced below this file so that they can not be used by
# user scripts directly. Library functions that implement develoment features use the production mode to determine if those functions
# are available.
#
# The structure of this library supports efficient remote integrity checks so that a remote, unprivileged supervisor can
# idependently confirm whether the integrity of the system is intact. It can not prevent a local admin from violating the security
# constaints but it can detect whether the system has been violated since the last remote check.
#
# Scripts written to this library are more prone to automated security code scanning techniques which aids in creating an effective
# SDLC security review for script inclusion into a trusted repository. For example, the only use of the bash 'source' function should
# be to source /usr/lib/bg_core.sh. Any other instance of the 'source' builtin command in the code can be flagged as a
# violation. Scripts use import instead which, in production mode, garantees that only code from properly protected system folders
# will be sourced and that any sourced system library will run under the correct production mode evironment variable.


# provide a stand-alone implementation of assert so that the bootstrap code can have nice error handling
function earlyAssert()
{
	local contextVars exitCode
	while [[ "$1" =~ ^- ]]; do case $1 in
		-v) contextVars+=" $2"; shift ;;
		-e) exitCode="$2"; shift ;;
	esac; shift; done
	echo "error: $*" >&2
	echo "   bash library not found by in any of these paths" >&2
	local maxNameLen; for varName in $contextVars; do (( maxNameLen=(maxNameLen>${#varName})?maxNameLen:${#varName} )); done
	local varName; for varName in $contextVars; do
		printf "   %-*s = %s\n"  "$maxNameLen" "$varName" "${!varName}" >&2
	done
	exit "${exitCode:-1}"
}

# provide a stand-alone implemntation of bgtrace so that bootstrap code can be debugged
function earlyTrace()
{
	if [ -w /tmp/bgtrace.out ]; then
		echo "$*" >> /tmp/bgtrace.out
	fi
}

# usage: setSecureEnv <varNameN> <value>
# this will create a readonly variable set to <value>. Its ok if the variable is readonly and already set to the right value or is
# not yet readonly but if it is already set readonly to a different value, we error out
function setSecureEnv()
{
	local varName="$1"
	local value="$2"
	declare -grx $varName="$value" &>/dev/null || [ "${!varName}" == "$value" ] || earlyAssert -e 3 "can not run an installed script with $varName='${!varName}'. It is expected to be '$value' in this environment. Is $varName set readonly in this shell ENV?"
}

setSecureEnv bgWS $' \t\n'

### Set the bgProductionMode variable
# This security only protects scripts that are installed in a hosts system folder via a package management from a trusted repository
# that enforces security review of content accepted into the repository. The whole point of this mechanism is to ensure that officially
# installed scripts can not be tricked into running in development mode. It can not ensure that a running script is trusted, only that
# official scripts can not have bgProductionMode=='development'
#  * root on the local host can violate this security
#  * a non-root user's scripts are only constrained by the fudamental linux file and other linux account based security.
# 1) A systems SDLC needs to enforce that all scripts in a package that uses the bg-lib scripting libraries initiate the library by
#    sourcing /usr/lib/bg_core.sh by its full path. The path may vary by distribution but needs to be a system folder only writable
#    by root.
#    This ensures every officially deployed script that uses the bg-lib library, we excute the officially installed version if this
#    bg_core.sh file.
# 2) This officially deployed version of this file will set a readonly bgProductionMode ENV variable based on whether the user can
#    write to the script file being ran.
#    This ensures that every officially installed script will not have bgProductionMode set to 'development' if its not being ran by root.
# 3) if bgProductionMode is not set to 'development', the any feature meant for development will not activate (because they may allow
#    exploits that violate a script's security constraints.
# 4) only fully qualified commands can be used to give user's evelated permissions with sudo so script commands installed in system
#    folders can be used to give non-users limitted privileges without the possibility that bg-lib development time features will
#    compromise their security.
#


# check that the /etc/bgHostProductionMode file has reasonable permissions if it exists. The default is the most restrictive setting
# so its ok for it not to exist as long at privilege would be required to create it
[ "$(stat --printf="%a%u%g%F" /etc)" == "75500directory" ] || earlyAssert "The /etc folder has unexpected security. Expecting UID==0, GID==0, ugo==755, type=directory. Refusing to run system scripts"
[ ! -e /etc/bgHostProductionMode ] || [ "$(stat --printf="%a%u%g" /etc/bgHostProductionMode)" == "64400" ] || earlyAssert "The /etc/bgHostProductionMode file has unexpected security. Expecting UID==0, GID==0, ugo==755. Refusing to run system scripts"



# if /etc/bgHostProductionMode does not contain "mode=development" then this host is considered to be in production. We make this
# default to production so that its more fragile to be considered a less secure development environment. i.e. anything done to disrupt
# this test should result in it defaulting to the more restricted production mode.
declare bgHostProductionModeTemp=$([ ! -f /etc/bgHostProductionMode ] || awk '/^[[:space:]]*mode[[:space:]]*[:=][[:space:]]*development/ {print "development"; exit}' /etc/bgHostProductionMode) || earlyAssert -e 4 "error setting bgHostProductionModeTemp variable"
if [ "$bgHostProductionModeTemp" != "development" ]; then
	setSecureEnv bgHostProductionMode  "production"
else
	setSecureEnv bgHostProductionMode  "development"
fi
unset bgHostProductionModeTemp


# this block distinguishes scripts that the user can modify and those that they can not. Installed system scripts can not be modified
# by non-root users. The important thing is that those scripts can not be ran in a way tricks this code into the last, default case.
# Any other script can trick this code how ever they want.
# SECURITY: this is a critical block whose purpose is to ensure that installed system scripts can not be run with "$bgProductionMode"=="development"

# CRITICALTODO: 2020-10 after coming back to this while creating bg-core (from bg-lib), I think that this should be basing the decision more
#       on whether the script is being exectued is in a system folder with the proper permissions. I dont want to get sidetracked now
#       and this will require some deep thining and testing to get right.

# using sudo to be a a root-equivalent user
# this is the common case for system script ran with evelated permission with sudo.
# we rely on sudo config being the gateway to protect this case
# a developer with root control of the workstation can spoof into this block for testing, by using the sudoers policy NOSETENV
# This, like the lowest security default case below, does not enforce any constraints but thats because the root-equivalent user
# can modify commands  in /usr/bin and do anything that they want anyway.
# SECURITY: we need to make sure that this block only hits for real root-equivalent users. We can also add logging to this case supported by an auditd mechanism to make sure that the script is not tampered with by root
if [ -w "/usr/bin" ] && [ "$SUDO_USER" ] && [ "$bgHostProductionMode" != "development" ]; then
	# sudo takes care of resetting all the ENV variables for root (we dont need to confirm that sudo locked down becasue this user can change system scripts anyway)

	# CRITICALTODO: distinguish production (SETENV) and development mode (NOSETENV). Push dev down to the default case and enforce are script constraints for root. Force root to edit this file to defeat them which can be trapped with auditd
	setSecureEnv bgProductionMode          "production-rootEquiv"

	# root can change all the files so we have to turn this off for root (users that have file permissions to change system folders)
	setSecureEnv bgSourceOnlyUnchangable   ""

	setSecureEnv bgDevModeUnsecureAllowed  ""



# using sudo to be a different non-root user. This will be more common as a domain becomes more mature in its security
# a developer can spoof into elevating security into this block by setting SUDO_USER in the env
elif [ ! -w "/usr/bin" ] && [ "$SUDO_USER" ] && [ "$bgHostProductionMode" != "development" ]; then
	# sudo takes care of resetting all the ENV variables but we need to confirm that they did
	# CRITICALTODO: figure out how to 1) securely determine if we are running in sudo and if sudo allows us to keep environ (a dev workstation config thing)
	setSecureEnv bgProductionMode          "production-elevatated"

	setSecureEnv bgSourceOnlyUnchangable   "1"
	setSecureEnv bgDevModeUnsecureAllowed  ""



# non-sudo, non-privileged user running system scripts
# this is the typicall case of running a script without sudo
# a developer can spoof into increasing security into this block by changing ownership of their script to another non-root user but they can't spoof it the other way to lessen security
# the [ "$0" != "bash" ] check is to allow sourcing bg_core directly like bg-debugCntr does. The bash env is under user control just like a script they can modify is under their control
elif [ ! -w "$0" ] && [ "$0" != "bash" ] && [ "$bgHostProductionMode" != "development" ]; then
	# note that a non-root user can also do any of these declarations so code in other libraries can not use anything that we put here
	# to ensure that the script is ok. Thats OK because we only need to protect scripts that are used to give elevated sudo permissions
	# and those are installed in system folder where non-root users can not modify them
	setSecureEnv bgProductionMode        "production-nonPriv"

	[ "$bgLibPath" ] && echo "** WARNING ** scripts in system paths can not use bg-debugCntr vinstalled projects" >&2
	setSecureEnv bgLibPath ""

	# its ok to turn tracing on for system installed scripts but not the debugger
	# declare -r bgTracingOn=""

	setSecureEnv bgSourceOnlyUnchangable   "1"
	setSecureEnv bgDevModeUnsecureAllowed  ""

	# if we detect an invalid security constraint here, we can end the script with an error...
	# TODO: check to see that the host's validation is signed correctly or write a warning message



# default case is when user is running scripts that they wrote. Typically, this is developing on a workstation but on a production
# server this could be a sysadmin trying stuff, either benign or malicious. We do not need to impose any security because the user
# is constrained by the core linux file permission and other security
# This is the lowest security case that a hacker would like to get a system installed script to hit so the above conditions need to
# identify all cases of running system code so that they do not reach here.
# SECURITY: The key security point is that an installed script can not pass through this code and hit this default case.
else
	setSecureEnv bgProductionMode          "development"
	setSecureEnv bgSourceOnlyUnchangable   ""
	setSecureEnv bgDevModeUnsecureAllowed  "1"
fi


# detect when we are being invoked as a BC routing and do not debug
if [[ "$1" =~ ^-h ]]; then
	bgDebuggerOn=""
fi


unset setSecureEnv

# --queryMode is used by bg-debugCntr to have this file setup the script run environment and exit before going on to load bg_coreImport
# this allow bg-debugCntr or other tools to query the environment that a script will run under this host without actuall running anything
if [ "$1" != "--queryMode" ]; then

	# if bgtrace is turned on, manually start the default timer as soon as possible so that we can time
	# from the start of the script before bgtimerStart is sourced.
	if [ "$bgTracingOn" ]; then
		bgtimerGlobalTimer[0]="$(date +"%s%N")"
		bgtimerGlobalTimer[1]="${bgtimerGlobalTimer[0]}"
	fi

	# create the findInclude function so that we can find bg_coreImport.sh to load without introducing global vars for its algorithm
	function _coreFindInclude()
	{
		# SECURITY: each place that sources a script library needs to enforce that only system paths -- not vinstalled paths are
		# searched in non-develoment mode
		if [ "$bgSourceOnlyUnchangable" ]; then
			local includePaths="$scriptFolder:/usr/lib"
		else
			local includePaths="$scriptFolder:${bgLibPath}:/usr/lib"
		fi

		local found incPath tryPath
		local saveIFS=$IFS
		IFS=":"
		for incPath in ${includePaths}; do
			incPath="${incPath%/}"
			for tryPath in "$incPath${incPath:+/}"{,lib/,creqs/,core/,coreOnDemand/}"bg_coreImport.sh"; do
				if [ -f "$tryPath" ]; then
					bg_coreImport_path="$tryPath"
					break
				fi
			done
			[ "$bg_coreImport_path" ] && break
		done
		IFS=$saveIFS

		# end with error if not found
		if [ ! "$bg_coreImport_path" ]; then
			echo "error: Woops. Something is not right." >&2
			echo "   /usr/lib/bg_core.sh is being sourced by a script but it can not find the rest of the bg-core" >&2
			echo "   package which should contain the bg_coreImport.sh script libraries." >&2
			echo $includePaths | tr ":" "\n" | awk 'BEGIN{print "   Search path tried:"} /[^[:space:]]/ {print "      "$0}'  >&2
			exit 1
		fi
	}

	# this sets the bg_coreImport_path global var
	_coreFindInclude bg_coreImport.sh
	unset -f _coreFindInclude

	# this is a double check. The real prevention is that bgLibPath is cleared so that bg_coreImport_path will only be found in /usr/lib/
	if [ "$bgSourceOnlyUnchangable" ] && [ -w "$bg_coreImport_path" ]; then
		echo "error: can not source a writable library in a script that is not writeable by the user" >&2
		echo "   script path  = '$0'" >&2
		echo "   library path = '$bg_coreImport_path'" >&2
		exit 2
	fi

	# we have to load bg_coreImport.sh before 'import bg_coreImport.sh ;$L1;$L2' is available but we can predefine its
	# entry in the _importedLibraries associative array to record the path that we used. This allows
	# importCntr reloadAll to reload bg_coreImport.sh also if it changes.
	declare -gA _importedLibraries
	_importedLibraries[lib:bg_coreImport.sh]="$bg_coreImport_path"
	unset bg_coreImport_path
	source "${_importedLibraries[lib:bg_coreImport.sh]}"

	# bgtrace "in common.sh"
	# printfVars _bgtraceFile bgTracingOn bgTracingOnState  >>/tmp/bgtrace.out
	# printfVars bgProductionMode bgSourceOnlyUnchangable bgDevModeUnsecureAllowed bgLibPath  >>/tmp/bgtrace.out
fi
