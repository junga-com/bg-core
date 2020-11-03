
# Library
# FUNCMAN_NO_FUNCTION_LIST
# usage: # define one or more ut_* functions
#        function ut_myTest() { ...}
#        # make this the last line of the ut script file
#        unitTestCntr "$@"
# This is a bash script library that is imported only by bash unit test script files.
# A script follows these requirements to become a valid test script that can be ran under the unit test framework.
#    1) the file should be in its project's ./unitTests/ folder and end in the .ut extension.
#    2) make the file executable (chmode a+x uitTests/<file>.ut)
#    3) import bg_unitTest.sh ;$L1;$L2
#    4) define one or more functions starting with ut_
#    5) at the end of the file call unitTestCntr "$@"
#
# This pattern produces a script that can be invoked like a command for development or invoked within the unit test framework via
# "bg-dev tests".
#
# Writing Testcases:
# A testcase starts with a function named with a leading ut_*. That function will result in one or more testcases being created.
# Each testcase is the function plus a set of command line arguments that the function will be invoked with. The optional command
# line argument sets are defined in an array variable with the same name as the function. Each array index becomes the name of the
# argument list that is defined in the value at that index. The array can be an associative array with alphanumeric names or a
# regular array with only numeric names.
#
# Inside the testcase function, you can put any code. The prupose of the code is to invoke the target code and produce output that
# indicates what the target code did. The testcase output is derived from what it writes to stdout and stderr, the exit code of
# commands, and whether it ends normally or by exiting its process or calling an assert* function (aka throwing an exception).
#
# You can also include setup code in the testcase. The 'ut setup' and 'ut test' commands are used to identify setup vs test code.
# Setup code can also be any code but its output is treated differently. Writing to stderr, letting a command end with a non-zero
# exit code, exitting the process, or calling an assert* function from within setup code will result in the testcase being considered
# as not completed and therefore any output that it may or may not have produced will not be used. A testcase ending in this way
# is failed, but it does not mean that the target code it is testing ahs an error. Instead, the prerequisites to testing that target
# code could not be met therfore it is unknown if the target code has a problem. Once the cause of the setup failing is fixed, the
# testcase can be ran again.
#
# Also, the output of setup code is merged with the testcase output prefixed by # so that it will be considered comments and not
# part of the real output that will determine if the testcase passes or failed.
#
# Example
#    function ut_testMyTargetFunction() {
#       ut setup
#       local p1="$1"
#       local p2="$2"
#       prinftVars p1 p2
#
#       ut test
#       myTargetFunction "$p1" "$p2"
#    }
# In the setup section, printing the p1 and p2 variables will produce commented output that wont influance whether the testcase
# passes or fails but it serves to make the output easier to read and understand. The developer can more easily see that if the
# output makes sense because they see the value of the arguments sent to myTargetFunction.
#
# Example
#    declare -A ut_testSomething=(
#        [one]="$(cmdLine "45" "this and that")"
#        [two]="$(cmdLine "42" "is the answer")"
#    )
#    function ut_testSomething() {
#         ...
#    }
# This blocks creates two testcases that both use the same function but with different arguments to invoke that function. Note that
# using the cmdLine helper function will result in the arguments being escaped correctly so that you can write them as if you are
# calling a function directly.
# The utIDs created will be...
#    testSomething:one
#    testSomething:two
# If the array by the same name is not defined, then a ut_ function will produce one testcase with an empty last part like...
#    testMyTargetFunction:
# Note that the ut_ is removed in the utIDs. With the leading ut_ the token is a utFunc (function name) and without it, the token
# is the testcase base name.
#
# Debugging A Testcase:
# While writing a new testcase or debugging a failed testcase you can invoke it directly from a terminal (as opposed to from within
# the unit test framework). A major design goal of this system is that writing a testcase should be no harder that writing a
# simple test script to excercise some new feature so that it encourages the creation of testcases during development. You have to
# see if that new function works so you might as well put that test code in a testcase function and then invoke it from the
# terminal (or IDE) to see what happens.
#
# When invoked directly, the script does not even pull in the framework code so its quick and light. Unit test scripts get bash
# command completion of the testcase utIDs within them automatically so its easy to add a new test case and then go to the terminal
# to invoke it without having to type out the whole name.
#
# Even though this library uses the DEBUG, EXIT, and ERR traps to monitor the testcase function's progress, it is compatible with
# the traps set by the debugger. To run a testcase in the debugger, either use the debug subcommand to the ut script or place a
# bgtraceBreak statement in your testcase function at the point you want to debug. 
#
# See Also:
#    man(1) bg-unitTest.ut
#    man(1) bg-dev-tests.ut

