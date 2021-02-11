#!/bin/bash

import bg_template.sh ;$L1;$L2
import bg_cui.sh ;$L1;$L2

creqApplyLog="/var/log/creqs.log"

# Library
# The creq library provides a mechanism for declarative configuration and compliance. A creq class is a shell function or an
# external command that adheres to a protocal. The purpose of a creq class is to provide operations to check and apply a type of
# configuration on a host. A creq class is used in creq statements of the form '<creqClass> [<arg1>..<argN>]' which describes a
# specific, discrete unit of configuration. For example, a creq class could be "cr_fileExists" and creq statement of this class could
# be "cr_fileExists /etc/foo.conf". The check action of this statement would test [ -e /etc/foo.conf ] and the apply action would
# 'touch /etc/foo.conf'. (The actual cr_fileExists is a little more complicted. see man(3) cr_fileExists).
#
# The key behavior of a creq class is that whether it will only check and report on compliance or whether it will change the host
# to become complaint is not determined by the arguments sent to it but rather on the environment state in which it is executed.
# This is what makes it declarative. The creq statement describes something that should be. When it is executed in a 'check'
# environment it only returns pass/fail, but when exectued in an 'apply' environment and the check fails, it will attempt to change
# the host so that the check will pass.
#
# Creq Runners:
# A creq statement is executed with one of several creq runner commands.
#       `<creqRunner> <creqStatement>` (where <creqStatement> is `<creqClass> [<arg1>..<argN>]`)
# The runner ensures that the environment is set correctly and captures the output of the creq class execution to present it
# appropriately for the situation in which it is running.
#
#    creqCheck    : execute only the check operation in a stand alone environment passing output on to the caller.
#    bg-creqCheck : an external command wrapper over creqCheck so that statements can be executed from a terminal
#    creqApply    : execute the check operation and if it fails, execute the apply operation, all in a stand alone environment passing
#                   output on to the caller.
#    bg-creqApply : an external command wrapper over creqApply so that statements can be executed from a terminal
#    creq         : this runner must be used inside a pair of creqStartSession/creqEndSession calls which set the environment to either
#                   check or apply. The direct output of the creq class code is captured and contribute to the overall session output
#                   which is typically a report indicated the percentage of statements that end in the compliant state.
# The runners accept options before the <creqStatement>. See the manpage for each for details.
#
# Creq Profiles:
# A group of creq statements that are exectued together are called a creq profile. The bg-core package provides two types of creq
# profiles -- Standards plugins and Config plugins. See man(7) bg_plugins.sh.  Standards plugins will never be executed in apply
# mode because they only report compliance. Config plugins can be exectued in either mode. The reason that both exist is that when
# creating a Standards, the order of the statements do not matter and the statements do not have to be related in any way. A Config
# on the other hand must be written such that when the statements are applied in order, they will result in a descrete configuration
# goal being met. For example, you could create a linuxWebServerHardenning.Standards that checks many unrelated things on the host
# that are deemed necessary for the server to be secure but those things could be achieved in many different ways. The Standards
# does not know how you want to acheive those configuration goals.  Then you could create a companyWebSite.Config that handles
# installing a specific web server, retrieving the content and configuring the host it to serve the company web site. After the
# initial application of the companyWebSite.Config plugin, it can be executed again at any time to either check for or enforce
# that the server still complies with its configuration. You could activate both plugins on a host and the
# linuxWebServerHardenning.Standards will report whether the configuration acheived by the companyWebSite.Config complies with its
# standard.
#
# Nesting Creq:
# The creq mechanism is built so that lower level components can be reused to build higher level components however, a creq class
# (which, remember is a command or shell function) should not invoke other creq classes. Instead, nesting is performed in the creq
# profiles by using the cr_standardsActive and cr_configActive creq classes. Either a Standards or Config plugin can state that
# some other Standards or Config needs to be active. Being active implies that it must pass because any active profile will be
# reported on in the host's state and the implied goal is for all active Standards and Config to report 100% compliance.
#
# See Also:
#    man(3) DeclareCreqClass   : how to write creqClasses in bash
#    man(5) creqClassProtocal  : protocol for implementing creqClasses in other languages
#    man(7) Standards
#    man(7) Config


