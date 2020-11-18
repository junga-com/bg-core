#!/bin/bash


#function bgtrap() moved to bg_libCore.sh

# usage: bgwait [-P] <pidMapVar>    <succeedCountVar> <errorCountVar> <resultsByNameVar> <namesByResultsVar> <summaryStrVar>
# This is similar to the wait bash builtin function except you pass is the name of an associative array (pidMap>
# that has the structure pidMap[procName]=procPID and it optionally returns a number of variables that report
# on the results.
# This function returns when all the processes in pidMap are finished
# Params:
#    <pidMap> : this is the only input and the only requied param. an associative arry (pidMap[<procName?]=<procPID>)
#               typically, after launching a command in the background you set pidMap[<someName>]=$!
#               after all proccesses are done, pass the name of pidMap into this function to wait and report on
#               the results
#    all of the folowing are optional output return variables passes as names. use "" for any you dont want
#    <succeedCountVar>  : the number of processes that exited with code 0
#    <errorCountVar>    : the number of processes that exited with something other than code 0
#    <resultsByNameVar> : an associative array like resultsByName[<procName>]=<exitCode>
#    <namesByResultsVar> : an associative array like resultsByName[<exitCode>]=" <procName1> [.. <procNameN]>"
#    <summaryStrVar>    : a short string describing the results
#              all succedded
#              all failed
#              <n> succeeded, <m> failed
# Options:
#   -P : use the 'progress' function to report progress
# Return Code:
#   0 : all succeeded
#   1 : all failed
#   2 : some succeeded and some failed
function bgwait()
{
	local progressFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-P) progressFlag="-P" ;;
	esac; shift; done
	local pidsVar="$1"; assertNotEmpty pidsVar
	local succeedCountVar="${2:-succeedCountValue}" succeedCountValue=0
	local errorCountVar="${3:-errorCountValue}" errorCountValue=0
	local resultsByNameVar="$4"
	local namesByResultsVar="$5"
	local summaryStrVar="$6"

	# this code still support ubuntu 12.04 so copy the pidsvar array instead of using a -n ref
	local -A bgw_pids;     arrayCopy "$pidsVar" bgw_pids
	local -A bgw_pidNames; arrayTranspose -d" " "$pidsVar" bgw_pidNames


	# these keep track of which are still running. bgw_pidsLeft is an array of PIDS
	# waitingForList is a str list of the PID names from bgw_pids (just the ones that are still in bgw_pidsLeft)
	local bgw_pidsLeft=("${bgw_pids[@]}")
	local waitingForList waitingForListWithPID bgw_pid tmpPIDList

	# some of the PIDs could have ended already iterate and remove any that are not running
	tmpPIDList="${bgw_pidsLeft[@]}"; bgw_pidsLeft=(); waitingForList="" waitingForListWithPID=""
	for bgw_pid in $tmpPIDList; do if kill -0 "$bgw_pid" 2>/dev/null; then
		bgw_pidsLeft+=($bgw_pid)
		waitingForList+=" ${bgw_pidNames[$bgw_pid]}"
		waitingForListWithPID+=" ${bgw_pidNames[$bgw_pid]}($bgw_pid)"
	fi;	done

	[ "$progressFlag" ] && progress -s bgwait "waiting for ${#bgw_pidsLeft[@]} to finish : $waitingForList"

	local result=0
	while [ ${#bgw_pidsLeft[@]} -gt 0 ] && [ ${result:-0} -ne 127 ]; do
		# if needed, we can add $sleepPID to the wait -n command. This effectively implements a timeout so that
		# wait -n will wakeup whenever the sleep expires. This should not interfere with the real tasks because
		# as soon as we see that none of them are still running this loop will exit even if the sleep has not yet expired.
		#sleep 1 &
		#sleepPID=$?

		# the -n opt is not well documented in the man page but it seems that it ignores the pids passed in.
		# you can either wait for a list of PIDs to finish or you can wait for the next one to finish
		# wait -n seems to return the exit code of the PID that finished but I see no way to tell the PID
		# of the one that just finished. Its exit code will be 127 if there are no more PIDs whose exit codes
		# have not yet been returned. Luckily, you  can retrieve the exit code of a PID once with -n and then
		# again with "wait <pid>". So we ignore the exit codes here because we do not know which PID they corespond
		# to but we do have the loop end if the exit code is 127. That should not be needed because in that case
		# ${#bgw_pidsLeft[@]} should be empty too, but this is an additional guard against an infinite loop

		# there is no race condition between finding out if any are still running and calling this, because there
		# can be only one wait in this process. ie, the parent that calls wait is inherently single threaded
		wait -n  &>/dev/null
		result=$?

		# wait -n returns when ANY child ends. We don't even know if its one of ours. It ignores any PIDs passed into it
		# so iterate the PIDs that were left before we called wait and see which ones are still running
		tmpPIDList="${bgw_pidsLeft[@]}"; bgw_pidsLeft=(); waitingForList="" waitingForListWithPID=""
		for bgw_pid in $tmpPIDList; do if kill -0 "$bgw_pid" 2>/dev/null; then
			bgw_pidsLeft+=($bgw_pid)
			waitingForList+=" ${bgw_pidNames[$bgw_pid]}"
			waitingForListWithPID+=" ${bgw_pidNames[$bgw_pid]}($bgw_pid)"
		fi;	done

		[ "$progressFlag" ] && progress -u "waiting for ${#bgw_pidsLeft[@]} to finish : $waitingForList"
	done

	### Now they are all done, collect their exit codes
	# even though wait -n above already returned all these exit codes, up there we did not know which PID they corresponded to.
	# its ok to retrieve the exit code of a PID with wait <pid> multiple times
	for name in "${!bgw_pids[@]}"; do
		local refNamePID="$pidsVar[$name]"
		wait "${!refNamePID}" &>/dev/null
		local result=$?
		[ "$namesByResultsVar" ] && stringJoin -R "$namesByResultsVar[$result]" -d " " -a "$name"
		[ "$resultsByNameVar" ]  && stringJoin -R "$resultsByNameVar[$name]" -d " " -a "$result"
		[ $result -eq 0 ] && setRef "$succeedCountVar"  $((${!succeedCountVar}+1))
		[ $result -ne 0 ] && setRef "$errorCountVar"    $((${!errorCountVar}+1))
	done

	### result will be set to the overall status for all the process - all good, all bad, or some of each
	# TODO: maybe we should return the value errorCountVar directly, capping it at 256 or something
	result=0
	if [ ${!errorCountVar:-0} -eq 0 ]; then
		setReturnValue "$summaryStrVar" "all succeeded"
		result=0
	elif [ ${!succeedCountVar:-0} -eq 0 ]; then
		setReturnValue "$summaryStrVar" "all failed"
		result=1
	else
		setReturnValue "$summaryStrVar" "${!succeedCountVar:-0} succeeded, ${!errorCountVar:-0} failed"
		result=3
	fi

	[ "$progressFlag" ] && progress -e bgwait "done"
	return $result
}

#function bgkillTree() moved to bg_libCore.sh

# usage: local bgPID="$(bgGetSpawnedPID $!)
# this is a work around for a strange error that I do not fully understand. When spawning multiple
# "git $gitFolderOpt gui &" processes in a tight loop, the PIDs returned by $! turn out to be the
# aspell child process that git gui creates and not the git processes itself. It seems if I put a 1 second
# sleep in the loop we get the git PID. It also seems that running an external command in the loop also
# fixes the problem.
# This function walks takes the PID returned by $! and walks back up the ppid links until the ppid == $$
# that should be the real process we spawned in the background. Ironically, because this function calls ps
# in a subshell (apparently) the $! passed in always seems to be right anyway.
function bgGetSpawnedPID()
{
	local pid="$1"
	local count=0
	local data=""
	while [ "$pid" ] && ((count++ < 10)); do
		local ppid=$(ps -o ppid= $pid)
		data="$pid:$(ps c -o cmd= $pid):$ppid==$$ | $data"
		if [ "$ppid" == "$$" ]; then
			data="success: $data"
			#bgtraceVars data
			echo "$pid"
			return
		fi
		pid=$ppid
	done

	data="fail: $data"
	#bgtraceVars data
	echo "$1"
}



# usage: procIsRunning <pid>
# usage: procIsRunning -f <pidFile>
# exit code is true if running, false if not
# Params:
#     <pid> : the pid of the process to check. If not specified, the -f option must be specified
# Options:
#     -f <pidFile> : specify the file that contains the pid. Typically this is in /var/run/<daemonName>
#     -P <pidVarName> : if the -f <pidFile> is specified, the pid value it contains will be returned in this variable name
# Exit Codes:
#    0 : true. the specified process is running
#    1 : the pid is no longer running. If a pidFile was specified, this indicates a crash (non-graceful termination)
#    2 : the pidFile does not exist or is empty, indicating the proc is in the graceful shutdown state
function procIsRunning()
{
	local pidFile pidVarName
	while [ $# -gt 0 ]; do case $1 in
		-f*|--pidFile*) bgOptionGetOpt val: pidFile "$@" && shift ;;
		-P*|--retVar*) bgOptionGetOpt val: pidVarName "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local pidValue="$1"

	if [ "$pidFile" ]; then
		[ -f "$pidFile" ] || return 2
		read -r pidValue < "$pidFile"
	fi

	[ "$pidVarName" ] && eval $pidVarName="\$pidValue"

	[  "$pidValue" ] || return 2

	if $(kill -0 "$pidValue" 2>/dev/null); then
		return 0
	elif ps "$pidValue" >/dev/null 2>&1; then
		return 0 # program is running, but not owned by this user
	else
		return 1
	fi
}


