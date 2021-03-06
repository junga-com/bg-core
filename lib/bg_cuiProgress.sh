
import bg_cui.sh  ;$L1;$L2
import bg_ini.sh  ;$L1;$L2

# Library
# bash script progress indicators.
# This bash script library implements a system for scripts to anounce their progress and for it to be displayed or not given the
# environment that the script is running in. This is a core on-demand module meaning that a stub of the progress API is
# unconditionally loaded when /usr/lib/bg_core.sh is sourced and if the script called it, this library will automatically be
# sourced.
#
#
# Separation of Concerns:
# The principle design feature of this system is that the author of low level code does not need to know if the progress data
# generated by the code will be used and how it will be displayed. Those decisions are orthogonal to the production of progress
# data and are determined by the environment that the code is running in. For example, when a user runs a script from a terminal
# a progress bar might be displayed in the terminal but if that same script is invoked from within a GUI application, the progress
# data might be displayed in a feedback window of the application and if its run from inside a daemon, the generation of progress
# the progress data stream might be suppressed alltogether.
#
# The script author should be free to put progress calls anywhere that it might make sense. The only restriction by this system is
# that the script author should try to avoid sending over around 30 updates per second. Too many updates can start to impact performance.
# If the performance of the script is significantly better when ran with progressDisplayType=off, then reduce the number of updates.
# A common technique when iterating with a loop counter 'count' would be ((count++%N)) && progress "..." "$count"
#
#
# Compositable Progress Data:
# Progress data is compositable. Each algorithm that produces progress data, be it top level script code or a script library function
# will typically bracket the algorithm with start and end <subTask> progress calls and then call update progress calls to inform
# how the <subTask> is advancing. When a <subTask> calls a command that creates its own <subTask> the progress data will push another
# layer on the stack to keep track of the new <subTask> independently. Messages sent to the progress data stream include the details
# of the current <subTask> and also the names of the rest of the <subTasks> on the stack.
#
# The <subTask> stack can span nested script invocations and even nested commands written if different langauges so that the
# envirnoment can report on progress regaurdless of what language and framework was used to create the command as long as the
# command produces progress data compatible with the protocol.
#
#
# Progress Drivers:
# When a command produces progress data by calling "progress ..." the first call to progress will load the progress libraries and
# load/start the progress driver which it identifies through the algorithm described below.
#
# The driver sets file descriptor which is where progress messages will be sent, sets the protocol of the message stream to
# either 'structured' or 'passthrough' and optionally creates a process that will read the other end of file descriptor to render
# the messages.
#
# The drivers for stdout and stderr are passive. The progress file descriptor is set directly to stdout or stderr and the protocol
# is set to 'passthrough' so that messages suitable for direct display are written to the stream.
#
# Other drivers like statusline and oneline are active and create a background process to read and render the structured progress
# messages in a particular way.
#
# It also possible for a driver to open a pipe to an existing progress UI for example, an IDE integration could invoke scripts that
# send their progress message stream to an IDE window.
#
#
# Default Driver Determination:
# A script could load a particular driver explicitly with "progressCntr start <drvName> <drvParams>" but it is bad form to do so.
# Instead the driver is loaded on demand the first time a progress call is made. If the script prefers a particular driver, it can
# call "progressCntr setDefaultDriver <drvName> <drvParams>".
#
# The driver to load will be the first of these values that is set.
#    1) progressDisplayType env var if set
#    2) /etc/bg-core.conf[.]progressDisplayType config file setting if set
#    3) _progressDefaultDriver if set (which is set if the script calls "progressCntr setDefaultDriver <drvName> <drvParams")
#    4) "statusline" if the process has a tty
#    5) "null" as a last resort
#
# When a driver is set in a variable or config file setting, it has the following format..
#     <drvName>[:<drvParams...>]
# <drvName> can be any of the builtin names (off,null,stdout,stderr,file,bgtrace) or the name of a plugin. Two plugin drivers are
#     included statusline and oneline. To implement a new driver, install a script library named bg_progress<DrvName>.sh
# <drvParams...> is passed to the driver's constructor (aka 'start' case). Whitespace separates individual arguments that will be
#     passed to the constructor so any argument the contains whitespace must escape it as described in man(3) escapeTokens.
#
#
# Progress Template:
# The progress template determines how progress messages are formatted for display. The template can be specified in the user's
# environment by setting the progressTemplate variable. A driver can specify its prefered template which will only be used if
# progressTemplate is not set. If neither are set the default template is "plain".
#
# The value of progressTemplate can be set to several names or can be an actual template expanded against the progress meassage fields.
#    'plain'   : (terse) [<parentSubTasks>/]<subTask>:<updateMsg>
#    'detailed': (more vebose) <deltaTime> <-s|-u|-e> [<parentSubTasks>/]<subTask>:<updateMsg>
#    <templateSyntax> : 2020-11 this is not yet implemented
#
# Passthrough Progress Stream Protocol:
# When a driver sets the progress protocol to "passthrough", rendered messages suitable for direct display are sent to the progress
# file descriptor. The format of the message is determined by the progress template.
#
# This protocol is meant to support dumb display destinations like stdout and stderr that have no inteligence to interpret and render
# the progress data, but instead simply displays or stores what is sent to them. In practice, these are used to analize what a command
# is doing since it leaves a history like an executation trace that can be examined after the run.
#
#
# Structured Progress Stream Protocol:
# The structured protocol sends messages that can contain progress updates or other directives to the progress UI on the other end
# of the stream.
#
# Each message is terminated by a linefeed and contains a variable number of whitespace seaparated arguments.
#    <cmd> [<p1>..<pN>]\n
#
# All arguments are escaped according to man(3) escapeTokens so that the receiver can delimit them on whitespace.
#
# <cmd>
#     @1  : structured progress message
#       "@1 <scopeID> <formattedMsg> <subTaskStack> <subTask> <msg> <startTime> <prevTime> <currentTime> <target> <current>"
#     @end : terminate the UI process and close the connection
#     @hide : temporaily hide the UI
#     @show : undo the @hide function
#
#
# The Progress Stack:
# This section describes what originally was called "progressScope" but is starting to be called progress stack.
# NOTE: this section is a work in progress.
#
# A progress stack is a stack of nested tasks/subTask.
#
# The core idea is that all synchronous subshells can reuse the same progressScope to track the cumulative progress because there
# is one synchrous thread of actions that progress. Those actions may consist of sub parts which can be displayed as a hierarchy
# but each sub part has to finish before the parent part proceeds so its still one synchronous progression.
#
# An asynchronous sub task, however progreses in a different thread that proceeds in parallel to other subTasks and the parent.
# Each asynchronous subTask branches the pro
#
# SubTask Progress Fields
#    <taskName>        : a short name to identify the task. This is the name set with the progress -s <name> ... call.
#    <progressMsg>     : the string describing what is happenning right after the progress call
#    <startTimeStamp>  : the start of the task (when progress -s was called)
#    <lastTimeStamp>   : the timestamp from the pevious message in this task
#    <currentTimeStamp>: the timestamp when the progress call that created this message was called
#    <target>          : the target integer count that this task is expected to count up to
#    <current>         : the current integer count that is progressing towards target.
#
# Known Drivers:
#    stdout : send progress messages to stdout, the same as echo would
#    stderr : send progress messages to stderr, the same as echo >&2 would
#    null   : suppress progress messages. The progressStack(s) are still maintained but are not sent anywhere.
#    oneline: display each progress message from a process to one consistent line that may scroll up the terminal.
#             The line is tracked so if the script writes to the terminal and the line scrolls up it will still be updated.
#             If the script uses asynchronous subtasks which create different progress stack, a new line will be written for each
#             new progress stack encountered and each will be tracked in the terminal and updated separately.
#    statusline:
#             The statusline driver reserves a line at the bottom of the screen for each progressStack its asked to display.
#             The scroll region of the terminal is set so that the status line(s) at the bottom will not scroll as output is written
#             to the terminal. When the command ends, the status line(s) are cleared.
#    file:<filename> : send progress messages to <filename>
#    bgtrace : send progress messages to the configured bgtrace destination
#    termTitle : change the termianl title to reflect the progress
#
# TODO: add a gnome notify driver to show feedback in the popup windows that gnome uses
#
# Environment:
#    progressDisplayType : <drvName>[:<drvData...>] : determines how progress is displayed. see man(7) bg_cuiProgress
#                        <drvName> = (statusline|oneline|stderr|stdout|null|off|<plugableDriverName>)
#                        new drivers can be supported by installing a bash script library named bg_progress<plugableDriverName>.sh
#    /etc/bg-core.conf[.]progressDisplayType : specify the progressDisplayType ENV variable in a persistent config





