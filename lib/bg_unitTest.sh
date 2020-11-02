
# Library
# This bash script library is imported by all unit test files. When a unit test file is executed from the command line, this
# library provides its main code to make it act like a cmd so that it can stand alone and be ran directly for tesing and development.
# When the unit test file is sourced by the unit test framework, that code does nothing and lets the unit test frame work control
# the execution.
#
# See Also:
#    man(1) bg-unitTestScriptName.ut

# bgUnitTestMode=utRuntime|direct
declare -g bgUnitTestMode="utRuntime"; [[ "$bgLibExecCmd" =~ [.]ut$ ]] && bgUnitTestMode="direct"

declare -g bgUnitTestScript="${BASH_SOURCE[1]}"
declare -g ufFile="${bgUnitTestScript##*/}"
ufFile="${ufFile%.ut}"


##################################################################################################################################
### Common Section
# the functions defined in this section are always included so that they are available regardless of whether the ut script is
# executed directly or sourced by the unit test framework

# usage: unitTestCntr <spec>
# usage: unitTestCntr "$@"
# This function is called at the end of each unit test script file passing in any arguments that the script was invoked with.
# When a ut script is invoked directly, it implements various commands to query and invoke the unit test cases contained in the file.
# When a ut script is sourced by the unit test framework, this function returns without doing anything.
function unitTestCntr()
{
	# if we are being sourced, the utRuntime will manage the unit tests so just return
	if [ "$bgUnitTestMode" == "utRuntime" ]; then
		return
	else
		utfDirectScriptRun "$@"
	fi
}

# usage: utEsc [<p1> ...<pN>]
# usage: cmdline [<p1> ...<pN>]
# this escapes each parameter passed into it by replacing each IFS character with its %nn equivalent token and returns all parameters
# as string with a single IFS character separating each parameter. If that string is subsequently passed to utUnEsc, it will populate
# an array properly with each element containing the original version of the parameter
function cmdline() { utEsc "$@" ; }
function utEsc()
{
	local params=("$@")
	params=("${params[@]// /%20}")
	params=("${params[@]//$'\t'/%09}")
	params=("${params[@]//$'\n'/%0A}")
	params=("${params[@]//$'\r'/%0D}")
	echo "${params[*]}"
}

# usage: utUnEsc <retArrayVar> [<escapedP1> ...<escapedPN>]
# this is the companion function to utEsc. It populates the array variable named in <retArrayVar> with the unescaped versions of
# each of the parameters passed in.
function utUnEsc()
{
	local -n _params="$1"; shift
	_params=("$@")
	_params=("${_params[@]//%20/ }")
	_params=("${_params[@]//%09/$'\t'}")
	_params=("${_params[@]//%0A/$'\n'}")
	_params=("${_params[@]//%0D/$'\r'}")
}