#############################################################################################################################################
### Other proc control functions



# usage: bgSleep <timeout>
# like sleep but is interruptable
function bgsleep() { bgSleep "$@"; }
function bgSleep()
{
	sleep "$@" &
	wait $!
}



# usage: delayedExec <jobSpecName> <delayMinutes> <cmd> ...
# this function schedules a command in the future.
# If an existing <jobSpecName> is already scheduled, it resets the delay to the new value.
# This supports a convenient pattern for commands that rebuild a cache after data has changed when
# changes are made in clumps. If the cache is rebuilt after every small change, it performs too much work
# and only the last time it runs matters. By using this function after each small change, the rebuild
# function will not run right away. While new changes are happenning, it only pushes the job's sheduled time
# out further and further. As soon as there is a pause in changes greater that delay, the rebuild will run.
# This could be combined with a cron job that invokes the command periodically but only if the cache is dirty.
# That way the cache is quaranteed to not be dirty for longer than that time
function delayedExec()
{
	local deName="$1" ; shift
	local deDelay="$1" ; shift
	local jobSpecFile="/tmp/.${deName}.delayedJobSpec.$UID"
	(
		aaaTouch "$jobSpecFile" world:writable
		local lockID; startLock -u lockID $jobSpecFile
		local jobSpec="$(cat $jobSpecFile)"
		if [ "$jobSpec" ]; then
			atrm $jobSpec 2>/dev/null
			echo "" > $jobSpecFile
		fi
		[ $(date +"%S") -gt 40 ] && (( deDelay += 1 ))
		local timespec="now +$deDelay minute"
		echo "$@" | at "$timespec" 2>&1 | awk '/^job[ \t][0-9][ \t]*/{print $2}' > $jobSpecFile
		atq | grep "^$(cat $jobSpecFile)[[:space:]]"
	)
}




