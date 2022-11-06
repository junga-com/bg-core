
# Library bg_debugTrace.sh
# This library provides a set of bgtrace* functions that can be used to trace the operation of a script.
# These statements can be used with or without the interactive debugger. Any breakpoint feature of the interactive debugger
# is implemented by inserting a bgtrace* function in the code. The debugger can fixup the code of sourced functions in mode scripts
# bash shell environment.
#
# Script authors can manually add bgtrace* function calls in their scripts. Typically, bgtrace* functions are only added to scripts
# durring a development session and then removed before the script is committed but they can be circumstances when it make sence to
# leave a bgtrace* call in production code. The convention is that temporary calls are not indented with the rest of the code so that
# 1) they stand out visually as not being part of the real code and 2) the regex "^bgtrace" will match all of these statements so
# that they can be identified and removed.
#
#
# .SH ENV variable bgTracingOn:
# When a script sources /usr/lib/bg_core.sh, the value in bgTracingOn and the production mode of the server determines if bgtracing
# will be active and what the output destination will be. This ENV variable is typically maintained by the bg-debugCntr command.
# Programatically, it can be changed wihin a script by calling the bgtraceCntr function although that is not typical. If its value is
# directly changed in a script it will take effect the next time bgtraceIsActive is called. Most bgtrace* functions call bgtraceIsActive
# so setting bgTracingOn directly typically works the same as using bgtraceCntr.
#
# .SH bgtrace:
# bgtrace is the most basic output function. It is like echo that automatically redirects to the bgtracing destination. Often higher
# level bgtrace* functions format output and pass it to this function.
#
# .SH bgtraceVars:
# bgtraceVars is the most common output funciton. It is the basis for the debugger watch window. You give it a list of variable names
# and optional modifiers and it will detect what they are and display their value appropriately. It is implemented as a thin wrapper
# over with the printfVars function which redirects the output to $_bgtraceFile
#
# .SH bgtraceBreak:
# this will stop the script in an interactive debugger, positioned on the following line. If a debugger is not yet active for the
# script, debuggerOn will be called to active one.
#
# .SH Other bgtrace* functions:
# User man bgtrace<tab><tab> to discover other bgtrace functions.
#
# .SH $_bgtraceFile
# _bgtraceFile is a variable that always contains a valid filename that output can be redirected to. When bgtracing is not active
# it contains "/dev/null".  After /usr/lib/bg_core.sh is sourced, any code can always do '<cmd> >>$_bgtraceFile'
#
# See Also:
#    bg-debugCntr : interative interface to control bgtrace* features and other development/debugging features.
#                   for an interactive terminal session
#    bgtrace
#    bgtraceVars
#    bgtraceBreak
#    bgtrace* (any function that starts with bgtrace)

##################################################################################################################
### bgtrace Subsystem State variables

#declare -xg bgTracingOn                moved to bg_libCore.sh
#declare -g _bgtraceFile="/dev/null"    moved to bg_libCore.sh
#declare -g bgTracingOnState=""         moved to bg_libCore.sh




##################################################################################################################
### bgtrace* Subsystem Management Functions

#function bgtraceIsActive()   moved to bg_libCore.sh
#function bgtraceTurnOn()     moved to bg_libCore.sh

# this tells bash to record function arguments in the stack data and source file and line number
# of functions. search for extdebug in man bash
shopt -s extdebug


# usage: bgtraceTurnOff
# turn bgtracing off
function bgtraceTurnOff()
{
	bgtraceCntr "off"
}