# man(5) creqClassProtocal:
# A creq class can be implemented as an external command written in any language. This library provides a shell function stub which
# allows a creqClass to be implemented easily in a bash script without having to deal with the protocol. It is expected that other
# language environments would implement a similar framework that would allow the check and apply algotithm of a new creqClass to be
# written without having to understand and comply with this protocol explicitly. This protocol description is intended for library
# writers in other languages who wish to support written creqClasses in those languages.
#
# Regardless of how its creq class is implemented, every creq statement is executed as one command exection exection of the creqClass
# command passing the arguments of the statement to the command.
#
# The creqClass command uses stdout and stderr according to the standard convention. General informative information is written to
# stdout and only if an error occurrs, an error message is written to stdout. The exit code should be 0 when no error occurrs.
# None of the the exit code, stdout and stderr output of the command determines the real outcome of an executed creqStatement. Only
# the output on file descriptor 3 (FD(3)) determines the output.
#
# It is mandatory that the creqClass command writes a message to its file descriptor number 3 (FD(3)) in the form...
#    `<resultState>[<whitespace><descriptionMsg>]`
# Where...
#    <resultState> : indicates the result of the creqStatment execution.
#       for creqAction='check', <resultState> must be one of (Pass|Fail|ErrorInCheck)
#       for creqAction='apply', <resultState> must be one of (Pass|Applied|ErrorInCheck|ErrorInApply)
#       If <resultState> is not one of the expected words it is set to "ErrorInProtocol" regardless of what was written.
#    <descriptionMsg> is an alternate one line decription of what happenned. The default <descriptionMsg> is the creqStatement itself.
#        this can provide a more human readable description like "the file <filename> exists" or "<filename> is missing as opposed
#        to 'cr_fileExists <filename>' for both Pass and Fail.
#
# By standard conventions, the exit code should be 0 when the <resultState> is (Pass|Fail|Applied) and should be non-zero if <resultState>
# is (ErrorInCheck|ErrorInApply|<other>) but that is redundant given the <resultState> written to FD(3) and the exit code is not used.
# It would be reasonable for a creqRunner to consider a missmatched <resultState> and exit code a protocol violation but at the time
# of this writing, none do.
#
# The creq runners that execute creqStatements use the environment to communicate input to the creqClass. At this time the ENV var
# `creqAction` is only input. creqAction will be set to 'apply' if it is being executed in apply mode. It may be set to 'check' if
# it is being executed in check mode but that is the default so as long as creqAction is not set to 'apply', the creqClass should
# executed in check mode.
#
# The creqClass must implement this psuedo algorithm where the 'check operation' and 'apply operation' are specific to the particular
# creqClass.
#    START
#    do check operation
#    if check operation ends abnormally (an exception)
#        write "ErrorInCheck", optional message text to FD(3) and exit
#    else if check operation returns true
#        write "Pass", optional message text to FD(3) and exit
#    else if creqAction ENV var is not "Apply"
#        write "Fail", optional message text to FD(3) and exit
#    else
#        do apply operation
#        if apply operation completes normally
#            write "Applied", optional message text to FD(3) and exit
#        else
#            write "ErrorInApply", optional message text to FD(3) and exit
#    END
#
# Depending on the creqRunner, the exit code, stdout and stderr output may or may not be used. In the following table, for each
# possible commbination of creqAction and FD(3), the resulting <resultState> is shown and also the convention for exit code, stdout
# and stderr output even though there is no requirement that exitCode, stdout and stderr have any particular values/content.
#
# creqAction  FD(3) output             | <resultState>   exitCode     stdout      stderr
# ----------  ------------------------ | -------------   -----------  ----------  ------------
# check       "ErrorInCheck "          | ErrorInCheck    <errorCode>  <anything>  <error msg>
# apply       "ErrorInCheck "          | ErrorInCheck    <errorCode>  <anything>  <error msg>
# check       "Pass <msg text...>"     | Pass             0           <anything>  <empty>
# apply       "Pass <msg text...>"     | Pass             0           <anything>  <empty>
# check       "Fail <msg text...>"     | Fail             0           <anything>  <empty>
# apply       "Fail <msg text...>"     | ErrorInProtocol  --          --          --
# check       "ErrorInApply "          | ErrorInProtocol  --          --          --
# apply       "ErrorInApply "          | ErrorInApply    <errorCode>  <anything>  <error msg>
# check       "Applied <msg text...>"  | ErrorInProtocol  --          --          --
# apply       "Applied <msg text...>"  | Applied          0           <anything>  <empty>
# check       "<unrecognized output>"  | ErrorInProtocol  --          --          --
# apply       "<unrecognized output>"  | ErrorInProtocol  --          --          --
#
#
# See Also:
#    man(7) bg_creqs.sh
#    man(3) DeclareCreqClass  : the current way to create creqClasses in bash
#    man(3) creqLegacyShellFnImplStub  : the legacy, depreciated way to create creqClasses in bash



##################################################################################################################################
### Bash creqClass Implementations

