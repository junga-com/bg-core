
# Library bg_coreAssertError.sh
# This library provides the core assertError functionality and a set of assert* functions that relate to core library features.
# assertError stops the current subshell. If its subshell 0, it will exist the script. If its subshell 0 while sourced in a
# See Also:
#     assertError  : (core function) all assert* functions eventually call this if the assertion is false.
#     Try:/Catch:  : try / catch pattern to catch assertError calls
#     assertDefaultFormatter : (core function) formats the error msg or creates one from the context
#     assertLogicError : use when you want to assert that a algorithm path should never be reached and you would like to
#             know if it ever is.
#     assertEmpty / assertNotEmpty : assert that a variable is empty or not
#     assert(File|Folder|Path)[Not]Exists : assert the state of a file system object
#



##################################################################################################################
### Error Handling Functions
#
# assert* set of functions. asserting something means that if that thing is true, its fine, as expected and
# the script should just continue. If that thing is not true, however, the script should output an error message
# and exit.
#
# be aware that calling assert* (or exist directly) from a function that is called from a subshell will not exit
# the script, just the subshell. e.i foo="$(myFunctThatMightCallAnAssertFn "param")"
#




#function assertError() moved to bg_libCore.sh
#function assertDefaultFormatter() moved to bg_libCore.sh
#function Try() moved to bg_libCore.sh
#function Catch() moved to bg_libCore.sh




# usage: assertLogicError [<errorDescription>]
# a logic error is one that is rooted in the script logic rather than a run time environment condition
# For example, LOGIC ERROR: (( count1 < count2 )) || assertLogicError
#     In this example, the script author is checking that the alogorithm that resulted in these two variables
#     does not have a mistake. If count1 < count2 is not true, its because the author made a mistake in the
#     algorithm. The significant difference to the operator is that the problem is thought to be within the
#     script, not: not the environment.
# For example, RUNTIME ERROR: assertFileExists "myFile"
#     This says that the script would get past this point if only that file existed. The operator may be
#     able to tell why it does not, fix it and re-run the script.
function assertLogicError()
{
	# collect the context of the error
	local -A stackFrame=(); bgStackFrameGet +1  stackFrame
	local context="$(gawk '
		NR>=('"${stackFrame[cmdLineNo]}"'-7) {printf("%4s: %s\n", NR, $0)}
		NR>=('"${stackFrame[cmdLineNo]}"'+2) {exit}
	' < "${stackFrame[cmdFile]}")"

	# include the stack trace even if tracing is not turned on
	bgtraceTurnOn -n /dev/stdout
	assertError -v LogicError -v context "$@"
}


# usage: assertValidFilename [-i <invalidChars>] "varToTest" "error description to display if it fails"
# this displays a standard error format and exits the script
# assert that the specified variable contains a valid filename string. It could refer to a file or folder
# and does not need to exist. The main criteria is that it does not contain an invalid character like "\n".
# the set of invalid chars can be set with the -i option.
# This may be more restrictive than the OS allows. i.e. it might be technically possible to have a filename
# with a "\n" but typical good coding should not permit that.
function assertValidFilename()
{
	local invalidChars=$'\n'
	while [[ "$1" =~ ^- ]]; do case $1 in
		-i) bgOptionGetOpt val: invalidChars "$@" && shift ;;
	esac; shift; done

	if [ ! "${!1}" ] || [[ "${!1}" =~ [$invalidChars] ]]; then
		local varName="$1"
		local varValue="${!1}"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the variable '$varName'='$varValue' should be a valid filename but is not}"
		assertError -e39 "$msg"
	fi
}

# usage: assertPathExists <pathToTest> "error description to display if it fails"
# assert that <pathToTest> exists as any file system entity
function assertPathExists()
{
	if [ ! -e "$1" ]; then
		local filename="$1"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the file '$filename' should exit}"
		assertError -e38 "$msg"
	fi
}