# usage: bgtraceCntr isOn|off|on|on:[<filename>]|file:[<filename>]|<filename>
# set the attributes or query state of the bgtrace subsystem.
# Sub Commands:
#    isOn : return 0(true) or 1(false) to indicate whether bgtrace functions are sending their output
#           anywhere
#    off  : set the state to off so that bgtrace functions do not send their output anywhere
#    on[:[<filename>]] : configure to send bgtrace output to <filename>. If the : is included, the default
#           <filename> is /tmp/bgtrace.out but if not, the default is /dev/tty
#    file:<filename> : synonom for on:<filename>
#    <filename> : synonom for on:<filename>
# BGENV: bgTracingOn : controls bgtrace statements. empty string means tracing is off. file:<path> writes traces to <path>. file: or on: writes to default path /tmp/bgtrace.out. anything else mean stderr
# Options:
#     -n : ifNotOnFlag. If tracing is already on, it will leave it going to the current destination file. If not, it will set it to the new, specified tracing file
# See Also:
#   bgtraceIsActive   : (core function) synonom for bgtraceCntr isOn
#   bgtraceTurnOn     : (core function) synonom for bgtraceCntr on:...
function bgtraceCntr()
{
	if [ "$1" == "isOn" ]; then
		bgtraceIsActive
		return
	fi

	while [[ "$1" =~ ^- ]]; do case $1 in
		# in the case of -n, we can asssume that bgtracing is realized and even if its not, it will be the next time a bgtrace* function
		# calls bgtraceIsActive. In either case we ignore the dstination provided, because bgTracingOn contains a destination
		-n) [ "$bgTracingOn" ] && return 0 ;;
	esac; shift; done

	local result=0
	bgTracingOn="${1-$bgTracingOn}"
	if [ "$bgTracingOn" != "$bgTracingOnState" ]; then
		case ${bgTracingOn:-off} in
			off)
				bgTracingOn=""
				_bgtraceFile="/dev/null"
				# if "shopt -s expand_aliases" is active, the alias will be use and is more efficient but
				# if not, the function will be used and its pretty efficient too.
				eval alias bgtrace='#'
				;;
			on|1|tty|file:tty|on:tty)
				_bgtraceFile="/dev/tty"
				;;
			stderr|2|file:stderr|on:stderr)
				_bgtraceFile="/dev/stderr"
				;;
			stdout|file:stdout|on:stdout)
				_bgtraceFile="/dev/stdout"
				;;
			on:win*|win*)
				local win=${bgTracingOn#on:}
				[ "$win" == "win" ] && win="out"
				_bgtraceFile="/tmp/bgtrace.$win"
				if [ ! -e "/tmp/bgtrace.$win.cntr" ]; then
					touch "$_bgtraceFile" || _assertError "file '$_bgtraceFile' can not be used as a trace file because it is not writable"
					type -t cuiWinCntr>/dev/null || import bg_cuiWin.sh ;$L1;$L2
					cuiWinCntr "$win" open >/dev/null || assertError -v win "failed to open cuiWin '$win'"
					cuiWinCntr "$win" tailFile "$_bgtraceFile" || assertError -v win -v _bgtraceFile "failed to tail '$_bgtraceFile' in cuiWin '$win'"
					if [ ! -e "/tmp/bgtrace.$win.cntr" ]; then
						echo "warning: the bgtrace viewer win '$win' could not be openned. bgtrace is being directed to '$_bgtraceFile'" >&2
					fi
				fi
			;;
			on:*|file:*|*)
				_bgtraceFile=${bgTracingOn#file:}
				_bgtraceFile=${_bgtraceFile#on:}
				_bgtraceFile=${_bgtraceFile:-/tmp/bgtrace.out}
				;;
		esac
		# 2022-08 bobg: in 5.1 if anything executed by a DEBUG trap creates a subshell (as the following block does), it will re-enter
		#               the DEBUG trap and leades to infinite recursion so I inhibit this block if the debug trap is active.
		if [ ! "$bgBASH_debugTrapExitCode" ] && [ "$_bgtraceFile" != "/dev/null" ]; then
			eval unalias bgtrace 2>/dev/null

			if [ -w "$_bgtraceFile" ] && ! (echo -n >> "$_bgtraceFile") &>/dev/null; then
				# turn tracing off
				local fileOwner="$(stat -c"%U" "$_bgtraceFile")"
				bgTracingOnState=""
				bgTracingOn=""
				_bgtraceFile="/dev/null"
				eval alias bgtrace='#'

				assertError -v _bgtraceFile -v USER -v fileOwner "
					The _bgtraceFile can not be written to because it is in the /tmp filesystem and owned by a different user.
					There was a kernel change circa 4.19 which made this the default behavior to make it harder to leak information
					from programs by hijacking tmp files.

					If you are working on a single user workstation it is relatively safe to disable that new feature with this command.
					    sudo sysctl fs.protected_regular=0

					An alternative to disabling the feature is to change the location of this terminal's trace file.
					    bg-debugCntr trace on:<pathToFile>

					Here is the information on the trace file and users
				"
			fi
		fi
		bgTracingOnState="$bgTracingOn"
	fi
	return $result
}



##################################################################################################################
### bgtrace* functions
# This section contains functions that produce some bgtrace output.


# usage: bgtrace ...
# use this command like echo to display debugging information for the script
# The advantage over echo are...
#    1) its easy to search for "bgtrace" to remove them when you are done
#    2) the output destination is controlled all together -- turn on/off, direct to a file...
#    3) several forms to format common things .. bgtraceVars, etc...
# It sends its output to the destination specified in the bgTracingOn env variable
# The user can turn these traces on /off and direct them to a file or stderr with the command
#       bg-debugCntr trace on|off|on[:<filename>]
# The default filename (e.g 'on:') is /tmp/bgtrace.out On a multi user server, there could be conflict
# about who owns that file but typically tracing/debugging is not done on multiuser servers.
# bgtrace statements could be left in the scripts if desired. It will always be called but if bgtrace is off,
# it will do nothing. However, its command line will always be processed which is no big deal if its a simple
# string constant but if it includes $(..), they will be called. At some point that may change by using function folding
# See Also:
#    bgtraceVars    : interpret and format a list of variable names
#    bgtraceParams  : show the invocation line of the current function
#    bgtraceLine    : show a code line after bash expansion but before simple cmd invocation
#    bgtraceXTrace  : turn on/off bash set -x tracing only if bgtracing is activated
#    bgtraceStack   : show the logical call stack at that point in the script
#    bgtracePSTree  : show the current proccess tree of the script
#    bgtraceRun     : run a command only if bgtrace system is activated
#    bgtimer*Trace  : create timers in code that send their output to the bgtrace desitination
#    bgtraceCntr    : programatically change the state of the bgtrace system
#    bg-debugCntr   : control the state of the bgtrace system for the interactive bash terminal
function bgtrace()
{
	bgtraceIsActive || return 0

	local includeTimer timerStr
	while ([[ "$1" =~ ^- ]]); do case $1 in
		-t) includeTimer="-t" ;;
	esac; shift; done

	if [ "${bgTracingTimer}${includeTimer}" ]; then
		local deltaTime deltaForks
		bgtimerLapGet -R deltaTime -F deltaForks
		timerStr="$deltaTime ${deltaForks:+$deltaForks }"
	fi

	local msg="$*"
	local indent="${msg%%[^[:space:]]*}"
	local msg="${msg#$indent}"

	echo "${indent}${timerStr}${msg}" >>  "$_bgtraceFile"
}