# usage: (start)  progress -s [--async] <subTask> [<initialProgMsg>] [<target> [<current>] ]
# usage: (update) progress [-u] <progUpdateMsg> [<current>]
# usage: (end)    progress -e <subTask> [<resultMsg>]
# The progress function can be used in any function to indicate its progress in completing an operation.
# Its safe to use it in any function regardless of whether the author expects it to be used in an environment
# with user feedback or not. The progress call indicates what the algorithm is doing without dictating how or
# or even if it is displayed to the user.
#
# The typical usage is to put a call to progress -s <subTask> (start) at the top of a function, progress -e <subTask> (end)
# at the botton, and optionally one or more progress -u (update) in the middle to indicate how that algorithm is advancing.
#
# Avoid generating an excessive rate of progress updates. Circa 2020-11, under 30/sec is no problem and probably 100/sec is fine.
# Beyond that, the progress data will start to make the scipt take longer to run.
#
# Options:
#    -s|--start [--async]  : start a sub-task under the current task
#      --async: signal that this start call should start its own progress stack frame. Typically this is done when you spawn
#               a new thread.
#    -u|--update : update the state of the current task
#    -e|--end    : end the current sub-task and pop back to the previous
# Params:
#    <subTask>: a name is used to identify the a sub-task. It is a single word, no spaces. It should be short and reasonably mnemonic.
#               <subTask> are nestable. A any point a progress message has a stack of <subTasks> that represent where the command is
#    <*Msg>   : quoted, one line of text that describes the current operation. It typically should describe the
#               operation that will start after the progress call so that it will be displayed while that operation
#               progresses. In some forms of progress UI the <msg> sent to the start and end calls will be displayed for such a
#               short time that the user will not see them, but they are still important b/c in other forms they provide important
#               information that can be examined by the user.
#   <target>  : in the start call, you can optionally provide an integer <target> value which is the expected value that updates
#               will count up to. This allows some progress UIs to display a progress meter.
#   <current> : when target was specified in start <current> is the integer value that represents the algorithm's progression to
#               that target. (current / target *100) is the percentage of <subTask> that is complete.
# Environment:
#     progressDisplayType : the display driver and parameters to use if the progress system is started implicitly
#     progressTemplate : the template to use to format the rendered progress msg
#     progressScope : the current state of progresssion including all active parent <subTasks> and the current <subTask>
#                     The structure of this variable's value depends on which CntxImpl is loaded. See man(3) progressCntr
#     progressFSync : if set to any non-empty string, this causes 'sync' command to be invoked before and after each progress
#                     message is written. This can adversely impact performance but can lead to a better output if the progress
#                     output destination is shared with other processes.
# BGENV: progressDisplayType: statusline|oneline|stderr|stdout|null|off|<plugableDriverName>: overrride a script's default progress type 
function progress()
{
	# 2016-06 bobg. by short circuiting this the off case at the top of this function, running 350 unit
	# tests went from 22sec(using oneline) to 20sec(using null w/o short circuit) to 16sec(short circuit)
	# 2022-03 bobg: I did not update comments after a pretty big refactor. The shortcircuit mechanism is now that there is a
	#               progress() stub function in bg_coreLibMisc.sh that loads this library only if progressDisplayType is not set
	#               to (none|null|off), but its not really needed anymore because now there is plugable progress stack
	#               implementations and the default Array impl is about as fast as the short circuit.
	#                      305 testcases:
	#                         short circuit: ~ 2m46s
	#                         Array stack  : ~ 2m47s
	#                         file stack   : ~ 3m05s
	#               The Array stack can not update the parent's status automatically but thats OK for many scenarios.

	# if progress is being called for the first time and the script has not set a specific progress driver,
	# set the default driver now
	declare -gAx _progressDriver
	declare -gx progressScope
	[ ! "$_progressDriver" ] && progressCntr start default

	# likewise, if there is not yet a stack driver loaded, load the default now
	type -t _progressStackInit &>/dev/null || progressCntr loadCntxImpl default

	# this is probably not needed since the progress() stub wont even load this library if its set to (off|null|none)
	[ "$_progressDriver" == "off" ] && return 0

	# -u is the default command
	local cmd="-u"  asyncFlag
	while [ $# -gt 0 ]; do case $1 in
		--async) asyncFlag="--async" ;;
		-*) cmd="$1" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# there will be one progressScope for the whole script unless the script spawns a background task setting the progressScope=""
	# for the new task. Each progressScope is a separate thread of execution so the progress has to be kept separate.
	# TODO: automatically detect when we need a new progressScope
	#       1. keep track of the PID and PPID for each progress call in the subTask stack of the current progressScope
	#       2. if we see a progress call from a second sibling, create a new progressScope
	#       3. if we see a progress call from a parent while a child is still open, create a new progressScope
	if [ ! "$progressScope" ] || { [ "$cmd" == "-s" ] && [ "$asyncFlag" ]; }; then
		_progressStackInit
	fi

	assertNotEmpty progressScope

	local -a data
	local indent=0
	case $cmd in
		-s)
			local subTask="$1"
			local msg="$2"
			local target="$3"
			local current="$4"
			[ "$target" ] && current="${current:-0}"
			data[1]="$subTask"
			data[2]="$msg"
			data[3]=$(date +"%s%N")  # task start time
			data[4]=${data[3]}       # task lapTimeStamp
			data[5]=${data[3]}       # task currentTimeStamp
			data[6]="${target}"      # target count
			data[7]="${current}"     # current count
			data[8]="$$"             # script PID
			data[9]="$BASHPID"       # subShell PID
			_progressStackPush data
			indent=${data[0]//[^\/]}; indent=$((${#indent}+1))
			;;

		-u)
			local msg="$1"
			local current="$2"
			_progressStackUpdate data "$msg" "$current"
			indent=${data[0]//[^\/]}; indent=$((${#indent}+1))

			# if updates are coming in fast, throttle them to about 20 per sec
			# 50100100==0.05sec (1/20th sec)
			if (( (${data[5]} - ${data[4]}) < 50100100 )); then
				# the first couple we display because it might be an -u imediately following a -s
				# we also display every 20th update so that the feedback is not starved for ever
			 	if ((_progSkipCounter++ > 3 && _progSkipCounter%20!=0)); then
					return 0
				fi
			else
				_progSkipCounter=0
			fi
			;;

		-e)
			local subTask="$1"; shift
			local msg="$1"; shift

			_progressStackPop data
			[ "$subTask" != "${data[1]}" ] && assertError -v subTask -v data "missmatched calls to progress start(-s) and end(-e)"

			data[2]="$msg"
			data[4]=${data[5]}
			data[5]=$(date +"%s%N")
			data[7]=${data[6]} # current now equals target

			indent=${data[0]//[^\/]}; indent=$((${#indent}))

			if [ "$asyncFlag" ]; then
				if [ "${_progressDriver["userFeedbackFD"]}" ] && [ -w "/dev/fd/${_progressDriver["userFeedbackFD"]}" ]; then
					local pipeError
					[ "${progressFSync:-${_progressDriver["fsync"]}}" ] && sync
					bgTrapStack push PIPE 'pipeError="1"'
					echo "@scopeEnd $progressScope" >&${_progressDriver["userFeedbackFD"]} 2>/dev/null
					bgTrapStack pop PIPE
					[ "$pipeError" ] && { progressCntr off; bgtrace "progress pipe write failed. turning progress system off"; }
					[ "${progressFSync:-${_progressDriver["fsync"]}}" ] && sync
				fi
				return 0
			fi
			;;

		-h) progressCntr hide
			return
			;;

		-g) _progressStackGet data
			(IFS=$'\n'; echo "${data[@]}")
			return 0
			;;
	esac

	# note that we don't always send the complete, detailed and structured data to the progress UI
	# b/c we want to support plain stdout and stderr and other simple 'log' destinations. Those things
	# have no inteligence to understand the content so the 'plain' and 'unstructured' types will format
	# the state in a reasonable way.
	local str=""
	case ${progressTemplate:-${_progressDriver["template"]:-plain}} in
		plain) str="${data[0]}:${data[2]}" ;;
		detailed)
			local cmpTime=${data[3]//--/0}
			[ $cmd == "-u" ] && cmpTime=${data[4]//--/0}
			data[5]=${data[5]//--/0}
			local spaces=$(printf "%*s" $((indent*3)) "")
			local timeDelta=$(( ${data[5]:-0} - ${cmpTime:-0} ))
			str="$(bgNanoToSec "$timeDelta" 3) $spaces $cmd ${data[0]}:${data[2]} "
			;;
	esac

	if [ "${_progressDriver["protocol"]}" == "structured" ]; then
		escapeTokens str data[0] data[1] data[2] data[6] data[7]
		str="@1 $progressScope $str $cmd ${data[*]}"
	fi

	# its ok if we do not write anything because the driver could have been turned off or in the process
	# of exiting
	if [ "${_progressDriver["userFeedbackFD"]}" ] && [ -w "/dev/fd/${_progressDriver["userFeedbackFD"]}" ]; then
		# 2019-09-17 bobg: When ${_progressDriver["userFeedbackFD"]} is a PIPE, If there are no readers on it, then this write will raise a SIGPIPE signal
		# the default SIGPIPE handler will exit the process. This will happen if the driver coproc exits prematurely. I wonder if
		# it will also happen in the time when the driver is processing the command so maybe we need to indicate if ${_progressDriver["userFeedbackFD"]}
		# is a PIPE and if so, make the protocol send a response to syncronize this message passing.
		#
		# SIGPIPE's purpose is to make the default action of writing to a broken PIPE to exit the process. This makes *nix command
		# piplines more reliable.We can turn that off by trapping SIGPIPE but a low level library should not change the default
		# for the script which might be pipable and rely on that behavior.  If this continues to be a problem we could set the trap
		# just around this call with bgTrapStack
		# 2020-11 added PIPE trap and progressCntr off. We need to redirect stderr to null b/c PIPE error will write an error
		local pipeError
		[ "${progressFSync:-${_progressDriver["fsync"]}}" ] && sync
		bgTrapStack push PIPE 'pipeError="1"'
		echo "$str" >&${_progressDriver["userFeedbackFD"]} 2>/dev/null
		bgTrapStack pop PIPE
		[ "$pipeError" ] && { progressCntr off; bgtrace "progress pipe write failed. turning progress system off"; }
		[ "${progressFSync:-${_progressDriver["fsync"]}}" ] && sync
	fi
	return 0
}

# usage: progressCntr <cmd> [<p1>..<pN>]
# usage: progressCntr setDefaultDriver <drvName> [<p1>..<pN>]
#        progressCntr off
#        progressCntr @hide
#        progressCntr @show
#        progressCntr loadCntxImpl TmpFile|Array|<other>
#        progressCntr setDefaultTemplate <template>
#        progressCntr setTemplate <template>
#        progressCntr @drvCmd [<p1>..<pN>]
# This function allows a script to interact with the progress feedback mechanism. Commands that start with '@' are sent to the active
# driver to process. Each driver may or may not support a particular @drvCmd so when a script invokes driver commands, it should be
# regarded as a hint of something that may or may not be acted on.
function progressCntr()
{
	declare -gAx _progressDriver

	local cmd="$1"

	case $cmd in
		start)
			shift
			_progressStartDriver "$@"
			return
			;;

		stop|off)
			_progressStartDriver off
			;;

		setDefaultDriver)
			_progressDefaultDriver="$2"
			;;

		setTemplate)
			progressTemplate="$2"
			;;

		setDefaultTemplate)
			progressTemplate="${progressTemplate:-$2}"
			;;

		loadCntxImpl)
			# importing this replaces the _progressStack* functions with a different implementation
			local implName="$2"
			[[ "$implName" =~ ^(default|)$ ]] && implName="Array"
			#implName="TmpFile"
			import bg_progressCntxImpl${implName}.sh ;$L1;$L2
			;;

		exit)
			[ "${_progressDriver["driverFn"]}" ] && ${_progressDriver["driverFn"]} "end"
			;;



		@*)	# its fine if the active feedback driver does not have a control function registered because some
			# like stdin, stderr, null are simple an have no controlls
			local driverFn="${_progressDriver["driverFn"]}"
			[ "$driverFn" ] && $driverFn "$@"
			;;

		*) assertError -v cmd "unknown cmd"
	esac
}





