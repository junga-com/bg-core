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
#    man(3) DeclareCreqClass



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
#
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
			builtin trap 'echo ErrorInApply  >&3' EXIT
			objectMethod=apply $creqClass || exit
			printf "Applied\n${appliedMsg:-${creqMsg:-$msg}}" >&3
		fi
	fi
	builtin trap '' EXIT
}



##################################################################################################################################
### Creq Execution functions


# usage: creqStartSession [--verbosity=<vlevel>] [--profileID=<pluginKey>] check|apply
# Start a session to run a group of creq statements. The session should be closed with creqEndSession.
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

	declare -gx creqVerbosity=1 creqProfileID="<anon>" statementLog
	while [ $# -gt 0 ]; do case $1 in
		--verbosity*) bgOptionGetOpt val: creqVerbosity "$@" && shift ;;
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
	printfVars creqRun
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

	# shell functions are invoked with a stub function. If ${creqClass}::check is a function it the new way, otherwise it the old.
	local classRunCmd
	case $(type -t $creqClass):$(type -t ${creqClass}::check) in
		function:function) classRunCmd="creqShellFnImplStub " ;;
		function:*)        classRunCmd="creqLegacyShellFnImplStub " ;;
		file:*)            classRunCmd="$creqClass" ;;
		*) assertError -v creqClass "The creq class name is not a shell function nor an external command" ;;
	esac

	# run the statement with the cmd we just determined
	local resultMsg="$(objectMethod="newStyle" $classRunCmd "$@" 3>&1 >$stdoutFile 2>$stderrFile)"
bgtraceVars resultMsg

	# parse the stdout msg:  <resultState> <msg text...>
	local resultState="${resultMsg%%[ $'\n\t']*}"
	[[ "$resultState" =~ ^(Pass|Fail|Applied|ErrorInCheck|ErrorInApply)$ ]] || resultState="ErrorInProtocol"
	resultMsg="${resultMsg#$resultState}"; stringTrim -R resultMsg
	resultMsg="${resultMsg:-$defaultMsg}"

	((creqRun[countTotal]++))
	((creqRun[count${resultState^}]++))
	[[ "$resultState" =~ ^ErrorIn ]] && ((creqRun[countError]++))

	case $resultState in
		Pass)
			[ ${creqVerbosity:-1} -ge 2 ] && printf "${csiGreen}%-7s${csiNorm} : %s\n" "PASSED" "$resultMsg"
			;;
		Applied)
			[ ${creqVerbosity:-1} -ge 1 ] && printf "${csiBlue}%-7s${csiNorm} : %s\n" "APPLIED"  "$resultMsg"
			;;
		Fail)
			[ ${creqVerbosity:-1} -ge 1 ] && printf "${csiHiYellow}%-7s${csiNorm} : %s\n" "FAILED"  "$resultMsg"
			;;
		ErrorInCheck|ErrorInApply|ErrorInProtocol)
			[ ${creqVerbosity:-1} -ge 0 ] && printf "${csiHiRed}%-7s${csiNorm} : %s\n" "$resultState"  "$resultMsg"
			if [ "$logFileFD" ]; then
				echo "$resultState: $resultMsg" >&$logFileFD
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

	# shell functions are invoked with a stub function. If ${creqClass}::check is a function it the new way, otherwise it the old.
	local classRunCmd
	case $(type -t $creqClass):$(type -t ${creqClass}::check) in
		function:function) classRunCmd="creqShellFnImplStub " ;;
		function:*)        classRunCmd="creqLegacyShellFnImplStub " ;;
		file:*)            classRunCmd="$creqClass" ;;
		*) assertError -v creqClass "The creq class name is not a shell function nor an external command" ;;
	esac

	# run the statement with the cmd we just determined
	exec {outFD}>&1
	local resultMsg="$(objectMethod="newStyle" creqAction="check" $classRunCmd "$@" 3>&1  >&$outFD)"
	exec {outFD}>-

	# parse the stdout msg:  <resultState> <msg text...>
	local resultState="${resultMsg%%[ $'\n\t']*}"
	[[ "$resultState" =~ ^(Pass|Fail|Applied|ErrorInCheck|ErrorInApply)$ ]] || resultState="ErrorInProtocol"
	resultMsg="${resultMsg#$resultState}"; stringTrim -R resultMsg
	resultMsg="${resultMsg:-$defaultMsg}"

	case $resultState in
		Pass)
			[ ${verbosity:-1} -ge 2 ] && printf "${csiGreen}%-7s${csiNorm} : %s\n" "PASSED" "$resultMsg"
			return 0
			;;
		Fail)
			[ ${verbosity:-1} -ge 1 ] && printf "${csiHiYellow}%-7s${csiNorm} : %s\n" "FAILED"  "$resultMsg"
			return 1
			;;
		ErrorInCheck|ErrorInApply|ErrorInProtocol)
			[ ${verbosity:-1} -ge 0 ] && printf "${csiHiRed}%-7s${csiNorm} : %s\n" "$resultState"  "$resultMsg"
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

	# shell functions are invoked with a stub function. If ${creqClass}::check is a function it the new way, otherwise it the old.
	local classRunCmd
	case $(type -t $creqClass):$(type -t ${creqClass}::check) in
		function:function) classRunCmd="creqShellFnImplStub " ;;
		function:*)        classRunCmd="creqLegacyShellFnImplStub " ;;
		file:*)            classRunCmd="$creqClass" ;;
		*) assertError -v creqClass "The creq class name is not a shell function nor an external command" ;;
	esac

	# run the statement with the cmd we just determined
	exec {outFD}>&1
	local resultMsg="$(objectMethod="newStyle" creqAction="apply" $classRunCmd "$@" 3>&1  >&$outFD)"
	exec {outFD}>-

	# parse the stdout msg:  <resultState> <msg text...>
	local resultState="${resultMsg%%[ $'\n\t']*}"
	[[ "$resultState" =~ ^(Pass|Fail|Applied|ErrorInCheck|ErrorInApply)$ ]] || resultState="ErrorInProtocol"
	resultMsg="${resultMsg#$resultState}"; stringTrim -R resultMsg
	resultMsg="${resultMsg:-$defaultMsg}"

	case $resultState in
		Pass)
			[ ${verbosity:-1} -ge 2 ] && printf "${csiGreen}%-7s${csiNorm} : %s\n" "PASSED" "$resultMsg"
			return 0
			;;
		Applied)
			[ ${verbosity:-1} -ge 1 ] && printf "${csiBlue}%-7s${csiNorm} : %s\n" "APPLIED"  "$resultMsg"
			return 0
			;;
		ErrorInCheck|ErrorInApply|ErrorInProtocol)
			[ ${verbosity:-1} -ge 0 ] && printf "${csiHiRed}%-7s${csiNorm} : %s\n" "$resultState"  "$resultMsg"
			return 202
			;;
		*) assertLogicError
	esac
}