# usage: bgtracef <fmtStr> [<p1> [..<p2>]]
# just like bgtrace but uses printf instead of echo
function bgtracef()
{
	bgtraceIsActive || return 0

	local includeTimer timerStr
	while [[ "$1" =~ ^- ]]; do case $1 in
		-t) includeTimer="-t" ;;
	esac; shift; done

	if [ "${bgTracingTimer}${includeTimer}" ]; then
		local deltaTime deltaForks
		bgtimerLapGet -R deltaTime -F deltaForks
		timerStr="$deltaTime ${deltaForks:+$deltaForks }"
	fi

	local msg="$1"
	local indent="${msg%%[^[:space:]]*}"
	local msg="${msg#$indent}"

	printf "${indent}${timerStr}${msg}" "${@:1}" >>  "$_bgtraceFile"
}


# usage: bgtraceLine <line of script>
# this is similar to bgtrace but its intended to be placed in front of a script line to output how that cmd
# would have been executed after bash line processing (variable expansion, command susstitution, etc...)
# Typically you would copy a command line (no matter how complex) and then...
#    1) insert bgtraceLine at the start of the line. Dont worry about whitespace.
#    2) if the line contains pipe or redirection chars, you still have to escape them  like \> \| and \<
#       or delete everything after the first pipe or redirection char if you are not interested in them.
#    3) if you don't want to see the final results of a $(....), but rather how it would be ran, escape
#        it by putting a \ in front of the $ like \$(...). Typically $() will be inside quotes. if not you also
#        need to quote the \( and \)
function bgtraceLine()
{
	_cmdSw_bgtrace "$@"
}