# this global array is a registry for progressDisplayType drivers.
# progressTypeRegistry[<typeName>]="<driverFunctionName>"
declare -gA progressTypeRegistry
declare -gx _progressDefaultDriver


# usage: _progressStartDriver <drvName> [<drvParams>]
# This starts the specified driver so that subsequent progress messages will be handled by it. The main responsibility of the driver
# is to set _progressDriver["userFeedbackFD"] to the file descriptor where progress messages are sent and _progressDriver["protocol"]
# that determines whether only the rendered msg should be sent or the full structured data of the message should be sent.
#
# Output:
# This function will set the global _progressDriver associative array variable to reflect the active driver. The progress function
# uses the values contained in _progressDriver to determine how to process the progress msg. Several keys in that map (aka
# associative array) are set by this function and others are set by the driver's 'start' case.
#    _progressDriver[0] : is set to the <drvName> or 'off' if the driver fails to start. Note that [0] is the default key in bash
#                         which is used when the array variable is refernced as a scalar variable. e.g. echo "$_progressDriver"
#    _progressDriver["driverFn"] : is set to the name of the function that is used to communicate with the driver. The progressCntr
#                         function will invoke this function with various commands which the driver acts on.
#
# The driver's start function is responsible for setting the other keys in _progressDriver associative array variable to reflect
# the driver's state. Only _progressDriver["userFeedbackFD"] is mandatory.
#      _progressDriver["userFeedbackFD"] : is the numeric file descriptor of the stream where progress msg will be sent.
#      _progressDriver["protocol"]  : structured|passThrough. (default:passThrough) The protocol that the driver expects the msgs
#                                     to be written with.
#      _progressDriver["fsync"]     : if set, 'sync' will be called before and after each progress msg write (typically not set)
#      _progressDriver["template"]  : (default:plain). if the driver has a prefered template. The progressTemplate env variable overrides this.
#
# Params:
#   <drvName>      : The name of the driver that will handle progress messages. It can be set to "default" or left unspecified to use the
#                    default driver
#    <drvParams...> : parameters sent to the driverFn's 'start' case. These are driver specific. If a parameter contains whitespace
#                    it must be escaped. See man(3) unescapeTokens for escaping protocol.
function _progressStartDriver()
{
	declare -gAx _progressDriver

	# if a previous driver is active, stop it
	[ "${_progressDriver["driverFn"]}" ] && ${_progressDriver["driverFn"]} stop
	_progressDriver=()

	local type="${1:-default}"; shift

	# if a driver was not explicitly specified, determine the default driver from the environment
	if [ "$type" == "default" ] || [ ! "$type" ]; then
		[ $# -eq 0 ] || assertError -v "cmdline:default $*" "driver parameters can not be specified for the default driver"
		if [ "$progressDisplayType" ]; then
			type="$progressDisplayType"
		else
			type="$(getIniParam /etc/bg-core.conf . progressDisplayType)"
		fi

		if [ "$type" == "default" ] || [ ! "$type" ]; then
			# in a deamon, the default is to not display any progress UI
			if ! cuiHasControllingTerminal; then
				type="null"
			else
				type="${_progressDefaultDriver:-statusline}"
			fi
		fi

		if [[ "$type" =~ : ]]; then
			local drvParams
			stringSplit -d: "$type" type drvParams
			drvParams=($drvParams); arrayFromBashTokens drvParams
			set -- "${drvParams[@]}"
		fi
	fi

	# the default protocol is passThru. The driver may change it.
	_progressDriver["protocol"]="passThru"

	case $type in
		off)
			_progressDriver="$type"
			;;

		null)
			_progressDriver="$type"
			exec {_progressDriver["userFeedbackFD"]}>/dev/null
			;;

		stdout)
			_progressDriver="$type"
			_progressDriver["userFeedbackFD"]="1"
			_progressDriver["fsync"]="true"
			;;

		stderr)
			_progressDriver="$type"
			_progressDriver["userFeedbackFD"]="2"
			_progressDriver["fsync"]="true"
			;;

		file)
			_progressDriver="$type"
			exec {_progressDriver["userFeedbackFD"]}>"$1"
			;;

		bgtrace)
			_progressDriver="$type"
			exec {_progressDriver["userFeedbackFD"]}>"$_bgtraceFile"
			;;

		# plugable drivers...
		*)
			local driverFn="${progressTypeRegistry[$type]}"

			# try loading it from an external library
			if [ ! "$driverFn" ]; then
				import -q bg_progress${type^}.sh ;$L1;$L2 || bgtraceVars -l"notFound" L1 L2
				driverFn="${progressTypeRegistry[$type]}"
			fi

			[ ! "$driverFn" ] && assertError -v "progressDriver:$type" "unknown cui progress UI driver"

			# start the driver
			if $driverFn start; then
				_progressDriver="$type"
				_progressDriver["driverFn"]="$driverFn"
			else
				# if the driver failed to start set the driver to 'off' so that the next call will not go through the same process
				# to try to start it. A common scenario is that there is no controlling terminal because the code is exectuting
				# inside a daemon.
				_progressDriver=()  # in case the failed start attempt left some keys set.
				_progressDriver="off"
				bgtrace "failed to start cui progress UI driver '$type' Setting the progress driver to 'off'"
			fi
			;;
	esac

	# if the newly started driver has a driverFn, then register an EXIT trap so that it's stop case will be invoked
	# otherwise remove the EXIT trap which may or may not be set from the last driver.
	if [ "${_progressDriver["driverFn"]}" ]; then
		bgtrap -n progressCntr 'progressCntr exit' EXIT
	else
		bgtrap -r -n progressCntr EXIT
	fi
}
