
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

# This is called from the DEBUG trap while running test case functions. global (set +T) is turned off and only the utFunc will
# have the -t attribute set so only the commands in that function will get the trap called.
# The purpose is to print the source line to stdout just before it is executed and posibly write output to stdout.
# The trap is called per simple command instead of by line so we read the function source from its script file. In the trap we know
# the source lineno so we use that to identify the line to print and suppress printing the same line multiple times in a row.
function _utfRunner_debugTrap()
{
	[[ "$BASH_COMMAND" =~ ^[$]utFunc ]] && return 0
	[ "$BASH_COMMAND" == "builtin trap - DEBUG" ] && return 0
	[[ "$BASH_COMMAND" =~ ^ut\  ]] && return 0

	if [ ${#_utfRunner_debugTrapData[@]} -eq 0 ]; then
		declare -g _utfRunner_debugTrapData=()
		declare -g _utfRunner_debugTrapStart=""
		declare -g _utfRunner_debugTrapCurrent=0
		while read -r line; do
			if [ ! "$_utfRunner_debugTrapStart" ]; then
				_utfRunner_debugTrapStart="$line"
			else
				_utfRunner_debugTrapData+=("$line")
			fi
		done < <(awk '
			!inFunc && $1=="function" && $2=="'"$utFunc"'()" {
				linestart=FNR
				print linestart
			}
			!inFunc && $1=="'"$utFunc"'()" {
				linestart=FNR
				print linestart
			}
			linestart {print $0}
			linestart && /^}/ {linestart=0; exit}

		' $bgUnitTestScript)
	fi

	if [ ${_utfRunner_debugTrapCurrent:-0} -ne ${bgBASH_debugTrapLINENO:-0} ]; then
		_utfRunner_debugTrapCurrent="$bgBASH_debugTrapLINENO"
		local lineIndex=$(($bgBASH_debugTrapLINENO-$_utfRunner_debugTrapStart))
		if (( 0 < lineIndex && lineIndex < _utfRunner_debugTrapStart+${#_utfRunner_debugTrapData[@]} )); then
			printf "cmd> %s\n" "${_utfRunner_debugTrapData[$lineIndex]}"
		# else
		# 	printfVars -l"!!! index for source array is out of bounds " lineIndex _utfRunner_debugTrapStart bgBASH_debugTrapLINENO -l"scr array size=${#_utfRunner_debugTrapData[@]}" _utfRunner_debugTrapData
		fi
	fi
}

# this is the function that implements the "ut setup|test" syntax in test cases
function ut()
{
	[ ! "$stdoutFD" ] && assertError "ut called outside of a unit test run"

	# flush the setup file to stdout if it exists because we are changing sections
	sync
	[ -s "$setupOut" ] && awk '{printf("##     | %s\n", $0)}' $setupOut >&$stdoutFD
	truncate -s0 "$setupOut"

	if [ "$1" == "exitCaught" ]; then
		printf "!!! test case is exiting prematurely code=%s\n" "$2"
		exec >&$stdoutFD
		return 0
	else
		{
			echo
			echo "###############################################################################################################################"
			echo "## $*"
		}
	fi >&$stdoutFD

	if [ "$1" == "setup" ]; then
		exec >&$setupOutFD
	elif [ "$1" == "test" ]; then
		exec >&$stdoutFD
	else
		assertError -v directive:"$1" "unknown ut <directive> in testcase"
	fi
}

# usage: utfRunner_execute <utFunc> <utParams>
# execute one test case which sould already be loaded (aka sourced, aka imported) into the bash process.
# The output will go to stdout.
function utfRunner_execute()
{
	local utFunc="ut_${1#ut_}"; shift

	[ "$(type -t "$utFunc")" == "function" ] || assertError -v utFile -v utFunc -v utParams "the unit test function is not defined in the unit test file"
	varIsA array "$utFunc"                   || assertError -v utFile -v utFunc -v utParams "the unit test file does not define an array variable with the same name as the function to hold the utParams."
	local -n inputArray="$utFunc"
	[ "${inputArray[$utParams]+exists}" ]    || assertError -v utFile -v utFunc -v utParams "utParams is not a key the in the array variable with the same name as the function. It should be a key whose value is the parameter string to invoke the test function with"

	bgmktemp setupOut

	while [ $# -gt 0 ]; do
		local utParams="$1"; shift
		local params=(); utUnEsc params ${inputArray[$utParams]}

		(
			exec {setupOutFD}>$setupOut
			exec {stdoutFD}>&1

			builtin trap 'exitCode="$?"; [ "$normExit" ] || { ut exitCaught "$exitCode"; exit 0; }' EXIT

			# turn off DEBUG trap globally with set +T and then turn it on just for the utFunc function
			set +T; declare -ft "$utFunc"; builtin trap 'bgBASH_debugTrapLINENO=$LINENO; _utfRunner_debugTrap' DEBUG
			Try:
				$utFunc "${params[@]}"
			Catch: && {
				exec >&$stdoutFD
				printf "** Exception thrown by testcase **\n"
				catch_errorDescription="${catch_errorDescription##$'\n'}"
				printfVars "   " ${!catch_*}

			}
			builtin trap - DEBUG
			normExit="1"
		)
		local result="$?"
		# exits are caught and suppressed in the EXIT trap but just in case...
		[ ${result:-0} -ne 0 ] && printf "!!! UNIT TEST FRAMEWORK ERROR test case ended with exit code (%s)\n" "$result"
	done

	bgmktemp --release setupOut
}
















##################################################################################################################################
### Direct Execution Code

# the rest of this file is only included if the ut script is being directly executed
[ "$bgUnitTestMode" == "utRuntime" ] && return 0

# man(1) bg-unitTestScriptName.ut
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
	local projectFolder="${0%unitTests*}"
	[ "$projectFolder" ] && cd "$projectFolder"

	# the default action is to list the test cases contained in the ut script
	[ $# -eq 0 ] && set -- list

	local spec="$1"; shift
	case ${spec} in
	  runAll)
		for utFunc in "${!ut_*}"; do
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
	for utFunc in "${!ut_*}"; do
		local -n inputArray="$utFunc"
		[ "$(type -t "$utFunc")" != "function" ] && assertError "malformed unit test. '$utFunc' should be a function name as well as the input array name"

		local utParams; for utParams in "${!inputArray[@]}"; do
			echo "${utFunc#ut_}:$utParams"
		done
	done
}

function directUT_listLoadedUTFunc()
{
	for utFunc in "${!ut_*}"; do
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