# usage: ut <event> ...
# The ut function monitors and manages the state of the running testcase. The testcase author calls it to signal entering 'setup'
# and 'test' sections that change the way the output of commands are written and the way that the exit codes are handled. The author
# can go back and forth between setup and test section as many times as they want for example to include several logical tests in
# one function.
#
# Also, the utf calls this function to signals various events in the testcase run.
#
# ut setup:
# Used when writing testcases to signal that the follow code is setup and not the taget of the testcase. The output of setup code
# is not significant for determining if the testcase passes. Also, if any setup code exits with non-zero or writes to stderr,
# the testcase will terminate and be considered not elgible for running because its setup is failing.
#
# ut test
# Used when writing testcases to signal that the follow code is the target of the testcase that is being tested. There is nothing
# that test code can do that is considered wrong. All actions from writing to stderr, to having a command that exits non-zero, to
# exiting the function prematurely (with exit; or assert*) will produce output in the testcase's stdout stream which will be compared
# to the 'plato' output. If its identical, then the testcase passes and if not it fails.
#
# ut onStart
# Called before the first line of the test function is executed.
#
# ut onEnd
# Called after the testcase function has finished running if it ended normally.
#
# ut onExitCaught <exitCode>
# Called after the testcase function has finished running if it ended by terminating the function early.
#
# ut onBeforeSrcLine <lineNo> <srcLine>
# called before the first simple command in a source file line is called. There may be multiple simple commands called per src line.
#
# ut onAfterSrcLine <lineNo> <srcLine>
# called after the last simple command on a src line is called.
function ut()
{
	local event="$1"; shift

	# if the last command produced stderr output, flush it
	if [ -s "$errOut" ]; then
		sync
		cat "$errOut" | awk '{printf("stderr> %s\n", $0)}'
		truncate -s0 "$errOut"
		[ "$_utRun_section" == "setup" ] && ut setupFailed
	fi

	case $event in
	  setup)
		echo >&$stdoutFD
		echo "##----------" >&$stdoutFD
		echo "## $event" >&$stdoutFD
		_utRun_section="$event"
		exec >&$setupOutFD
		;;

	  test)
		exec >&$stdoutFD
		_ut_flushSetupFile
		echo >&$stdoutFD
		echo "##----------" >&$stdoutFD
		echo "## $event" >&$stdoutFD
		_utRun_section="$event"
		;;

	  onBeforeSrcLine)
		local lineNo="$1"
		local srcLine="$2"
		# print the  source line that we are about to start executing so that its output will appear after it
		printf "cmd> %s\n" "$srcLine"
		;;

	  onAfterSrcLine)
		local lineNo="$1"
		local srcLine="$2"
		_ut_flushLineInfo
		;;

	  onCmdErrCode)
		_utRun_lineInfo+="['$2' exitted $1]"
		[ "$_utRun_section" == "setup" ] && ut setupFailed
		;;


	  onStart)
		local utID="$1"; shift
		exec {setupOutFD}>$setupOut
		exec {stdoutFD}>&1
		exec {errOutFD}>$errOut
		exec 2>&$errOutFD

		# these are the state variables of the unit test run. the ut function and trap handlers and all the helper functions
		# they use will treat these as their member state variables
		_utRun_id="$utID"
		_utRun_funcName="$utFunc"
		_utRun_section=""  # default is 'test'. init to "" allows us to distinguish the case were no section is declared
		_utRun_curLineNo=0
		_utRun_srcCode=()
		_utRun_srcLineStart="<uninit>"
		_utRun_srcLineEnd=""

		# load this ut_ function's source into an array
		while read -r line; do
			if [ "$_utRun_srcLineStart" == "<uninit>" ]; then
				_utRun_srcLineStart=$line
				_utRun_srcLineEnd=$line
			else
				_utRun_srcCode[$((_utRun_srcLineEnd++))]="$line"
			fi
		done < <(awk '
			!inFunc && $1=="function" && $2=="'"$utFunc"'()" {linestart=FNR; print linestart}
			!inFunc && $1=="'"$utFunc"'()"                   {linestart=FNR; print linestart}
			linestart {print $0}
			linestart && /^}/ {linestart=0; exit}
		' $bgUnitTestScript)

		for ((i=_utRun_srcLineStart; i<_utRun_srcLineEnd; i++)); do
			if [[ "${_utRun_srcCode[i]}" =~ ^[[:space:]]*#[[:space:]]*expect ]]; then
				_utRun_expect="${_utRun_srcCode[i]#*expect }"
			fi
		done

		# set an EXIT trap to detect when the testcase ends prematurely
		builtin trap 'exitCode="$?"; ut onExitCaught "$exitCode"; exit $?' EXIT

		# make sure ERR trap is not set to inherit. The first time the DEBUG trap fires from inside the target ut_ function, we
		# will set the ERR trap there
		set +E;

		# turn off DEBUG trap inheritance globally with set +T and then turn it on just for the utFunc function
		# the trap will turn on immediately for the process and any functions on the stack will be debugged but any newly launched
		# function will not be debugged except the utFunc for which we explicitly set the DEBUG inherit flag. DEBUG will fire for
		# the remainder of this call of 'ut' but the next time 'ut' is called, it wont.
		set +T; declare -ft "$utFunc"; builtin trap 'bgBASH_debugTrapLINENO=$LINENO; bgBASH_debugTrapFUNCNAME=$FUNCNAME;  _ut_debugTrap' DEBUG

		echo >&$stdoutFD
		echo "###############################################################################################################################" >&$stdoutFD
		echo "## $_utRun_id start" >&$stdoutFD
		echo "## expect: $_utRun_expect" >&$stdoutFD
		;;

	  onFirstTimeInsideUTFunc)
		# set an ERR trap to monitor non-zero exit codes
		builtin trap 'ut onCmdErrCode "$?" "$BASH_COMMAND"' ERR
		;;

	  setupFailed)
		builtin trap '' DEBUG ERR EXIT
		_ut_flushLineInfo
		exec >&$stdoutFD
		_ut_flushSetupFile
		printf "** Setup Failed: testcase not finished.  **\n"
		exit 222
		;;

	  onExitCaught)
		builtin trap '' DEBUG ERR EXIT
		local exitCode="$1"
		_ut_flushLineInfo
		printf "!!! test case is exiting prematurely code=%s\n" "$exitCode"
		exec >&$stdoutFD
		_ut_flushSetupFile
		if [ "$_utRun_section" == "setup" ]; then
			ut setupFailed
		else
			return 1
		fi
		;;

	  onExceptionCaught)
		builtin trap '' DEBUG ERR EXIT
		_ut_flushLineInfo
		exec >&$stdoutFD
		_ut_flushSetupFile
		printf "** Exception thrown by testcase **\n"
		catch_errorDescription="${catch_errorDescription##$'\n'}"
		printfVars "   " ${!catch_*}
		[ "$_utRun_section" == "setup" ] && ut setupFailed;
		;;

	  onEnd)
		_ut_flushLineInfo
		builtin trap '' DEBUG ERR EXIT
		echo  # if we end normally, put a blank line in between the last testcase output and the end banner
		true
		;;

	  onFinal)
		_ut_flushLineInfo
		builtin trap '' DEBUG ERR EXIT
		if [ "$2" == "OK" ]; then
			echo "## $1 finished"
		else
			echo "## $1 ERROR: setup could not complete"
		fi
		echo "###############################################################################################################################"
		echo
		;;

	  *) assertError -v event:"$event" "unknown ut <event> in testcase" ;;

	esac
}

