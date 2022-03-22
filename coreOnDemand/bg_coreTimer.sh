
#######################################################################################################################################
### Timer Functions  and Some Time/Data Functions

##################################################################################################################
### bgtimer -- time and report on sections of scripts
# TODO: now that we are using the numeric array method, implement a stack of lap structs with (startTime,endTime,description)
#       $timerVar[0] would be the stackSize. each stack frame would increment by 3. each attribute would be an offset (0,1 or 2)

declare -a bgtimerGlobalTimer

# usage: bgtimerStart [-T <timerVar>] [-f]
# start or restart the timer.
# If <timerVar> is specified, a new timer will be allocated and the ID of the timer stored in the variable <timerVar>.
# If not, a global timer is used which is fine, for common, simple cases, but bgtimer calls can not be nested so library
# code should always use -T because it does not know if the user is using a bgtimer above it.
# Options:
#    -T <timerVar> : <timerVar> is a simple var declared in the callers scope that will identify the timer information
#    -f : forks.  turn on fork counting as well as time counting
function bgtimerStart()
{
	declare -g _forkCnt=0 forkFlag
	local timerVar_start="bgtimerGlobalTimer[0]"
	local timerVar_lap="bgtimerGlobalTimer[1]"
	local timerVar_forkStart="bgtimerGlobalTimer[2]"
	local timerVar_forkLap="bgtimerGlobalTimer[3]"
	local timerVar_indent="bgtimerGlobalTimer[4]"
	local noResetFlag indentFlag
	while [ $# -gt 0 ]; do case $1 in
		--stub) ;;
		-p*)  bgOptionGetOpt val: prec "$@" && shift ;;
		-T*)local tname; bgOptionGetOpt val: tname "$@" && shift; assertNotEmpty tname
			timerVar_start="$tname[0]"
			timerVar_lap="$tname[1]"
			timerVar_forkStart="$tname[2]"
			timerVar_forkLap="$tname[3]"
			timerVar_indent="$tname[4]"
			;;
		-f) forkFlag="-f"
			set -o monitor
			_forkCnt=1
			bgtrap "((_forkCnt++))" CHLD
			;;
		--no-reset) noResetFlag="--no-reset" ;;
		-i) indentFlag="-i" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ "$indentFlag" ] && printf -v "$timerVar_indent" "%s" "$indentFlag"
	[ "$noResetFlag" ] && return

	printf -v "$timerVar_start"     "%s" "$(date +"%s%N")"
	printf -v "$timerVar_lap"       "%s" "${!timerVar_start}"

	[ "$forkFlag" ] && printf -v "$timerVar_forkStart" "%s" "${_forkCnt:-0}"
	[ "$forkFlag" ] && printf -v "$timerVar_forkLap"   "%s" "${_forkCnt:-0}"
}


# usage: bgtimerConfig [-T <timerVar>] [-f]
# set the options for the <timerVar> or default <timerVar>
# Options:
#    -T <timerVar> : <timerVar> is a simple var declared in the callers scope that will identify the timer information
#    -f : forks.  turn on fork counting as well as time counting
function bgtimerConfig()
{
	bgtimerStart --no-reset "$@"
}


# usage: bgtimerIsPast [-T <timerVar>] <timePeriod>
# checks whether the specified amount of time has past since the start of the timer
# Exit Codes:
#     0 (true)  : the current value of the timer is greater than <timePeriod>
#     1 (false) : the current value of the timer is less than <timePeriod>
function bgtimerIsPast()
{
	local timerVar_start="bgtimerGlobalTimer[0]"
	local timerVar_lap="bgtimerGlobalTimer[1]"
	local timerVar_forkStart="bgtimerGlobalTimer[2]"
	local timerVar_forkLap="bgtimerGlobalTimer[3]"
	local timerVar_indent="bgtimerGlobalTimer[4]"
	local prec=3 retVar retForksVar
	while [ $# -gt 0 ]; do case $1 in
		-p*)  bgOptionGetOpt val: prec "$@" && shift ;;
		-T*)local tname; bgOptionGetOpt val: tname "$@" && shift; assertNotEmpty tname
			timerVar_start="$tname[0]"
			timerVar_lap="$tname[1]"
			timerVar_forkStart="$tname[2]"
			timerVar_forkLap="$tname[3]"
			timerVar_indent="$tname[4]"
			;;
		-R)  retVar="$2"; shift ;;
		-F)  retForksVar="$2"; shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	while [[ "$1" =~ ^- ]]; do case $1 in
	esac; shift; done
	local timePeriod="$1"

	local timePeriodInNS; bgtimePeriodConvert -ns "${timePeriod}" timePeriodInNS

	local delta="$(( $(date +"%s%N") - ${!timerVar_start:-0} ))"

	(( delta > timePeriodInNS ))
}