# usage: bgtraceVars <data1>|<option> [... <dataN>|<option>]
# this uses bgtrace(f) to show the listed variables with a standard format
# Unlike most function, options can appear anywhere. options only effect the variables after it
# Params:
#   <dataN> : a variable name to print. It formats differently based on what it is
#        not a variable  : simply prints the content of <dataN>
#        simple variable : prints <varName>='<value>'
#        array variable  : prints <varName>[]
#                                 <varName>[idx1]='<value>'
#                                 ...
#                                 <varName>[idxN]='<value>'
#        object ref      : calls the bgtrace -m -s method on the object
# Options:
#   -w : set the width of the variable name field. this can be used to align a group of variables.
#   -1 : display vars on one line. this supresses the \n after each var output
#   +1 : display vars on multiple lines. this is the default. it undoes the -1 effect
#   "" : write a blank line. this is used to make vertical whitespace. with -1 you can use this
#        to specify where line breaks happen in a list
#   "  " : a string whitespace sets the prefix used on all output. this will indent subsequent vars
function bgtraceVars()
{
	bgtraceIsActive || return 0

	if [ "${bgTracingTimer}${includeTimer}" ]; then
		local deltaTime deltaForks
		bgtimerLapGet -R deltaTime -F deltaForks
		timerStr="$deltaTime ${deltaForks:+$deltaForks }"
		printf "$timerStr" >>$_bgtraceFile
	fi

	printfVars "$@" >>$_bgtraceFile || echo "could not write to '$_bgtraceFile' with user '$USER'"
}