function _ut_flushSetupFile()
{
	# if we are entering test mode and there is collected setup content, flush it
	if [ -s "$setupOut" ]; then
		sync
		awk '{printf("##     | %s\n", $0)}' $setupOut >&$stdoutFD
		truncate -s0 "$setupOut"
	fi
}

function _ut_flushLineInfo()
{
	[ "$_utRun_lineInfo" ] && echo "$_utRun_lineInfo"
	_utRun_lineInfo=""
}


# This is called from the DEBUG trap while running test case functions. global (set +T) is turned off and only the utFunc will
# have the -t attribute set so only the commands in that function will get the trap called.
# The purpose is to print the source line to stdout just before it is executed and posibly write output to stdout.
# The trap is called per simple command instead of by line so we read the function source from its script file. In the trap we know
# the source lineno so we use that to identify the line to print and suppress printing the same line multiple times in a row.
function _ut_debugTrap()
{
	#bgtrace "$bgBASH_debugTrapFUNCNAME | $BASH_COMMAND"

	# we are only interested in DEBUG traps for the target ut_ function but its not possible to turn it on only for it so filter out
	# the other calls
	[[ "$bgBASH_debugTrapFUNCNAME" == ut_* ]] || return 0

	# The DEBUG trap is called once in the begining of a function call with the BASH_COMMAND set to the command that invoked it
	# the ERR trap can only be set from that time.
	[[ "$BASH_COMMAND" == '$utFunc '* ]] && { ut onFirstTimeInsideUTFunc; return 0; }

	# calls to ut setup|test take care of themselves
	[[ "$BASH_COMMAND" == 'ut '* ]] && return 0

	# there might be multiple BASH_COMMAND (which are simple cmd) on each source line so only drop in the first time we see a new lineno
	# inside this block is just before we are about to run the first simple cmd on a new source line.
	if [ ${_utRun_curLineNo:-0} -ne ${bgBASH_debugTrapLINENO:-0} ]; then
		if (( _utRun_srcLineStart < _utRun_curLineNo && _utRun_curLineNo < _utRun_srcLineEnd )); then
			ut onAfterSrcLine "$_utRun_curLineNo"  "${_utRun_srcCode[$_utRun_curLineNo]}"
		fi

		_utRun_curLineNo="$bgBASH_debugTrapLINENO"

		if (( _utRun_srcLineStart < _utRun_curLineNo && _utRun_curLineNo < _utRun_srcLineEnd )); then
			ut onBeforeSrcLine "$_utRun_curLineNo"  "${_utRun_srcCode[$_utRun_curLineNo]}"
		fi
	fi
}