# usage: bgtimerGet [-T <timerVar>] [-p <precision>] [-R <retVar>] [-F <retForksVar>]
# get current elapsed time from the last time bgtimerStart was called
function bgtimerGet()
{
	local timerVar_start="bgtimerGlobalTimer[0]"
	local timerVar_lap="bgtimerGlobalTimer[1]"
	local timerVar_forkStart="bgtimerGlobalTimer[2]"
	local timerVar_forkLap="bgtimerGlobalTimer[3]"
	local timerVar_indent="bgtimerGlobalTimer[4]"
	local prec=3 retVar retForksVar
	while [ $# -gt 0 ]; do case $1 in
		-p*)  bgOptionGetOpt val: prec "$@" && shift ;;
		-T*)local tname; bgOptionGetOpt val: tname "$@" && shift; assertNotEmpty tname
			timerVar_start="$tname[0]"
			timerVar_lap="$tname[1]"
			timerVar_forkStart="$tname[2]"
			timerVar_forkLap="$tname[3]"
			timerVar_indent="$tname[4]"
			;;
		-R)  retVar="$2"; shift ;;
		-F)  retForksVar="$2"; shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ "${!timerVar_start}" ] || bgtimerStart

	local delta="$(( $(date +"%s%N") - ${!timerVar_start:-0} ))"
	local results; bgNanoToSec -R results $delta $prec
	returnValue "$results" "$retVar"

	[ "$retForksVar" ] &&  printf -v "$retForksVar"   "%s" "$(( ${_forkCnt:-0}-${!timerVar_forkStart:-0} ))"
}

# usage: bgtimerGetNano [-T <timerVar>] [-R <retVar>] [-F <retForksVar>]
# get current elapsed time from the last time bgtimerStart was called
function bgtimerGetNano()
{
	local timerVar_start="bgtimerGlobalTimer[0]"
	local timerVar_lap="bgtimerGlobalTimer[1]"
	local timerVar_forkStart="bgtimerGlobalTimer[2]"
	local timerVar_forkLap="bgtimerGlobalTimer[3]"
	local timerVar_indent="bgtimerGlobalTimer[4]"
	local prec=3 retVar retForksVar
	while [ $# -gt 0 ]; do case $1 in
		-p*)  bgOptionGetOpt val: prec "$@" && shift ;;
		-T*)local tname; bgOptionGetOpt val: tname "$@" && shift; assertNotEmpty tname
			timerVar_start="$tname[0]"
			timerVar_lap="$tname[1]"
			timerVar_forkStart="$tname[2]"
			timerVar_forkLap="$tname[3]"
			timerVar_indent="$tname[4]"
			;;
		-R)  retVar="$2"; shift ;;
		-F)  retForksVar="$2"; shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ "${!timerVar_start}" ] || bgtimerStart

	local delta="$(( $(date +"%s%N") - ${!timerVar_start:-0} ))"
	returnValue "$delta" "$retVar"

	[ "$retForksVar" ] &&  printf -v "$retForksVar"   "%s" "$(( ${_forkCnt:-0}-${!timerVar_forkStart:-0} ))"
}

# usage: bgtimerLapGet [-T <timerVar>] [-p <precision>] [-R <retVar>] [-F <retForksVar>]
# get current elapsed time from the last time bgtimerLapPrint was called
# this does not reset the lap time so it is typically call just before bgtimerLapPrint
# if the lap time is needed in a variable
function bgtimerLapGet()
{
	local timerVar_start="bgtimerGlobalTimer[0]"
	local timerVar_lap="bgtimerGlobalTimer[1]"
	local timerVar_forkStart="bgtimerGlobalTimer[2]"
	local timerVar_forkLap="bgtimerGlobalTimer[3]"
	local timerVar_indent="bgtimerGlobalTimer[4]"
	local prec=3 retVar retForksVar
	while [ $# -gt 0 ]; do case $1 in
		-p*)  bgOptionGetOpt val: prec "$@" && shift ;;
		-T*)local tname; bgOptionGetOpt val: tname "$@" && shift; assertNotEmpty tname
			timerVar_start="$tname[0]"
			timerVar_lap="$tname[1]"
			timerVar_forkStart="$tname[2]"
			timerVar_forkLap="$tname[3]"
			timerVar_indent="$tname[4]"
			;;
		-R)  retVar="$2"; shift ;;
		-F)  retForksVar="$2"; shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ "${!timerVar_start}" ] || bgtimerStart

	local delta="$(( $(date +"%s%N") - ${!timerVar_lap:-0} ))"
	local results; bgNanoToSec -R results $delta $prec
	returnValue "$results" "$retVar"

	[ "$retForksVar" ] &&  printf -v "$retForksVar"   "%s" "$(( ${_forkCnt:-0}-${!timerVar_forkLap:-0} ))"
}