# usage: bgtraceParams <token1> [... <tokenN>]
# usage: bgtraceParams
# This formats the input so that you can see where bash separates tokens. Typically useful at the start of a function
# If no tokens are given, the default is to use the current function's command line.
function bgtraceParams()
{
	bgtraceIsActive || return 0

	if [ "${bgTracingTimer}${includeTimer}" ]; then
		local deltaTime deltaForks
		bgtimerLapGet -R deltaTime -F deltaForks
		timerStr="$deltaTime ${deltaForks:+$deltaForks }"
		printf "$timerStr" >>$_bgtraceFile
	fi

	# this is the typical case where the caller did not pass anything in so we glean the function name and arguments
	if [ $# -eq 0 ]; then
		local objInfo; [[ "${FUNCNAME[1]}" =~ :: ]] && objInfo="${_this[_OID]}."
		printf "starting: %s%s "  "${objInfo}" "${FUNCNAME[1]}" >>$_bgtraceFile
		local i; for ((i=${BASH_ARGC[1]:-0}; i>0; i--)); do
			printf "'%s' " "${BASH_ARGV[$((i-1))]}" >>$_bgtraceFile
		done
		printf "\n" >>$_bgtraceFile
		return
	fi

	local p; for p in "$@"; do
		printf "'%s' " "$p" >>$_bgtraceFile
	done
	printf "\n" >>$_bgtraceFile
}

# usage: bgtraceStack
# print the current stack trace to bgtrace destination
# it is called by  assertError
function bgtraceStack()
{
	bgtraceIsActive || return 0
	bgStackPrint "$@" >>$_bgtraceFile
}


# usage: bgtracePSTree
# print process tree of the script at this point
# this is used by assertError to gather information when bgtracing is on
function bgtracePSTree()
{
	bgtraceIsActive || return 0
	bgGetPSTree "$@" >>$_bgtraceFile
}


# usage: $objRef.bgtrace [-r] [-h] [-a] [-m] [-s] [-l<level>]
# This adds a method to the Object Class (the base of all objects so this method is available in all
# objects) for debugging purposes.
# It prints all the attributes and methods that the object reference contains. A class can overrde
# this method to print information in a way specific to the class and then optionally call the object
# version to display this information
# Options:
#    Note that 'toggle' options can be given multiple times. This facilitates a default and then reversing the default
#    -r  : toggle recurse flag. recurse means descend into Object member attributes to show their state too.
#    --rlevel <N> : recurse this number of levels and then stop
#    -h  : toggle the display of header lines
#    -a  : toggle the display of member attributes
#    -m  : toggle the display of methods
#    -s  : toggle the display of system attributes (those starting with _)
#    -l<level> : indent this amount. used when descending member Objects
function Object::bgtrace()
{
	bgtraceIsActive || return 0

	local level=0 rlevel=100 recurseFlag="-r" attribsOff="" methodsOff="" sysAttrOff="" headersOff=""
	while [ $# -gt 0 ]; do case $1 in
		-l*) bgOptionGetOpt val: level "$@" && shift ;;
		-r)  varToggleRef recurseFlag "-r"  ;;
		--rlevel*) bgOptionGetOpt val: rlevel "$@" && shift
			# setting rlevel on the initial call implies that recursion should start on
			[ ${level:-0} -eq 0 ] && recurseFlag="-r"
			;;
		--rstate) recurseFlag="$2"; shift   ;;
		-h)  varToggleRef headersOff "-h"  ;;
		-a)  varToggleRef attribsOff "-a" ;;
		-m)  varToggleRef methodsOff "-m" ;;
		-s)  varToggleRef sysAttrOff "-s" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# if we have reached the recursion level limit, set recurseFlag to off
	[ ${level:-0} -ge ${rlevel:-0} ] && recurseFlag=""

	# $level increases by +1 each recursion but $rlevel keeps it initial value from the first call
	local pad="$(printf %$((${level}*3))s)"

	#[ ! "$headersOff" ] && bgtrace "${pad}$_CLASS::$_OID :"
	echo "${pad}$_CLASS::$_OID :" >>$_bgtraceFile

	if [ ! "$attribsOff" ]; then
		[ ! "$headersOff" ] && echo "${pad}  ### Attributes " >>$_bgtraceFile
		local i; for i in "${!this[@]}"; do
			if [[ ! "$i" =~ ^((_)|(0$)) ]]; then
				printf "${pad}   %-18s : %s" "$i" "${this[$i]}" | awk 'NR>1{printf("'"${pad}"'   %-18s  +", "")}  {print $0}' >>$_bgtraceFile
				if [ "$recurseFlag" ] && IsAnObjRef ${this[$i]}; then
					${this[$i]}.bgtrace -l$((level+1)) --rlevel "$rlevel" --rstate "$recurseFlag" -m -s -h "$@"
				fi
			fi
		done
	fi

	[ "$1" == "dataOnly" ] && return

	if [ ! "$methodsOff" ]; then
		[ ! "$headersOff" ] && echo "${pad}  ### Methods " >>$_bgtraceFile
		local i; for i in "${!this[@]}"; do
			if [ "${i:0:9}" == "_method::" ]; then
				printf "${pad}   %-21s : %s\n" "$i" "${this[$i]}" >>$_bgtraceFile
			fi
		done
	fi

	if [ ! "$sysAttrOff" ]; then
		[ ! "$headersOff" ] && echo "${pad}  ### System Attributes " >>$_bgtraceFile
		local i; for i in "${!this[@]}"; do
			if [[ "$i" =~ ^((0)|(_)) ]] && [ "${i:0:9}" != "_method::" ]; then
				printf "${pad}   %-18s : %s" "$i" "${this[$i]}" | awk 'NR>1{printf("'"${pad}"'   %-18s  +", "")}  {print $0}' >>$_bgtraceFile
				if [ "$recurseFlag" ] && IsAnObjRef ${this[$i]} && [ "$i" != "_Ref" ] && [ "$i" != "0" ] ; then
					${this[$i]}.bgtrace -l$((level+1)) --rlevel "$rlevel" --rstate "$recurseFlag" -m -s -h "$@"
				fi
			fi
		done
	fi
}


##################################################################################################################
### misc functions



