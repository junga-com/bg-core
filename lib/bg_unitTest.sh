

# Library
# FUNCMAN_NO_FUNCTION_LIST
# usage: #!/usr/bin/env bg-utRunner
#        # import script libraries as needed
#        # define one or more ut_* functions
#        function ut_myTest() { ...}
# This is a bash script library that implements a unit test script system.
# Unit test scripts are simple bash scripts that follow a minimal pattern. They can be invoked directly from the command line or
# within the unit test framework provided by the `bg-dev` package. They get bash command line completion support automatically. The
# command line syntax allows listing the testcase names contained within, running a specific testcase, or lauching the debugger
# stopped at the first line of a specific testcase.
#
# Writing a testcase is no harder than writing a one-off test script. A unit test script contains one or more functions and the
# command line arguments allow you to select which function will run and with what arguments.
#
# These test scripts can be used to test not only bash script libraries and commands, but also the output and effects of any cli
# program written in any language. The premise of the system is that the testcase produces output on stdout, stderr, and the
# exit codes of the commands it runs. If that output matches what is saved in the project for that testcase, it passes and if not,
# it fails. When a testcase fails, it is either because a bug was introduced that changed the target code's behavior, or the behavior
# of the target code was changed on purpose, in which case the saved output would be updated to reflect the new expected behavior.
# The change history of the saved output documents how the expected behavior changes over the lifetime of the code.
#
# Creating a Unit Test Script:
#    1) create a script file using these naming conventions.
#       * end in the .ut extension. This tells the bash completion loader provided by bg-core to enable BC.
#       * place the file in a project's ./unitTests/ folder. This allows it to participate in the project's unit testing.
#       * by convention, use the name of the library that it will test. e.g. unitTests/bg_coreStack.sh.ut contains tests for bg_coreStack.sh
#    2) make the file executable (chmode a+x uitTests/<file>.ut)
#    3) put this text on the file's first line "#!/usr/bin/env bg-utRunner"
#    4) define one or more testcase Functions starting with ut_
#
# Now you can invoke the test script from the command line, using <tab><tab> to have bash completion lead you through composing the
# command line.  Running directly from the command line sends the normalized output of a testcase to stdout so that you can
# quickly develop and debug each testcase. It does not tell you if the testcase passes or fails.
#
# You can also run the testcases from the project's unit test system.
#    `bg-dev tests run <fileNameWith_.ut_removed>[:<testcaseName>]`
# The first time you run the new script, the state of its testcases will be "unintialized". Run ...
#    `bg-dev tests show <fileNameWith_.ut_removed>[:<testcaseName>]`
#  ...to open a comparison application (default is `meld`) which allows you to create the expected data (aka 'plato' data). Creating
# the plato data is documenting the expected behavior of the target code being tested so make sure that you review the output of the
# new tests carefully. If its a work-in-progress, edit the plato data to either be the exact output that it should eventually be, or
# just type a note explaining what the output should be in the future. As long as the plato data is not a match to the actual output,
# the testcase will report as being in the failed state, indicating that work needs to be done before the target code and testcase
# are finished.
#
#
# Creating Testcases:
# A unit test script can have multiple, independent testcase functions and for each function can specify multiple command lines
# to invoke the function with. Each (function + arguments) command line is a unique testcase that run independently of other test
# cases.
#
# **Testcase Functions** : Any function defined in the file that starts with ut_* is a testcase function. By default the test
# case function produces one testcase that invokes the function with no arguments.
#    function ut_myTest() {
#       echo "hello word"
#    }
#
# **Testcase Arguments** : Optionally, a bash array variable can be defined with the same name as the unit test function. Each
# array entry in that variable will become a unique testcase that invokes the corresponding testcase function with the arguments
# defined in that entry's value. Each space separated token in the value will be passed as a separate argument. Arguments with
# spaces or are empty, or contain other special characters can be escaped using the convention described in
# `man(3) strEscapeToToken`. A conventient way to do that is with the syntax `$(cmdline "arg 1" "my secound arg" ...)`.
#
# Note that if the array variable is defined, a testcase with empty arguments will no longer be defined automatically but you can
# create such a testcase by including an array element with an empty value.
#
# The index of the array elements will become part of the testcase name. If the variable is a numeric (-a) array, the indexes will
# only be numbers. If you make it an associative array (-A), you can use descriptive names to distinguish the testcases that all
# use the same testcase function.
#
# Its good practice to explicitly name the indexes even when its a numeric array because its best if each testcase has a persistent
# name that will not change if you insert a new testcase above it in the list.
#     ut_myTest=(
#        [0]=""
#        [1]="$(cmdline "this and that" "second Arg")"
#     )
#  ... or ...
#     declare -A ut_myTest=(
#        [defaultArgs]=""
#        [somethingCool]="$(cmdline "this and that" "second Arg")"
#     )
#
# **Testcase Names** : Each testcase has a name derived from the file that its in, the testcase function and the array index of
# the element that defines the arguments to the testcase function.
#      <utFile*>:<utFunction*>:<utCmdlineName>
# '*' note that  <utFile> and <utFunction> have the trailing '.ut' and leading 'ut_' removed to make the names a little shorter and
# clearer.
#
#
# Output of a Testcase:
# Inside the testcase function, you can put any code. It can invoke external commands or bash functions. It can import bash
# libraries as needed.
#
# The purpose of the testcase is to invoke some target code that the testcase professes to test and produce output that indicates
# what that target code did. Typically, the testcase function does not try to tell if the output is correct or not. Instead, the
# correct behavior is documented in the testcase's plato data saved in the project.
#
# The testcase output is derived from what it writes to stdout and stderr, the exit code of each command called directly by from
# the testcase function, and whether it ends normally or exits its process (possibly by calling an assert* function).
#
# The execution of the direct code in the testcase function is monitored by a DEBUG trap which anotates the output. Each command
# is echoed to stdout so that the arguments passed to it becomes part of the output. This also makes it easier to read the output
# and determine what has happened. Its kind of like a captured terminal session. The goal should be that someone can read the test
# case output and know what output is expected from the target code being excercised. You can suppress printing the command by
# appending it with the comment ` #noecho`
#
# Sometimes the expected output of the code being tested will vary from run to run. For example, if the output conatians the PID
# of the running process. In this case, you can define a filter, either in a specific testcase or for a group of testcases that
# will match and 'redact' that output. The `ut filter ...` directive will be described in a later section.
#
# Testcase States:
# When executed under the `bg-dev tests ...` framework, each executed testcase will end in one of four states -- pass, fail,
# unitializaed or error.
#  * pass: means that the aggregate output is what we expect
#  * fail: means that the aggregate output is not what we expect
#  * unitializaed : means that the expected behavior has not yet be documented
#  * error: means that the testcase ran into a problem that prevented it from completing so the output should not be considered.
#           The error is typically in the behavior of code used in a setup section of the testcase so this state does not say
#           anything about whether the target code has an error. In fact, the more likely interpretation is that the testcase would
#           have passed if not for a prerequisite problem.
#
# The `bg-dev tests` system maintains '.plato' files for each unit test script file. These files contain the expected output and
# comparing the actual output of each testcase with its corresponding section in the '.plato' file is what determines whether the
# testcase passes or fails. The text does not have to be exact. Only differences in uncommented lines are considered important
# which allows us to update the comments in the testcases without causing them to fail.
#
# 'bg-dev tests show ...' will open a comparison application to show you differences if any between the plato data and the actual
# output of the last run. If there are differences, you need to decide if the new output of the testcase is now correct and update
# the plato data to match, or if the new output is incorrect and the code needs to change so that it is correct again.
#
# Note that even though the spirit of this system is to have the testcase just reveal the bevaior of the target code and to document
# the correct behavior in the plato data, there may be times when its more efficient to algoithmically determine pass/fail. In this
# case, a testcase could simply output 'pass' or 'fail' and the plato data would be set to 'pass'.
#
# If a project already has a unit test framework that can be invoked from the command line, you could integrate it into the bg-dev
# tests framework by creating a testcase that invokes the other system and setting the plato data to indicate the expected output
# of that system when the tests it performs all pass.
#
# Running Testcases directly:
# When developing code and testcases it is convenient to run testcases directly without the framework getting between you and
# the direct output. Unit test scripts use the bg-utRunner interpretter line to make them indepentently runnable. They automatically
# support bash command line completion to make it easy to run withoutout looking up the syntax or remembering the exact testcase
# name you want to run.
# **Syntax**
#    <utFile> list
#    <utFile> run <testcaseName>
#    <utFile> debug <testcaseName>
#
# The idea is that writing a unit test script should be no harder than writing the simplest of one off test scripts to excercise
# some code you are working on so it encourages you to test your code during development in a way that is repeatable and participates
# in the ongoing software development lifecycle of the project.
#
# When ran this way, the output that would be compared to the plato data is just written to stdout without comparing it to plato
# or trying to determine if it passes. If you want to know if it passes, run it with `bg-dev tests ...`.
#
# The debug sub command launches the debugger stopped at the start of the specified testcase. Otherwise you would have to step
# through the unit test runner code to get there.
#
# It is anticipated that an IDE could use the direct run feature to show the output in various ways to achieve a tighter workflow.
#
# UT Directives:
# The body of a testcase function can contain testcase directives that start with `ut ...`.
#
# **ut setup [noecho|echo] [noexitcodes|exitcodes] [normWhitespace]**
# ** ut test [noecho|echo] [noexitcodes|exitcodes] [normWhitespace]**
# All code in the testcase function is either in a setup section or a test section. The default is 'test' when the function starts.
# The directive `ut setup` switches to 'setup' and `ut test` switches to 'test'.
#
# The code in a setup section is not part of the test and its output will all be commented so that it wont be part of determining
# pass or fail. Also, if it writes to stderr or any direct command returns non-zero, the testcase will stop and its state will be
# 'error'. That same behavior in a 'test' section is perfectly fine and just becomes part of the output.
#
# You can switch back and forth between setup and test sections as much as you want and having multiple setup/test sections can be
# useful to separate logical parts of the test.
#
# setup sections typically create the environment needed to run the target code.
#
# **ut expect "..."**
# The expect directive is a comment with the specific intention to tell the reader what to expect in the output that follows.
#
# **ut filter '<matchRegEx>[###<replaceText>]'**
# When the code being tested has output that changes with each run, a filter can be used to 'redact' that output so that the output
# will be stable and not change each time its run. Changing output would not work in this system because it would never match the
# plato data. The filter is applied to the final output before its compared to the plato file. When ran directly filters are not
# applied to the output to the terminal.
#    <matchRegEx> uses the syntax supported by gawk.
#    <replaceText> may refere to capture groups from <matchRegEx> like '\1'. The default value for <replaceText> is "redacted".
#     example: ut filter 'heap_([^_]*)_([^_ ]*)###heap_\1_<redacted>' changes heap_Ar_87ABC to heap_Ar_<redacted>
#
# There are some builtin, global filters that match names of temorary files created with mktemp and heap variables used in the bash
# object library.
#
# An alternative to using the filter directive would be to capture the output to a string, algorithmically test to see it it is what
# you expect and then write output indicating if it passed your test or not.
#
# **ut noecho** and **ut echo**
# These directives turn on and off the feature that echos the testcase commands to the output.
# While echoing is off, a single command can be echoed by appending the line comment ` #echo`.
# Likewise, while echoing is on, a single command's echo can be suppressed by appending the line comment ` #noecho`
#
# ** ut normWhitespace**
# use a filter on the output that normalizes runs of spaces and tabs to a single space so that runs that vary only in indenting will
# continue to pass
#
# Example Testcase using some directives...
#    function ut_testMyTargetFunction() {
#       ut setup
#       local p1="$1"
#       local p2="$2"
#       prinftVars p1 p2
#
#       ut test
#       ut expect "the first output to come before the last output and all M&Ms to be only green"
#       myTargetFunction "$p1" "$p2"
#    }
# In the setup section, printing the p1 and p2 variables will produce commented output that wont influence whether the testcase
# passes or fails but it serves to make the output easier to read and understand. The reader can more easily see that if the
# output of myTargetFunction makes sense because they see the values of the arguments sent to it.
#
#
# See Also:
#    man(1) bg-unitTest.ut
#    man(1) bg-dev-tests