# usage: DeclareCreqClass <creqClass> <debconfClassAttributes>
# DeclareCreqClass is the newer, prefered style of writing creqClasses in bash scripts.
#
# Example...
#    DeclareCreqClass cr_fileExists
#    function cr_fileExists::check() { [ -e "$1" ]; }
#    function cr_fileExists::apply() { touch "$1"; }
#
# The ::check() must return 0 if the host configuration complies with the creqStatment and non-zero if it does not. It may write
# to stdout to display information whether or not it returns 0. Typically it might write a message about why the host does not pass.
# It probably should not write to stdout if the check passes but it can if it wnats to. If it is not able to complete the check for
# any reason it should exit or raise an exception by calling an assertError* function. By convention, it should write an error
# message to stderr if its going to exit. The arguments in the creqStatement are passed to the check function.
#
# The ::apply() should attempt to change the host configuarion so that it will comply with the creqStatment. It may produce informative
# output on stdout but does not need to. If it is successful in changing the host to comply, it must return 0. If it is not successfull,
# it must either return non-zero or exit (typically by calling an assertError* function). It is good practice to write an error
# message to stderr if it return non-zero or exits. The ::apply() function will only get called if the ::check() function has been
# called and indicates that the host is not in compliance so the apply algorithm can assume that the host is not yet compliant.
# The arguments in the creqStatement are passed to the check function.
#
# The author can optionally define a ::construct() function which will be called first, once per creqStatement execution.
# The ::construct() function is passed the creqStatement arguments and would typically process and store the results in variables
# that the ::check() and ::apply() functions would then use instead of repeating the work to process the arguments from scratch.
# The entire creqStatment is executed in a subshell so the ::construct(), ::check() and ::apply() functions share a private 'global'
# variable scope that they can use to communicate between each other. This means that as long as the ::construct() function does not
# decalare a variable that it sets as 'local', that variable will be avaialble to the ::check() and ::apply() functions. Because the
# ::check() function is always called before the ::apply() function, the author could use the ::check() function to process the
# arguments instead of dong it in the ::construct() function. Either way, as long as a variable is not declared local in the
# ::construct() or ::check() functions, the ::apply() function can rely on its value.  Also, an associative array named 'this' is
# declared in the execution sub shell so the function may use it to pass variables between each other which some authors may find
# more descriptive -- particularely if they are used to writing bash object methods using 'this'.
#
# CreqStatement Description:
# By default the display version of the creqStatement is the actual `<creqClass> [<arg1>..<argN>]` command line but the author of
# a <creqClass> can override that for its creqStatements.
#
# The default output for each of the non-error outcomes of a cr_fileExists creqClass would look somthing like...
#     PASS:    fileExists /etc/foo.conf
#     FAIL:    fileExists /etc/foo.conf
#     APPLIED: fileExists /etc/foo.conf
# By providing bespoke pass, fail, and applied messages, the output could look like this...
#     PASS:    file /etc/foo.conf exists
#     FAIL:    file /etc/foo.conf is missing
#     APPLIED: created file /etc/foo.conf
#
# In the call to DeclareCreqClass, the author can provide template strings to use or in the ::*() functions, it can set the actual
# message to use. Note that a difference is that when passed to the DeclareCreqClass, it must be a template because those strings
# are constant for all creqStatments but when set in one of the ::*() functions, the statement arguments are available so the code
# can compose the text directly.
#
# The author can provide one msg that will be used as the display text for all <resultState>s or can provide different text for
# the <resultState>s (Pass|Fail|Apply). The ErrorIn* <resultState>s will always use the original creqStatement text since those
# represent an error for which the exact statement should be visible to inspect for errors in the statement.
#
# In one of the functions, the code can set one of these variables which will be taken as-is and NOT expanded as a template
#    msg or this[msg]   : a new default stmText which will be used if a more specific stmText is not set
#    passMsg or this[passMsg] : the stmText to use when the <resultState> is "Pass"
#    failMsg or this[failMsg] : the stmText to use when the <resultState> is "Fail"
#    appliedMsg or this[appliedMsg] : the stmText to use when the <resultState> is "Applied"
#
# The DeclareCreqClass function accepts an optional second parameter that is a deb conf file syntax string containing attribute definitions.
# The following attributes are recognized by the creqShellFnImplStub function as template strings that will be expanded against any
# non-local variables set by the <creqClass>::*() functions to create the statement text.
#     msg     : a template string that will be the default creqStatement text if a more specific msg is not defined.
#     passMsg : template string to use when as the the creqStatement when the check passes
#     failMsg : template string to use when as the the creqStatement when the check does not pass and its running in check mode
#     appliedMsg : template string to use when as the the creqStatement when the apply function suceeds in making the host comply
# The template strings can reference any variables set in either the ::construct() or ::check() functions. Also the variable creqStatement
# can be used in template strings.
#
# Example:
#    DeclareCreqClass cr_fileExists "
#        passMsg: file %filename% exists
#        failMsg: file %filename% is missing
#        appliedMsg: created file %filename%
#    "
#    function cr_fileExists::check() {
#        filename="$1"  # note! no 'local ...'
#        [ -f "$filename" ]
#    }
#    function cr_fileExists::apply() {
#        touch "$filename"
#    }
#
# See Also:
#    man(7) bg_creqs.sh
#    man(3) creqShellFnImplStub
#    man(3) creqLegacyShellFnImplStub  : creq bash stub function for running legacy cr_* functions that use the case statement style
function DeclareCreqClass()
{
	local creqClass="$1"
	[[ "$creqClass" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]] || assertError "invalid creqClass name"
	declare -gA $creqClass='()'
	[ $# -gt 0 ] && parseDebControlFile $creqClass "$@"
	eval 'function '$creqClass'() { creqClass="'"$creqClass"'" creqShellFnImplStub "$@" ; }'
}

# usage: creqShellFnImplStub [<arg1>..<argN>]
# This is a stub function used to invoke the shell function style of implementing a creqClass using DeclareCreqClass.
# Writing creqClass in this style is documented in man(3) DeclareCreqClass
# ENV Vars:
# The <argN> passed to this function are reserved for the official creqStatement arguments so the creqClass is passed in as an ENV
# variable
#
# See Also:
#    man(3) DeclareCreqClass
function creqShellFnImplStub()
{
	builtin trap 'echo ErrorInCheck  >&3' EXIT

	declare -A this=()
	if [ "$(type -t ${creqClass}::construct)" == "function" ]; then
		$creqClass::construct "$@" || exit
	fi

	local expandedMsg
	if $creqClass::check "$@"; then
		_creqShellFnImplStubWriteFD3Output Pass
	else
		if [ "$creqAction" != "apply" ]; then
			_creqShellFnImplStubWriteFD3Output Fail
		else
			builtin trap 'echo ErrorInApply  >&3' EXIT
			$creqClass::apply "$@" || exit
			$creqClass::check "$@" || assertError "'check' failed after performing 'apply'"
			_creqShellFnImplStubWriteFD3Output Applied
		fi
	fi
	builtin trap '' EXIT
}

# usage: _creqShellFnImplStubWriteFD3Output <resultState>
# getting the stmText defined by the creqClass author is not a one line operation so we factored it out into this function.
function _creqShellFnImplStubWriteFD3Output()
{
	local resultState="$1"
	local rsVar="${resultState,,}Msg"

	# write the resultState unconditionally as the first, whitespace deliminated word. The protocol says it should be capitalized
	echo "${resultState^}" >&3

	# next, see if the code set passMsg, this[passMsg], msg, or this[msg] in that order of preference
	local stmText="${!rsVar:-${this[$rsVar]:-${msg:-${this[msg]}}}}"
	if [ "$stmText" ]; then
		echo "$stmText" >&3
		return 0
	fi

	# next, see if there is a template provided in the DeclareCreqClass call we can expand to make the stmText
	local -n static="$creqClass"
	local stmText="${static[$rsVar]:-${static[msg]}}"
	if [ "$stmText" ]; then
		import bg_template.sh ;$L1;$L2
		templateExpandStr "$stmText" >&3
		return 0
	fi

	# if the class autor has not provided a stmText, we write nothing so that the generic default is implemented by the runner and
	# is consistent across all types of implementaions.
}

# usage: creqLegacyShellFnImplStub [<arg1>..<argN>]
# This is a stub function used to invoke the old, legacy style of creq class shell function so that it produces compatible output
# to the new protocol which makes it call-exchangable with the other styles of implemnetation.
#
# This style of writting a creqClass in bash is no longer the prefered method but allows compatibility with libraries of
# creqClasses written for the original version of the mechanism.
#
# Note that a feature of the original creq version was that you did not have to explicitly invoke the creqRunner (`creq`) because
# when the creqClass function was executed whithout the objectMethod being defined, it would invoke the creqRunner. That is
# depreciated and a creqRunner is always required to execute a creqStatement.
#
# The body of the shell function is a single case statement that uses the 'global' variable $objectMethod as the case variable.
# When a creq class of this type is executed, a stub function will call the function seperately for each operation that it needs to
# perform, indicating the operation by setting the $objectMethod variable before the call.
#    function cr_boilerplate()
#    {
#    	case $objectMethod in
#    		objectVars) echo "p1 p2=5 localVar1" ;;
#    		construct)
#    			# process parameters and set variables
#    			;;
#
#    		check)
#    			# do the check operation
#    			;;
#
#    		apply)
#    			# do the apply operation
#    			;;
#
#    		*) cr_baseClass "$@" ;;
#    	esac
#    }
# In the 'construct' case, the creq class can set these variables that the stub function will use to complete the protocol
#    displayName  : the name of the creq class to use in msgs. default removes the leading cr_ from the function name
#    creqMsg      : a generic message used as the default for all <resultStates> if one of the specific msgs is not provided
#    msg          : alias for creqMsg
#    passMsg      : a specific message to use for the Pass  <resultStates>
#    noPassMsg    : a specific message to use for the Fail  <resultStates>
#    appliedMsg   : a specific message to use for the Applied  <resultStates>
#    failedMsg    : a specific message to use for the ErrorInCheck and ErrorInApply  <resultStates>
function creqLegacyShellFnImplStub()
{
	builtin trap 'echo ErrorInCheck  >&3' EXIT
	classVars="$(objectMethod=objectVars $creqClass)" || exit
	for classVar in $classVars; do
		eval local -x $classVar || exit
	done

	this="_creqThisSyntaxHandler "

	objectMethod=construct $creqClass "$@" || exit
	this[statementName]="${this[statementName]:-$creqClass}"
	local displayName="${this[statementName]}"

	local expandedMsg

	objectMethod=check $creqClass
	if [ $? -eq 0 ]; then
		printf "Pass\n${passMsg:-${creqMsg:-$msg}}" >&3
	else
		if [ "$creqAction" != "apply" ]; then
			printf "Fail\n${noPassMsg:-${creqMsg:-$msg}}" >&3
		else
			builtin trap 'echo "ErrorInApply"  >&3' EXIT
			objectMethod=apply $creqClass || exit
			objectMethod=check $creqClass || assertError "'check' failed after performing 'apply'"
			printf "Applied\n${appliedMsg:-${creqMsg:-$msg}}" >&3
		fi
	fi
	builtin trap '' EXIT
}
# usage: $this.<varname>=<value
# This internal creq helper function supports using member variable assignment syntax in creq class member functions
# like construct, check, and apply. creq defines the variable local this="_creqThisSyntaxHandler " before invoking the
# member functions. Inside those functions a script line like...
#      $this.msg="hello world"
# will expand to the following line after variable substitution, word splitting and quote removal
#      _creqThisSyntaxHandler '.msg=hello world'
# which will call this function
function _creqThisSyntaxHandler()
{
	local line="$*" local sq="'"
	local _mnameShort="${1#.}";  [ $# -gt 0 ] && shift
	if [[ "$_mnameShort" =~ ^[a-zA-Z0-9_]*= ]]; then
		eval "${_mnameShort/=/=$sq}'"

	else
		assertError "unknown 'this' syntax '\$this.$line'"
	fi
}

# usage: cr_baseClass
# this provides the default implementation for cr_ function classes
# most cr_* type functions call this from their default (*) case statement
# if the caller does not set the objectMethod var, this function knows that
# it was not invoked by the creq fucntion so it reinvokes with the creq function
function cr_baseClass()
{
	if [ "$objectMethod" == "newStyle" ]; then
		className="${FUNCNAME[1]}" creqLegacyShellFnImplStub "$@"
	elif [ ! "$objectMethod" ]; then
		assertError "creqStatements can no longer be executed on their own. You must explicitly use a creqRunner (creq,creqCheck,or creqApply) to execute a creqStatement"
	fi
}



##################################################################################################################################
### CreqRunner Execution functions


# usage: creqStartSession [--verbosity=<vlevel>] [--profileID=<pluginKey>] check|apply
# Start a session to run a group of creq statements. The session should be closed with creqEndSession. In between creqStatements
# are run with the `creq` creqRunner.
#
# Session Execution Output:
# The spirit of creq session execution output is to report on the larger process of the profile, not the details of individual creq
# statements. This is not meant to provide the information required for development and debugging a particular creq class. For that
# a particular creq statement can be executed directly at a terminal either invoking the class name directly if its an external
# command or by using the creqTest command if its a shell function implementation. This allows debugging the creq class similar to
# any command written in its implementation language.
#
# A creq session can be invoked interactively or as a part of the automated compliance engine on a host. The difference is that
# when invoked as a part of the automted compliance engine, its output will contribute to the stateful logs of the host.
#
# A session to run a creq profile can optionally produce reports of various types to indicate what happened.
#     progress feedback: the pupose is to give the user running the session feedback on what is happenning. The user can controll
#          how the progress messages are displayed. See "man(3) progress"
#          If progressType=none, this output will be supressed which is how system daemons invoke a creq session.
#     stdout : in addition to the progress feedback, an interactive user can get information on stdout about what is happenning.
#          Typically, the progress information is displayed in a way that new information replaces the previous information so
#          the user might also want to see a line printed for each creq statement being executed to make it more transparent about
#          what the profile is doing. The user can set the verbosity level to get more or less information on stdout
#                 verbosityLevels
#                     0          : print a line for any statement that ends in an error (ErrorInCheck, ErrorInApply, or ErrorInProtocol)
#                     1 (default): print a line also for any statement that ends in 'Fail' or 'Applied'
#                     2          : print a line for each statement regardless of its <resultState>
#     stderr : Typically, there is no stderr output from a creq session regardless of how the creq statements complete. stderr
#          output indicates an unexpected fault in the creq session execution mechanism itself.
#     Statement Report : the session can optional write out a list of the fully qulified statement IDs executed during the run.
#          A fully qulified statement IDs has the form <creqProfileID>:<creqStatementID> (e.g. "Standards:linuxBase:0004"). By
#          default the statement ID will change if order of statements is changed in the profile but a profile can be written to
#          give each statment a persistent ID that will not change.  The Statement Report is used to audit the compliance coverage
#          of a host. The file that receives the Statement Report will be overwritten each run.
#     Log : The log writes a header record at the start of the session that identifies the profileID and creqAction and a footer at
#          the end of the session that reports on the number of statements executed and how many ended in each <resultState>. In
#          between the header and footer, a record is printed for each statement that ends in a <resultState> of ErrorInCheck,
#          ErrorInApply or ErrorInProtocol.
#
# Params:
#    <creqAction> : check|apply.  "check" just reports on compliance. 'apply' will attempt to make the host comply
# Options:
#    --verbosity  : higher numbers cause more verbose output
#    --profileID  : The key of the plugin that is being ran. (Standards|Config):<name>
function creqStartSession()
{
	varExists creqAction && assertError "nesting creq profile sessions is not (yet?) allowed"

	declare -gx verbosity="${verbosity:-1}" creqProfileID="<anon>" statementLog
	while [ $# -gt 0 ]; do case $1 in
		--profileID*) bgOptionGetOpt val: creqProfileID "$@" && shift ;;
		--statementLog*) bgOptionGetOpt val: statementLog "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	declare -gx creqAction="${1:-check}"
	[[ "$creqAction" =~ ^(check|apply)$ ]] || assertError -v creqAction "The first positional argument must be 'check' or 'apply'"


	if [ "$statementLog" ]; then
		fsTouch "$statementLog"
		echo > "$statementLog"
	fi

	declare -gA creqRun=(
		[profileID]="$creqProfileID"
		[profileType]="${creqProfileID%%:*}"
		[profileName]="${creqProfileID#*:}"
		[action]="$creqAction"
	)

	declare -g stderrFile; bgmktemp stderrFile
	declare -g stdoutFile; bgmktemp stdoutFile
}

# usage: creqEndSession
function creqEndSession()
{
	creqRun[countCompliant]="$(( ${creqRun[countPass]:-0}+${creqRun[countApplied]:-0} ))"
	creqRun[completeness]="$(( ${creqRun[countCompliant]:-0} * 100 / ${creqRun[countTotal]:-1} ))"

	printf "%-18s : %s/%s %3s%% compliant\n" "${creqRun[profileID]}" "${creqRun[countCompliant]}" "${creqRun[countTotal]}" "${creqRun[completeness]}"

	for countVar in Pass Fail Applied ErrorInCheck ErrorInApply ErrorInProtocol; do
		[ ${creqRun[count${countVar}]:-0} -gt 0 ] && printf "   %4s: %s\n"  "${creqRun[count${countVar}]}" "$countVar"
	done

	bgmktemp --release stderrFile
	bgmktemp --release stdoutFile
	unset creqRun creqAction
}


# usage: creq <creqClass> [<arg1>..<argN>]
# creq is the creqStatement runner used inside creqStartSession and creqEndSession calls used to run Standards and Config plugin
# creqProfiles. This function invokes the creqStatement using the check or apply mode set by creqStartSession
function creq()
{
	local defaultMsg="$*"; defaultMsg="${defaultMsg#cr_}"; defaultMsg="${defaultMsg/$'\n'*/ ...}"; defaultMsg="${defaultMsg:0:100}"
	local policyID
	while [ $# -gt 0 ]; do case $1 in
		-p*|--policyID) bgOptionGetOpt val: policyID "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local creqClass="$1"; shift

	# typically Config profiles do not provide a GUID for the policyID so we create a transient one that will be unique within a
	# profile and consistent only for each particular version of the profile. Standards profiles typically do provide them so that
	# each statement can match up to a policy ID in an organization's policy and standards documentation
	[ ! "$policyID" ] && printf -v policyID "%s-%04d" "$creqClass" "$creqCountTotal"
	[ "$statementLog" ] && echo "${creqRun[profileID]}:$policyID" >> "$statementLog"


	# run the statement with the cmd we just determined
	local resultMsg="$( (objectMethod="newStyle" $creqClass "$@") 3>&1 >$stdoutFile 2>$stderrFile)"

	# parse the stdout msg:  <resultState> <msg text...>
	local resultState="${resultMsg%%[ $'\n\t']*}"
	[[ "$resultState" =~ ^(Pass|Fail|Applied|ErrorInCheck|ErrorInApply)$ ]] || resultState="ErrorInProtocol"
	local stmText="${resultMsg#$resultState}"; stringTrim -R stmText
	stmText="${stmText:-$defaultMsg}"

	((creqRun[countTotal]++))
	((creqRun[count${resultState^}]++))
	[[ "$resultState" =~ ^ErrorIn ]] && ((creqRun[countError]++))

	case $resultState in
		Pass)
			[ ${verbosity:-1} -ge 2 ] && printf "${csiGreen}%-7s${csiNorm} : %s\n" "PASSED" "$stmText"
			;;
		Applied)
			[ ${verbosity:-1} -ge 1 ] && printf "${csiBlue}%-7s${csiNorm} : %s\n" "APPLIED"  "$stmText"
			;;
		Fail)
			[ ${verbosity:-1} -ge 1 ] && printf "${csiHiYellow}%-7s${csiNorm} : %s\n" "FAILED"  "$stmText"
			;;
		ErrorInCheck|ErrorInApply)
			[ ${verbosity:-1} -ge 0 ] && printf "${csiHiRed}%-7s${csiNorm} : %s\n" "$resultState"  "$stmText"
			if [ "$logFileFD" ]; then
				echo "$resultState: $stmText" >&$logFileFD
				[ "$stdoutFile" ] && awk '{print "   stdout: " $0}' "$stdoutFile" >&$logFileFD
				[ "$stderrFile" ] && awk '{print "   stderr: " $0}' "$stderrFile" >&$logFileFD
			fi
			;;
		ErrorInProtocol)
			[ ${verbosity:-1} -ge 0 ] && printf "${csiHiRed}%-7s${csiNorm} : \ntext returned by creqClass='%s'\n" "$resultState"  "$resultMsg"
			if [ "$logFileFD" ]; then
				printf "ErrorInProtocol : \ntext returned by creqClass='%s'" "$resultMsg" >&$logFileFD
				[ "$stdoutFile" ] && awk '{print "   stdout: " $0}' "$stdoutFile" >&$logFileFD
				[ "$stderrFile" ] && awk '{print "   stderr: " $0}' "$stderrFile" >&$logFileFD
			fi
			;;
		*) assertLogicError
	esac
}