# # usage: creq cr_<type> [ p1 [ p2 ... pN ] ]
# # this is used to create configuration items using a declarative syntax.
# # cr_type is the name of a function written in a particular way that behaves
# # like a Object Class of type ConfReqs so that one function can define several
# # methods (actions) and this creq function decides which actions should be invoked
# # creq implements the main algorithm for running the declarative statements
# # It can be called explicitly like "creq cr_<type> [ p1 [ p2 ... pN ] ]"
# # or it can be called implicitly like "cr_<type> [ p1 [ p2 ... pN ] ] "
# # see cr_boilerplate for writing cr_ type functions
# function creqOLD()
# {
# 	local fullOrigCmdLine="creq $*"
#
# 	function testAndProcTestLog()
# 	{
# 		# creqTestLog is a tmp filename used to capture the stdout and stderr of each small command. Its content is consumed and reset to empty
# 		# creqLogfile is the persistent log file that lasts the entire current run session
#
# 		if [ -s ${creqTestLog}.out ]; then
# 			awk '{printf("     %-5s: %s\n","'"$crSection"'", $0)}' ${creqTestLog}.out | tee -a $creqLogfile  >>$creqStdout
# 			echo -n > ${creqTestLog}.out
# 		fi
#
# 		if [ -s ${creqTestLog}.err ]; then
# 			awk '{printf("   %-5s(ERR): %s\n","'"$crSection"'", $0)}' ${creqTestLog}.err | tee -a $creqLogfile  >>$creqStderr
# 			echo -n > ${creqTestLog}.err
# 			return 1
# 		fi
# 		return 0
# 	}
#
# 	local exitTrapAction='
# 		(
# 			awk '\''{print "      (stderr): "$0}'\'' '"${creqTestLog}.err"'
# 			_creqEcho -v1 "ERROR: creq run ended prematurely in $classFn::$objectMethod"
# 			local -A stackFrame=(); bgStackGetFrame creq-1 stackFrame
# 			assertError "
# 				      $classFn::$objectMethod called exit/assert and has ended the creq run prematurely.
# 				      this function should use return instead of exit. The equivalent to exit in creq class
# 				      methods is to write an error message to stderr and return n. This error can be fixed by
# 				      enclosing any function call in $classFn::$objectMethod that might call exit
# 				      (or assert*) in (). For example: use '\''(assertNotEmpty myRequiredVar) || return'\''
# 				      to assert an error condition. Make sure that any class variable assignments are not
# 				      inside any (). The offending line is...
# 				         ${stackFrame[printLine]}
# 			"
# 		) >&3 2>&3
# 	'
#
#
# 	### initialize the creq execution environment
# 	if [[ ! "$creqAction" =~ (check)|(apply) ]]; then
# 		assertError "creq system not initialized. see creqInit "
# 	fi
#
# 	# 2016-07 bobg: not sure if sync is needed. do we still use coprocs to capture output anywhere? It would be faster without sync probably
# 	sync
# 	crSection="init "
# 	echo -n > ${creqTestLog}.out
# 	echo -n > ${creqTestLog}.err
# 	_creqLogMarker "creq start: $*"
# 	local _creqUID
# 	while [[ "$1" =~ ^- ]]; do
# 		case $1 in
# 			-p)  _creqUID="$2"; shift ;;
# 			-p*) _creqUID="${1#-u}" ;;
# 			*) echo "unknown optional parameter to creq: '$1': params: $@" >>${creqTestLog}.err
# 		esac
# 		shift
# 	done
# 	if ! testAndProcTestLog $creqTestLog; then
# 		(( creqCountCtorError++ ))
# 		_creqEcho -v1 "ERROR in statement: unknown optional parameter to creq: '$1': params: $@"
# 		crSection=""
# 		_creqLogStmtResult ERROR inStmtParams
# 		return 100
# 	fi
#
# 	# typically creqConfig do not provide a GUID for the _creqUID so we create a transient (TRANS) one
# 	# that will be unique within a particular version of the creq profile.
# 	if [ ! "$_creqUID" ]; then
# 		printf -v _creqUID "TRANS%04d" "$creqCountTotal"
# 	fi
#
#
# 	### construct the cr_ object
# 	crSection="ctor "
# 	local classFn="$1" ; shift
# 	if ! type -t "$classFn" >/dev/null; then
# 		_creqEcho -v1 "ERROR in init: '$classFn' not found' "
# 		crSection=""
# 		_creqLogStmtResult ERROR inStmtCtor
# 		return 103
# 	fi
#
# 	(( creqCountTotal++ ))
# 	creqCompleteness="$((creqCountPass+creqCountApplyPass))/${creqCountTotal}..."
# 	creqCompletenessPercent="$(((creqCountPass+creqCountApplyPass)*100/((creqCountTotal>0)?creqCountTotal:1) -1))%..."
#
# 	# declare these class vars for the ut_ class to set if needed
# 	local this="_creqThisSyntaxHandler "
# 	local displayName=""
# 	local creqMsg=""
# 	local passMsg=""
# 	local noPassMsg=""
# 	local appliedMsg=""
# 	local failedMsg=""
#
# 	# declare the variable names local at this scope so that they will be
# 	# shared among all the calls to classFn
# 	bgtrap '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
# 	local classVars="$(objectMethod=objectVars $classFn 3>&2  2>>${creqTestLog}.err)"
# 	for classVar in $classVars; do
# 		eval local -x $classVar >>${creqTestLog}.out 2>>${creqTestLog}.err
# 	done
# 	bgtrap -r '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
# 	if ! testAndProcTestLog $creqTestLog; then
# 		(( creqCountCtorError++ ))
# 		_creqEcho -v1 "ERROR in objectVars: '$classFn $@' "
# 		crSection=""
# 		_creqLogStmtResult ERROR inStmtObjVars
# 		return 101
# 	fi
#
# 	# call the construct 'method'
# 	bgtrap '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
# 	objectMethod=construct $classFn "$@" 3>&2 >>${creqTestLog}.out 2>>${creqTestLog}.err
# 	local result=$?
# 	bgtrap -r '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
# 	if ! testAndProcTestLog $creqTestLog || [ $result -ne 0 ]; then
# 		(( creqCountCtorError++ ))
# 		_creqEcho -v1 "ERROR in construct: '$classFn $@' returned '$result'"
# 		crSection=""
# 		_creqLogStmtResult ERROR inStmtCtor
# 		return 102
# 	fi
#
# 	# check to see if the constructor assigned the class variables
# 	# This catches the easy to make mistake of declaring the variables 'local' in the cr_statement ctor.
# 	local unassignedVarList
# 	for classVar in $classVars; do
# 		classVar="${classVar%%=*}"
# 		[ ! "${!classVar+wasAssigned}" ] && unassignedVarList+=($classVar)
# 	done
# 	[ "$unassignedVarList" ] && assertError -v fullOrigCmdLine -v classFn -v displayName -v unassignedVarList "The 'constructor' case of a cr_statement must assign a value (it can be empty) to every variable it declares in the 'objectVars' section. A common mistake is to declare them 'local' in the construct section instead of just assinging them without the 'local'"
#
# 	displayName="${displayName:-$(creqMakeDisplayName "$classFn" "$@")}"
#
#
#
# 	### call the check 'method'
# 	crSection="check"
# 	# set a trap for the duration of the check call to trap exit. check functions should never exit the process.
# 	# we do not wrap it in () to catch exit, because that would prohibit the check function from setting the creqMsg
# 	# variable or any 'class' variable used by us or the ::apply method
# 	bgtrap '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
# 	objectMethod=check $classFn 3>&2 >>${creqTestLog}.out 2>>${creqTestLog}.err
# 	local checkResult=$?
# 	bgtrap -r '_creqTrapExitingCrStmts >&3 2>&3 ' EXIT
# 	if ! testAndProcTestLog $creqTestLog; then
# 		(( creqCountCheckError++ ))
# 		creqMsg="${creqMsg:-${msg:-$displayName}}"
# 		_creqEcho -v1 "ERROR in check: $creqMsg"
# 		crSection=""; creqMsg=""
# 		_creqLogStmtResult ERROR check
# 		return 103
# 	fi
#
#
#
# 	### check PASSED case
# 	local applyResult=0
# 	if [ $checkResult -eq 0 ]; then
# 		# the check passed
# 		(( creqCountPass++ ))
# 		creqCompleteness="$((creqCountPass+creqCountApplyPass))/${creqCountTotal}..."
# 		creqCompletenessPercent="$(((creqCountPass+creqCountApplyPass)*100/creqCountTotal -1))%..."
# 		creqMsg="${passMsg:-${creqMsg:-${msg:-$displayName}}}"
# 		_creqEcho -v2 "PASS: $creqMsg"
# 		_creqLogStmtResult PASS
#
#
#
# 	### check FAILED case
# 	else
# 		# the check did not pass
# 		creqMsg="${noPassMsg:-${creqMsg:-${msg:-$displayName}}}"
# 		_creqEcho -v1 "FAIL: $creqMsg"
# 		(( creqCountNoPass++ ))
# 		_creqLogState
#
#
# 		### APPLY the change if we are in apply mode
# 		if creqIsApply; then
#
# 			# to protect against accidental changes we require an env variable to
# 			# be set also before we proceed to make any changes
# 			if [ ! "$creqWriteModeEnabled" ]; then
# 				_creqEcho -v0 "ERROR: readonly mode refusing to make changes to configuration"
# 				_creqLogStmtResult ERROR applyInROmode
# 				exit 59
# 			fi
#
# 			# call the apply method and report differently based on its exit code
# 			crSection="apply"
# 			_creqEcho -v1 -o "APPLYING...: $creqMsg"
#
# 			# this case statement can be removed eventually. the 'new' case seems to work well and will be all we need but until
# 			# it withstands the test of time, the case shows the alternative and allows easy testing. 'simple' is meant for debugging
# 			# we could select different methods based on verbosity if needed but I don't think that will be needed.
# 			creqMsg=""
# 			case new in
# 				orig)
# 					objectMethod=apply $classFn  \
# 						>  >(awk '{printf("     %-5s: %s\n","'"$crSection"'", $0);fflush()}' | tee -a $creqLogfile >>$creqStdout) \
# 						2> >(awk '{printf("   %-5s(ERR): %s\n","'"$crSection"'", $0);fflush()}' | tee -a $creqLogfile >>$creqStderr)
# 					applyResult=$?
# 					;;
#
# 				new)
# 					# the problem with this style of running the ::apply method in the sub process is that we are loosing
# 					#
# 					while IFS="" read -r line; do
# 						if [ "$line" == "---M(exit)M---" ]; then
# 							# this manual termination check was implemented 2015-10-21 b/c packageInstalled_mysql in siemServer_on would
# 							# hang after the apply was done and all output written to $creqLogfile
# 							break
# 						elif [[ "$line" =~ ^---M\(classMember\)M--- ]]; then
# 							_creqThisSyntaxHandler "${line#---M(classMember)M---}"
# 						else
# 							printf "     %s\n" "$line" | tee -a $creqLogfile >>$creqStdout
# 						fi
# 					done < <(
# 						this="echo ---M(classMember)M---"
# 						(objectMethod=apply $classFn 2>&1)
# 						local res=$?
# 						$this.applyResult="$res"
# 						echo "---M(exit)M---"
# 					)
# 					;;
#
# 				simple)
# 					objectMethod=apply $classFn
# 					applyResult=$?
# 					;;
# 			esac
#
# 			crSection="dtor "
# 			if [ $applyResult -eq 0 ]; then
# 				(( creqCountApplyPass++ ))
# 				creqMsg="${appliedMsg:-${creqMsg:-${msg:-$displayName}}}"
# 				_creqEcho -v1 -o "APPLIED: $creqMsg"
# 				checkResult=0
# 				local iz; for iz in ${!creqsChangetrackersActive[@]}; do creqsChangetrackersActive[$iz]="1"; done
# 				_creqLogStmtResult PASS APPLIED
# 			else
# 				creqMsg="${failedMsg:-${creqMsg:-${msg:-$displayName}}}"
# 				_creqEcho -v1 -o "ERROR($applyResult) in apply: $creqMsg"
# 				(( creqCountApplyError++ ))
# 				[ "$creqStopOnApplyError" ] && assertError "stop on apply error requested"
# 				_creqLogStmtResult FAIL errorInApply
# 				_creqLogState
# 			fi
# 			(( creqCountChange++ ))
# 		else
# 			_creqLogStmtResult FAIL
# 		fi
# 	fi
# 	crSection=""
# 	return $(( $checkResult + $applyResult ))
# }