# bgUnitTestMode=utRuntime|direct
declare -g bgUnitTestMode="utRuntime"; [[ "$bgLibExecCmd" =~ [.]ut$ ]] && bgUnitTestMode="direct"

declare -g bgUnitTestScript="${BASH_SOURCE[1]}"


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
		local trimmedLine="${srcLine#[]}"; stringTrim -i trimmedLine
		printf "cmd> %s\n" "${trimmedLine}"
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

		bgtrace "funcLevel=${#FUNCNAME[@]} BASHPID='$BASHPID'  \$\$=$$   "

		# set an EXIT trap to detect when the testcase ends prematurely
		trap -n unitTests 'exitCode="$?"
			ut onExitCaught "$exitCode"
			exit $?' EXIT

		# make sure ERR trap is not set to inherit. The first time the DEBUG trap fires from inside the target ut_ function, we
		# will set the ERR trap there
		set +E;

		# turn off DEBUG trap inheritance globally with set +T and then turn it on just for the utFunc function
		# the trap will turn on immediately for the process and any functions on the stack will be debugged but any newly launched
		# function will not be debugged except the utFunc for which we explicitly set the DEBUG inherit flag. DEBUG will fire for
		# the remainder of this call of 'ut' but the next time 'ut' is called, it wont.
		set +T; declare -ft "$utFunc"; builtin trap 'bgBASH_debugTrapLINENO=$LINENO; bgBASH_debugTrapFUNCNAME=$FUNCNAME;  _ut_debugTrap' DEBUG
		_utRun_debugHandlerHack="1" # this telle the debugger's DEBUG handler to call _ut_debugTrap

		echo >&$stdoutFD
		echo "###############################################################################################################################" >&$stdoutFD
		echo "## $_utRun_id start" >&$stdoutFD
		echo "## expect: $_utRun_expect" >&$stdoutFD
		;;

	  onFirstTimeInsideUTFunc)
		# set an ERR trap to monitor non-zero exit codes
		trap -n unitTests '[ "$FUNCNAME" == "$_utRun_funcName" ] && ut onCmdErrCode "$?" "$BASH_COMMAND"' ERR
		_utRun_errHandlerHack="$(builtin trap -p ERR)"

		if [ "$_utRun_debugFlag" ]; then
			type -t debuggerOn &>/dev/null || import bg_debugger.sh ;$L1;$L2
			debugSetTrap --logicalStart+${logicalFrameStart:-1}
			#debuggerOn
		fi
		;;

	  setupFailed)
		trap -n unitTests -r '' ERR EXIT
		builtin trap '' DEBUG
		_ut_flushLineInfo
		exec >&$stdoutFD
		_ut_flushSetupFile
		printf "** Setup Failed: testcase not finished.  **\n"
		exit 222
		;;

	  onExitCaught)
		trap -n unitTests -r '' ERR EXIT
		builtin trap '' DEBUG
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
		trap -n unitTests -r '' ERR EXIT
		builtin trap '' DEBUG
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
		trap -n unitTests -r '' ERR EXIT
		_utRun_debugHandlerHack="1"
		builtin trap '' DEBUG
		echo  # if we end normally, put a blank line in between the last testcase output and the end banner
		true
		;;

	  onFinal)
		_ut_flushLineInfo
		trap -n unitTests -r '' ERR EXIT
		builtin trap '' DEBUG
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
	# the other calls.
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