# usage: creqCheck <creqClass> [<arg1>..<argN>]
# creqCheck is the runner used to run creqStatement outside of a creqProfile to only test to see if the host is compliant.
function creqCheck()
{
	varExists creqRun && assertError "Creq statements can not be executed with creqCheck nor creqApply inside a creq Statndards or Config profile "

	local verbosity="1"
	while [ $# -gt 0 ]; do case $1 in
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local defaultMsg="$*"; defaultMsg="${defaultMsg#cr_}"; defaultMsg="${defaultMsg/$'\n'*/ ...}"; defaultMsg="${defaultMsg:0:100}"
	local creqClass="$1"; shift


	# run the statement with the cmd we just determined
	exec {outFD}>&1
	local resultMsg="$( (objectMethod="newStyle" creqAction="check" $creqClass "$@") 3>&1  >&$outFD)"
	exec {outFD}>-

	# parse the stdout msg:  <resultState> <msg text...>
	local resultState="${resultMsg%%[ $'\n\t']*}"
	[[ "$resultState" =~ ^(Pass|Fail|Applied|ErrorInCheck|ErrorInApply)$ ]] || resultState="ErrorInProtocol"
	local stmText="${resultMsg#$resultState}"; stringTrim -R stmText
	stmText="${stmText:-$defaultMsg}"

	case $resultState in
		Pass)
			[ ${verbosity:-1} -ge 2 ] && printf "${csiGreen}%-7s${csiNorm} : %s\n" "PASSED" "$stmText"
			return 0
			;;
		Fail)
			[ ${verbosity:-1} -ge 1 ] && printf "${csiHiYellow}%-7s${csiNorm} : %s\n" "FAILED"  "$stmText"
			return 1
			;;
		ErrorInCheck|ErrorInApply|ErrorInProtocol)
			[ ${verbosity:-1} -ge 0 ] && printf "${csiHiRed}%-7s${csiNorm} : %s\n" "$resultState"  "$stmText"
			return 202
			;;
		*) assertLogicError
	esac
}