# usage: _creqLogState
# This internal creq helper function that logs information about creq statement when it failes, based
# on the verbosity
function _creqLogState()
{
	if [ ${creqVerbosity:-0} -ge 4 ]; then
		creqLog0 "   creq state:"
		local classVar; for classVar in $classVars; do
			local __creqTmpVal
			printf -v __creqTmpVal "      > this.%-16s : '%s'"  "$classVar" "${!classVar}"
			creqLog0 "$__creqTmpVal"
		done
	fi
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


# # This is meant to be copied to make other cr_* functions/classes
# # usage: cr_boilerplate p1 p2
# # see man creq
# # declares that <TODO: description of what it declares>
# function cr_boilerplate()
# {
# 	case $objectMethod in
# 		objectVars) echo "p1 p2=5 localVar1" ;;
# 		construct)
# 			# TODO: replace these sample variables with the real ones
# 			p1="$1"
# 			p2="$2"
# 			localVar1="$p1 + $p2"
# 			displayName="<TODO: terse description that will show on outputs>"
# 			;;
#
# 		check)
# 			# TODO: replace with a real check.
# 			[ "$localVar1" == "this + that" ]
# 			;;
#
# 		apply)
# 			# TODO: replace with code to make a config change
# 			echo "change something here using $p1, $p2, $localVar1, etc..."
# 			;;
#
# 		*) cr_baseClass "$@" ;;
# 	esac
# }


##############################################################################################
### lifecycle functions to initialize the environment to run cr_ statements and to report
#   on what happened afterward.
#
# typically:
#     creqInit check verbosity:1
#
#     cr_fileExists foo
#     cr_iniParamExists foo . myName myValue
#     ...
#     creqReport

declare -A creqsChangetrackers
declare -A creqsChangetrackersActive
declare -A creqsTrackedServices
declare -A creqsTrackedServicesActions


# # usage: creqInit action verbosity
# # this function sets the environment for using subsequent calls to creq
# # in a certain way.
# #	action: can be "check" or "apply"
# #			check: will cause subsequent creq calls to only report compliance
# #			apply: will cause subsequent creq calls to apply changes if needed
# #				to use 'apply' the env var 'creqWriteModeEnabled' must be
# # 				non-empty
# #	verbosity: control how much information will be written to standard out
# #			0: terse.   only display a summary at the end
# #			1: default. also display a msg at the start, line for each item that fails the check
# #			2: verbose. also display a line for every item checked
# #			3: debug1.  also display all stderr output produced by creq items
# #			4: debug2.  also display all stderr and stdout output produced by creq items plus log entering each method.
# # TODO: rewrite. there are now better techniques to implement this. the creqs was implemented as the very first OO organized bash feature
# function creqInit()
# {
# 	declare -gx creqCollectFlag="" creqRunLog="" creqProfileID="transientStatements"
# 	while [[ "$1" =~ ^- ]]; do case $1 in
# 		--profileID) creqProfileID="$2"; shift ;;
# 		--collect)   collectPreamble && creqCollectFlag="1" ;;
# 		--runLog)    creqRunLog="$2"; shift ;;
# 	esac; shift; done
# 	declare -gx  creqAction="${1:-check}"
# 	declare -gx  creqVerbosity="${2#*:}" # support 'N' and 'verbosity:N'
# 	creqVerbosity="${creqVerbosity:-2}"
#
# 	if [[ ! "$creqAction" =~ (check)|(apply) ]]; then
# 		assertError "creqInit called with unknown action '$creqAction'"
# 	fi
#
# 	declare -gA creqRunningPluginType=""
# 	declare -gA creqRunningProfileName="$creqProfileID"
# 	[[ "$creqProfileID" =~ : ]] && splitString -d":" "$creqProfileID" creqRunningPluginType creqRunningProfileName
#
#
# 	# init the vars using in the change tracking mechanism. creqsChangetrackers holds all
# 	# varNames that we are tracking and creqsChangetrackersActive holds just the ones that
# 	# are currently tracking. When a apply block is done, all active varNames are set to "1"
# 	declare -gA creqsChangetrackers=()
# 	declare -gA creqsChangetrackersActive=()
#
# 	declare -gx creqStderr="/dev/null"; [ ${creqVerbosity:-0} -ge 3 ] && creqStderr="/dev/stderr"
# 	declare -gx creqStdout="/dev/null"; [ ${creqVerbosity:-0} -ge 4 ] && creqStdout="/dev/stdout"
#
# 	declare -gx creqCountTotal=0             # +count every creq statment
# 	declare -gx creqCountCtorError=0         #    An error ocured outside of check and apply methods
# 		                                     #    + (uncounted)
# 	declare -gx creqCountCheckError=0        #       the ones the have a error in check method so we don't know the pass state -- assumed noPass
# 	declare -gx creqCountPass=0              #       the ones that pass cleanly (no errors)
# 	declare -gx creqCountNoPass=0            #       +the ones the do not pass cleanly (no errors)
# 	declare -gx creqCountChange=0            #           +any that apply was called
# 	declare -gx creqCountApplyPass=0         #              apply was called and exited cleanly
# 	declare -gx creqCountApplyError=0        #              apply was called but had errors
# 	declare -gx creqCompleteness="0/1"
# 	declare -gx creqCompletenessPercent="0%..."
#
# 	declare -gx crSection=""
# 	declare -gx creqStopOnApplyError=""; [ "$creqVerbosity" -gt 3 ] && creqStopOnApplyError="1"
#
# 	declare -gx _creqProfileLog
# 	if [ "$creqProfileID" ] && [ "$creqCollectFlag" ]; then
# 		_creqProfileLog="${scopeFolder%/}/collect/creqs/$creqProfileID"
# 		domTouch "${_creqProfileLog}.statements"
# 		domTouch "${_creqProfileLog}.results"
# 		domTouch "${_creqProfileLog}.applyLog"
# 		# truncate and write header (-H) to the profle's statement log
# 		_creqLogStmtResult -H
# 	else
# 		_creqProfileLog="$(mktemp)"
# 	fi
#
# 	declare -gx creqTestLog=$(mktemp)
# 	declare -gx creqLogfile
# 	#bgtraceIsActive && creqLogfile="$(bgtraceGetLogFile)"
# 	if creqIsApply && [ "$creqApplyLog" ] && touch "$creqApplyLog" 2>/dev/null; then
# 		creqLogfile="$creqApplyLog"
# 	fi
# 	if [ ! "$creqLogfile" ]; then
# 		creqLogfile="$(mktemp)"
# 		declare -gx creqLogfileIsTmp="1"
# 	fi
#
# 	declare -gx creqStartTimeFile=""
# 	if creqIsApply; then
# 		creqStartTimeFile=$(mktemp)
# 		touch "$creqStartTimeFile"
# 	fi
#
# 	[ ${creqVerbosity:-1} -ge 1 ] && printf "%s: (%s)\n"  "$creqProfileID" "$creqAction";
# 	creqLog0 "start '$creqProfileID'"
#
# 	echo "" >> "$creqLogfile"
# 	echo "" >> "$creqLogfile"
# 	echo "#################################################################################################" >> "$creqLogfile"
# 	echo "### creqInit $*" >> "$creqLogfile"
# 	echo "### creqProfileID=$creqProfileID" >> "$creqLogfile"
# 	echo "### run by '$USER' at $(date)" >> "$creqLogfile"
# }


# # usage: creqReport
# # End the run of cr_ statements. report the stats of what happened.
# # this is typically called only by bg-creqCntr and bg-standards.
# function creqReport()
# {
# 	creqLog0 "finish '$creqProfileID'"
#
# 	local resultCode=0
# 	if [ "$creqStartTimeFile" ]; then
# 		rm "$creqStartTimeFile"
# 	fi
#
# 	local profIDLabel
# 	if [ ${creqVerbosity:-1} -lt 1 ]; then
# 		printf -v profIDLabel "%-30s: " "$creqProfileID"
# 	fi
#
# 	for service in "${!creqsTrackedServices[@]}"; do
# 		creqServiceAction "$service" "${creqsTrackedServicesActions[$service]}" "${creqsTrackedServices[$service]}"
# 	done
#
# 	creqCompleteness="$((creqCountPass+creqCountApplyPass))/${creqCountTotal}"
# 	creqCompletenessPercent="$(((creqCountPass+creqCountApplyPass)*100/((creqCountTotal) ? creqCountTotal : 1)))%"
# 	if [ ${creqCountTotal:-0} -gt 0 ]; then
# 		if ! creqIsApply; then
# 			if [  $creqCountPass -eq $creqCountTotal ]; then
# 				echo "   ${profIDLabel}pass: all $creqCountTotal statements comply with configuration goals"
# 			elif [ $((creqCountPass+creqCountNoPass)) -eq $creqCountTotal ]; then
# 				echo "   ${profIDLabel}fail: $creqCountNoPass out of $creqCountTotal statements do not comply with configuration goals"
# 			else
# 				echo "   ${profIDLabel}fail:"
# 				[ $creqCountNoPass -gt 0 ] && echo "      $creqCountNoPass statements do not comply with configuration goals"
# 			fi
#
# 		else
# 			if [ $creqCountPass -eq $creqCountTotal ]; then
# 				echo "   ${profIDLabel}pass: all $creqCountTotal statements already complied with configuration goals"
# 			elif [ $((creqCountPass+creqCountApplyPass)) -eq $creqCountTotal ]; then
# 				echo "   ${profIDLabel}pass: $creqCountChange configuration statements were applied and now all $creqCountTotal statements comply"
# 			else
# 				echo "   ${profIDLabel}fail:"
# 				[ $creqCountApplyError -gt 0 ] && echo "      $creqCountApplyError statements failed while applying changes and may not comply with configuration goals"
# 			fi
# 		fi
# 	else
# 		echo "   ${profIDLabel}pass: no configuration statements are required in this configuration"
# 	fi
# 	[ ${creqCountCheckError:-0} -gt 0 ] && echo "      $creqCountCheckError statements had errors while performing checks"
# 	[ ${creqCountCtorError:-0} -gt 0 ]  && echo "      $creqCountCtorError statements had errors while consctructing the creq object"
# 	resultCode=$(( creqCountApplyError + creqCountCheckError + creqCountCtorError ))
#
# 	if [ $((creqVerbosity + ((resultCode>0)?1:0) )) -ge 3 ]; then
# 		echo "   details of this run logged in '$creqLogfile'"
# 	else
# 		[ "$creqLogfileIsTmp" ] && rm $creqLogfile
# 	fi
#
# 	rm ${creqTestLog}.out ${creqTestLog}.err ${creqTestLog} &>/dev/null
#
# 	local cols="server    pluginType profileName       total passPercent             pass  applyPass  fail   applyError checkError  statementError"
# 	#           scopeName creqRunningPluginType creqRunningProfileName  Total creqCompletenessPercent Pass  ApplyPass  NoPass ApplyError CheckError  CtorError
# 	local fmtStr="%-18s %13s %-20s %5s  %11s  %4s  %9s  %4s  %10s  %10s  %14s\n"
# 	printf "$fmtStr" $cols > "${_creqProfileLog}.results"
# 	printf "\n"  >> "${_creqProfileLog}.results"
# 	printf "$fmtStr" "${scopeName:--}" "${creqRunningPluginType:---}" "${creqRunningProfileName:---}" "$creqCountTotal" "$creqCompletenessPercent" "$((0+creqCountPass+creqCountApplyPass))"  "$((0+creqCountNoPass-creqCountApplyPass))" "$creqCountApplyError" "$creqCountCheckError"  "$creqCountCtorError" >> "${_creqProfileLog}.results"
#
# 	return $resultCode
# }

##############################################################################################
### functions to use in cr_* sections / lists to augment and add features
#   For example to keep track of what has changed to know if a daemon needs to be restarted


# usage: if creqGetState; then ...
# returns "check", "apply", or empty string to indication whether the creq system is running and in what state
function creqGetState() { echo "$creqAction"; }

# usage: if creqIsCheck; then ...
# test if the configuration required system is in the 'check' mode
function creqIsCheck() { [ "$creqAction" == "check" ]; }

# usage: if creqIsApply; then ...
# test if the configuration required system is in the 'apply' mode
function creqIsApply() { [ "$creqAction" == "apply" ]; }

# usage: creqLog0 ...
# write to the log file even if the level is 0 (typically when the user specifies -q)
function creqLog0()
{
	if [ "$crSection" ]; then
		echo "$*"
	elif [ "$creqStdout" ]; then
		echo "$*" | awk '{printf("--- %s\n", $0)}' | tee -a $creqLogfile  >>$creqStdout
	fi
	true
}

# usage: creqLog1 ...
# write to the log file if verbosity is level 1 or more (default is level 1)
function creqLog1() { [ ${creqVerbosity:-0} -ge 1 ] && creqLog0 "$*"; true; }

# usage: creqLog2 ...
# write to the log file if verbosity is level 2 (typically when user specifies -v)
function creqLog2() { [ ${creqVerbosity:-0} -ge 2 ] && creqLog0 "$*"; true; }

# usage: creqLog3 ...
# write to the log file if verbosity is level 3 (typically when user specifies -vv)
function creqLog3() { [ ${creqVerbosity:-0} -ge 3 ] && creqLog0 "$*"; true; }

# usage: creqLog4 ...
# write to the log file if verbosity is level 4 (typically when user specifies -vvv)
function creqLog4() { [ ${creqVerbosity:-0} -ge 4 ] && creqLog0 "$*"; true; }



# # usage: creqsDelayedServiceAction [-s] <serviceName>[:<action>] [<varName>]
# # declare that the specified servive should have an action performed at the end of the creq profile run
# # this is typically used in creqConfigs. The more typical pattern is to wrap some creq statements in
# # creqsTrackChangesStart and creqsTrackChangesStop calls so that the service will be flagged for an action
# # only if some creq statements result in configuration changes being applied. This function unconditionally
# # flags the service/action to happen.
# function creqsDelayedServiceAction()
# {
# 	while [[ "$1" =~ ^- ]]; do case $1 in
# 		-s) nothing="-s" ;;
# 	esac; shift; done
# 	local serviceName serviceAction varName
# 	serviceName="$1"
# 	[[ "$serviceName" =~ : ]] && splitAttribute "$serviceName" serviceName serviceAction
# 	local varName="${2:-$serviceName}"
# 	creqsTrackedServices["$serviceName"]="$varName"
# 	creqsTrackedServicesActions["$serviceName"]="${serviceAction:-restart}"
# 	creqsChangetrackers[$varName]="1"
# }

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
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s*) serviceName="$(bgetopt "$@")" && shift
			[[ "$serviceName" =~ : ]] && splitAttribute "$serviceName" serviceName serviceAction
			varName="${2:-$serviceName}"
			creqsTrackedServices["$serviceName"]="$varName"
			creqsTrackedServicesActions["$serviceName"]="${serviceAction:-restart}"
			;;
	esac; shift; done
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
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s*) serviceName="$(bgetopt "$@")" && shift
			[[ "$serviceName" =~ : ]] && splitAttribute "$serviceName" serviceName serviceAction
			varName="${2:-$serviceName}"
			;;
	esac; shift; done
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