# usage: utfRunner_execute <utFilePath> <utFunc> <utParams>
# execute one testcase. A testcasse is a call to the utFunc with a particular array of cmdline arguments identified by utParams.
# This function is written so that it will do what ever work it needs to to setup the environment for the testcase to run, but it
# will detect if the caller has already done the work to set the environment and use it without repeatin the work. This makes it
# efficient to call in a batch and functional to call on its own for a single testcase. This is the only function that executes
# testcases.
#
# Output:
# The output will go to stdout.
#
# Params:
#    <utFilePath> : the path to the ut script that contains the testcases to run. This is a path that exists (relative or absolute)
#                   The <utFile> component of the utID is created by removing the leading folders and the trailing .ut
#    <utFunc>     : the name of the function that implements the testcase.
#    <utParams>   : the name of the key (aka index) of the array of comdLine parameters that that this testcase instanace will be
#                   invoked with
# Source Context Variables:
# The variables derived by scanning the source of the utFile are required to run the testcase. This function will get them if needed
# but it is more efficient for the caller to provide their values when the caller is running multiple testcases from the same utFile.
# So if they are already set they will not be calculated by this function.
#    _utRun_srcCode      : an array containing the source file contents of the utFile script. The indexes are the line numbers
#    _utRun_srcLineStart : the line number of the function declaration line of utFunc in the source file
#    _utRun_srcLineEnd   : the line number of the ending } line of utFunc in the source file
#    _utRun_expect       : the contents of the # expect comment contained inside the utFunc
#
function utfRunner_execute()
{
	local _utRun_debugFlag
	while [ $# -gt 0 ]; do case $1 in
		--debug) _utRun_debugFlag="--debug" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local utFilePath="$1"; shift
	local utFunc="ut_${1#ut_}"; shift
	local utParams="$1"; shift

	local utFile="${utFilePath##*/}"; utFile="${utFile%.ut}"
	local utID="${utFile}:${utFunc#ut_}:$utParams"

	# import script if needed and validate that the utFunc exists
	[ "$(type -t "$utFunc")" == "function" ] || import "$utFilePath" ;$L1;$L2
	[ "$(type -t "$utFunc")" == "function" ] || assertError -v utFile -v utFunc -v utParams "the unit test function is not defined in the unit test file"

	# if utParams is emptyString, invoke with no params. Otherwise, utParams is the key of the array of cmdline arguments with the
	# same name as the utFunc
	local params=()
	if [ "$utParams" ]; then
		varIsA array "$utFunc"                   || assertError -v utFile -v utFunc -v utParams "the unit test file does not define an array variable with the same name as the function to hold the utParams."
		local -n inputArray="$utFunc"
		[ "${inputArray[$utParams]+exists}" ]    || assertError -v utFile -v utFunc -v utParams "utParams is not a key the in the array variable with the same name as the function. It should be a key whose value is the parameter string to invoke the test function with"
		# for each utParams passed in, run the testcase function
		utUnEsc params ${inputArray[$utParams]}
	fi

	# these are the state variables of the unit test run. the ut function and trap handlers and all their helper functions
	# will treat these as their member state variables. Some of them that require work to set will use the value defined in the
	# caller's scope if they exist. Notice that when declaring a variable local and seting it from itself, the initializer is the
	# variable from the parent's scope b/c its not yet a local variable.
	local _utRun_id="$utID"
	local _utRun_funcName="$utFunc"
	local _utRun_srcLineEnd=("${_utRun_srcLineEnd[@]}")  # maybe we dont need to copy the src file array? just comment out this line
	local _utRun_srcLineStart=${_utRun_srcLineStart:-0}
	local _utRun_srcLineEnd=${_utRun_srcLineEnd:-0}
	local _utRun_section=""  # default is 'test'. init to "" allows us to distinguish the case were no section is declared
	local _utRun_curLineNo=0

	# if the caller has not already loaded the source,  load source file into an array
	if [ ${#_utRun_srcCode[@]} -eq 0 ]; then
		local line i=1; while IFS= read -r line; do
			_utRun_srcCode[i++]="$line"
		done < "$utFilePath"
	fi

	# if the caller has not already filled these in,  get the start line, end line and expect data from the src
	[ ${_utRun_srcLineStart:-0} -eq 0 ] && for ((i=1; i<${#_utRun_srcCode[@]}; i++)); do
		if [ $_utRun_srcLineStart -eq 0 ] && [[ ${_utRun_srcCode[i]} =~ ^[[:space:]]*(function)?[[:space:]]*$utFunc'()' ]]; then
			_utRun_srcLineStart=$i
		fi
		if [ $_utRun_srcLineStart -ne 0 ]; then
			if [[ "${_utRun_srcCode[i]}" =~ ^[[:space:]]*#[[:space:]]*expect ]]; then
				_utRun_expect="${_utRun_srcCode[i]#*expect }"
			fi
			if [[ ${_utRun_srcCode[i]} =~ ^} ]]; then
				_utRun_srcLineEnd=$i
				break;
			fi
		fi
	done


	local setupOut; bgmktemp setupOut
	local errOut;   bgmktemp errOut

	if [ "$_utRun_debugFlag" ]; then
		type -t debuggerOn &>/dev/null || import bg_debugger.sh ;$L1;$L2
		debuggerOn "" "resume"
	fi

	(
		# require an extra config to keep tracing on for tests because they can have many exceptions printing stack traces
		# see bg-debugCntr trace tests:on|off
		[ "$bgTracingTestRunner" == "on" ] || [ "$_utRun_debugFlag" ] || bgtraceCntr off

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

	bgmktemp --release setupOut
	bgmktemp --release errOut
}
















##################################################################################################################################
### Direct Execution Code

# the rest of this file is only included if the ut script is being directly executed
[ "$bgUnitTestMode" == "utRuntime" ] && return 0

# MAN(1.bashCmd) bg-unitTest.ut
# usage: <bg-unitTestScriptName>.ut list|runAll|<utID>
# *.ut files are scripts containing test cases. This is the man page for all *.ut files.
# A ut script looks like a library but can also be executed as a stand alone command complete with bash command line completion.
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
# list sub command
#    print a list of the utIDs contained in this script. Each is a unique testcase that can be ran.
#
# runAll sub command
#    Run all the utIDs contained in this script, one after another. The output goes to stdout.
#
# <utId> sub command
#    Run a specific utIDs contained in this script. The output goes to stdout.
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
	local cmd="${1:-list}"; shift

	case $cmd in
		list)   directUT_listContainedUtIDs ;;
		run)    directUT_runTestCases "$1" ;;
		debug)  directUT_runTestCases "--debug" "$1" ;;
		*)      assertError -v cmd -v bgUnitTestScript "unkown cmd. expeting list run or debug"
	esac
}

function directUT_runTestCases()
{
	local debugFlag
	while [ $# -gt 0 ]; do case $1 in
		--debug) debugFlag="--debug" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local spec="$1"

	# load this ut_ function's source into an array
	local line i=1; while IFS= read -r line; do
		_utRun_srcCode[i++]="$line"
	done < "$bgUnitTestScript"

	# always run the testcases in the order found in the script (by bg_unitTests.awk)
	local count=0
	while read -r _utRun_srcLineStart _utRun_srcLineEnd utID _utRun_expect; do
		if [ "$spec" == "" ] || [[ "$utID" == $spec ]]; then
			((count++))
			[[ "$utID" =~ ^([^:]*):?(.*)?$ ]]
			local utFunc="ut_${BASH_REMATCH[1]}"
			local utParams="${BASH_REMATCH[2]}"
			utfRunner_execute $debugFlag "$bgUnitTestScript" "$utFunc" "$utParams"
		fi
	done < <(awk -v lineNumFlag='on' \
				 -v fullyQualyfied='' \
				 -v expectCommentsFlag='on' '
		@include "bg_unitTest.awk"
	' "$bgUnitTestScript")
}

function directUT_listContainedUtIDs()
{
	local fullyQualyfiedFlag
	while [ $# -gt 0 ]; do case $1 in
		-f|--fullyQualyfied) fullyQualyfiedFlag="--fullyQualyfied" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	awk -v fullyQualyfied="$fullyQualyfiedFlag" '@include "bg_unitTest.awk"' "$bgUnitTestScript"
}

function directUT_listContainedUtFuncs()
{
	awk -v cmd='getUtFuncs' '@include "bg_unitTest.awk"' "$bgUnitTestScript"
}

function directUT_listContainedUTParamsForUtFunc()
{
	local utFunc="$1"
	awk -v cmd='getUtParamsForUtFunc' -v utFunc="$utFunc" '@include "bg_unitTest.awk"' "$bgUnitTestScript"
}

# this is invoked by invokeOutOfBandSystem when -hb is the first param
# The bash completion script calls this get the list of possible words.
function oob_printBashCompletion()
{
	bgBCParse "" "$@"; set -- "${posWords[@]:1}"

	local cmd="$1"

	case $cmd:$posCwords in
		*:1) echo "run list debug"
			;;

		run:2|debug:2)
			local utID="$2"
			if [[ ! "$utID" =~ : ]]; then
				directUT_listContainedUtFuncs | sed 's/\>/:%3A/g'
			else
				[[ "$utID" =~ ^([^:]*):?(.*)?$ ]]
				local utFunc="ut_${BASH_REMATCH[1]}"
				local utParams="${BASH_REMATCH[2]}"
				echo "\$(cur:$utParams)"
				directUT_listContainedUTParamsForUtFunc "$utFunc"
			fi
			;;
	esac
	exit
}