# usage: creqApply <creqClass> [<arg1>..<argN>]
# creqApply is the runner used to run creqStatement outside of a creqProfile in apply mode
function creqApply()
{
	varExists creqRun && assertError "Creq statements can not be executed with creqCheck nor creqApply inside a creq Statndards or Config profile "

	local verbosity="1"
	while [ $# -gt 0 ]; do case $1 in
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local defaultMsg="$*"; defaultMsg="${defaultMsg#cr_}"; defaultMsg="${defaultMsg/$'\n'*/ ...}"; defaultMsg="${defaultMsg:0:100}"
	local creqClass="$1"; shift


	# run the statement with the cmd we just determined
	exec {outFD}>&1
	local resultMsg="$( (objectMethod="newStyle" creqAction="apply" $creqClass "$@") 3>&1  >&$outFD)"
	exec {outFD}>-

	# parse the stdout msg:  <resultState> <msg text...>
	local resultState="${resultMsg%%[ $'\n\t']*}"
	[[ "$resultState" =~ ^(Pass|Fail|Applied|ErrorInCheck|ErrorInApply)$ ]] || resultState="ErrorInProtocol"
	local stmText="${resultMsg#$resultState}"; stringTrim -R stmText
	stmText="${stmText:-$defaultMsg}"

	case $resultState in
		Pass)
			[ ${verbosity:-1} -ge 2 ] && printf "${csiGreen}%-7s${csiNorm} : %s\n" "PASSED" "$stmText"
			return 0
			;;
		Applied)
			[ ${verbosity:-1} -ge 1 ] && printf "${csiBlue}%-7s${csiNorm} : %s\n" "APPLIED"  "$stmText"
			return 0
			;;
		ErrorInCheck|ErrorInApply|ErrorInProtocol)
			[ ${verbosity:-1} -ge 0 ] && printf "${csiHiRed}%-7s${csiNorm} : %s\n" "$resultState"  "$stmText"
			return 202
			;;
		*) assertLogicError
	esac
}