##############################################################################################
### internal functions

# # usage: _creqEcho [-o] [-v <level>] ... text ...
# # internal function used to display progress of a creqs execution.
# # Options:
# #    -o : overwrite. move cursor back to the previous line. If you use -o with single line output
# #         each call will replace the last line
# #    -v<level> : verbosity threshold. the level at which this message should be displed.
# #         e.g. a msg sent with -v3 will only be output when verbosity is 3 or higher
# function _creqEcho()
# {
# 	local overWriteFlag=""
# 	local vLevel=""
# 	while [[ "$1" =~ ^- ]]; do case $1 in
# 		-o) overWriteFlag="1" ;;
# 		-v) vLevel="$2"; shift ;;
# 		-v*) vLevel="${1#-v}" ;;
# 	esac; shift; done
#
# 	# if the verbosity is 3 or more or if we are not writing to a terminal, turn off overwrite even if it was asked for
# 	[ ! -t 1 ] && overWriteFlag=""
# 	[ ${creqVerbosity:-1} -ge 3 ] && overWriteFlag=""
#
# 	# 2015-09 bg: not sure why this line check for "^/dev". Why wouldn't this be like the rest?
# 	[[ ! "$creqLogfile" =~ ^/dev ]] && echo "$*" > >(awk '{print "  # : "$0}' >>$creqLogfile)
#
# 	if [ ${creqVerbosity:-1} -ge ${vLevel:-0} ]; then
# 		[ "$overWriteFlag" ] && echo -en "\033[1A"  # move cursor back up one line to overwrite the last message
# 		echo -en "${@}"  | wrapLines "   " "      "
# 		[ "$overWriteFlag" ] && echo -en "\033[K"  # clear to eol
# 		echo
# 	fi
# }


