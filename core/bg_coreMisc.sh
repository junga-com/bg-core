#!/bin/bash

#######################################################################################################################################
### Misc Functions

# usage: myGIT_DIR="$(getGitDir [<gitFolder>])"
# in newer git versions, the .git folder in a subproject might be a file instead that has the path of the real .git folder
function getGitDir()
{
	local prefix=${1:-.}
	prefix=${prefix%/}
	if [ -d $prefix/.git ]; then
		echo "$prefix/.git"
	elif [ -f $prefix/.git ]; then
		local p="$(sed -ne 's/^[ \t]*gitdir:[ \t]*//p' $prefix/.git)"
		if [[ "$p" =~ ^/ ]]; then
			echo "$p"
		else
			echo "$prefix/$p"
		fi
	fi
}


# AWKLIB: awkMathLibraryStr : functions: min(a,b), max(a,b)
awkMathLibraryStr='
	function min(a,b) {return (a<b)?a:b}
	function max(a,b) {return (a>b)?a:b}
'

# usage: bgFloatEval <expression>
# evaluates the <expression> using awk so that it can contain floating point math.
# The following functions are available in addition to any builtin awk functions
#     min(a,b)
#     max(a,b)
function bgFloatEval()
{
	awk "$awkMathLibraryStr"'BEGIN{print ('"$*"' )}'
}

# usage: bgFloatCond <expression>
# returns true (0) or false(1) to reflect the math expression with can contain floating point numbers.
# the exression can be any valid awk condition
# The following functions are available in addition to any builtin awk functions
#     min(a,b)
#     max(a,b)
function bgFloatCond()
{
	awk "$awkMathLibraryStr"'BEGIN{if ('"$*"' ) exit(0); else exit(1)}'
}


##################################################################################################################
### cmd control -- suitible to leave in production code. supports having a -d (debug) option


# usage: cmdSw <action>
# typical usage: $(cmdSw $action1) <cmd...>
# typical usage: $(cmdSw $action1) <cmd...> | $(cmdSw $action2) <cmd2...> ...
# example:  $(cmdSw $findCntr) find $folder | $(cmdSw $awkCntr) awk '{print "i am awk, yo: "$0}'
#
# cmd switch. placing $(cmdSw $cntrOpt) in front of a cmd lets its execution and output be controlled dynamically
# with the <action> variable. The default when <action> is "" or "on" is that it will evaluate to an empty string
# and will have no impact on the cmd's invocation at all. This makes it efficient to leave in the code and not consider
# it debugging code that should be removed. A typical use is supporting the -d (debug) option for scripts that provide
# a wrapper over common linux commands. The operator can then use -d to print the command line that would have ran.
#
# TODO: consider changing to accept separate parameters that can be mixed and matched and then have the actions below
#       map to those settings or allow specifying them separately for finer control. This way we don't have to add
#       many actions for every possibility. However we may not need any more than is currently provided.
#       Example: would you want to 'skip' and 'echo' at the same time?
#    1) whether to run|dontRun (and what to do with stdin if cmd not ran) -- what to run cmd|cat|true
#    2) Whether to print the CmdLine (and where)
#    3) what to do with the output --  redirect destination or tee
#
# Params:
#    <action>  : one of these actions to perform on the pipe command.
#                Remember that these actions can only effect whether the cmd immediately following will execute. All remaining
#                pipe components will run, but depending on the <action>, they may or may not get any input to process.
#       ""      : do default action which is normally 'on' but can be changed by setting the cmdSw_DEFAULT ENV variable
#       on      : the cmd is 'on'. behave as if cmdSw is not present in front of the cmd. The cmd will run like normal.
#                 This really is equivalent to removing the $(cmdSw ...) term from the line manually.
#       off     : turn the cmd 'off'. silently ignore the cmd and and produce no output. Note the rest of the pipeline will
#                 still run and any redirects will be in effect. This is the same as replacing the command and all its arguments
#                 with the command 'true'
#       skip    : like off, but when used in the middle or end of a pipeline, it passes the pipeline output thru. This
#                 is the same as replacing the command and all its arguments with the command 'cat'
#       skipAll : like skip but copies stdin to stderr instead of stdout so that the output will not go through any of the
#                 remaining pipeline elements. This is the same as replacing the command and all its arguments with the
#                 command 'cat >&2'
#       echo    : like 'off' but also print the bash prepared cmd line to stderr so that the operator can see what would have ran
#       bgtrace : like 'on' but also print the bash prepared cmd line to the bgtrace destination,
#                 Note, that unlike the "on" command, bgtrace is active and has to prepare the command so that it runs correctly
#                 with eval. It should be equivalent but its possible that it won't be.
#       tee <file> : like 'on' but grab a copy of the command's output to 'log' somewhere. This is particularly useful in pipes
#                 to get the partially processed commands.
#
# BGENV: cmdSw_DEFAULT : the default action for cmdSw function
#
function cmdSw()
{
	local action="${1:-${cmdSw_DEFAULT}}"; [ $# -gt 0 ] && shift

	# when the case statement returns the name of one of these functions, they will get called with the tokens of the
	# cmd and args passed in as cmd line input to the function. cmd will be $1, the first argument $2, etc..
	# The tokens have gone thru all the bash preparation steps so that variable expansion, command substitution, etc..
	# have all been done. We can iterate "$@" to get each token separately. Any given element could contain spaces, $
	# and other special bash chars but since they just went through the bash line processing, what ever is there is plain
	# data that is to be sent to the cmd as parameters. As such, we should single quote them before using eval to run the
	# command. eval can not accept pre word splitted data. No matter how you pass it, hte data will be processed by bash
	# as one combined string token that word splitting is applied to.

	# do nothing. makes the command go away like its been replaced with the command 'true'
	function _cmdSw_off() { return; }

	# ignore "$@" but pass stdin on to stdout so that piplines remain intact, just without this part
	function _cmdSw_skip() { cat; }

	# ignore "$@" and redirect stdin to stderr which will bypass the rest of the pipeline parts and display to the terminal (typically)
	function _cmdSw_skipAll() { cat >&2; }

	# print the cmd line to stderr instead of running the command
	function _cmdSw_echo()
	{
		local longFormatFlag=""
		while [[ "$1" =~ ^- ]]; do case $1 in
			-l) longFormatFlag="-l" ;;
			-n) lineNumbers="-n" ;;
		esac; shift; done

		local cmdTokens
		cmdTokensToArray cmdTokens "$@"
		if [ "$longFormatFlag" ]; then
			echo "cmdSw: ${cmdTokens[0]}" >&2
			cmdTokens=( "${cmdTokens[@]:1}" )
			local i; for i in "${!cmdTokens[@]}"; do
				echo "  \$$i = ${cmdTokens[$i]}" >&2
			done
		elif [ "$lineNumbers" ]; then
			echo "${cmdTokens[@]}" | cat -n >&2
		else
			echo "${cmdTokens[@]}" >&2
		fi
	}


	# print the cmd line to stderr instead of running the command
	function _cmdSw_writeTo()
	{
		local file="$1"; shift
		echo "$*" >"$file"
	}


	# print the cmd line to the bgtrace destination, and run the cmd so that it should behave normally
	function _cmdSw_bgtrace()
	{
		local longFormatFlag=""
		while [[ "$1" =~ ^- ]]; do case $1 in
			-l) longFormatFlag="-l" ;;
		esac; shift; done

		local cmdTokens
		cmdTokensToArray cmdTokens "$@"
		if [ "$longFormatFlag" ]; then
			bgtrace "cmdSw: ${cmdTokens[0]}"
			cmdTokens=( "${cmdTokens[@]:1}" )
			local i; for i in "${!cmdTokens[@]}"; do
				bgtrace "  \$$i = ${cmdTokens[$i]}"
			done
		else
			bgtrace "cmdSw: ${cmdTokens[@]}"
		fi

		eval "${cmdTokens[*]}"
	}

	# run the cmd but send its output thru tee so that it gets recorded and gets sent through to stdout so that
	# it runs normally. As a special case, if filename is "bgtrace" the tee desination will be set to the bgtrace
	# destination, if set and it will be a noop if bgtrace is not active
	function _cmdSw_tee()
	{
		local filename="$1"; [ $# -gt 0 ] && shift
		local cmdTokens
		cmdTokensToArray cmdTokens "$@"
		if [ "$filename" == "bgtrace" ]; then
			eval "${cmdTokens[*]}" | tee "$filename"
		else
			eval "${cmdTokens[*]}" | tee "$filename"
		fi
	}

	case ${action} in
		on)      return ;;  # returning nothing makes our term disappear in the cmd line
		off)     echo _cmdSw_off     "$@" ;;
		skip)    echo _cmdSw_skip    "$@" ;;
		skipAll) echo _cmdSw_skipAll "$@" ;;
		echo)    echo _cmdSw_echo    "$@" ;;
		writeTo) echo _cmdSw_writeTo "$@" ;;
		bgtrace) echo _cmdSw_bgtrace "$@" ;;
		tee)     echo _cmdSw_tee     "$@" ;;
	esac
}