# usage: ${myHookFn:-$requiredFn} ...
# usage: ${myHookFn:-$optionalFn} ...
# The global variables requiredFn and optionalFn can be used as the default values for variables that
# contain call back functions. This makes it so the caller does not need to check to see if the variable
# is empty before calling it. If the variable is empty, requiredFn or optionalFn will provide the command
# that will be invoked.  requiredFn will assert an error that the required callback function is not set
# and optionalFn will be a noop so that the optional missing call back is just ignored.
# SECURITY: assertRequiredFn,  requiredFn and optionalFn support a pattern to invoke dynamic code. The caller must know to only invoke dynamic code from system code sources.
declare requiredFn="assertRequiredFn "
declare optionalFn=": "
function assertRequiredFn()
{
	local cmdLine="<hookFunction> $*"
	assertError -v cmdLine "a required dynamic plugin function was invoked but it is empty  "
}

# usage: runPluginCmd <cmdToken> [ <p1> .. <pN>]
# This runs a plugin cmd only if it passes the security policy. The security policy may be different on a production
# host vs a development host.
# Plugin commands are data fields that can be set by untrusted actors that are converted to code via execution. A secure
# plugin command is safe to run because it is restricted to:
#    1) running only installed commands on the host -- no arbitrary scripts with unvetted content.
#       * Any path is stripped off so that the command has to be either a function, builtin or an external cmd installed
#         into a system path
#       * TODO: in production mode, hard set PATH and bgLibPaths, etc.. to know vlaues
#    2) running only commands that match a naming convention so that we can audit the set of potential commands
#       and make sure that they do not allow arbitrary execution by crafting particular parameters.
#       Alternatively, we could allow executing other commands as long as the parameter list is empty. This is not done now.
#    3) currently, eval is not used so quoted or escaped parameters will not work. If that is changed, it must additionally
#       escape the tokens so that ; or other constructs can not execute a second, hidden command.
# Params:
#      Note that unlike most functions, this treats the entire command line as one string. Each token
#      will be whitespace delimitted even if it is quoted when passing to this function. %20 can be used
#      to prevent spaces from making separate tokens but they will be passed that way to the cmd so
#      the target command needs to know how to handle %20
#      <cmdToken> : the first whitespace delimitted token is taken as the command name
#      <pN> : each subsequent whitespace delimitted token is taken as a positional paramter
# Options:
#     -o <optOrParam> : add this option or parameter to to the plugin command in between the cmd token
#                       and the params provided by the plugin cmd string. This can be used to ensure
#                       that a expected class of commands are ran in a particular mode that the plugin
#                       cmd author can not change
# SECURITY: function runPluginCmd() : code that invokes dynamic behavior should use this so that we can check potentially untrusted code
function runPluginCmd()
{
	local opts=()
	while [ $# -gt 0 ]; do case $1 in
		-o) bgOptionGetOpt valArray: opts "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local pluginCmd="$*"

	# assert that this command complies with the naming convention to prevent execution of commands that support unsafe
	# parameters.
	if [[ ! "${pluginCmd%% *}" =~ ^((at-.*)|(bg-.*)|(.*::.*))$ ]]; then
		assertError -v pluginCmd "
			This plugin command can not be guaranteed safe and will not be run. Acceptable commands can be
				* a bash library function like <libFile>::<functionInLib>
				* a command that begins with either at-* or bg-*
				* signed by a trusted source
			"
	fi

	### parse into components [<libFile>::]<progName> [<params>]
	local progName="${pluginCmd%% *}"
	local params="${pluginCmd#* }"

	local libFile
	if [[ "$progName" =~ :: ]]; then
		libFile="${progName%%::*}"

		# strip off any path so that only libs installed into the system paths can be run
		libFile="${libFile##*/}"

		progName="${progName#*::}"
	fi

	# strip off any path so that only functions, builtins and programs installed into the system paths can be run
	progName="${progName##*/}"

	### Load the libFile if needed and confirm that progName exists as the right type
	if [ "$libFile" ]; then
		local libPath="$(import --getPath "$libFile")"
		if [ ! "$libPath" ] || [ ! -e "$libPath" ]; then
			assertError "library '$libFile' not installed when invoking '$pluginCmd'"
		fi
		if ! grep -q "\<$progName()" "$libPath"; then
			assertError -v pluginCmd -v libPath -v progName "the function is not present in the specified library"
		fi

		import "$libFile" ;$L1;$L2

		# since the function syntax is used it must resolve to a function
		if [ "$(type -t "$progName")" != "function" ]; then
			assertError -v pluginCmd -v libPath -v progName "the function is not present after sourcing the specified library"
		fi
	else
		#
		local cmdType="$(type -t $progName)"
		case :$cmdType in
			:function) assertError -v pluginCmd -v progName -v cmdType "program name resolves to a function but the function syntax <libScript>::<functionName> was not used" ;;
			:builtin)  assertError -v pluginCmd -v progName -v cmdType "plugin commands can not execute builtins" ;;
			:)         assertError -v pluginCmd -v progName -v cmdType "plugin command not installed"
		esac

	fi

	### execute the cmd.
	# TODO: consider using eval to support quoted/escaped params but then we must escape the tokens to prevent ; and other
	#       constructs from running a second, hidden command
	$progName "${opts[@]}" $debugFlag $params
}