# usage: assertPathNotExists <pathToTest> "error description to display if it fails"
# assert that <pathToTest> does not exist as any file system entity
function assertPathNotExists()
{
	if [ -e "$1" ]; then
		local filename="$1"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the file '$filename' should not exist}"
		assertError -e38 "$msg"
	fi
}


# usage: assertFileExists <fileToTest> "error description to display if it fails"
# assert that <fileToTest> exists and is a regular file
function assertFileExists()
{
	if [[ ! "$1" =~ ^((/dev/fd/[0-9]*)|(-))$ ]] && [ ! -f "$1" ]; then
		local filename="$1"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the file '$filename' should exist as a regular file}"
		assertError -e37 "$msg"
	fi
}

# usage: assertFileNotExists <fileToTest> "error description to display if it fails"
# assert that <fileToTest> is not a reqular file. It passes if it exists as a different
# file system object
# NOTE: many times assertPathNotExists is what you really want instead of this
function assertFileNotExists()
{
	if [ -f "$1" ]; then
		local filename="$1"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the file '$filename' should not be a reqular file}"
		assertError -e38 "$msg"
	fi
}

# usage: assertFolderExists folderToTest "error description to display if it fails"
# assert that folderToTest exists and is type folder
function assertFolderExists()
{
	if [ ! -d "$1" ]; then
		local foldername="$1"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the folder '$foldername' should be a folder}"
		assertError -e37 "$msg"
	fi
}

# usage: assertFolderNotExists folderToTest "error description to display if it fails"
# assert that folderToTest is not a folder. It passes if it exists as a file
# NOTE: many times assertPathNotExists is what you really want instead of this
function assertFolderNotExists()
{
	if [ -d "$1" ]; then
		local foldername="$1"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the folder '$foldername' should not be a folder}"
		assertError -e38 "$msg"
	fi
}


# function assertNotEmpty() moved to bg_libCore.sh

# usage: assertNotEmpty2 "$valueToTest" "error description to display if it fails"
# assert that $valueToTest is not empty
# Note! the difference between assertNotEmpty and assertNotEmpty2 is whether the parameter to test
#       is passed by reference or by value
function assertNotEmpty2()
{
	if [ ! "$1" ]; then
		shift
		local msg="$@"
		msg="${msg:-the tested variable should not be empty}"
		assertError -e39 "$msg"
	fi
}

# usage: assertEmpty "varToTest" "error description to display if it fails"
# assert that the the specified variable is empty
# Note! You pass the name of the variable, not its value i.e. without the '$'
# this displays a standard error format and exits the script
function assertEmpty()
{
	if [ "${!1}" ]; then
		local varName="$1"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the variable '${varName}(${!varName})' should be empty}"
		assertError -e39 "$msg"
	fi
}

# usage: assertEmpty2 "$valueToTest" "error description to display if it fails"
# assert that $valueToTest is  empty
# Note! the difference between assertEmpty and assertEmpty2 is whether the parameter to test
#       is passed by reference or by value
function assertEmpty2()
{
	if [ "$1" ]; then
		shift
		local msg="$@"
		msg="${msg:-the tested variable should be empty}"
		assertError -e39 "$msg"
	fi
}



# usage: assertNoBashSpecialChars "varToTest" "error description to display if it fails"
# assert that the specified variable does not contain any bash special characters
# this may be used to varify that a var safely contains a valid variable name and
# not malicious code
# Note! You pass the name of the variable, not its value i.e. without the '$'
# this displays a standard error format and exits the script
function assertNoBashSpecialChars()
{
	if [ "${!1}" ] && [ "${!1}" != "$(printf "%q" "${!1}")" ]; then
		local varName="$1"
		[ "$1" ] && shift
		local msg="$@"
		msg="${msg:-the variable '${varName}(${!varName})' should not contain special bash characters}"
		assertError -e40 "$msg"
	fi
}