# usage: bgtimerLapPrint [-T <timerVar>] [-p <precision>] [<description>]
# mark the current lap and print the lap time
# the notion of a lap is that each lap is a separate part of the whole. If you add up all the lap times
# since the start, you get the total elapsed time. This facilitates printing the intermediate lap times and the
# overall elapsed time
function bgtimerLapPrint()
{
	local timerVar_start="bgtimerGlobalTimer[0]"
	local timerVar_lap="bgtimerGlobalTimer[1]"
	local timerVar_forkStart="bgtimerGlobalTimer[2]"
	local timerVar_forkLap="bgtimerGlobalTimer[3]"
	local timerVar_indent="bgtimerGlobalTimer[4]"
	local prec=3 indentFlag
	while [ $# -gt 0 ]; do case $1 in
		-p*)  bgOptionGetOpt val: prec "$@" && shift ;;
		-T*)local tname; bgOptionGetOpt val: tname "$@" && shift; assertNotEmpty tname
			timerVar_start="$tname[0]"
			timerVar_lap="$tname[1]"
			timerVar_forkStart="$tname[2]"
			timerVar_forkLap="$tname[3]"
			timerVar_indent="$tname[4]"
			;;
		-i) indentFlag="-i" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ "$indentFlag" ] && printf -v "$timerVar_indent" "%s" "$indentFlag"
	[ "${!timerVar_start}" ] || bgtimerStart

	local forkStr
	if [ "${!timerVar_forkStart}" ]; then
		local forkDelta="$(( ${_forkCnt:-0} - ${!timerVar_forkLap:-0} ))"
		printf -v "$timerVar_forkLap"   "%s" "${_forkCnt:-0}"
		forkStr=" $forkDelta forks"
	fi

	local current="$(date +"%s%N")"
	local delta="$(( $current - ${!timerVar_lap:-0} ))"
	printf -v "$timerVar_lap"   "%s" "$current"
	local desc="$*"
	local leadingIndent="${desc%%[^[:space:]]*}"
	desc="${desc#$leadingIndent}"
	[ "${!timerVar_indent}" ] && printf -v leadingIndent "%s%*s" "$leadingIndent" "$((${#FUNCNAME[*]} * 1))"  ""
	echo "${leadingIndent}lap: $(bgNanoToSec $delta $prec)$forkStr : $desc"
}

# usage: bgtimerPrint [-T <timerVar>] [-p <precision>] [<description>]
# print the current elapsed time from bgtimerStart in secs as a decimal with <prec> number of places after the .
function bgtimerPrint()
{
	local timerVar_start="bgtimerGlobalTimer[0]"
	local timerVar_lap="bgtimerGlobalTimer[1]"
	local timerVar_forkStart="bgtimerGlobalTimer[2]"
	local timerVar_forkLap="bgtimerGlobalTimer[3]"
	local timerVar_indent="bgtimerGlobalTimer[4]"
	local prec=3 indentFlag accumulateVar
	while [ $# -gt 0 ]; do case $1 in
		-p*)  bgOptionGetOpt val: prec "$@" && shift ;;
		-T*)local tname; bgOptionGetOpt val: tname "$@" && shift; assertNotEmpty tname
			timerVar_start="$tname[0]"
			timerVar_lap="$tname[1]"
			timerVar_forkStart="$tname[2]"
			timerVar_forkLap="$tname[3]"
			timerVar_indent="$tname[4]"
			;;
		-i) indentFlag="-i" ;;
		--accumulate*) bgOptionGetOpt val: accumulateVar "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ "$indentFlag" ] && printf -v "$timerVar_indent" "%s" "$indentFlag"
	[ "${!timerVar_start}" ] || bgtimerStart

	local delta="$(( $(date +"%s%N") - ${!timerVar_start:-0} ))"
	[ "$accumulateVar" ] && printf -v "$accumulateVar" "%s" $((${!accumulateVar}+delta))
	local desc="$@"
	local leadingIndent="${desc%%[^[:space:]]*}"
	desc="${desc#$leadingIndent}"
	[ "${!timerVar_indent}" ] && printf -v leadingIndent "%s%*s" "$leadingIndent" "$((${#FUNCNAME[*]} * 1))"  ""
	echo "${leadingIndent}total: $(bgNanoToSec $delta $prec) : $desc"
}