# # usage: _creqTrapExitingCrStmts
# # internal function used in trap .. EXIT by creqs()
# function _creqTrapExitingCrStmts()
# {
# 	sync
# 	(
# 		awk '{print "      (stderr): "$0}' "${creqTestLog}.err"
# 		_creqEcho -v1 "ERROR: creq run ended prematurely in $classFn::$objectMethod"
# 		local -A stackFrame=(); bgStackGetFrame creq-1 stackFrame
# 		assertError -v classFn -v objectMethod -v file -v lineno -v function -v scriptLine "
# 			       $classFn::$objectMethod called exit/assert and has ended the creq run prematurely.
# 			       this function should use return instead of exit. The equivalent to exit in creq class
# 			       methods is to write an error message to stderr and return n. This error can be fixed by
# 			       enclosing the exit with (). Typically that means putting assert calls in ().
# 			       For example: use '(assertNotEmpty myRequiredVar) || return'
# 			       to assert an error condition. Make sure that any class variable assignments are not
# 			       inside any (). The offending line is...
# 			          ${stackFrame[printLine]}
# 		"
# 	)
# }



# # usage: _creqLogStmtResult <result> <resultDetail>
# # usage: _creqLogStmtResult -H
# # TODO: refactor this whole module.
# # this is a temp measure. Its used in similar places to _creqEcho but only the places where creq statement ends.
# # so this is called exactly once per statement
# function _creqLogStmtResult()
# {
# 	# TODO: record parameters too in a separate file keyed on (creqProfileID,_creqUID)
# 	if [ "$_creqProfileLog" ]; then
# 		local fmtStr="%-18s %13s %-20s %-18s %-7s %12s %-18s \n"
# 		if [ "$1" == "-H" ]; then
# 			printf "${fmtStr}\n" "server" "pluginType" "profileName" "stmtID" "result" "resultDetail" "stmtType"  > "${_creqProfileLog}.statements"
# 		else
# 			local result="$1"
# 			local resultDetail="$2"
#
# 			# if it passes because we just applied the statement, record the timestamp in a log that grows
# 			if [ "$result:$resultDetail" == "PASS:APPLIED" ]; then
# 				# we don't record the APPLIED in the state file because on the next run, it will change again to PASS:-- and we want to avoid double commits like that
# 				# the growing apply log file will change just once per APPLY
# 				resultDetail=""
#
# 				local fmtStr2="%-19s %-10s %-18s %13s %-20s %-18s %-18s \n"
# 				if [ ! -s "${_creqProfileLog}.applyLog" ]; then
# 					printf "${fmtStr2}\n" "time" "timeEpoch" "server" "pluginType" "profileName" "stmtID" "stmtType"  > "${_creqProfileLog}.applyLog"
# 				fi
# 				local nowTS="$(date +"%s")"
# 				local nowStr="$(date +"%Y-%m-%d:%H:%M:%S")"
# 				printf "$fmtStr2" "${nowStr:--}" "${nowTS:--}" "${scopeName:--}"  "${creqRunningPluginType:---}" "${creqRunningProfileName:---}" "${_creqUID:---}" "${classFn:---}"  >> "${_creqProfileLog}.applyLog"
# 			fi
#
# 			printf "$fmtStr" "${scopeName:--}" "${creqRunningPluginType:---}" "${creqRunningProfileName:---}" "${_creqUID:---}" "${result:---}" "${resultDetail:---}" "${classFn:---}"  >>"${_creqProfileLog}.statements"
# 		fi
# 	fi
# }


# # usage: _creqLogMarker ...
# # Writes the content passed on the command line to the log file decorated as a marker section to indicate
# function _creqLogMarker()
# {
# 	sync
# 	echo "$*" > >(awk '
# 		NR==1{printf("\n### : %s\n", $0)}
# 		NR>1 {printf(  "  # : %s\n", $0)}
# 	' | tee -a $creqLogfile >>$creqStdout)
# 	sync
# }

# # usage: dn="$(creqMakeDisplayName "cr_funcName" "$@" )"
# # the creq function uses this to create a default display name when the cr_* function
# # does not define one
# function creqMakeDisplayName()
# {
# 	stringShorten -j fuzzy 90 "$@"
# }


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