# usage: cronNormSchedule <cronScheduleSpec>
# Returns a string with the cron standard 5 period specs (like "30 1 * * * " == run every 1:30 am)
# <cronScheduleSpec> could already be a cron standard string ("man -s5 crontab" (minute, hour, dayOfMonth, month, dayOfWeek))
# or it could contain the following extentions
# Cron Spec Extensions
#    1) trailing fields can be omitted and will take the value '*'
#    2) leading fields can be skipped by adding a suffix to the next field to indicate its position
#       skipped leading fields will use the lowest value ( 0 for most, 1 for day and month
#       sufixes= m,min,minute  h,hour  d,day  m,mon,month  dow
#    3) if a simple number is used instead of * when an interval is specified (e.g. 4/10min) the first number is interpretted
#       a starting offset instead of a particular value. In native cron, "4/10" results in no run b/c the 10th interval
#       of the range 4 does not exist. This function will expand it to the explicit list of numbers that should run.
#       4/10min will create the cron spec "4,14,24,34,44,54   *   *   *   *"
#    4) a day name or month name can appear anywhere and not effect the rest of the terms
#    5) "SLAm [+|-<H>hours [.. +|-<M>minutes]" Run one time relative to the start of the SLA maintenance period as defined in the domConfig
#       SLAm section start and stop parameters. The default is 18:00UTC Saturday to 18:00 UTC Sunday.
#       if plus or minus H or M are specified, they adjust the start time accordingly
# Params:
#    <cronScheduleSpec> : a string containing a cron schedule spec which might contain extsions to the cron standard
#           it can contain the five fields described by .
function cronNormSchedule()
{
	[ $# == 1 ] || assertError "requires exactly one parameter. a string containing a cron schedule spec"
	local cronScheduleSpecOrig="$1"
	local cronScheduleSpec="${1,,}"
	cronScheduleSpec="${cronScheduleSpec//"*"/&}";   # replace '*' so bash does not expand them. & is not valid in crons
	cronScheduleSpec="${cronScheduleSpec//sla/slam}"; cronScheduleSpec="${cronScheduleSpec//slamm/slam}"
	cronScheduleSpec="${cronScheduleSpec//slam/slam }";   # slam+2h is a easier to interpret as "slam +2h"

	local slamStart slamStartDay slamStartHour slamStartMinute
	local pParts=(${cronScheduleSpec})
	local pSched=()
	local pStart=(0 0 1 1 0)
	local pRanges=(60 24 31 12 7)
	local pFields=(min hour day month dow)
	local dayNames=(monday mon tuesday tue wednesday wed thursday thu friday fri saturday sat sunday sun)
	local monthNames=(january jan february feb march mar april apr may june jun july jul august aug september sep october oct november nov december dec)
	local -A pFieldsMap=([minutes]=0 [minute]=0 [min]=0 [m]=0 [hours]=1 [hour]=1 [h]=1 [days]=2 [day]=2 [d]=2 [months]=3 [month]=3 [mon]=3 [dow]=4 [default]="")
	local i
	for i in ${monthNames[@]}; do pFieldsMap[$i]=3; done
	for i in ${dayNames[@]}; do pFieldsMap[$i]=4; done
	local pCur=0
	local part; for part in "${pParts[@]}"; do
		# & was a place holder for * to avoid file expansion. We don't need * because its the default so now we can just remove the &
		part="${part//&}"

		### assert the parts format is valid and that we are not doing more than 5 parts
		[[ "$part" =~ ^(([+-]{0,1}([*]|[0-9,-]{1,}|)([/][0-9]{1,2}){0,1}($(arrayJoin -i -d"|"  pFieldsMap)){0,1})|(($(arrayJoin -d"|" dayNames)),{0,1}){0,}|($(arrayJoin -d"|" monthNames)|slam))$ ]] || assertError -v cronScheduleSpecOrig "could not interpret '$part'"
		[ ${pCur:-100} -lt 5 ] || assertError -v cronScheduleSpecOrig "malformed cron schedule spec. more than 5 parts specified."

		# syntax=<pValOffset>[/<pValPeriod>][<pSuf>]
		# syntax=/<pValPeriod>[<pSuf>]
		# syntax=<name>[,<name>]
		local pValOffset="" pValPeriod="" pField=""

		### detected and handle name and name-lists for dow and month
		if [[ "$part" =~ ^(($(arrayJoin -d"|" dayNames)|$(arrayJoin -d"|" monthNames)),{0,1}){1,}$ ]]; then
			pField="${pFieldsMap[${part%%,*}]}"
			local i; for i in ${part//,/ }; do
				pValOffset="${pValOffset}${pValOffset:+,}${i:0:3}"
			done

		### detected and handle SLAm keyword
		elif [[ "$part" =~ slam ]]; then
			domConfigGet -r slamStart SLAm start "saturday 18:00UTC"
			read -r slamStartDay slamStartHour slamStartMinute < <(date -d "$slamStart" +"%A %-H %-M")
			slamStartDay="${slamStartDay,,}"
			continue

		### typical numeric range, list, and interval expressions
		else
			local pValue="$part"; while [[ "${pValue: -1:1}" =~ [a-zA-Z] ]]; do pValue="${pValue:0:-1}"; done
			local pSuf="${part#$pValue}"
			local pField="${pFieldsMap[${pSuf:-default}]}"; pField="${pField:-$pCur}"

			# check that that value(s) are in range
			[[ ! "$pValue" =~ / ]] && pValue="$pValue/"
			splitAttribute -q -- "${pValue/\//:}" pValOffset pValPeriod
			local limit="${pRanges[$pField]}"
			local pNumber; for pNumber in ${pValOffset//[,-]/ } $pValPeriod; do
				[ $(( ${limit:-0} - ${pNumber/[*]/1} )) -gt 0 ] || assertError -v cronScheduleSpecOrig "value '$pValue' is out of range [0-$((${limit:-0}-1))]"
				[[ "$pField" =~ 2|3 ]] && [ ${pNumber//[*]/1} -eq 0 ] && assertError -v cronScheduleSpecOrig -v pField "${pFields[$pField]} can not be '0'"
			done

			# expand offset-interval expressions (e.g. 4/10min)
			if [[ ! "${pValOffset:-"*"}" =~ [*,-] ]] && [ "$pValPeriod" != "" ]; then
				pValOffset="$(( pValOffset % pValPeriod ))"
				local n="$pValOffset"
				while [ $(( n += pValPeriod )) -lt $limit ]; do
					pValOffset="$pValOffset,$n"
				done
				pValPeriod=""
			fi

			# move the current field position to the next
			pCur=$((pField+1))
		fi

		pSched[$pField]="${pValOffset:-*}"; [ "$pValPeriod" != "" ] && pSched[$pField]="${pSched[$pField]}/$pValPeriod"
	done

	# if SLAm was specified...
	if [ "$slamStart" ]; then
		((slamStartHour+=${pSched[1]:-0}))
		((slamStartMinute+=${pSched[0]:-0}))
		echo "$slamStartMinute   $slamStartHour   * * $slamStartDay"
		return
	fi


	### Fill in defaults for each part not specified
	# min hour day month dow
	# In general, the default for larger time periods than is specified is all (*)
	# and the default for smaller time periods than is specified will one occurance at (pStart[?])
	# We start out with a state variable default='*' and iterate from right to left (large time periods to smaller time periods)
	# once we hit a part that is not set to all(*), we change default='pStart[?]'
	local default='*'
	[ "${pSched[4]}" == "" ] && pSched[4]='*'

	[ "${pSched[3]}" == "" ] && pSched[3]='*'
	[ "${pSched[3]}" != "*" ] && default=''

	[ "${pSched[2]}" == "" ] && pSched[2]="${default:-1}"
	[ "${pSched[2]}" != "*" ] && default=''

	# if DOW is set, it does not effect the default for month and day but is does for hour and min
	[ "${pSched[4]}" != "*" ] && default=''

	[ "${pSched[1]}" == "" ] && pSched[1]="${default:-0}"
	[ "${pSched[1]}" != "*" ] && default=''

	[ "${pSched[0]}" == "" ] && pSched[0]="${default:-0}"


	local results="${pSched[0]}   ${pSched[1]}   ${pSched[2]}   ${pSched[3]}   ${pSched[4]}"
	echo "${results}"
}


# usage: cronGetNextTime [+<dateFormatStr>] <runSpec>
# Returns the next time in the future that <runSpec> specifies.  The return value is in epoc time (seconds since Jan 1 1970 in UTC)
# Params:
#    <runSpec>     : the spec that determines how often or exactly when something should be ran. see cronNormSchedule for supported syntax.
# Options:
#    +<dateFormatStr> : see man date. default is "%s" which is epoc time
function cronGetNextTime()
{
	cronGetMostRecentTime -next "$@"
}


# usage: cronGetMostRecentTime [+<dateFormatStr>] <runSpec>
# Returns the most recent time in the past that <runSpec> specifies.  The return value is in epoc time (seconds since Jan 1 1970 in UTC)
# Params:
#    <runSpec>     : the spec that determines how often or exactly when something should be ran. see cronNormSchedule for supported syntax.
# Options:
#    +<dateFormatStr> : see man date. default is "%s" which is epoc time
function cronGetMostRecentTime()
{
	local dateFormatStr="%s" direction=-1
	while [[ "$1" =~ ^[-+] ]]; do case $1 in
		+*) dateFormatStr="${1#+}" ;;
		-next) direction=1 ;;
	esac; shift; done

	local runSpec="$1"      ; assertNotEmpty runSpec

	# *Spec vars are the 5 cron terms that runSpec generates
	local minSpec hourSpec daySpec monthSpec dowSpec

	# *Eligible vars are space separated lists of the eligible values defined by *Spec.  day/month names are replaced with numeric values
	local minEligible hourEligible dayEligible monthEligible dowEligible

	# *Set vars are associative arrays where each elible value is an index and its value is non-empty
	local -A minSet hourSet daySet monthSet dowSet


	### populate the *Spec vars from runSpec
	read -r minSpec hourSpec daySpec monthSpec dowSpec < <(cronNormSchedule "$runSpec") || exit

	### prepare the data structures that contain the eligible elements of each type
	local i

	# prepare month vars
	local -A monthMap=([1]=1 [jan]=1 [january]=1 [2]=2 [feburary]=2 [feb]=2 [3]=3 [march]=3 [mar]=3 [4]=4 [april]=4 [apr]=4 [5]=5 [may]=5 [6]=6 [june]=6 [jun]=6 [7]=7 [july]=7 [jul]=7 [8]=8 [august]=8 [aug]=8 [9]=9 [september]=9 [sep]=9 [10]=10 [october]=10 [oct]=10 [11]=11 [november]=11 [nov]=11 [12]=12 [december]=12 [dec]=12)
	monthEligible="$(strSetExpandRangeNotation "1 2 3 4 5 6 7 8 9 10 11 12" "$monthSpec" monthMap)"
	for i in ${monthEligible}; do monthSet[$i]="1"; done

	# prepare day of week vars
	local -A dowMap=([sunday]=0 [sun]=0 [monday]=1 [mon]=1 [tuesday]=2 [tue]=2 [wednesday]=3 [wed]=3 [thursday]=4 [thu]=4 [friday]=5 [fri]=5 [saturday]=6 [sat]=6 [0]=0 [1]=1 [2]=2 [3]=3 [4]=4 [5]=5 [6]=6 [7]=0)
	dowEligible="$(strSetExpandRangeNotation "0 1 2 3 4 5 6" "$dowSpec" dowMap)"
	for i in ${dowEligible}; do dowSet[$i]="1"; done

	# prepare day of month vars
	dayEligible="$(strSetExpandRangeNotation "1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31" "$daySpec")"
	for i in ${dayEligible}; do daySet[$i]="1"; done

	# prepare hour of day vars
	hourEligible="$(strSetExpandRangeNotation "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23" "$hourSpec")"
	for i in ${hourEligible}; do hourSet[$i]="1"; done

	# prepare minute of hour vars
	minEligible="$(strSetExpandRangeNotation "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59" "$minSpec")"
	for i in ${minEligible}; do minSet[$i]="1"; done


	### start calculating the final values. The algorithm is a waterfall. minutes possibly overflow to effect hours. hours possibly overflow to effect days
	local dow month day hour min

	local hourNow minNow
	read -r hourNow minNow < <(date +"%-H %-M")
	[ $direction -gt 0 ] && ((minNow++))

	# see if there was a eligible minute in the current hour. If not, we know that minute will be the largest eligible value and this hour is not eligible
	# even it there is one in this hour, later if we find the current hour is not eligible, we will set the min to the largest value
	for ((min=minNow; min>=0 && min<60; min+=direction)); do
		[ "${minSet[$min]}" ] && break
	done
	if [ ${min:--1} -lt 0 ]; then
		((hourNow--))
		min="${minEligible##* }"
	elif [ ${min:--1} -eq 60 ]; then
		((hourNow++))
		min="${minEligible%% *}"
	fi


	# see if there was a eligible hour in the current day. We already decremented hourNow if it was not eligible b/c of the minute spec.
	# The algorithm for hour/day is the same as for minute/hour in the previous block
	local dayStart=0
	for ((hour=hourNow; hour>=0 && hour<24; hour+=direction)); do
		[ "${hourSet[$hour]}" ] && break
	done
	if [ ${hour:--1} -lt 0 ]; then
		dayStart=1
		hour="${hourEligible##* }"
		min="${minEligible##* }"
	elif [ ${hour:--1} -eq 24 ]; then
		dayStart=1
		hour="${hourEligible%% *}"
		min="${minEligible%% *}"
	fi

	# now find the latest eligible day. If the current day is not eligible b/c it has not gotten to the first eligible hour, dayStart would have been
	# set to 1 so that the first day we check will be yesterday
	local found=""
	for ((dayOffset=dayStart; dayOffset<366; dayOffset++)); do
		read -r dow year month day < <(date +"%w %Y %-m %-d" -d"today $((direction*dayOffset))day")
		if [ "${dowSet[$dow]}" ] && [ "${monthSet[$month]}" ] && [ "${daySet[$day]}" ]; then
			found="1"
			break
		fi
		# TODO: if this turns out to be slow, we could do better by incrementing dayOffset by larger values to skip to the next vlaid month, dow, or day
	done
	assertNotEmpty found "could not find any run time from spec '$runSpec'"

	# if its not today, the hour and minute will be the last eligible values in that previous day
	if [ "$dayOffset" != "0" ] && [ $direction -gt 0 ]; then
		hour="${hourEligible%% *}"
		min="${minEligible%% *}"
	elif [ "$dayOffset" != "0" ] && [ $direction -lt 0 ]; then
		hour="${hourEligible##* }"
		min="${minEligible##* }"
	fi

	# return the epoc (%s) time for the time found
	date -d "${year}-${month}-${day} ${hour}:${min}" +"$dateFormatStr"
}

# usage: cronShouldRun <runSpec> <lastRunTime>
# The exit code of this function is true(0) if it is time to run or false(1) if its not
# The algorithm calculates the last time that runSpec should have ran and if lastRunTime is before that time it
# returns true. If it has never ran or its been turned off for a while, it will return true even if its off cycle
# but the next time it runs, it will get back to running at or close to the times specified in <runSpec>
# Params:
#    <runSpec>     : the spec that determines how often or exactly when something should be ran. see cronNormSchedule for supported syntax.
#    <lastRunTime> : the timestamp of when the thing last ran
# Exit code:
#    0  : success, should be run now
#    1  : failure, it is not time to run
function cronShouldRun()
{
	local runSpec="$1"      ; assertNotEmpty runSpec
	local lastRunTime="$2"  ; assertNotEmpty lastRunTime

	# get the last time it should have run
	local lastScheduledTime="$(cronGetMostRecentTime +"%s" "$runSpec")"

	# if it has not ran since the last scheduled run time, it should run now
	[ ${lastRunTime:-0} -lt ${lastScheduledTime:-0} ]
}




# usage: cronCntr -n <cronName> show
# usage: cronCntr -n <cronName> -c <cronCmd> [-p <cronPeriod>] [-u <cronUser>] on
# usage: cronCntr -n <cronName> off
# Manage a cron.d/<confFile> to have a command ran in periodically in the background
# Params:
#      on   : creates the cron script in /etc/cron.d/<cronName>
#      off  : removes the cron script from /etc/cron.d/<cronName>
#      show : shows the status of whether the cron script exists and whats inside it
# Options:
#      -n <cronName> : each cron must have a unique name. It will be used as the file name in the /etc/cron.d/
#      -c <cronCmd>  : the command that will be executed by the cron
#      -p <period>   : default is /30m. see man cronNormSchedule for details. It can be any 5 field cron spec plus some extensions
function cronCntr()
{
	local cronName cronUser ldFolder cronCmd period="/30m"
	while [ $# -gt 0 ]; do case $1 in
		-n*|--name*)   bgOptionGetOpt val: cronName "$@" && shift ;;
		-u*|--user*)   bgOptionGetOpt val: cronUser "$@" && shift ;;
		-c*|--cmd*)    bgOptionGetOpt val: cronCmd  "$@" && shift ;;
		-p*|--period*) bgOptionGetOpt val: period   "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	assertNotEmpty cronName
	local cmd="${1:-show}"; [ $# -gt 0 ] && shift
	local cronFile="/etc/cron.d/$cronName"

	case ${cmd:-show} in
		state)
			if [ -f "$cronFile" ]; then
				spec="$(awk '
					$0~"^[ \t]*#[ \t]*cronSpec:.*$"	{
						spec=$0; sub("^.*:[[:space:]]*","", spec)
						print spec
					}
				' "$cronFile")"
				echo "on using spec '${spec}'"

			else
				echo "off"
			fi
			;;

		show)
			if [ -f "$cronFile" ]; then
				echo "sync is on"
				awk '{print "   "$0}' "$cronFile" |wrapLines -t
			else
				echo "sync is off"
			fi
			;;

		on)
			assertNotEmpty cronCmd

			local cronSchedule="$(cronNormSchedule "$period")" || exit
			echo "normalized cron schedule='$cronSchedule'"

			# calculate the PATH variable to support testing with virtually installed projects
			# if you install a cron from a terminal with virtually installed projects those paths will be added to
			# that the cron script will find that verion of the command
			local path="PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
			if [ "$bgVinstalledPaths" ]; then
				echo "Warning: installing cron in development mode because this shell has virtually installed projects"
				echo "         This is typically best for debugging in a VM"
				read -d"\0" -r path <<-EOS
					bgVinstalledPaths="$bgVinstalledPaths"
					bgDataPath="$bgDataPath"
					bgIntalled="$bgIntalled"
					bgLibPath="$bgLibPath"
					PATH="$PATH"
					EOS
			fi

			cat <<-EOS2 | sudo tee "$cronFile" >/dev/null
				# this file was created by cronCntr feature in $(basename $0)
				# changes to this file could be overwritten so use that cmd to manage this file
				# or copy to a different name
				# cronSpec: $period
				SHELL=/bin/bash
				$path
				USER=${cronUser:-root}

				  ${cronSchedule} ${cronUser:-root} $cronCmd
				EOS2

			;;

		off)
			sudo rm "$cronFile"
			;;
	esac
}