# usage: bgtimePeriodConvert [-s|-m|-h|-d|-w|-y|-ms|-us|-ns]  <timePeriod>
# takes <timePeriod> in the long format and returns an integer in seconds or the unit specified by
# one of the options. If the input has more precision than the output unit, it is rounded down. The
# output will not contain a unit character. It will only be a integer value.
#
# Signs and Addition Subtraction:
# The default sign of the timePeriod starts as positive (+). Plus(+) and minus(-) characters can appear
# in front of any component term. If it has a +- prefix, the : is optional to delimit that term from
# its preceeding term. Each + will set the default sign to positive. Each - will negate the default
# sign so that positive becomes negative and negative becomes positive. The new default will apply to
# the current term and any that follow it until other +- are encountered. Its ok if multiple plus and
# minus characters appear one right after another in front of one term.
#
# This has the effect that timePeriods can be negative by adding a minus(-) character in front of it
# and they can be added and subtracted by concatonating them together with plus or minus character.
# "${timePeriod1}+${timePeriod2}" and "${timePeriod1}-${timePeriod2}" will produce a valid <timePeriod>
# that can be passed to this function as long as timePeriod1 and timePeriod2 are both valid. Subtracting
# a negative timePeriod will behave the same as normal arithmitic. The number returned by this function
# may or may not be negative.
#
# Params:
#    <timePeriod> : a time period like 1d:3h:30m:10s:990ms:0us or 3d or 30s. Any of the components
#           could be missing. If a component does not have a unit, it is taken as being seconds.
#           the time from all the components are added together. Typically each unit would only
#           appear once but if it is repeated it the values will be summed taking into account the
#           sign of the term.
# Options:
#    note: none of these options are case sensitive
#    -ns  : return the result in nano seconds  (0.000000001 seconds is one nanoseconds)
#    -us  : return the result in micro seconds (0.000001 seconds is one microseconds)
#    -ms  : return the result in milli seconds (0.001 seconds is one milliseconds)
#    -S   : (default) return the result in seconds
#    -M   : return the result in minutes, rounded down
#    -H   : return the result in hours, rounded down
#    -D   : return the result in days, rounded down
#    -W   : return the result in weeks, rounded down
#    -Y   : return the result in years, rounded down
function bgtimePeriodConvert()
{
	local units="seconds" seconds
	while [[ "${1,,}" =~ ^- ]]; do case $1 in
		-ns) units="nanosecs" ;;
		-us) units="microsecs" ;;
		-ms) units="millisecs" ;;
		-s) units="seconds" ;;
		-m) units="minutes" ;;
		-h) units="hours" ;;
		-d) units="days" ;;
		-w) units="weeks" ;;
		-y) units="years" ;;
	esac; shift; done
	local timePeriod="${1,,}"

	local seconds nanosecs
	local signFactor="1"
	while [ "$timePeriod" ] && [[ "$timePeriod" =~ ^([-+]+)?([0-9]+)?(s|m|h|d|y|ns|us|ms)?(:)? ]]; do
		timePeriod="${timePeriod#${BASH_REMATCH[0]}}"
		local sign="${BASH_REMATCH[1]}"
		local number="${BASH_REMATCH[2]}"
		local unit="${BASH_REMATCH[3]:-s}"
		while [ "$sign" ]; do case ${sign:0:1} in
			-) signFactor="$((signFactor*-1))" ;;
			+) signFactor="1" ;;
		esac; sign="${sign:1}"; done
		case $unit in
			s)  seconds=$((  seconds  + (signFactor*number)         )) ;;
			m)  seconds=$((  seconds  + (signFactor*number*60)      )) ;;
			h)  seconds=$((  seconds  + (signFactor*number*3600)    )) ;;
			d)  seconds=$((  seconds  + (signFactor*number*86400)   )) ;;
			y)  seconds=$((  seconds  + (signFactor*number*86400*365))) ;;
			w)  seconds=$((  seconds  + (signFactor*number*86400*7  ))) ;;
			ms) nanosecs=$(( nanosecs + (signFactor*number*1000000) )) ;;
			us) nanosecs=$(( nanosecs + (signFactor*number*1000)    )) ;;
			ns) nanosecs=$(( nanosecs + (signFactor*number)         )) ;;
		esac
	done
	[ "$timePeriod" ] && assertError "malformed timePeriod '$1'. Error token is '${timePeriod%%:*}'"

	local result
	case $units in
		nanosecs)  result=$(( seconds*1000000000 + nanosecs                   )) || assertError ;;
		microsecs) result=$(( seconds*1000000    + nanosecs/1000              )) || assertError ;;
		millisecs) result=$(( seconds*1000       + nanosecs/1000000           )) || assertError ;;
		seconds)   result=$(( seconds            + nanosecs/1000000000        )) || assertError ;;
		minutes)   result=$(( seconds/60         + nanosecs/60000000000       )) || assertError ;;
		hours)     result=$(( seconds/3600       + nanosecs/3600000000000     )) || assertError ;;
		days)      result=$(( seconds/86400      + nanosecs/86400000000000    )) || assertError ;;
		weeks)     result=$(( seconds/86400/7    + nanosecs/86400000000000/7  )) || assertError ;;
		years)     result=$(( seconds/86400/365  + nanosecs/86400000000000/365)) || assertError ;;
	esac
	returnValue "$result" "$2"
}