##############################################################################################
### functions to use in creqProfile scripts (Standards and Config)
#   For example to keep track of what has changed to know if a daemon needs to be restarted

declare -A creqsChangetrackers
declare -A creqsChangetrackersActive
declare -A creqsTrackedServices
declare -A creqsTrackedServicesActions

# usage: creqGetState
# returns "check", "apply", or empty string to indication whether the creq system is running and in what state
function creqGetState() { echo "$creqAction"; }

# usage: if creqIsCheck; then ...
# test if the configuration required system is in the 'check' mode
function creqIsCheck() { [ "$creqAction" == "check" ]; }

# usage: if creqIsApply; then ...
# test if the configuration required system is in the 'apply' mode
function creqIsApply() { [ "$creqAction" == "apply" ]; }


# usage: creqsTrackChangesStart -s <serviceName>[:<action>] [<varName>]
# usage: creqsTrackChangesStart <varName>
# start tracking changes with varName. If a cr_ is applied while varName is tracking changes,
# it will be set to a non empty string (true). This facilitates surrounding a set of cr_ statements
# with a start/stop pair and if any of those statements resulted in a change(apply), then varName
# will be true. This -s form records serviceName so that at the end it will be restarted if its coresponding
# varName has be set to true. The default varName is serviceName if the second param is not specified
# a varName can be stopped and restarted multiple times.
function creqsTrackChangesStart()
{
	local serviceName serviceAction varName
	while [ $# -gt 0 ]; do case $1 in
		-s*) bgOptionGetOpt val: serviceName "$@" && shift
			[[ "$serviceName" =~ : ]] && splitAttribute "$serviceName" serviceName serviceAction
			varName="${2:-$serviceName}"
			creqsTrackedServices["$serviceName"]="$varName"
			creqsTrackedServicesActions["$serviceName"]="${serviceAction:-restart}"
			;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	varName="${varName:-$1}"

	# this ensures that there is a $varName index in the creqsChangetrackersActive map. the value at the index
	# is "" unless its been set to 1 when a cr_ runs. Since we can start and stop the tracked varname multiple
	# times, we preserve the previous value which will be "" if this is the first start.
	creqsChangetrackersActive[$varName]="${creqsChangetrackers[$varName]}${creqsChangetrackersActive[$varName]}"
}

