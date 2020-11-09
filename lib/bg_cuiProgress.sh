import bg_cui.sh  ;$L1;$L2
import bg_ini.sh  ;$L1;$L2

# Library
# bash script progress indicators.
# This bash script library implements a system for scripts to anounce their progress and for it to be displayed or not given the
# environment that the script is running in. This is a core on demand module meaning that a stub of the progress API is
# unconditionally loaded when /usr/lib/bg_core.sh is sourced and if the script called it, this library will automatically be
# sourced.
#
# Currently, the main documentation for this pibrary is in the man(3) progress page.


# usage: (start)  progress -s <subTask> [<initialProgMsg>] [<target> [<current>] ]
# usage: (update) progress [-u] <progUpdateMsg> [<current>]
# usage: (end)    progress -e <subTask> [<resultMsg>]
# usage: (hide)   progress -h
# usage: (hide)   progress -g
#
# The progress function can be used in any function to indicate its progress in completing an operation.
# Its safe to use it in any function reguardless of whether the author expects it to be using in an interactive
# or batch script/command. The progress call indicates what the algorithm is doing without dictating how or
# or even if it is displayed to the user. Any function can be decorated with progress calls and if its
# executed in a batch envoronment, they will be close to noops. In interactive environments, the user can
# control if and how the progress messages are displayed by setting the progressDisplayType ENV variable.
# Progress state is kept in per thread/process memory so they work corectly in multi-threaded scripts.
#
# The typical usage is to put a call to progress -s (start scope) at the top of a function, progress -e (end scope)
# at the botton, and optionally one or more progress -u (update) in the middle.
#
# Options:
#    -s : start a sub-task under the current task
#    -u : update the state of the current task
#    -e : end the current sub-task and pop back to the previous
#    -h : hide. hint that the user does not need to see the progress UI anymore.
#    -g : get. get the progress state for the current thread
# Params:
#    <subTask>: id is used to identify the start and end of a sub-task. It is a single word, no spaces. It should
#               be short and reasonably mnemonic.
#    <*Msg>   : quoted, one line of text that describes the current operation. It typically should describe the
#               operation the will start after the progress call so that it will be displayed while that operation
#               progresses. If the start(-s) call is immediately followed by an update(-u) call, the msg can be ommitted.
#               in some forms of progress UI the end msg will display for such a short time that the user will not
#               see it, but its important b/c in other forms -- if the user is seeking more details it will be
#               visible and can provide important diagnostic information.
#   <target>  : in the start call, you can optionally provide an integer value which expect the algorithm
#               calling subsequent update calls will get to. For example if you are entering a loop of 245 iterations
#               and in the loop you call update, you can set target to 245. This optional information allows some
#               progress UI to display a bar/percentage indicator
#   <current> : when target was specified in start, some progress UIs will indecate the percentage complete as
#               (current / target *100). If target was not given some UIs will use this as a progressing counter
#.SH Separation of indicating and displaying progress
# The progress mechanism separates the two independent notions of 1) keeping a progress stack associated with the currently
# running thread and 2) some place to send progress messages.
# This facilitates nice feedback. A potentially long running function can call this to indicate to the user the progress
# and what is happening whether or not the calling application decides to display the progress and how it is displayed.
# The -s and -e forms are optional and should be used in pairs. -s starts a new sub-task by pushing it onto a stack so that
# subsequent -u calls are interpreted as being relative to that sub-task. -e will end that sub-task by popping it off the stack
#
#.SH How its displayed to the user:
#    This function is only responsible for keeping track of the progress stack for the enclosing process tree and to write
#    the current progress info to the $userFeedbackFD file descriptor whenever it changes. The $userFeedbackFD is set by the
#    _progressStartDriver function. If an application does not call _progressStartDriver, it will be called
#    on demand with the type specified as 'default'. The default can be changed in an environment variable or config file setting.
#
#    Even if the progress is not being displayed, the progress can be checked by sending the proc a kill USR1.
#
#.SH The Progress scope (process tree):
#    Each progressScope displays the progress of some linear task as it moves to completion. If multiple threads of execution
#    exists, they each need their own progressScope. Often each progress scope is shown on its own terminal line but the UI could
#    be tabs or panes etc...
#
#    The core idea is that all synchronous subshells can reuse the same progressScope because there is one synchrous thread of
#    actions that the progress feedback UI represents. Those actions may consist of sub parts which can be displayed as a hierarchy
#    but a sub part has to finish before the parent part proceeds so its still one synchronous progression.
#
#    Each asynchronous branch, however, is a separate thread of actions and it needs its own progress scope. If multiple asynchronous
#    threads reported to the same progressScope, it would be chaos as they represent more than one progression.
#
#    In a bash script many things create subshells synchronously which inherent their parents environment but can not update their
#    parent's environment. The progress scope is defined by an exported env variable which is automatically inherited by subshells.
#    The value of that variable points to a temp file. By writing to the temp file pointed to by that progressScope variable, the
#    subshell can contribute to the progression of the parents progress meter.
#
#    For typical, single threaded scripts there is a single progressScope that gets created only if needed. If a script or function
#    spawns new threads of execution (e.g. running a command/function in the background with '&') then care should be taken to clear
#    the progressScope variable in the childs environment so that it will create a new progressScope for the new thread of execution.
#    For example:
#         progressScope="" myBackgroundFn &
#    If the function running in the new thread calls this 'progress' function then the first call will see that progressScope is not
#    set and create a new progress scope.
#
#.SH ScopeFile Format:
#     The scope file has a line for each time start (-s) is called. If -u is called without calling -s, a -s with an empty
#     description is implied
#     Each line has the following format:
#           field1 field2 fieldN...
#     Where:
#          field1=label
#          field2=progressMsg
#          field3=startTimeStamp
#          field4=lapTimeStamp
#          field5=currentTimeStamp
#          field6=target
#          field7=current
function progress()
{
	# 2016-06 bobg. by short circuiting this the off case at the top of this function, running 350 unit
	# tests went from 22sec(using oneline) to 20sec(using null w/o short circuit) to 16sec(short circuit)

	# if progress is being called for the first time and the script has not set a specific progress driver,
	# set the default driver now
	declare -gx userFeedbackFD
	declare -gx _progressCurrentType
	declare -gx _progressAlreadyInitialized
	if [ ! "$_progressCurrentType" ] && [ ! "$_progressAlreadyInitialized" ]; then
		declare -gx _progressAlreadyInitialized="1"
		progressCntr start default
	fi

	# if no progress display driver is created now, either its configured to be 'off' or it failed to
	# initialize or it was shut down.
	if [ ! "$_progressCurrentType" ] || [ "$_progressCurrentType" == "off" ]; then
		return 0
	fi


	local cmd="-u"
	if [[ "$1" =~ ^- ]]; then
		cmd="$1"; shift
	fi


	if [ ! "$progressScope" ]; then
		/bin/mkdir -p "/tmp/bg-progress-$USER"
		export progressScope="/tmp/bg-progress-$USER/$BASHPID"
		touch "$progressScope"
		bgtrap -n progress-$BASHPID 'rm $progressScope &>/dev/null' EXIT
	fi

	# TODO: some refactors to consider....
	#       1) not sure if we need the temp file. We can pass info down through ENV variables and it seems that we do not pass info
	#          up. We can adopt the rule that a new subshell, identified by $BASHPID != $SAVEDPID, will implicitly create a new
	#          -s sub-task level. This means that an update never needs to change the information in a subtack that is not in its
	#          PID.

	local -a data
	local indent=0
	case $cmd in
		-s)
			local label="$1"
			local msg="$2"
			local target="$3"
			local current="$4"
			data[1]="$label"
			data[2]="$msg"
			data[3]=$(date +"%s%N")  # task start time
			data[4]=${data[3]}       # task lapTimeStamp
			data[5]=${data[3]}       # task currentTimeStamp
			data[6]="${target}"      # target count
			data[7]="${current}"     # current count
			_progressStackPush data
			indent=${data[0]//[^\/]}; indent=$((${#indent}+1))
			;;

		-u)
			local msg="$1"
			local current="$2"
			_progressStackUpdate data "$msg" "$current"
			indent=${data[0]//[^\/]}; indent=$((${#indent}+1))
			;;

		-e)
			local label="$1"; shift
			local msg="$1"; shift

			_progressStackPop data
			[ "$label" != "${data[1]}" ] && assertError -v label -v data "missmatched calls to progress start(-s) and end(-e)"

			data[2]="$msg"
			data[4]=${data[5]}
			data[5]=$(date +"%s%N")
			data[7]=${data[6]} # current now equals target

			indent=${data[0]//[^\/]}; indent=$((${#indent}))
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
	# TODO: the $userFeedbackTemplate and $userFeedbackProtocol do not yet seem quite right. userFeedbackTemplate
	#       should only be used if $userFeedbackProtocol is unstructured, (unstructured should mean that the
	#       userFeedbackFD is a dumb terminal or logfile and in that case, only the selected $userFeedbackTemplate
	#       is used. All progressUI plugins should get the structured protocol that has all infomation.
	local str=""
	case $userFeedbackTemplate in
		plain) str="${data[0]}:${data[2]}" ;;
		detailed)
			local cmpTime=${data[3]//--/0}
			[ $cmd == "-u" ] && cmpTime=${data[4]//--/0}
			data[5]=${data[5]//--/0}
			local spaces=$(printf "%*s" $((indent*3)) "")
			local timeDelta=$(( ${data[5]:-0} - ${cmpTime:-0} ))
			str="$(bgNanoToSec "$timeDelta" 3) $spaces $cmd ${data[0]}:${data[2]} "
			;;
		*) str="${data[*]}" ;;
	esac

	if [ "$userFeedbackProtocol" == "structured" ]; then
		str="@1 $progressScope $str"
	else
		str="${str//%20/ }"
	fi

	# its ok if we do not write anything because the driver could have been turned off or in the process
	# of exiting
	if [ "$userFeedbackFD" ] && [ -w "/dev/fd/$userFeedbackFD" ]; then
		# 2019-09-17 bobg: When $userFeedbackFD is a PIPE, If there are no readers on it, then this write will raise a SIGPIPE signal
		# the default SIGPIPE handler will exit the process. This will happen if the driver coproc exits prematurely. I wonder if
		# it will also happen in the time when the driver is processing the command so maybe we need to indicate if $userFeedbackFD
		# is a PIPE and if so, make the protocol send a response to syncronize this message passing.
		#
		# SIGPIPE's purpose is to make the default action of writing to a broken PIPE to exit the process. This makes *nix command
		# piplines more reliable.We can turn that off by trapping SIGPIPE but a low level library should not change the default
		# for the script which might be pipable and rely on that behavior.  If this continues to be a problem we could set the trap
		# just around this call with bgTrapStack
		echo "$str" >&$userFeedbackFD 2>/dev/null
		[ "$userFeedbackSync" ] && sync
	fi
	return 0
}

# usage: progressCntr <message to current driver ...>
# usage: progressCntr start  <type> <template> <sync>
function progressCntr()
{
	local cmd="$1"

	case $1 in
		start)
			shift
			_progressStartDriver "$@"
			return
			;;

		*)	# its fine if the active feedback driver does not have a control function registered because some
			# like stdin, stderr, null are simple an have no controlls
			local driverFn="${progressTypeRegistry[${_progressCurrentType:-none}]}"
			[ "$driverFn" ] && $driverFn "$@"
			;;
	esac
}