# we need to call it once to bring its inside functions into scope. I think its neater to have those function inside
cmdSw


# usage: cmdTokensToArray <cmdTokensVar> <cmd line ...>
# This takes the cmd line passed in from $2 on .. and populates the <cmdTokensVar> array with elements that correspond
# to each token $N in the cmd line. Each element is in the form of a single quoted string which will preserve the meaning
# of the command (i.e. word splitting) when used in eval
# Example:
#   local cmdAry
#   cmdTokensToArray cmdAry grep -i ./foo.txt ".*jim's stuff$"
#   eval ${cmdAry[*]}  # the regex will be interpreted as one token  '.*jim'\''s stuff$'
# Note that eval does not respect the word split done when making the eval statement.
#   eval grep -i ./foo.txt ".*jim's stuff$"
# becomes
#   eval "grep -i ./foo.txt .*jim's stuff$"
# The quotes get removed and ".*jim's stuff$" becomes ".*jim's" "stuff$" to the grep command.
# so eval "$@" will not work even if ".*jim's stuff$" occupies one element because when its expanded it will loose the quotes
function cmdTokensToArray()
{
	local cmdTokensVar="$1"; [ $# -gt 0 ] && shift
	local cmdTokensValue i q="'";

	# assume that the first token which is the cmd name does not have any special chars that would break the word
	cmdTokensValue="$1"; [ $# -gt 0 ] && shift

	# unconditional add single quotes to all other tokens. We could probably check for a set of special chars (space, $, etc..)
	# but its more conservative to do all of them. The only special character inside a single quote string is the single
	# quote char itself. We can represent a single quote, like 'this is bob'\''s pencil'. To bash this is 3 strings with no space
	# between them so they get concatenated. the middle string is just the escaped single quote \'
	for i in "$@"; do
		cmdTokensValue+=("${q}${i//\'/\'\\\'\'}${q}")
	done

	eval $cmdTokensVar=\( \"\${cmdTokensValue[@]}\" \)
}