# usage: creqsTrackChangesStop -s <serviceName>[:<action>] [<varName>]
# usage: creqsTrackChangesStop <varName>
# stop tracking varName. This means that if a cr_ results in an applied and makes a change,
# varName will not be set to true.
# this also returns the value of varName so that the caller can stop tracking changes and
# check to see if any changes had been made while it was tracking in one operation.
# if creqsTrackChangesStop apacheRestartNeeded; then ...
function creqsTrackChangesStop()
{
	local serviceName varName
	while [ $# -gt 0 ]; do case $1 in
		-s*) bgOptionGetOpt val: serviceName "$@" && shift
			[[ "$serviceName" =~ : ]] && splitAttribute "$serviceName" serviceName serviceAction
			varName="${2:-$serviceName}"
			;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	varName="${varName:-$1}"

	creqsChangetrackers[$varName]="${creqsChangetrackers[$varName]}${creqsChangetrackersActive[$varName]}"
	unset creqsChangetrackersActive[$varName]
	[ "${creqsChangetrackers[$varName]}" ]
}

# usage: creqsTrackChangesCheck <varName>
# check the tracking varName value. see creqsTrackChangesStart for a description.
# typical: if creqsTrackChangesCheck apacheRestartNeeded; then ...
function creqsTrackChangesCheck()
{
	local varName="$1"
	[ "$varName" ] || return 1
	creqsChangetrackers[$varName]="${creqsChangetrackers[$varName]}${creqsChangetrackersActive[$varName]}"
	[ "${creqsChangetrackers[$varName]}" ]
}