# usage: utfRunner_execute <utFunc> <utParams> [...<utParamsN>]
# execute a testcase function one or more times with the specified utParams keys.
# The ut script which contains the function should already be loaded (aka sourced, aka imported).
# The output will go to stdout.
function utfRunner_execute()
{
	local utFunc="ut_${1#ut_}"; shift

	[ "$(type -t "$utFunc")" == "function" ] || assertError -v utFile -v utFunc -v utParams "the unit test function is not defined in the unit test file"
	varIsA array "$utFunc"                   || assertError -v utFile -v utFunc -v utParams "the unit test file does not define an array variable with the same name as the function to hold the utParams."
	local -n inputArray="$utFunc"
	[ "${inputArray[$utParams]+exists}" ]    || assertError -v utFile -v utFunc -v utParams "utParams is not a key the in the array variable with the same name as the function. It should be a key whose value is the parameter string to invoke the test function with"

	local setupOut; bgmktemp setupOut
	local errOut; bgmktemp errOut

	# for each utParams passed in, run the testcase function
	while [ $# -gt 0 ]; do
		local utParams="$1"; shift
		local params=(); utUnEsc params ${inputArray[$utParams]}
		local utID="${ufFile}:${utFunc#ut_}:$utParams"

		(
			# require an extra config to keep tracing on for tests because they can have many exceptions printing stack traces
			# see bg-debugCntr trace tests:on|off
			[ "$bgTracingTestRunner" == "on" ] || bgtraceCntr off

			ut onStart "$utID"

			Try:
				$utFunc "${params[@]}"
				ut onEnd
			Catch: && {
				ut onExceptionCaught
			}

			ut onFinal "$_utRun_id" "OK"
		)

		local result="$?"
		case $result in
			  0) : ;;
			  1) ut onFinal "$utID" "OK"; result=0 ;;
			222) ut onFinal "$utID" "FAIL" ;;  # setup failure -- writing to stderr, cmd returns!=0, setup asserts or calls exit
			  *) assertError "Unit test framework logic error. The testcase block ended with an unexpected exit code ($result)."
		esac

		[ -s "$setupOut" ] && assertError -f setupOut "Unit test framework error. Content was left in the setupOut temp file after a testcase run"
		[ -s "$errOut" ]   && assertError -f errOut   "Unit test framework error. Content was left in the errOut temp file after a testcase run"
	done

	bgmktemp --release setupOut
	bgmktemp --release errOut
}
















##################################################################################################################################
### Direct Execution Code

# the rest of this file is only included if the ut script is being directly executed
[ "$bgUnitTestMode" == "utRuntime" ] && return 0