# usage: bgtraceBreak [--defaultDbgID <defaultDbgID>] [<contextData> ..]
# Invoke the interactive debugger at this point in the script.  It results in the DEBUG trap being set with a condition that will
# result in the debugger stopping on the script line that immediately follows the bgtraceBreak call. That can be adjusted with the
# --logicalFrameStart option.
#
# The advantage of placing bgtraceBreak calls in your script over stepping through the script from the beginning is performance.
# while the debugger is inactive or in 'resume' mode, the script operates at full speed until it stops at a bgtraceBreak call. Also,
# stepping to a specific low level library function may be tedious to get exactly right, knowing what to step over and what to step
# into. On the other hand, its quick and easy to put a bgtraceBreak call in that function and just run the script. Each time resume
# is executed, the script will run at full speed until the next bgtraceBreak is reached.
#
# Invoking the Debugger:
# If the debugger is already running, it will stop in that instance of the debugger. If not, it will invoke the debugger with
# debuggerOn passing in the <defaultDbgID> value if provided. debuggerOn determines the default if <defaultDbgID> is
# not specified.
#
# If bgtracing is turned off with bg-debugCntr, bgtraceBreak will not stop the script.
#
# bgtraceBreak works the same regardless of the bg-debugCntr debugger on/off setting. That setting only determines if the script
# will initially stop in the debugger at its first line.
#
# Manual Use:
# Script authors can temporarily place calls to bgtraceBreak in as section of their script that they are working on. Its a natural
# extention to the bgtraceVars function that allows tracing the values of variables. Its one of multiple bgtrace* functions that
# script authors can employ while developing and testing that are meant to be removed beofore commiting the script for use.
#
# Integration With Debugger UIs:
# The core debugger implements a method of patching functions so that they include calls to bgtraceBreak tranparently to the operator.
# A debugger UI can use that to implement interactive breakpoints in the debugger.
#
# The contextData mechanism is meant for use with Debugger UIs. Particular contextData can be included when the breakpoint is set
# and then when the dubugger is invoked from that breakpoint the UI can examine contextData and decide whether to keep going or
# invoke the interactive UI.
#
# For example, a debugger UI could set the context "onVariableChange <varName>" and then when the debugger invokes the UI as a result
# of that breakpoint, it can resume without user interaction if <varName> has not changed.
#
# Params:
#    <contextData> ..    : if any command line parameters are provided, they are made available to the debugger process to use as
#                          it sees fit. A debugger UI can use this when it dynamically inserts bgtraceBreak commands in the code to
#                          implement various types of breakPoints.
# Options:
#    --inBashSource      : attach to gdb to $BASHPID to step through bash code. After gdb is attached, it will continue to run until
#                          the C function that invoked the bgtraceBreak bash cmd is at the bottom (aka newest) of the stack. The user
#                          can then step out of that function and into the execution of the following bash cmd which will be the
#                          script line following the call to bgtraceBreak. The bash script debugger will also be invoked if it is
#                          not already and it will stop in the DEBUG trap that precedes that next bash cmd so the gdb debug session
#                          could step into the running of the DEBUG trap that is part of the bash script debugger.
#                          Note: Initially (circa 2022-10) this is only supportted when using the atom front end debugger driver.
#                          To be useful, the bash executable that the script is running in should have debugging symbols available
#                          in a way that gdb can find them. Typically that means building from the bash source with
#                          'make CFLAGS="-g -O0" clean all'. You can clone and build the bash source anywhere on your host since
#                          the debug symbols will contain the absolute path to the source files it built from.
#                          Once you have a suitable bash executable file, 'bg-debugCntr vinstall devBash <pathToAlternateBash>' can
#                          be used to run the alternate bash in that vinstalled environment and all subsequent bash invocations from
#                          that terminal.
#    --inBashSourceNoStep: similar to --inBashSource except that it leaves gdb stopped at the earliest location after attaching.
#                          In practice, only try this if --inBashSource is having problems.
#                          Whereas --inBashSource will try to leave the user stopped at the last moment before this call to
#                          bgtraceBreak returns, this command will stop somewhere deep in the implementation of this command right
#                          after it request the gdb debugger to attach. This can be 10's to 100's of C functions deep that the user
#                          will have to step out through until getting to the point after this bgtraceBreak.
#    --skipCount=<n>     : don't break until <n> times the code passes it.
#    --logicalStart+<n>  : this adjusts where the debugger should stop in the script. By default it will stop at the line of code
#                          immediately following the bgtraceBreak call. However, if bgtraceBreak is called in another library function
#                          it might not want to stop inside that function but instead at the line following whatever called it.
#                          <n> represents the number of functions to skip. +1 means go up one function from where bgtraceBreak is
#                          called.
#    --defaultDbgID <id> : only in the case that the debugger is not yet active, this will be passed to debuggerOn. See debuggerOn.
# See Also:
#     bg-debugCntr : the cmd line command to control the interactive debug environment.
#     debuggerOn   : if a debugger is not already active for this process, it deferes to this
#     _debugSetTrap : if a debugger active for this process, it deferes to this
#     _debugEnterDebugger : the lower level break (called by DEBUGTrap) which actually initiates the debugger. bgtraceBreak installs the DEBUG trap
function bgtraceBreak()
{
	[ "$bgDevModeUnsecureAllowed" ] || return 35

	# protect against infinite recursion if a user puts a breakpoint in a function that this function indirectly uses
	[ "$bgtraceBreakRecursionTest" ] && return; local bgtraceBreakRecursionTest="1"

	local logicalFrameStart=1 breakContext defaultDbgID skipCount inBashSourceFlag
	while [ $# -gt 0 ]; do case $1 in
		--inBashSource)        inBashSourceFlag="--inBashSource" ;;
		--inBashSourceNoStep)  inBashSourceFlag="--inBashSourceNoStep" ;;
		--plumbing)      bgDebuggerStepIntoPlumbing="1" ;;
		--skipCount*)    bgOptionGetOpt val: skipCount "$@" && shift ;;
		--defaultDbgID*) bgOptionGetOpt val: defaultDbgID "$@" && shift ;;
		--context*) bgOptionGetOpt val: breakContext "$@" && shift ;;
		--logicalStart*) ((logicalFrameStart= 1 + ${1#--logicalStart?})) ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# when bgtracing is not active, bgtraceBreak is a noop just like all other bgtrace* functions. This allows the user to temporarily
	# run the script in production mode in the middle of a debugging session.
	bgtraceIsActive || return 0

	if [ "$skipCount" ]; then
		local breakPointID="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}"

		declare -gA bgtraceBreak_skipCounts

		if [ ! "${bgtraceBreak_skipCounts[$breakPointID]+exists}" ]; then
			bgtraceBreak_skipCounts[$breakPointID]=$(( skipCount ))
			return
		elif [ ${bgtraceBreak_skipCounts[$breakPointID]:-0} -gt 0 ]; then
			bgtraceBreak_skipCounts[$breakPointID]=$(( ${bgtraceBreak_skipCounts[$breakPointID]} - 1 ))
			bgtraceVars -1 bgtraceBreak_skipCounts[$breakPointID]
			(( ${bgtraceBreak_skipCounts[$breakPointID]:-0} > 0 )) && return
		fi
	fi

	# the debugger library is dynamically loaded on demand
	[ ! "$(import --getPath bg_debugger.sh)" ] && assertError "the debugger is not installed. Try installing the bg-dev package"
	type -t debuggerOn &>/dev/null || { import bg_debugger.sh ;$L1;$L2; }

	# stepOver is typically the only reasonable option to call because it goes to the next line at the level maintained by the
	# logicalFrameStart mechanism.
	if debuggerIsActive; then
		_debugSetTrap --logicalStart+${logicalFrameStart:-1} stepOver
	else
		debuggerOn --logicalStart+${logicalFrameStart:-1} ${defaultDbgID:+--driver="$defaultDbgID"} stepOver
	fi

	if [ "$inBashSourceFlag" == "--inBashSource" ]; then
		# the -1 in the following locationSpec makes it so that after the step to this locationSpec, the last frame on the stack
		# will be the one that is augmented with the 'bgtraceBreak --inBashSource' shell cmd. They will then need to step out of
		# that function to get to the line after the one that invoked 'bgtraceBreak --inBashSource', but it seems worth it to
		# have the reference to better understand where the code is stopped at.
		# At some point we may augment other frames so that the user will understand where they are at without the -1
		debuggerAttachToGdb "frmShFunc:-1 bgtraceBreak"
	elif [ "$inBashSourceFlag" == "--inBashSourceNoStep" ]; then
		debuggerAttachToGdb
	fi
}

# usage: bgtraceXTrace [-f <file>] on|off
# usage: bgtraceXTrace [-f <file>] marker [<label> [<msg>]]
# turn on|off the bash set -x feature only if bgtracing is on
# Params:
#   <file> : the file to write the XTrace log to. default is the _bgtraceFile destination
function bgtraceXTrace()
{
	[ "off" ] && set +x # turn off early to avoid tracing this function
	local file="$_bgtraceFile"
	while [ $# -gt 0 ]; do case $1 in
		-f*|--file*) bgOptionGetOpt val: file "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local cmd="${1:-on}"; [ $# -gt 0 ] && shift
	local traceState="curOff"; [[ "$-" =~ x ]] && traceState="curOn"
	case $cmd:$traceState in
		on:curOff)
			bgtraceIsActive || return 1
			exec {BASH_XTRACEFD}>>$file
			# note: that the first char of PS4 will be repeated to reflect the function depth
			export PS4='+(${BASH_SOURCE##*/}:${LINENO}): ${FUNCNAME[0]:-main}() | '
			set -x
			;;
		off:curOn)
			export PS4=''
			set +x
			exec {BASH_XTRACEFD}>$-
			;;
		marker:*)
			local label="$1"; shift
			local msg="$*"; msg="$msg${msg:+\n}"
			local lineCount="$(gawk '/^lines since last marker/ {lastCount=NR} END{ print NR-lastCount}' "$file")"
			printf "lines since last marker = %-6s -- %s\n" "$lineCount" "$label" >> "$file.markCounts"
			cat >> "$file" <<-EOS


				********************************************* $label ************************************************************
				lines since last marker = $lineCount
				$msg*****************************************************************************************************************

			EOS
			;;
	esac
	return 0
}