# usage: creqServiceAction <serviceName> <action> [<varName>]
# Perform an action (ie. restart,reload, etc..) on a service daemon only if varName has been set and the mode is 'apply'
# This is typically only called by creqReport at the end of a creq run on any service/actions that have been registered
# during the creq run with creqsTrackChangesStart/Stop or creqsDelayedServiceAction.
# It only does the action in apply mode so check mode can be sure not to change anything on the host.
# Typically, varName is the service name and if any creq changes are applied between creqsTrackChangesStart/Stop statements
# for varName, it will be set and the service action will be performed at the end of the run
function creqServiceAction()
{
	local serviceName="$1"
	local action="$2"
	local varName="${3:-$serviceName}"
	assertNotEmpty varName
	if creqIsApply; then
		if creqsTrackChangesCheck $varName; then
			_creqEcho -v1 "${action^^}ing... : service '$serviceName' because its configuration has changed USER='$USER'"
			# note: 2015-09 the sudo prefix to service is needed even if you are already root. related to User Sessions for upstart services
			local line temp; while IFS="" read -r temp; do
				line="${temp/+-M-+/$line}"
				_creqEcho -v1 -o "${action^^}ing... : $line"
			done < <(sudo service $serviceName $action || echo "FAILED($?) +-M-+")
			_creqEcho -v1 -o "${action^^}ed '$serviceName' : $line"
		fi
	fi
}

# usage: creqWasChanged file1 [ file2 [ .. fileN] ]
# test the files to see if any have a modification time stamp newer than the start of the
# creqInit run. This can be called any time before the creqReport call
# returns 0 (true) if any of the files have been changed
# returns 1 (false) if none have been changed
function creqWasChanged()
{
	while [ "$creqStartTimeFile" ] && [ "$1" ]; do
		if [ "$1" -nt "$creqStartTimeFile" ]; then
			return 0
		fi
		shift
	done
	return 1
}