# usage: timeExprNormalize [-f <formatStr>] [-Z <inputTimezone>] [-z <outputTimezone>] <dateTimeExpr>
# returns the normalized, fully qualified expression for the date expression
# If a time zone is not explicitly stated in the input it will be taken as the TZ of the session (which is typically the host's TZ)
# If the expression is relative to now and a time zone is included or the -Z option changes the input zone, the date util returns a
# misleading value so avoid that. E.G. If its 3am now in $TZ, then "5 minutes ago UTC" would return what time it was in $TZ when it was 2:55am UTC"
# Params:
#     <dateTimeExpr> : this can be any expression that the linux 'data' utility accepts. See 'info date' for details
#                      examples: "now", "5 minutes ago",  "5 minutes" (which is same as) "now + 5 minutes"
# Options:
#     -f <formatStr> : specify the output of the result. can be any string accepted by the date +<formatStr> option.
#                      default is %Y-%m-%d %H:%M:%S
#     -Z <inputTimezone> : If the <dateTimeExpr> does not specify the timezone, it will be interpreted as being in this time zone
#                      default is $TZ environment var.
#                      WARNING: if you do not know that the <dateTimeExpr> does not use any times relative to "now", do not use this option
#     -z <outputTimezone> : the result will be in this zimezone requardless of whether the formatStr includes time zone phrase (i.e. %z)
#                      default is UTC
function timeExprNormalize()
{
	local outputFormat="%Y-%m-%d %H:%M:%S" inputTimezone outputTimezone
	while [ $# -gt 0 ]; do case $1 in
		-f*)  bgOptionGetOpt val: outputFormat "$@" && shift ;;
		-Z*)  bgOptionGetOpt val: inputTimezone "$@" && shift ;;
		-z*)  bgOptionGetOpt val: outputTimezone "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local dateTimeExpr="$1"
	normExpr="$(TZ="${inputTimezone:-$TZ}" date +"%Y-%m-%d %H:%M:%S %z" -d "$dateTimeExpr" 2>/dev/null)"
	[ ! "$normExpr" ] && assertError "invalid date/time expression '$endTimeValue'" >&2

	# this second call to date only converts from the expressions's time zone to UTC. We do not do that in the first call because
	# the date util mishandles expressions relative to "now" when you convert to a time zone. it gets the value of now in
	# the local TZ and interprets it as that time in the target TZ without changing the value.  So 'now' won't be 'now' anymore
	# when the input and output time zones differ. We can avoid that problem by doing it in two steps. (unless the input has "now" and timezone info)
	TZ="${outputTimezone:-UTC}" date +"${outputFormat}" -d "$normExpr"
}