# Backtrace () {
#    echo "Backtrace is:"
#    i=0
#    while caller $i
#    do
#       i=$((i+1))
#    done
# }

# usage: bgtraceRun <cmd line...>
# run a command only when bgTracing is enabled
function bgtraceRun()
{
	if [ ! "$bgTracingOn" ]; then
		"$@"
	fi
	return 0
}


##################################################################################################################
### bgtimerTrace -- time and report on sections of scripts conditionally on whether bgtracing is on

# usage: bgtimerStartTrace [-T <timerVar>] [-p <precision>] [<description>]
# same as bgtimerStart but is a noop if bgtrace sub system is not on
# Options:
#   -T* -p* -f : passed through to bgtimerStart.
#   --add-to-bgrace-out : if this is set, every bgtrace* output will start with a
#        lap time which is the time since the last lap time
# See Also:
#    bgtimerStart
function bgtimerStartTrace()
{
	[ ! "$bgTracingOn" ] && return 0
	local passThruOpts
	while [ $# -gt 0 ]; do case $1 in
		--add-to-bgrace-out) bgTracingTimer="on" ;;
		-T*) bgOptionGetOpt  opt: passThruOpts "$@" && shift ;;
		-p*) bgOptionGetOpt  opt: passThruOpts "$@" && shift ;;
		-f)  bgOptionGetOpt  opt  passThruOpts "$@" && shift ;;
		-i)  bgOptionGetOpt  opt  passThruOpts "$@" && shift ;;
		--no-reset) bgOptionGetOpt  opt  passThruOpts "$@" && shift ;;
		*)   bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done

	bgtimerStart "${passThruOpts[@]}" "$@"
}