# man(1.bashCmd) bg-unitTestScriptName.ut
# usage: <bg-unitTestScriptName>.ut list|runAll|<utID>
# This is the man page for all *.ut unit test script files in bg-core style packages. A ut script looks like a library but can also
# be executed as a stand alone command.
#
# Unit Test Framework:
# The "bg-dev test ..." command sources and runs the test cases contained in *.ut files in a special way that redirect their
# output and determines if they pass or fail.
#
# Direct Execution:
# *.ut unit test scripts can be executed directly from the command line also. The utfDirectScriptRun function in bg_unitTest.sh
# provides this functionality. It supports command line completion so that the user can see how to run it and complete the utIDs
# contained in the script.
#
# When a test case is run via direct execution, it is meant for testing and development of the test case as opposed to running it
# under the unit test framework which records the results in the project. The output of the test case(s) goes to stdout so that it
# can be immediately examined.  Running a test case this way makes it easier to run in the debugger.
#
# Direct Command list:
# print a list of the utIDs contained in this script.
#
# Direct Command runAll:
# Run all the utIDs contained in this script, one after another. The output goes to stdout.
#
# Direct Command <utId>:
# Run a specific utIDs contained in this script. The output goes to stdout.
#
# Params:
#    <utID> : A utID to run. It must be one that resides in this ut script. Use bash completion to fill it in. Use the 'list'
#             command to see a list of all of the utID contained in the script.
# See Also:
#    man(7) bg_unitTest.ut



#NO_FUNC_MAN
# this function is called at the end of every *.ut ut script and implements the direct execution stand alone command behavior of
# the test script.  It provides bash completion, querying to see what test cases are contained and stand alone running  of test cases.
function utfDirectScriptRun()
{
	invokeOutOfBandSystem "$@"

	# run unit tests from their project root folder no matter where the user ran the command from
	local projectFolder="${0%unitTests/*}"
	[ "$projectFolder" ] && cd "$projectFolder"

	# the default action is to list the test cases contained in the ut script
	[ $# -eq 0 ] && set -- list

	local spec="$1"; shift
	case ${spec} in
	  runAll)
		for utFunc in ${!ut_*}; do
			local -n inputArray="$utFunc"
			[ "$(type -t "$utFunc")" != "function" ] && assertError "malformed unit test. '$utFunc' should be a function name as well as the input array name"

			local utParams; for utParams in "${!inputArray[@]}"; do
				utfRunner_execute "$utFunc" "$utParams"
			done
		done
		;;

	  list) directUT_listLoadedIDs ;;

	  *)
		[[ "$spec" =~ ^([^:]*):?(.*)?$ ]]
		local utFunc="ut_${BASH_REMATCH[1]}"
		local utParams="${BASH_REMATCH[2]}"
		utfRunner_execute "$utFunc" "$utParams"
		;;
	esac
}

function directUT_listLoadedIDs()
{
	for utFunc in ${!ut_*}; do
		local -n inputArray="$utFunc"
		[ "$(type -t "$utFunc")" != "function" ] && assertError "malformed unit test. '$utFunc' should be a function name as well as the input array name"

		local utParams; for utParams in "${!inputArray[@]}"; do
			echo "${utFunc#ut_}:$utParams"
		done
	done
}

function directUT_listLoadedUTFunc()
{
	for utFunc in ${!ut_*}; do
		local -n inputArray="$utFunc"
		[ "$(type -t "$utFunc")" != "function" ] && assertError "malformed unit test. '$utFunc' should be a function name as well as the input array name"
		echo "${utFunc#ut_}"
	done
}

function directUT_listUTParams()
{
	local utFunc="$1"
	local -n inputArray="$utFunc"
	[ "$(type -t "$utFunc")" != "function" ] && assertError "malformed unit test. '$utFunc' should be a function name as well as the input array name"
	local utParams; for utParams in "${!inputArray[@]}"; do
		echo "$utParams"
	done
}

# this is invoked by invokeOutOfBandSystem when -hb is the first param
# The bash completion script calls this get the list of possible words.
function oob_printBashCompletion()
{
	bgBCParse "" "$@"; set -- "${posWords[@]:1}"

	if [ "$posCwords" == "1" ]; then
		local utID="$1"
		if [[ ! "$utID" =~ : ]]; then
			echo "runAll list"
			directUT_listLoadedUTFunc | sed 's/\>/:%3A/g'
		else
			[[ "$utID" =~ ^([^:]*):?(.*)?$ ]]
			local utFunc="ut_${BASH_REMATCH[1]}"
			local utParams="${BASH_REMATCH[2]}"
			echo "\$(cur:$utParams)"
			directUT_listUTParams "$utFunc"
		fi
	fi
	exit
}