# usage: bgNanoToSec [-R <retVar>] <nanoSec> [<numDecPlace=3>]
# convert a number of nano seconds to secs. numDecPlace is the number of decimal points of precision to keep
# nanoSec is the number of nano seconds as a whole number. The output is the number of seconds as a decimal sss.sss
function bgNanoToSec()
{
	local tenseFlag retVar
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R)  retVar="$2"; shift ;;
	esac; shift; done
	local nano="$1"
	[[ "$nano" =~ ^[0-9]*$ ]] || assertError "expected integer number of nanosecs. got '$nano'"
	local numDecPlace="${2:-3}"
	while [ ${#nano} -lt 10 ]; do nano="0$nano"; done
	local frac="${nano: -9}"
	local sec="${nano%$frac}"
	local decPoint="."; [ $numDecPlace -eq 0 ] && decPoint=""
	returnValue "${sec}${decPoint}${frac:0:$numDecPlace}" "$retVar"
}

# usage: bgTimePeriodFromLabel [-S|-M|-H|-D|-L<p>] <label>
# returns the time period represented by <label> as a simple integer number in the units specified
# Params:
#   <label> : the time period as a string in a format compatible with that produced be bgTimePeriodToLabel (see  that function for details)
#              Examples  "2h", "2h:30m", "45s"
# Options:
#    -S  : (default) return the result in seconds
#    -M  : return the result in minutes, rounded down
#    -H  : return the result in hours, rounded down
#    -D  : return the result in days, rounded down
#    -L<p> : return the result in long format with precision <p>. <p> can be 1,2,3,4
#          Long format is like "1d:2m:43m:12s". Leading terms that are 0 are not included
#          <p> specifies the maximum number of terms to include.
# See Also:
#   bgTimePeriodToLabel
function bgTimePeriodFromLabel()
{
	local -A normalizeSuffix=([default]="" [seconds]=s [second]=s [sec]=s [s]=s  [minutes]=m [minute]=m [min]=m [m]=m [hours]=h [hour]=h [h]=h [days]=d [day]=d [d]=d [ago]="+" [from]="-" [now]="-")
	local -A unitToOrder=([d]=3 [h]=2 [m]=1 [s]=0)
	local    unitFormOrder=( s m h d )

	local units="seconds" precision fromTime posOrNeg="+"
	while [ $# -gt 0 ]; do case $1 in
		-S) units="seconds" ;;
		-M) units="minutes" ;;
		-H) units="hours" ;;
		-D) units="days" ;;
		-L*)bgOptionGetOpt val: precision "$@" && shift
			units="long"
			;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local label="$1"

	if [[ "$label" == ^[+-] ]]; then
		posOrNeg="${label:0:1}"
		label="${label:1}"
	fi


	local partsNum partsSuf unitIndex i
	local parts=(${label//:/ })

	# go thru left to right, normalizing each part. we remove the tense terms and update posOrNeg
	# as soon as a unit is specified, adjacent terms without a unit will be the next smaller unit
	# if no unit suffix are given, the last term will be given "s"
	for ((i=0; i<${#parts[@]}; i++)); do
		part="${parts[$i]}"
		local pValue="$part"; while [[ "${pValue: -1:1}" =~ [a-zA-Z] ]]; do pValue="${pValue:0:-1}"; done
		[[ "$pValue" =~ ^[0-9]+$ ]] || assertError "invalid time period term '$part' in '$label'"
		local pSuf="${part#$pValue}"
		local normSuf="${normalizeSuffix[${pSuf:-default}]}"
		case $normSuf in
			d|h|m|s) unitIndex="${unitToOrder[$normSuf]}" ;;
			[+-])    posOrNeg="$normSuf"; break ;;
			*)       [ "$unitIndex" ] && normSuf="${unitFormOrder[$unitIndex]}" ;;
		esac
		[ ! "$normSuf" ] && (( ${#parts[@]} == i+1 ))  && normSuf="s"
		if [[ ! "$normSuf" =~ ^[+-] ]]; then
			partsNum+=("$pValue")
			partsSuf+=("$normSuf")
		fi
		[ ${unitIndex:-0} -gt 0 ] && ((unitIndex--))
	done

	# now go thru right to left, filling in the leading terms with missing suffixes (e.g.  30:15s  will become 30m:15s)
	for ((i=${#partsNum[@]}-1; i>=0;  i--)); do
		case ${partsSuf[$i]} in
			d|h|m|s) unitIndex="${unitToOrder[${partsSuf[$i]}]}" ;;
			*)       [ "$unitIndex" ] && partsSuf[$i]="${unitFormOrder[$unitIndex]}" ;;
		esac
		[ ${unitIndex:-3} -lt 3 ] && ((unitIndex++))
	done



	local seconds=0
	for i in "${!partsNum[@]}"; do
		local pValue="${partsNum[$i]}"
		local pSuf="${partsSuf[$i]}"
		case $pSuf in
			s) ((seconds+=pValue           )) ;;
			m) ((seconds+=(pValue *  60)   )) ;;
			h) ((seconds+=(pValue *  3600) )) ;;
			d) ((seconds+=(pValue * 86400) )) ;;
		esac
	done

	[ "$posOrNeg" == "+" ] && posOrNeg=""
	seconds="${posOrNeg}${seconds}"

	case $units in
		seconds) echo "$seconds" ;;
		minutes) echo $(( seconds /    60 )) ;;
		hours)   echo $(( seconds /  3600 )) ;;
		days)    echo $(( seconds / 86400 )) ;;
		long)    bgTimePeriodToLabel -p "$precision" "$seconds" ;;
	esac
}