# usage: bgtimerLapTrace [-T <timerVar>] [-p <precision>] [<description>]
# same as bgtimerLapPrint but uses bgtrace conditional output
function bgtimerLapTrace()
{
	bgtraceIsActive || return 0

	bgtimerLapPrint --bgtrace "$@" >> "$_bgtraceFile"
}


# usage: bgtimerTrace [-T <timerVar>] [-p <precision>] [<description>]
# same as bgtimerPrint but uses bgtrace conditional output
function bgtimerTrace()
{
	bgtraceIsActive || return 0

	bgtimerPrint "$@" >> "$_bgtraceFile"
}


##################################################################################################################
### bglog -- bglog is meant to be a permanent (leave in the code) alternative to bgtrace
# The main difference is that each bglog call is passed a <tag> that can be turned on/off to give the user fine grained control

# TODO: integrated bglog with bg-debugCntr and make a production standing for bg-debugCntr to control log channels
#       1) search code for "bglog <tag> ..." to build a list of all tags (installation should build a file similar to manifest)
#          bg-debugCntr will do it on the fly. in dev mode, if bglog gets a tag that does not already exist in _bglogData, it triggers a rebuild
#       2) make lazy restore the list of tags into the _bglogData assoc array
#       3) change bglogOn to use specs that match the existing keys of _bglogData

declare -gA _bglogData

function bglogOn()
{
	while [ $# -gt 0 ]; do
		_bglogData[$1]="on"
		shift
	done
}

# usage: bglog <tag> <msg> ...
function bglog()
{
	[ "${_bglogData[$1]}" ] || return 0
	local tag="$1"; shift
	printf "%s: %s\n" "$tag" "$*" >> "$_bgtraceFile"
}