# usage: _progressStackGet <retArrayVar>
# if progress is active for the current thread this will get the current progress message
# if not, it returns the empty string
# Output Format:
#    this function returns the progress in a structured one line string format
#    fields are separated by whitespace.
#    Fields are normalized with norm() so that they do not contain spaces and are not empty
#    field0 is a genereated parent field. This conveniently preserves the 1 based index positions used in awk
#    when its converted to a zero based base array so that the field indexes documented in the progress function
#
function _progressStackGet()
{
	local retArrayVar="$1"
	# if set, progressScope is the file that this thread is writing its progress messages to
	if [ "$progressScope" ]; then
		[ -f "$progressScope" ] || assertError -v progressScope "progress scope file is missing"
		varSetRef --array "$retArrayVar" $(awk '
			{parent=parent sep $1; sep="/"}
			END {
				print parent" "$0
			}
		' "$progressScope")
		local count; arraySize "$retArrayVar" count
		[ ${count:-0} -eq 8 ] || assertError -v count -v "$retArrayVar" -f "$progressScope" "logic error. the progress record should contain 8 fields"
		unescapeTokens "$retArrayVar[0]" "$retArrayVar[1]" "$retArrayVar[2]" "$retArrayVar[6]" "$retArrayVar[7]"
	fi
}

function _progressStackPush()
{
	local retArrayVar="$1"
	local out
	local i; for ((i=1; i<=7; i++)); do
		local value; varDeRef $retArrayVar[$i] value
		escapeTokens value
		out+="$value "
	done

	if [ "$progressScope" ]; then
		[ -f "$progressScope" ] || assertError -v progressScope "progress scope file is missing"
		varSetRef --array "$retArrayVar" $(
			bgawk -i -n -v record="$out" '
				{print $0}
				{parent=parent sep $1; sep="/"}
				END {
					print record
					print (parent? parent:"--")" "record >> "/dev/fd/3"
				}
			' "$progressScope"
		)
		local count; arraySize "$retArrayVar" count
		[ ${count:-0} -eq 8 ] || assertError -v count -v "$retArrayVar" -f "$progressScope" "logic error. the progress record should contain 8 fields"
		unescapeTokens "$retArrayVar[0]" "$retArrayVar[1]" "$retArrayVar[2]" "$retArrayVar[6]" "$retArrayVar[7]"
	fi
}

function _progressStackPop()
{
	local retArrayVar="$1"
	if [ "$progressScope" ]; then
		[ -f "$progressScope" ] || assertError -v progressScope "progress scope file is missing"
		varSetRef --array "$retArrayVar" $(
			bgawk -i -n '
				on {print last}
				{last=$0; on="1"}
				{parent=parent sep $1; sep="/"}
				END {
					print parent" "$0 >> "/dev/fd/3"
				}
			' "$progressScope"
		)
		local count; arraySize "$retArrayVar" count
		[ ${count:-0} -eq 8 ] || assertError -v count -v "$retArrayVar" -f "$progressScope" "logic error. the progress record should contain 8 fields"
		unescapeTokens "$retArrayVar[0]" "$retArrayVar[1]" "$retArrayVar[2]" "$retArrayVar[6]" "$retArrayVar[7]"
	fi
}

function _progressStackUpdate()
{
	local retArrayVar="$1"; shift
	local msg="$1"; shift
	local current="$1"; shift
	escapeTokens msg current
	if [ "$progressScope" ]; then
		[ -f "$progressScope" ] || assertError -v progressScope "progress scope file is missing"
		varSetRef --array "$retArrayVar" $(
			bgawk -i -n \
				-v msg="$msg" \
				-v current="$current" '
				on {print last}
				{last=$0; on="1"}
				{parent=parent sep $1; sep="/"}
				END {
					$2=msg
					$4=$5    # laptime
					$5="'"$(date +"%s%N")"'"
					$7=current

					print $0
					print parent" "$0 >> "/dev/fd/3"
				}
			' "$progressScope"
		)
		local count; arraySize "$retArrayVar" count
		[ ${count:-0} -eq 8 ] || assertError -v count -v "$retArrayVar" -f "$progressScope" "logic error. the progress record should contain 8 fields"
		unescapeTokens "$retArrayVar[0]" "$retArrayVar[1]" "$retArrayVar[2]" "$retArrayVar[6]" "$retArrayVar[7]"
	fi
}

# usage: escapeTokens <dataVar1> [... <dataVarN>]
# This does the same as awkDataNorm but passes the param as a reference to avoid a subshell
# These two are the same but escapeTokens avoids the subshell
#    myData="$(awkDataNorm "$myData")"
#    escapeTokens myData
function escapeTokens()
{
	while [ $# -gt 0 ]; do
		local _adnr_dataVar="$1"; shift
		assertNotEmpty _adnr_dataVar
		local _adnr_dataValue="${!_adnr_dataVar}"
		_adnr_dataValue="${_adnr_dataValue// /%20}"
		_adnr_dataValue="${_adnr_dataValue//$'\n'/%0A}"
		_adnr_dataValue="${_adnr_dataValue//$'\t'/%09}"
		_adnr_dataValue="${_adnr_dataValue:---}"
		printf -v $_adnr_dataVar "%s" "$_adnr_dataValue"
	done
}

# usage: unescapeTokens [-q] <data>
# unescapeTokens reverses the effect of awkDataNorm when data is read from a data file that uses whitespace delimiters
# Options:
#    -q : quotes. add quotes if the data contains spaces
function unescapeTokens()
{
	local quotesFlag
	if [ "$1" == "-q" ]; then
		quotesFlag='"'
		shift
	fi

	while [ $# -gt 0 ]; do
		local _adnr_dataVar="$1"; shift
		assertNotEmpty _adnr_dataVar
		local _adnr_dataValue="${!_adnr_dataVar}"
		_adnr_dataValue="${_adnr_dataValue//%20/ }"
		_adnr_dataValue="${_adnr_dataValue//%0A/$'\n'}"
		_adnr_dataValue="${_adnr_dataValue//%09/$'\t'}"
		[ "$_adnr_dataValue" == -- ] && _adnr_dataValue=""
		printf -v $_adnr_dataVar "%s%s%s"  "$quotesFlag" "$_adnr_dataValue" "$quotesFlag"
	done
}




# this global array is a registry for progressDisplayType drivers.
# progressTypeRegistry[<typeName>]="<driverFunctionName>"
declare -gA progressTypeRegistry


# usage: _progressStartDriver <type> <template> <sync>
# A script calls this to determine how feedback from the 'progress' function is displayed. This function typically
# does not need to be called expicitly but a script can if it wants to prefer a certain type. If nothing in the script
# calls 'progress' or '_progressStartDriver', this function will never be called. If the script
# (or a function it uses) calls 'progress' but does not select a Display type, then this function will be called
# automatically, on demand with the type 'default'.
#
# See the comments for the 'progress' function. That is what scripts typically call to interact with this mechanism.
# Lower level functions call 'progress' without regard to how or even if the messages are displayed to the user. In
# all cases, this progress / userFeedback mechanism creates a new stream for progress updates and writing to stdout
# and stderr continue to behaive as expected.
#
# Types:
#    stdout : send progress messages to stdout, the same as echo would
#    stdout : send progress messages to stderr, the same as echo >&2 would
#    null   : suppress progress messages, the same as echo >/dev/null would
#    oneline: display each progress message from a process to one line, overwriting the last. When a (sub) process
#             calls 'progress' for the first time, the message will be echo'd to the terminal with a trailing newline
#             which often cause the screen to scroll. From then on, subsequent calls to 'progress' will overwrite that
#             same line. If stdout is not a terminal, oneline reverts to using the 'stdout' type. If the script or a
#             invoked external command writes to stdout or stderr, it will work as expected, scrolling the progress
#             lines up as needed. When a progress line scrolls past the top of the terminal, it stops updating
#    statusline:
#             this is simililar to oneline but newer and more simple. It does not need the output and input filter pros to
#             catch when the screen scrolls because it statusline sets the terminal scroll area so that the output scrolls separately
#             The statusline driver reserves a line at the bottom of the screen for each progressScope its asked to display.
#             Initially it reserves the last line for the next bash prompt when the command finishes. That eliminates a jump
#             at the end of the progress lines that are static throughout the command run. If the command produces output on
#             stdout or std error, it is written above the progress lines and scrolls without effecting the progress lines.
#    default: chooses a type based on the first one of these that is set :
#                1) '$progressDisplayType' env var if set
#                2) the /etc/bg-lib.conf[.]defaultProgressDisplayType if set
#                3) statusline if stdout is a terminal
#                4) stdout
#
# Templates:
#    plain   : (terse) parent:progressMsg
#    detailed: (more vebose) deltaTime cmd parent:progressMsg
#    full    : <all fields>
#
# Sync:
#    If sync parameter is non-empty, progress will sync the streams after each update. This adds a small but non-trivial
#    performance hit but makes it more likely the progress and stdout and sterr output  will be in the correct order.
#    This is not often needed. Its better to leave it blank.
#
# Protocol:
#    When the progress function writes the progress to the userFeedbackFD file, the line that it writes complies
#    with the protocol that the handler reading the userFeedbackFD requires. The userFeedbackProtocol environment
#    variable specifies which protocol should be used. Typically the handler sets the value of userFeedbackProtocol
#    and the progress function formats the line in accordance.
#
#    passThru:   formated for display. This is the default and is appropriate when the handler will not do any formating
#                stdout, stderr and null are simple pipes that display the information as received.
#    structured: each field is escaped so that they are white space separated. This makes it easier for the handler to
#                parse it. The first field is "@1" to indicate that its a strunctured line. The second filed is the
#                progressScope with is the name of the filename that contains the progress stack. The third and remaining
#                fields are the text as specified by the template but with escaped whitespace.
#
# Environment:
#    BGENV: progressDisplayType : (statusline|oneline|stderr|stdout|null) : determines how progress is displayed. see 'progress' function
#          /etc/bg-lib.conf[.]defaultProgressDisplayType : specify the progressDisplayType in a persistent config
function _progressStartDriver()
{
	local type="${1:-default}"
	export userFeedbackTemplate="${2:-plain}"
	export userFeedbackSync="$3"
	export userFeedbackProtocol="passThru"


	# if a previous driver is active, stop it
	if [ "$_progressCurrentType" ]; then
		local driverFn="${progressTypeRegistry[$_progressCurrentType]}"
		[ "$driverFn" ] && $driverFn stop
		export _progressCurrentType=""
	fi

	# TODO: add termTitle progressDisplayType function to change xterm window title. This works via ssh too.
	# example: echo -en "\033]0;New terminal title $i\a"; sleep 1; done
	# example: set_term_title(){echo -en "\033]0;$1\a"}

	case $type in
		default)
			# in a deamon, the default is to not display any progress UI
			cuiHasControllingTerminal || return

			# respect the progressDisplayType ENV var and the /etc/bg-lib.conf config file. If those
			# are not set or set to 'default' then use 'statusline'
			local defaultType="statusline"
			if [ "$progressDisplayType" ]; then
				defaultType="$progressDisplayType"
			else
				defaultType="$(getIniParam /etc/bg-lib.conf . defaultProgressDisplayType "$defaultType")"
			fi
			[[ "${defaultType}" =~ ^[[:space:]]*default([[:space:]]|$) ]] && defaultType="statusline"

			# call ourselves again with the real display type (not 'default')
			_progressStartDriver $defaultType
			;;

		stdout)
			export _progressCurrentType="$type"
			export userFeedbackFD="1"
			;;

		stderr)
			export _progressCurrentType="$type"
			export userFeedbackFD="2"
			;;

		off)
			export _progressCurrentType=""
			export userFeedbackFD=""
			export userFeedbackTemplate=""
			;;

		null)
			export _progressCurrentType="$type"
			exec {userFeedbackFD}>/dev/null
			export userFeedbackFD
			;;

		*)
			local driverFn="${progressTypeRegistry[$type]}"

			# try loading it from an external library
			if [ ! "$driverFn" ]; then
				import -q bg_progress${type^}.sh ;$L1;$L2 || bgtraceVars -l"notFound" L1 L2
				driverFn="${progressTypeRegistry[$type]}"
			fi

			[ ! "$driverFn" ] && assertError -v "progressDriver:$type" "unknown progress display type"

			# if the driver failed to start it could be that there is no controlling terminal so just
			# ignore it unless another use-case comes up
			if $driverFn start; then
				export _progressCurrentType="$type"
			fi
			;;

	esac
# bgtrace "  !EXIT    |$(trap -p EXIT)|"
# bgtrace "  !SIGINT  |$(trap -p SIGINT)|"
# bgtrace "  !SIGTERM |$(trap -p SIGTERM)|"
}

function myTestTrapHandler()
{
	local intrName="$1";    [ $# -gt 0 ] && shift
	local startingPID="$1"; [ $# -gt 0 ] && shift
	local isScript=" "; [ "$$" == "$BASHPID" ] && isScript="*"
	bgtrace " !TRAP $isScript'$BASHPID' createdIn='$startingPID' $intrName '$*'"
}