# usage: bgTimePeriodToLabel [-t] [-p <numOfLevelesOfPrecision>] <seconds>
# returns a string label the represents the time period in human terms
# Output:
#   [-][<d>:d][<h>h:][<m>:m:][<s>:s] [tense]
#   1d:3h:54m:3s
#   Any unit that is "0" will be ommitted
#   tense can be "ago" (positive time periods) or "from now" (negative time periods)
# Params:
#   <seconds> : the time period in seconds. This typically comes from subtracting two timestaps
#               in linux epoch time $(( $(date +"%s") - $timeStampInEpoch ))
# Options:
#   -t : tense. include a suffix "ago"(positive period) or "from now"(negative) to indicate whether
#        the period is in the past or future. This is appropriate for time periods calulated like
#         $((  $now - $timestamp ))
# See Also:
#   bgTimePeriodFromLabel
function bgTimePeriodToRelativeLabel() { bgTimePeriodToLabel "$@"; }
function bgTimePeriodToLabel()
{
	local tenseFlag numOfLevelesOfPrecision=10
	while [[ "$1" =~ ^- ]]; do case $1 in
		-t)  tenseFlag="-t" ;;
		-p)  numOfLevelesOfPrecision="$2"; shift ;;
		-p*) numOfLevelesOfPrecision="${1#-p}" ;;
		-[0-9]*) break ;;
	esac; shift; done
	local seconds="$1"
	local posSec="$seconds"
	local tenseLabel="ago"
	if [ "${posSec:0:1}" == "-" ]; then
		posSec="${posSec:1}"
		tenseLabel="from now"
	fi
	local mins=$(( posSec / 60 )); posSec=$(( posSec % 60 ));
	local hours=$(( mins / 60 )); mins=$(( mins % 60 ));
	local days=$(( hours / 24 )); hours=$(( hours % 24 ));
	local label
	if [ ${days:-0} -gt 5000 ]; then
		label="never"
	else
		[ ${numOfLevelesOfPrecision:-0} -gt 0 ] && [ ${days:-0} -gt 0 ]   && { label="${days}d"; ((numOfLevelesOfPrecision--)); }
		[ ${numOfLevelesOfPrecision:-0} -gt 0 ] && [ ${hours:-0} -gt 0 ]  && { stringJoin -R label -d":" -e -a "${hours}h"; ((numOfLevelesOfPrecision--)); }
		[ ${numOfLevelesOfPrecision:-0} -gt 0 ] && [ ${mins:-0} -gt 0 ]   && { stringJoin -R label -d":" -e -a "${mins}m"; ((numOfLevelesOfPrecision--)); }
		[ ${numOfLevelesOfPrecision:-0} -gt 0 ] && [ ${posSec:-0} -gt 0 ] && { stringJoin -R label -d":" -e -a "${posSec}s"; ((numOfLevelesOfPrecision--)); }
		if [ "$tenseFlag" ]; then
			if [ "$label" ]; then
				stringJoin -R label -d" " -e -a "${tenseLabel}"
			else
				label="now"
			fi
		fi
		label="${label:-0s}"
	fi
	echo "$label"
}