# bgUnitTestMode=utRuntime|direct
declare -g bgUnitTestMode="utRuntime"; [[ "$bgLibExecCmd" =~ ([.]ut)|(bg-utRunner)$ ]] && bgUnitTestMode="direct"

declare -g bgUnitTestScript
[ ! "$bgUnitTestScript" ] && for _uttmpSrcname in "${BASH_SOURCE[@]}"; do
	if [[ "$_uttmpSrcname" =~ [.]ut$ ]]; then
		bgUnitTestScript="$_uttmpSrcname"
		break
	fi
done
assertNotEmpty bgUnitTestScript



##################################################################################################################################
### Common Section
# the functions defined in this section are always included so that they are available regardless of whether the ut script is
# executed directly or sourced by the unit test framework


# usage: ut <event> ...
# The ut function monitors and manages the state of the running testcase. The testcase author calls it to signal entering 'setup'
# and 'test' sections that change the way the output of commands are written and the way that the exit codes are handled. The author
# can go back and forth between setup and test section as many times as they want for example to include several logical tests in
# one function.
#
# Also, the utf calls this function to signals various events in the testcase run.
#
# ut setup [noecho] [noexitcodes] [normWhitespace]:
# Used when writing testcases to signal that the follow code is setup and not the taget of the testcase. The output of setup code
# is not significant for determining if the testcase passes. Also, if any setup code exits with non-zero or writes to stderr,
# the testcase will terminate and be considered not elgible for running because its setup is failing.
#
# ut test [noecho] [noexitcodes] [normWhitespace]:
# Used when writing testcases to signal that the follow code is the target of the testcase that is being tested. There is nothing
# that test code can do that is considered wrong. All actions from writing to stderr, to having a command that exits non-zero, to
# exiting the function prematurely (with exit; or assert*) will produce output in the testcase's stdout stream which will be compared
# to the 'plato' output. If its identical, then the testcase passes and if not it fails.
#
# Internal Cmds:
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
	# if the last command produced stderr output, flush it
	if [ -s "$errOut" ]; then
		sync
		cat "$errOut" | awk '{printf("stderr> %s\n", $0)}'
		truncate -s0 "$errOut"
		[ "$_utRun_section" == "setup" ] && ut setupFailed
	fi

	local event="$1"; shift
	case $event in
	  setup)
		echo >&$stdoutFD
		echo "##----------" >&$stdoutFD
		echo "## $event" >&$stdoutFD
		_utRun_section="$event"
		exec >&$setupOutFD

		# this allows combining some directives with the setup like
		#     ut setup noecho noexitcodes
		while [ $# -gt 0 ]; do
			ut "$1"; shift
		done
		;;

	  test)
		exec >&$stdoutFD
		_ut_flushSetupFile
		echo >&$stdoutFD
		echo "##----------" >&$stdoutFD
		echo "## $event" >&$stdoutFD
		_utRun_section="$event"

		# this allows combining some directives with the test like
		#     ut test noecho noexitcodes
		while [ $# -gt 0 ]; do
			ut "$1"; shift
		done
		;;

	  expect|expect:)
		_ut_flushLineInfo
		echo
		echo "# expect $*"
		;;

	  expectSetupFail) _utRun_expectSetupFail="1" ;;

	  filter)
		[ "$_utRun_section" == "setup" ] || assertError "ut filter statements must be placed inside the ut setup section"
		printf "ut filter '%s'\n" "$1"
		;;

	  echo)   utEchoOff="" ;;
	  noecho) utEchoOff="noecho" ;;
	  exitcodes)   utExitCodesOff="" ;;
	  noexitcodes) utExitCodesOff="noexitcodes" ;;
	  normWhitespace)  printf "ut filter '%s'\n" "[ \t]+### " ;;

	  onBeforeSrcLine)
		local lineNo="$1"
		local srcLine="$2"
		# print the  source line that we are about to start executing so that its output will appear after it
		local trimmedLine="${srcLine#[]}"; stringTrim -i trimmedLine
		if [ ! "$utEchoOff" ]; then
			[[ ! "$srcLine" =~ [#][[:space:]]*noecho ]] && printf "cmd> %s\n" "${trimmedLine}"
		else
			[[   "$srcLine" =~ [#][[:space:]]*echo   ]] && printf "cmd> %s\n" "${trimmedLine}"
		fi
		true
		;;

	  onAfterSrcLine)
		local lineNo="$1"
		local srcLine="$2"
		_ut_flushLineInfo
		;;

	  onCmdErrCode)
		# we get the cmd that produced a non-zero code in $2 but we dont display it b/c when the testcase invokes a function that
		# returns non-zero, the last cmd is the last cmd in the function. That is confusing to the output because it does not match
		# the cmd that the testcase ran.
		[ ! "$utExitCodesOff" ] && _utRun_lineInfo+="[exitCode $1]"
		[ "$_utRun_section" == "setup" ] && ut setupFailed
		;;


	  onStart)
		local utID="$1"; shift
		exec {setupOutFD}>$setupOut
		exec {stdoutFD}>&1
		exec {errOutFD}>$errOut
		exec 2>&$errOutFD

		# set an EXIT trap to detect when the testcase ends prematurely
		trap -n unitTests 'exitCode="$?"
			ut onExitCaught "$exitCode"
			exit $?' EXIT

		# make sure ERR trap is not set to inherit. The first time the DEBUG trap fires from inside the target ut_ function, we
		# will set the ERR trap there
		set +E;

		# if not debugging the testcase, set it so that the DEBUG trap will only get called while in the $utFunc to improve performance
		if [ ! "$_utRun_debugFlag" ]; then
			# turn off DEBUG trap inheritance globally with set +T and then turn it on just for the utFunc function
			# DEBUG will fire for the remainder of this call of 'ut' but the next time 'ut' is called, it wont.
			set +T
			declare -ft "$utFunc"
		fi
		builtin trap 'bgBASH_debugTrapExitCode=$?; bgBASH_debugTrapLINENO=$LINENO; bgBASH_debugTrapFUNCNAME=$FUNCNAME;  _ut_debugTrap' DEBUG
		_utRun_debugHandlerHack="1" # this tells the debugger's DEBUG handler to call _ut_debugTrap

		echo >&$stdoutFD
		echo "###############################################################################################################################" >&$stdoutFD
		echo "## $_utRun_id start" >&$stdoutFD
		echo "## expect: $_utRun_expect" >&$stdoutFD


		;;

	  onFirstTimeInsideUTFunc)
		# set an ERR trap to monitor non-zero exit codes. This has to be set from this event in order to be effective
		trap -n unitTests '[ "$FUNCNAME" == "$_utRun_funcName" ] && ut onCmdErrCode "$bgBASH_trapStkFrm_exitCode" "$bgBASH_trapStkFrm_lastCMD"' ERR
		_utRun_errHandlerHack="$(builtin trap -p ERR)"

		if [ "$_utRun_debugFlag" ]; then
			type -t debuggerOn &>/dev/null || import bg_debugger.sh ;$L1;$L2
			_debugSetTrap --logicalStart+${logicalFrameStart:-1}
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
		#catch_errorDescription="${catch_errorDescription##$'\n'}"
		#printfVars "   " ${!catch_*}
		printfVars "   " catch_errorClass catch_errorFn catch_errorCode catch_errorDescription
		if [ "$_utRun_section" == "setup" ]; then
			[ "$_utRun_expectSetupFail"  ] || printfVars catch_stkArray catch_psTree
		 	ut setupFailed;
		fi
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
	#bgtrace "_ut_debugTrap: $bgBASH_debugTrapFUNCNAME | $BASH_COMMAND"

	# we are only interested in DEBUG traps for the target ut_ function but its not possible to turn it on only for it so filter out
	# the other calls.
	if [[ "$bgBASH_debugTrapFUNCNAME" != ut_* ]] || [ "$bgBASH_trapStkFrm_signal" ]; then
		return 0
	fi

	# when BASH invokes a function, the DEBUG trap is called once in the begining of a function call with the stack set to the
	# openning { of the function and with the BASH_COMMAND set to the command that invoked it
	# We create this onFirstTimeInsideUTFunc because the ERR trap can only be set from that time.
	[[ "$BASH_COMMAND" == '$utFunc '* ]] && {
		ut onFirstTimeInsideUTFunc;
		return 0;
	}

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
#                   The <utFileID> component of the utID is created by removing the leading folders and the trailing .ut
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

	local utFileID="${utFilePath##*/}"; utFileID="${utFileID%.ut}"
	local utID="${utFileID}:${utFunc#ut_}:$utParams"

	# import script if needed and validate that the utFunc exists
	if [ ! "$(type -t "$utFunc")" == "function" ] && [ "$bgUnitTestMode" != "direct" ]; then
		import "$utFilePath" ;$L1;$L2
	fi
	[ "$(type -t "$utFunc")" == "function" ] || assertError -v utFileID -v utFunc -v utParams "the unit test function is not defined in the unit test file"

	# if utParams is emptyString, invoke with no params. If its '...' use the arguments passed in to this function by the caller,
	# Otherwise, utParams is the index (aka map key) of the array of cmdline arguments with the same name as the utFunc
	local params=()
	if [ "$utParams" == "..." ]; then
		params=("$@")
	elif [ "$utParams" ]; then
		varIsA array "$utFunc"                   || assertError -v utFileID -v utFunc -v utParams "the unit test file does not define an array variable with the same name as the function to hold the utParams."
		local -n inputArray="$utFunc"
		[ "${inputArray[$utParams]+exists}" ]    || assertError -v utFileID -v utFunc -v utParams "utParams is not a key the in the array variable with the same name as the function. It should be a key whose value is the parameter string to invoke the test function with"
		# for each utParams passed in, run the testcase function
		utUnEsc params ${inputArray[$utParams]}
	fi

	# these are the state variables of the unit test run. the ut function and trap handlers and all their helper functions
	# will treat these as their member state variables. Some of them that require work to set will use the value defined in the
	# caller's scope if they exist. Notice that when declaring a variable local and seting it from itself, the initializer is the
	# variable from the parent's scope b/c its not yet a local variable.
	local _utRun_id="$utID"
	local _utRun_funcName="$utFunc"
	#local _utRun_srcCode=("${_utRun_srcLineEnd[@]}")  # maybe we dont need to copy the src file array? just comment out this line
	local _utRun_srcLineStart=${_utRun_srcLineStart:-0}
	local _utRun_expect="${_utRun_expect}"
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
	[ ${_utRun_srcLineStart:-0} -eq 0 ] && for ((i=1; i<=${#_utRun_srcCode[@]}; i++)); do
		if [ $_utRun_srcLineStart -eq 0 ] && [[ ${_utRun_srcCode[i]} =~ ^[[:space:]]*(function)?[[:space:]]*$utFunc'()' ]]; then
			_utRun_srcLineStart=$i
		fi
		if [ $_utRun_srcLineStart -ne 0 ]; then
			if [[ "${_utRun_srcCode[i]}" =~ ^[[:space:]]*#[[:space:]]*expect ]]; then
				_utRun_expect="${_utRun_srcCode[i]#*expect[ :]}"
			fi
			if [[ ${_utRun_srcCode[i]} =~ ^} ]]; then
				_utRun_srcLineEnd=$i
				break;
			fi
		fi
	done
	[ ${_utRun_srcLineStart:-0} -lt ${_utRun_srcLineEnd:-0} ] || { assertError; }


	local setupOut; bgmktemp setupOut
	local errOut;   bgmktemp errOut

	if [ "$_utRun_debugFlag" ]; then
		type -t debuggerOn &>/dev/null || import bg_debugger.sh ;$L1;$L2
		# we need to start the debugger outside the subshell that we run the testcase in but we dont want to stop here
		debuggerOn "resume"
		bgDebuggerStepOverTraps="1"
	fi

	(
		# require an extra config to keep tracing on for tests because they can have many exceptions printing stack traces
		# when ran directly, bgTracingTestRunner is set to on so this only affects running from bg-dev tests ...
		# see bg-debugCntr trace tests:on|off
		[ "$bgTracingTestRunner" == "on" ] || [ "$_utRun_debugFlag" ] || {
			bgtraceCntr off
			bgAssertErrorInhibitTrace=1
		}

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
# usage: <bg-unitTestScriptName>.ut [list]
# usage: <bg-unitTestScriptName>.ut run <utID>
# usage: <bg-unitTestScriptName>.ut debug <utID>
# usage: <bg-unitTestScriptName>.ut run <testcaseFunction>:... [<p1>...<pN>]
# *.ut files are scripts containing test cases. This is the man page for all *.ut files.
# A ut script looks like a library but can also be executed as a stand alone command complete with bash command line completion.
# Each function in the script whose name starts with "ut_" will become a testcase function. A testcase function can produce multiple
# test cases, each with a different argument list. See man(7) bg_unitTest.ut.
#
# Unit Test Framework:
# The "bg-dev test ..." command sources and runs the test cases contained in *.ut files in a special way that redirect their
# output and determines if they pass or fail.
#
# Direct Execution:
# *.ut unit test scripts can be executed directly from the command line while developing. The utfDirectScriptRun function in bg_unitTest.sh
# provides this functionality. It supports command line completion so that the user can see how to run it and complete the utIDs
# contained in the script.
#
# When a test case is run via direct execution, it is meant for testing and development of the test case as opposed to running it
# under the unit test framework which records the results in the project. The output of the test case(s) goes to stdout so that it
# can be immediately examined.  Running a test case this way makes it easier to run in the debugger because its exceuption environment
# is more simple.
#
# A testcase function can be executed with arguments provided on the command line. Instead of specifying a complete testcase ID with
# the name of an argument list, "..." can be specified and then what ever arguments specified on the command line after it will be
# passed to the testcase function.
#
#
#
# <bg-unitTestScriptName>.ut [list]
#    print a list of the utIDs contained in this script. Each is a unique testcase that can be ran.
#
# <bg-unitTestScriptName>.ut run [<utID>]
# <bg-unitTestScriptName>.ut run <testcaseFunction>:... [<p1>...<pN>]
#    Run the specified testcase. If <utID> is empty, all testcases are ran. The ... syntax allows trying new aurgument lists on the
#    fly without adding a named argument list to the script for that testcase function  The output goes to stdout.
#
# <bg-unitTestScriptName>.ut debug [<utID>]
#    Run a specific utIDs and stop on the first line of the <utID> in the debugger.
#
# Params:
#    <utID> : A utID to run. It must be one that resides in this ut script. Use bash completion to fill it in. Use the 'list'
#             command to see a list of all of the utID contained in the script.
#             Syntax: <testcaseFunctionNameWithoutLeading "ut_">:<argListNameOr...>
# See Also:
#    man(7) bg_unitTest.ut
#    man(1) bg-dev-tests


#NO_FUNC_MAN
# this function is called at the end of every *.ut ut script and implements the direct execution stand alone command behavior of
# the test script.  It provides bash completion, querying to see what test cases are contained and stand alone running  of test cases.
function utfDirectScriptRun()
{
	invokeOutOfBandSystem "$@"

	# run unit tests from their project root folder no matter where the user ran the command from
	local projectFolder="${0%unitTests/*}"
	[ -d "$projectFolder" ] && cd "$projectFolder"

	# the default action is to list the test cases contained in the ut script
	local cmd="${1:-list}"; shift

	case $cmd in
		list)   directUT_listContainedUtIDs ;;
		run)    directUT_runTestCases "$@" ;;
		debug)  directUT_runTestCases "--debug" "$@" ;;
		*)      assertError -v cmd -v bgUnitTestScript "unkown cmd. expecting list run or debug"
	esac
}

function directUT_runTestCases()
{
	local debugFlag
	while [ $# -gt 0 ]; do case $1 in
		--debug) debugFlag="--debug" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local spec="$1"; shift

	# when running directly, we want to see any traces produced
	# see bg-debugCntr trace tests:on|off
	bgTracingTestRunner="on"

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
	done < <(gawk -v lineNumFlag='on' \
				 -v fullyQualyfied='' \
				 -v expectCommentsFlag='on' '
		@include "bg_unitTest.awk"
	' "$bgUnitTestScript")

	# allow the user to specific testcase arguments directly from the cmdline for testing.
	# usage: <testcaseName>:... [<p1>...<pN>]
	if [ ${count:-0} -eq 0 ] && [[ "$spec" =~ :...$ ]]; then
		((count++))
		local utFunc="ut_${spec%:...}"
		utfRunner_execute $debugFlag "$bgUnitTestScript" "$utFunc" "..." "$@"
	fi


	[ ${count:-0} -eq 0 ] && assertError -v spec "utID spec did not match any testcases"
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
