
# Library bg_outOfBandScriptFeatures.sh
# Out of Band (OOB) Functions are functions that deal with scripts as generic maintainable entities.
# In-band is the subject that the script is written to perform and can be anything. Out-of-band are the things
# that a script needs to support to be a good citizen in the OS and package environment.
#
# oob_invokeOutOfBandSystem is a logical part of this library that is a core function in bg_coreLibsMisc.sh. Scripts should call
# that function before they start doing their real work or processing their cmdline paramters. That function examines the cmdline
# parameters and will invoke callbacks functions in the script to perform bash completion processing or help system functions.
# This full library will be imported (aka sourced) before callbacks are invoked so a script does not need to import this library
# explicitly
#
# Out-Of-Band Mechanisms:
#    cmdline line syntax : common conventions for cmdline options and positional commands.
#    cmdline completion : support for providing cmdline completion UI
#    user and group selection : tie into rbacPermissions
#    man pages : invoke via cmdline. all commands have man(1) pages. libraries have man(3ba) pages for each public function
#    daemon support : daemon scripts have a common interface
#    package management : hook actions
# OOB are functions that are in the domain of programming scripts as opposed to the domain of
# what ever it is that a command does.




#######################################################################################################################################
### OOB Core

#function oob_invokeOutOfBandSystem() moved to bg_coreLibsMisc.sh

#######################################################################################################################################
### BASH Cmdline Option Processing Helper functions

#function bgOptionsEndLoop  moved to bg_corelibsMisc.sh
#function bgOptionGetOpt    moved to bg_corelibsMisc.sh



#################################################################################################################################
### Cmdline processing based on syntax strings
# The syntax string can be either a getopts style optspec like "qvf:" or a usage string like "[-q] [-v] [-f <filename>] <param1> ..."
# or a hybrid that starts as a optspec and then after a space inlcudes a usge string.



# usage: bgCmdlineParseBC <cmdlineSyntaxStr> <cword> <cmdName> [<arg1> ... <argN>]
#        bgCmdlineParseBC "<glean>" "$@"; set -- "${posWords[@]:1}"
#        bgCmdlineParseBC "fvqC:"   "$@"; set -- "${posWords[@]:1}"
# This function parses the cmdline arguments according to the syntax described in <cmdlineSyntaxStr>. It can produce three types of
# output.
#    1) it can write out bash completion information to stdout. See man(3) _bgbc-complete-viaCmdDelegation
#       based on the <cmdlineSyntaxStr> alone, it produces BC output for options, comment tokens to indicate the name of an argument
#       being completed and suggestions for arguments if literal tokens are included in the syntax (e.g. <param1>|one|two)
#    2) clInput[] associative array. This stores the values of the cmdline arguments indexed by canonical option name, positional
#       index, or named positional argument. This allows the caller to query the values specified on the command line directly.
#    3) environment variables to aid in producing additional BC output. This includes the traditional variables (cur,prev,cword,words[])
#       and also new variables (completingType, completingArgName, optWords[], posWords[], posCwords)
#
# The Structure of a Cmdline:
# This function parses cmdline arguments following the *nix tradition where optional arguments begin with a '-' and may or may not
# have an argument. Options appear first and the first non-option argument ends the options section and begins the positional section.
# When an option requires an argument, the option and argument can be combined into one token or can be separate in two tokens.
# When its in a separate token, the argument token is part of the options section even though it does not begin with a '-'. It is
# distinguished from the first positional token by the token preceeding it being an option which is known to require an argument.
#
# When a cmd supports sub cmds, its common for arguments that look like options to also appear in the positional section. Those
# will be parsed as positional arguments.
#
# The Syntax of a Cmdline:
# The caller passes in <cmdlineSyntaxStr> which describes the options and positional arguments that will be expected. At a minimum,
# it needs to idenify which options requre arguments so that the cmdline can be unambiguously parsed into optional and positional
# sections. (b/c otherwise the option arg can look like the first positional arg). In addition, describe the full syntax so that
# this function can provide the basic bash completion information for the user to understand what can and should be entered.
#
# Two standards are supported to provide the syntax information in the <cmdlineSyntaxStr>. First is the simple optspec syntax used
# by the man(1) getopts command. That is a list of short (single letter) options with a ':' following any option that requires an
# argument. An extension to this syntax is that the ':' can be replaces with '<argName>' to indicate not only that the preceeding
# option requires an argument, but also that that argument's name is 'argName'. Argument names are used in bash completion to let
# the user know what type of argument is expected.
#
# The second is 'usage:' syntax. This is the string used to document the accepted syntax to humans. The bg-core style of scripting
# starts the comment block for functions and commands with a usage: line. See man(3) bgMakeUsageSpec for the complete description
# of <cmdlineSyntaxStr>
#
# Common Pattern:
# This function is typically called from a cmd's oob_printBashCompletion function. <cmdlineSyntaxStr> is set to the text from the
# usage line in a function's comments or man page. This alone will result in the basic bash completion where options can be completed
# and the user sees the name of the argument that is being completed both for arguments to options and positional arguments.
#
# Next, you can case on completingArgName to provide suggestions for each type of argument. The code for each case can refer to the
# clInput array to find the values of options and positional arguments that have already been entered on the command line.
#
# Params:
#    <cmdlineSyntaxStr>  : the cmdline syntax. See man(3) bgMakeUsageSpec
#    <cword> : the token position in the cmdline that the user is currently completing.
#    <cmdName> : ($0) the name of the command whose commandline is being completed
#    <argN>  : ($[0-9]) parameters on the command line
#
# Output Vars:
# This function returns its results in these well-known variables. The caller can declare these local before calling this function
# to prevent them from becomeing global variables. The invokeOutOfBandSystem function does that so when used inside an oob_* callback
# you dont need to.
#    $completingArgName: this contains the name of the argument being completed as described in the <cmdlineSyntaxStr> usage syntax.
#         If an option is being completed or the <cmdlineSyntaxStr> did not name the argument being completed it will be empty.
#         Given "[-f <inputfile>] [-o <outfile>] <cmd>", $completingArgName will be '<inputfile>', '<outfile>', '<cmd>' or '' depending
#         on what is currently being completed.
#    $<clInput>[<arg>]=<value> : associative array filled in with the values of completed arguments on the cmdline. For options,
#         <arg> is the first option in a group of aliases. For example, given "[-f|--file=<myfile>] <cmd>", '-f' would be the key
#         where the value for <myfile> would be stored. Positional arguments are stored in the array twice, once as the numeric
#         position index and again as the name associated with that position. In this example the value for <cmd> would be stored
#         under the keys '1' and 'cmd'. For options without arguments, the value stored in the array is the name of the option.
#    $opt : (OBSOLETE) indicates if an option or its required argument is being completed. If its empty, a positional param is being
#         completed. It will contain one of these values.
#         ""         : if $opt is the empty string, the user is completing a positional argument (not an optional argument)
#         "@options" : the  user is completing an option but has not yet typed enough characters to identify which option. The
#                      suggestions are the list of supported options. This is case is typically handled suficiently by this
#                      function and the caller typically does not have to respond to this case but can add additional suggestions.
#         <option>   : if $opt contains the name of an option, that option requires an argument that is being completed. The
#                      caller typically handles this case to provide the valid suggestions for this option's argument.
#    $posWords[<n>]: this is words[] with the optional arguments removed. [0] is the command name. <n> matches what $<n> would be
#         inside the function after it processes its options.
#    $posCwords: is the index into $posWords of the word being completed. If it is 0, it means an option is being completed.
#    $optWords[] : this is the leading part of $words[] that contains the optional arguments and their arguments.
# Traditional bash completion function variables.
#    $words[<n>] $cword : words[] is an array of the entire cmdline. [0] is the command name. <n> matches what $<n> would be in the
#          function BEFORE it processes options.
#    $cword : the index in $words[cword] that is being completed
#    $cur : $cur is the current word being completed. It contains only the text behind the cursor which is the text that is
#         subject to change. Its coresponding word in words[$cword] will contain the whole word that is on the command line
#    $prev : $prev is the token before the one being completed. This is provided because the bash_completion project makes it
#         available but it is not typically used because other variables provide better information.
# See Also:
#    bgCmdlineParseBC  : meant for use in oob_printBashCompletion() functions. deos basic completion based on the provided <cmdlineSyntaxStr>
#                 and fills in clInput[] with any completed arguments from the cmdline. Also sets variables used to provide additional
#                 completion info.
#    bgCmdlineParse : meant for use in a function or cmd as an alternative to the standard options loop and positional assignment
#    bgMakeUsageSpec : used by bgCmdlineParseBC and bgCmdlineParse. 'compiles' a <cmdlineSyntaxStr> into an associative array with information
#                 about the syntax.
#    parseForBashCompletion : (OBSOLETE: use bgCmdlineParseBC)
#    invokeOutOfBandSystem : provides inline bash completion mechanism for scripts (among other things)
#    _bgbc-complete-viaCmdDelegation: documents the bash completion protocol written to stdout by inline BC routines
function bgBCParse() { bgCmdlineParseBC "$@" ; }
function bgCmdlineParseBC()
{
	local retVar
	while [ $# -gt 0 ]; do case $1 in
		-R*|--retVar*)  bgOptionGetOpt val: retVar "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	# remove and process the args to this function, leaving the cmdline being parsed in "$@"
	local cmdlineSyntaxStr="$1"; shift
	cword="${1:-1}"; shift; [[ ! "$cword" =~ ^[0-9]*$ ]] && assertError "the second parameter must be a number"
	words=( "$@" )
	shift # cmdName ($0)
	cur=""
	prev=""
	options=()
	completingArgName=""
	completingType=""
	optWords=()
	posWords=()
	posCwords=0

	local -n _clInputValue="${retVar:-options}"
	_clInputValue=()
	varIsAMapArray _clInputValue || assertError "The output variable '$retVar' must be declared as an associative array like 'declare -A $retVar' before calling this function"

	local -A syntaxSpec=()
	bgMakeUsageSpec "$cmdlineSyntaxStr" syntaxSpec
	#bgtraceVars syntaxSpec

	cur="${words[$cword]}"
	((cword>1)) && prev="${words[$(( $cword-1 ))]}"

	### this loop consumes the options and their arguments from the front end of the parameter list
	local _bcp_optPos=0 rematch canonOpt opt
	while [[ "$1" =~ ^- ]]; do
		local _bcp_opt="$1"; shift; ((_bcp_optPos++))
		optWords+=("$_bcp_opt")

		# if the token is a string of concatonated short options (this does not include a single short option with or without an arg)
		if match "$_bcp_opt" "^-[^-][^-]" rematch && [ "${syntaxSpec[-${_bcp_opt:1:1}]:-NOARG}" == "NOARG" ]; then
			# add each leading short option without arg to _clInputValue.
			for ((i=1; i<${#_bcp_opt}; i++)); do
				[ "${syntaxSpec[-${_bcp_opt:$i:1}]:-NOARG}" != "NOARG" ] && break
				opt="-${_bcp_opt:$i:1}"
				canonOpt="${syntaxSpec[canon:$opt]:-$opt}"
				_clInputValue[$canonOpt]="$opt"
			done

			if ((_bcp_optPos==cword)); then
				# if $i points to a a letter (and not one past the end), it means that letter is a short option with an argument
				if [ "${_bcp_opt:$i:1}" ]; then
					completingType="optArg"
					opt="-${_bcp_opt:$i:1}"
					cur="${_bcp_opt:$((i+1))}"
					completingArgName="${syntaxSpec[$opt]:-<argument>}"; completingArgName="${completingArgName%%\>*}>"
					echo "\$(cur:$cur) ${syntaxSpec[$opt]:-<argument>}"
				else
					completingType="shortOpts"
					echo "\$(cur:) ${syntaxSpec[shortOpts-ALL]}"
				fi
			else
				if [ "${_bcp_opt:$i:1}" ]; then
					opt="-${_bcp_opt:$i:1}"
					canonOpt="${syntaxSpec[canon:$opt]:-$opt}"
					_clInputValue[$canonOpt]="${_bcp_opt:$((i+1))}"
					match "${syntaxSpec[$canonOpt]}"   '^[^\<]*<([^\>]+).*$' rematch && _clInputValue[${rematch[1]}]="${_clInputValue[$canonOpt]}"
				fi
			fi

		# short or long opt with arg in one token
		elif { match "$_bcp_opt" "^(-[^-])(.+)$" rematch && [ "${syntaxSpec[${_bcp_opt:0:2}]:-NOARG}" != "NOARG" ]; } || match "$_bcp_opt" "^(--[^=]*)=(.*)$" rematch; then
			if ((_bcp_optPos==cword)); then
				if [ ${#cur} -lt ${#rematch[1]} ]; then
					completingType="options"
					echo "${rematch[1]}"
				else
					completingType="optArg"
					cur="${rematch[2]}"
					completingArgName="${syntaxSpec[${rematch[1]}]:-<argument>}"; completingArgName="${completingArgName%%\>*}>"
					echo "\$(cur:$cur) ${syntaxSpec[${rematch[1]}]:-<argument>}"
				fi
			else
				canonOpt="${syntaxSpec[canon:${rematch[1]}]:-${rematch[1]}}"
				_clInputValue[$canonOpt]="${rematch[2]}"
				match "${syntaxSpec[$canonOpt]}" '^[^\<]*<([^\>]+).*$' rematch && _clInputValue[${rematch[1]}]="${_clInputValue[$canonOpt]}"
			fi

		# a short or long option by itself and its one that we know requires an argument
		elif [ "${syntaxSpec[$_bcp_opt]:-NOARG}" != "NOARG" ]; then
			if ((_bcp_optPos==cword)); then
				completingType="options"
				echo "${syntaxSpec[options]}"
			elif ((_bcp_optPos+1==cword)); then
				opt="$_bcp_opt"
				optWords+=("$1"); shift; ((_bcp_optPos++))
				completingType="optArg"
				completingArgName="${syntaxSpec[$opt]:-<argument>}"; completingArgName="${completingArgName%%\>*}>"
				echo "${syntaxSpec[$opt]:-<argument>}"
			else
				opt="$_bcp_opt"
				canonOpt="${syntaxSpec[canon:$opt]:-$opt}"
				_clInputValue[$canonOpt]="$1"
				match "${syntaxSpec[$canonOpt]}" '^[^\<]*<([^\>]+).*$' rematch && _clInputValue[${rematch[1]}]="${_clInputValue[$canonOpt]}"
				optWords+=("$1"); shift; ((_bcp_optPos++))
			fi

		# a short option w/o arg by itself
		elif [[ "$_bcp_opt" =~ ^-[^-]$ ]]; then
			if ((_bcp_optPos==cword)); then
				completingType="options"
				echo "${syntaxSpec[options]}"
			else
				opt="$_bcp_opt"
				canonOpt="${syntaxSpec[canon:$opt]:-$opt}"
				_clInputValue[$canonOpt]="$opt"
			fi

		# whats left over must be an incomplete option ('-' by itself or --<something> where <something is not yet a recognized option)
		else
			if ((_bcp_optPos==cword)); then
				completingType="options"
				echo "${syntaxSpec[options]}"
			fi
		fi
	done

	_clInputValue["shiftCount"]="$_bcp_optPos"

	posWords=( "${words[0]}" "$@" )
	posCwords=$(( (_bcp_optPos<cword) ?(cword - _bcp_optPos) :0 ))

	# if the user is beginning the first positional argument, let them know that there are options availble if they enter '-'
	if [ ${posCwords:-0} -eq 1 ] && [ ! "$cur" ]; then
		echo "<optionsAvailable> -%3A  \$(emptyIsAnOption)"
	fi

	# if the user is completing a positional argument
	if [ ${posCwords:-0} -gt 0 ] && [ ${posCwords:-0} -le ${syntaxSpec[posCount]} ]; then
		completingType="positional"
		echo "${syntaxSpec[$posCwords]}"
		[ "${syntaxSpec[$posCwords]:0:1}" == "<" ] && completingArgName="${syntaxSpec[$posCwords]%% *}"
	fi

	# enter the positional argument values except for the one currently being completed
	for ((i=1; i<=$#; i++)); do
		if ((i != posCwords)); then
			_clInputValue[$i]="${!i}"
			match "${syntaxSpec[$i]}" '^[^\<]*<([^\>]+).*$' rematch && _clInputValue[${rematch[1]}]="${!i}"
		fi
	done
}



# usage: bgCmdlineParse [-R|--retVar=<clInput>] <cmdlineSyntaxStr> [<arg1> ... <argN>]
#        bgCmdlineParse -RclInput "fvqC:" "$@"; shift "${options["shiftCount"]}"
# Parses cmdline arguments into an associative array.
# This parses the <arg1> ... <argN> cmdline according to the syntax specified in <cmdlineSyntaxStr> and returns the results in the
# associative array <clInput>.
#
# Optional arguments are put in the array with the option as the key and positional arguments are put in the array as the numeric
# index of their position and also as the name of that position if it was specified in the <cmdlineSyntaxStr>. The value of positional
# arguments is the token at that location. The value of an optional argument is the option itself if it has no argument or the
# argument value if it has one.
#
# If no <cmdlineSyntaxStr> is given, it can still parse many cmdlines correctly based only on linux conventions, however, there are
# some cmdlines that are ambiguous unless the algorithm knows which options require arguments. For example, given the cmdline
# "... -f one ...", it is ambiguous whether 'one' is the value of the -f option or the first positional argument unless we know
# if -f requires an argument.
#
# In addition to indicating which options require parameters, the <cmdlineSyntaxStr> can also provide additional information that makes
# the <clInput> output better.
#    * It can provide names for the positional arguments so that they can be accessed like <clInput>[<name>].
#    * It can indicate that a group of options are aliases for the same optional arguments. The first one in the list is the canonical
#      option name so that if any of the aliases appear in the cmdline, it will be added to <clInput> as the canonical name. When
#      checking the value of the option, you only need to check the canonical name reguardless of how which alias was used.
#      (e.g. given "[-f|--file=<file>]", -f and --file are aliases for the same option known canonically as '-f'.
#
# In general, <cmdlineSyntaxStr> is a hybrid of getopt optspec syntax (see man(1) getopt) and usage syntax used at the top of function
# comments
# See man(3) bgMakeUsageSpec for the complete specification supported by <cmdlineSyntaxStr>
#
# This function only treats leading options as options. When a cmdline supports sub cmds, its common for options to appear later in
# the arguments but those options dont belong to the first group being parsed now. A cmd or function could consume its part of the
# cmdline and then launch a subcmd with the remainder of the cmdline.
#
#
# Params:
#    <cmdlineSyntaxStr>  : the cmdline syntax. See man(3) bgMakeUsageSpec
#    <argN>  : The $1 to $N parameters on the command line not including $0
#
# Output:
# This function returns its results in the options well-known variable. The caller should "declare -A options" before calling this
# function
#    $options[<opt>]=<value>
#         Indexes of this array are the options found on the cmdline. If the option does not require an argument, the value will
#         be the option. If is does require an argument the value is the argument.
#    $options["shiftCount"]=<N>
#         The index "shiftCount" is set to the number of args that were determined to be options. The caller can pass this to shift
#         to remove them and leave only the positional args in the "$@" vars
# See Also:
#    bgCmdlineParseBC  : meant for use in oob_printBashCompletion() functions. deos basic completion based on the provided <cmdlineSyntaxStr>
#                 and fills in clInput[] with any completed arguments from the cmdline. Also sets variables used to provide additional
#                 completion info.
#    bgCmdlineParse : meant for use in a function or cmd as an alternative to the standard options loop and positional assignment
#    bgMakeUsageSpec : used by bgCmdlineParseBC and bgCmdlineParse. 'compiles' a <cmdlineSyntaxStr> into an associative array with information
#                 about the syntax.
#    parseForBashCompletion : (OBSOLETE: use bgCmdlineParseBC)
#    invokeOutOfBandSystem : provides inline bash completion mechanism for scripts (among other things)
#    _bgbc-complete-viaCmdDelegation: documents the bash completion protocol written to stdout by inline BC routines
function bgCmdlineParse()
{
	local retVar
	while [ $# -gt 0 ]; do case $1 in
		-R*|--retVar*)  bgOptionGetOpt val: retVar "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local cmdlineSyntaxStr="$1"; shift
	local words=( "$0" "$@" )

	local -n _clInputValue="${retVar:-options}"
	_clInputValue=()
	varIsAMapArray _clInputValue || assertError "The output variable '$retVar' must be declared as an associative array like 'declare -A $retVar' before calling this function"

	local -A syntaxSpec=()
	bgMakeUsageSpec "$cmdlineSyntaxStr" syntaxSpec
	#bgtraceVars syntaxSpec

	local _bcp_optPos=0 rematch canonOpt opt value
	while [[ "$1" =~ ^- ]]; do
		local _bcp_opt="$1"; shift; ((_bcp_optPos++))

		# short or long opt with arg in one token
		if { match "$_bcp_opt" "^(-[^-])(.+)$" rematch && [ "${syntaxSpec[${_bcp_opt:0:2}]:-NOARG}" != "NOARG" ]; } || match "$_bcp_opt" "^(--[^=]*)=(.*)$" rematch; then
			canonOpt="${syntaxSpec[canon:${rematch[1]}]:-${rematch[1]}}"
			_clInputValue[$canonOpt]="${rematch[2]}"
			match "${syntaxSpec[$canonOpt]}" '^[^\<]*<([^\>]+).*$' rematch && _clInputValue[${rematch[1]}]="${_clInputValue[$canonOpt]}"

		# a short or long option by itself and its one that we know requires an argument
		elif [ "${syntaxSpec[$_bcp_opt]:-NOARG}" != "NOARG" ]; then
			canonOpt="${syntaxSpec[canon:$_bcp_opt]:-$_bcp_opt}"
			_clInputValue[$canonOpt]="$1"
			match "${syntaxSpec[$canonOpt]}" '^[^\<]*<([^\>]+).*$' rematch && _clInputValue[${rematch[1]}]="$1"
			shift; ((_bcp_optPos++))

		# a short or long option without an arg, by itself
		elif [[ "$_bcp_opt" =~ ^-[^-]$ ]] || [[ "$_bcp_opt" =~ ^-- ]]; then
			canonOpt="${syntaxSpec[canon:$_bcp_opt]:-$_bcp_opt}"
			_clInputValue[$canonOpt]="$_bcp_opt"

		# whats left over must be a string of short options strung together
		else
			_bcp_opt="${_bcp_opt#-}"
			while [ ${#_bcp_opt} -gt 0 ]; do
				local shortOpt="${_bcp_opt:0:1}"; _bcp_opt="${_bcp_opt:1}"
				if [[ "${syntaxSpec["-$shortOpt"]}" =~ ^\< ]]; then
					canonOpt="${syntaxSpec[canon:-$shortOpt]:--$shortOpt}"
					_clInputValue[$canonOpt]="${_bcp_opt}"
					match "${syntaxSpec[$canonOpt]}" '^[^\<]*<([^\>]+).*$' rematch && _clInputValue[${rematch[1]}]="${_bcp_opt}"
					_bcp_opt=""
				else
					canonOpt="${syntaxSpec[canon:-$shortOpt]:--$shortOpt}"
					_clInputValue["-$shortOpt"]="-$shortOpt"
				fi
			done
		fi
	done

	_clInputValue["shiftCount"]="$_bcp_optPos"

	local i; for ((i=1; i<=$#; i++)); do
		_clInputValue[$i]="${!i}"
		match "${syntaxSpec[$i]}" '^[^\<]*<([^\>]+).*$' rematch && _clInputValue[${rematch[1]}]="${!i}"
	done
}

# usage: bgMakeUsageSpec <cmdlineSyntaxStr> <syntaxSpecVar>
# populates the <syntaxSpecVar> associative array return variable to describe the cmdline syntax specified in <cmdlineSyntaxStr>
#
# This function is used by functions that do bash completion or parses a cmdline into variables. <cmdlineSyntaxStr> is a structured
# human readable description of the cmdline syntax. The output is an associative array containing the same information in a machine
# usable format.
#
# Input:
# <cmdlineSyntaxStr> can be either a usage strting that typically in the first line of a function comment section or an optspec string
# as decribed by man(3) getopts or a combination of both.
# The information contained in the syntax string is...
#    * the set of options recognized by the command
#    * which options require an argument and possible the name that characterizes the argument and possible valid literal values
#    * how many required positional arguments
#    * the names and possibly accepted literal values for each positional argument
#
# A <cmdlineSyntaxStr> consists of these sections.
# <-optspec-> <-------- options --------------> <--- positional ----------> <- optPos --> <-nextSyntax->
# qvf:p<path> [-q] [-v] [-f <file>] [-p <path>] <p1> literal1|literal2 <p3> [<p4> [<p5>]] [-q]
#
# Typically it will be either an optspec or a usage string but both can be combined as long as the optspec is first followed by a space.
# An extension to the optspec syntax is supported. <name> can replace ':' to indicate that an argument is required and to also
# indicate the name of the argument.
#
# Output:
# The <syntaxSpecVar> associative array will be cleared and then populated with data that reflects the <cmdlineSyntaxStr>
#    <syntaxSpecVar>[options]  : space separated list of all valid options suitable for output of a bash completion function while
#              a option (not its argument) is being completed. Options that require an argument are suffixed with %3A to tell BC
#              to accept further input after it is completed
#    <syntaxSpecVar>[posCount]=<N>  : is the number of positional arguments that the spec includes.
#    <syntaxSpecVar>[<opt>]=NOARG|<argName>  : The index is a valid long or short option (like syntaxSpec[-v]). the value indicates
#             if this option requires an argument and if so what its name is. <argument> is the default name.
#    <syntaxSpecVar>[<N>]=<argName>|val1|val2...  : <N> is the position number (1,2,3...), up to the value of posCount. The value
#             is a list of tokens separated by the | char. If the token is surrounded by <> it is the name of the argument,
#             otherwise its a possible value
#
# Example:
#    cmdlineSyntaxStr='[-t <templateFolder>] [-o|--output=<outputFolder>] [--dry-run] [-q|--quiet] <sourceFileSpec>'
#    Compiles into...
#       syntaxSpec[posCount]=1
#       syntaxSpec[options]="-t%3A -o%3A --output=%3A --dry-run -q --quiet"
#       syntaxSpec[-t]=<templateFolder>
#       syntaxSpec[-o]=<outputFolder>
#       syntaxSpec[--output]=<outputFolder>
#       syntaxSpec[--dry-run]=NOARG
#       syntaxSpec[-q]=NOARG
#       syntaxSpec[--quiet]=NOARG
#       syntaxSpec[1]=<sourceFileSpec>
# Params:
#    <cmdlineSyntaxStr>  : the input syntax. See section 'Input' above
#    <syntaxSpecVar> : the name of an associative array (local -A) variable declared by the caller that will receive the output of
#                  this function.
# See Also:
#    bgCmdlineParseBC  : meant for use in oob_printBashCompletion() functions. deos basic completion based on the provided <cmdlineSyntaxStr>
#                 and fills in clInput[] with any completed arguments from the cmdline. Also sets variables used to provide additional
#                 completion info.
#    bgCmdlineParse : meant for use in a function or cmd as an alternative to the standard options loop and positional assignment
#    bgMakeUsageSpec : used by bgCmdlineParseBC and bgCmdlineParse. 'compiles' a <cmdlineSyntaxStr> into an associative array with information
#                 about the syntax.
#    parseForBashCompletion : (OBSOLETE: use bgCmdlineParseBC)
#    invokeOutOfBandSystem : provides inline bash completion mechanism for scripts (among other things)
#    _bgbc-complete-viaCmdDelegation: documents the bash completion protocol written to stdout by inline BC routines
function bgMakeUsageSpec() {
	local cmdlineSyntaxStr="$1"
	local -n _syntaxSpecVar="$2"
	_syntaxSpecVar=()
	local cmdlineSyntax="$cmdlineSyntaxStr"
	local assertErrorContext+="-v cmdlineSyntax"

	### glean the syntax from the command script
	if [[ "$cmdlineSyntaxStr" =~ \<glean\> ]]; then
		cmdlineSyntaxStr="${cmdlineSyntaxStr//\<glean\>/ }"
		local name value
		while IFS="," read -r name value; do
			_syntaxSpecVar[$name]="$value"
			if [[ "$name" =~ ^-- ]] && [[ "$value" =~ ^\< ]]; then
				_syntaxSpecVar[options]+=" $name=%3A "
			elif [[ "$name" =~ ^-[^-]$ ]] && [[ "$value" =~ ^\< ]]; then
				_syntaxSpecVar[options]+=" $name%3A "
			else
				_syntaxSpecVar[options]+=" $name "
			fi
		done < <(gawk '
			@include "bg_core.awk"
			/invokeOutOfBandSystem/ {trigger=1}
			/^done|^esac/ {trigger=0}
			# 	-C*|--domID*)      bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
			#	-n|--noDirtyCheck) bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
			trigger && /^[[:space:]]*-/ {
				match($0, /^[[:space:]]*(-[^)]*)[)](.*)$/, rematch)
				optsStr=rematch[1]
				line=rematch[2]
				argReq="NOARG"
				if (optsStr ~ /[*]/) argReq="<argument>"
				gsub(/[*]/,"",optsStr)
				split(optsStr, opts, "|")
				for (i=1; i<NF; i++) if ($i=="val:") {i++; if ($i) argReq="<"$i">"; break}
				for (i in opts) {
					printf("%s,%s\n", opts[i], argReq)
				}
			}
		' $0)
	fi

	# to be compatible with simple optspec strings (single letter options with : to indicate required args) we start out
	# considering the default case to be a single letter option. After we see a space or a '<' we know that its our extended
	# syntanx and we consider the default case to be a literal token that can be entered at that point.
	# qvf:p<path> [-q] [-v] [-f <file>] [-p <path>] <p1> literal1|literal2 <p3> [<p4> [<p5>]] [-q]
	# <-optspec-> <-------- options --------------> <--- positional ----------> <- optPos --> <-nextSyntax->
	local syntaxSection="optspec"
	local pos=0 opt
	while [ "$cmdlineSyntaxStr" ] && [ "$syntaxSection" != "nextSyntax" ]; do
		# remove leading whitespace
		while [[ "${cmdlineSyntaxStr:0:1}" =~ ^[[:space:]] ]]; do
			cmdlineSyntaxStr="${cmdlineSyntaxStr:1}"
		done

		case $syntaxSection in
			optspec)
				# a letter followed by a ':' or a '<name>' is a short option with an argument. <name> is an extension to getopts
				# that allows naming the argument so that BC is more descriptive
				# 'f:' or 'f<txtFile>'
				if [[ "${cmdlineSyntaxStr}" =~ ^[^\ ][:\<] ]]; then
					opt="${cmdlineSyntaxStr:0:1}"; cmdlineSyntaxStr="${cmdlineSyntaxStr:1}"
					_syntaxSpecVar[-${opt}]="<argument>"
					_syntaxSpecVar[options]+=" -${opt}%3A "
					_syntaxSpecVar[shortOpts-ARG]+="$opt"

					[ "${cmdlineSyntaxStr:0:1}" == ":" ] && cmdlineSyntaxStr="${cmdlineSyntaxStr:1}"
					if [ "${cmdlineSyntaxStr:0:1}" == "<" ]; then
						_syntaxSpecVar[-${opt}]="${cmdlineSyntaxStr%%>*}>"
						cmdlineSyntaxStr="${cmdlineSyntaxStr#*>}"
					fi

				# a letter not followed by a ':' nor '<name>' is a single short option without an argument
				elif [[ "${cmdlineSyntaxStr:0:1}" =~ [a-zA-Z0-9] ]]; then
					opt="${cmdlineSyntaxStr:0:1}"; cmdlineSyntaxStr="${cmdlineSyntaxStr:1}"
					_syntaxSpecVar[-$opt]="NOARG"
					_syntaxSpecVar[options]+=" -$opt "
					_syntaxSpecVar[shortOpts-NOARG]+="$opt"
				else
					syntaxSection="options";
				fi
				;;

			options)
				# tokens in the options section must begin with '[-' or '-'. Note that the extra '\]?' in the regex does not
				# do anything in the regex but it fixes an atom editor syntax highlighting bug
				if [[ ! "$cmdlineSyntaxStr" =~ ^\[?-\]? ]]; then
					syntaxSection="positional";
				else
					# [-f|--file=<txtFile>]
					# [-f <txtFile>]
					# [--file=<txtFile>]
					# [-q|--quiet]
					# -a|--add|-r|--remove
					# this consists of two parts -- first, a list of option tokens separated by '|' and second an optional argument.
					# the argument can be delimited with a '=' or if the whole term is inside brackets, a space ' '
					# The argument is a list of tokens separated by '|'. One token can be surrounded with <> which indicates that is
					# the name of the argument. tokens w/o <> are literal values that can be specified for that argument.

					# consume this option spec from cmdlineSyntaxStr and put it in oneOptSpec
					local oneOptSpec inBrackets
					if [ "${cmdlineSyntaxStr:0:1}" == "[" ]; then
						inBrackets="1"
						cmdlineSyntaxStr="${cmdlineSyntaxStr:1}"
						oneOptSpec="${cmdlineSyntaxStr%%]*}"
						cmdlineSyntaxStr="${cmdlineSyntaxStr#*]}"
					else
						oneOptSpec="${cmdlineSyntaxStr%%[[:space:]]*}"
						cmdlineSyntaxStr="${cmdlineSyntaxStr#*[[:space:]]}"
					fi

					# separate the option list from the argument list (if the argument list is present)
					if [[ "${oneOptSpec}" =~ [=[:space:]] ]]; then
						local optList="${oneOptSpec%%[=[:space:]]*}"
						local argList="${oneOptSpec#$optList[=[:space:]]}"; argList="${argList//\|/ }"; [[ "$argList" =~ ^[[:space:]]*$ ]] && argList=""
					else
						local optList="$oneOptSpec"
						local argList=""
					fi

					local canonicalOpt="${optList%%\|*}"
					local opt; for opt in ${optList//\|/ }; do
						_syntaxSpecVar[canon:${opt}]="$canonicalOpt"
						_syntaxSpecVar[${opt}]="${argList:-NOARG}"
						if [ "${opt:0:2}" == "--" ]; then
							_syntaxSpecVar[options]+=" ${opt}${argList:+=%3A} "
						else
							_syntaxSpecVar[options]+=" ${opt}${argList:+%3A} "
							if [ "${argList:+exists}" ]; then
								_syntaxSpecVar[shortOpts-ARG]+="${opt#-}"
							else
								_syntaxSpecVar[shortOpts-NOARG]+="${opt#-}"
							fi
						fi
					done
				fi
				;;

			positional)
				# <argName>val1|val2
				# This is a list of one or more tokens separated by the | char. If one of the tokens is surrounded by <> is it the
				# name of the position. Other tokens are possible values.
				if [ "${cmdlineSyntaxStr:0:1}" != "[" ]; then
					local posArg="${cmdlineSyntaxStr%% *}"
					cmdlineSyntaxStr="${cmdlineSyntaxStr#$posArg}"
					((pos++))
					_syntaxSpecVar[$pos]="${posArg//\|/ }"
				else
					syntaxSection="optPos";
				fi
				;;

			optPos)
				# optional positional params at the end can not begin with a '-'. If we see a '-' token, it must belong to the
				# syntax of the next subcmd
				if [[ "$cmdlineSyntaxStr" =~ ^\[?-\]? ]]; then
					syntaxSection="nextSyntax";
				else
					# there are several syntax for the optional positional params at the end of the argument list.
					# [<oa1>] [<oa2>] [<oa3>]
					# [<oa1> [<oa2> [<oa3>] ] ]
					# [<oa1>] [...<oaN>]
					# [<oa1>...<oaN>]
					cmdlineSyntaxStr="${cmdlineSyntaxStr:1}"
					local token="${cmdlineSyntaxStr%%]*}"
					cmdlineSyntaxStr="${cmdlineSyntaxStr#*]}"
					local countOpen="${token//[^[]}"
					local countClose="${token//[^]]}"
					while [[ "$cmdlineSyntaxStr" =~ []] ]] && (( ${#countOpen} != ${#countClose} )); do
						token+="] ${cmdlineSyntaxStr%%]*}"
						cmdlineSyntaxStr="${cmdlineSyntaxStr#*]}"
						countOpen="${token//[^[]}"
						countClose="${token//[^]]}"
					done

					_syntaxSpecVar[$((pos+1))]+=" ${token//[].[]/ } "
				fi
				;;
			*) assertError "bad syntaxSection '$syntaxSection'"
		esac
	done

	_syntaxSpecVar[shortOpts-ALL]="${_syntaxSpecVar[shortOpts-ARG]}${_syntaxSpecVar[shortOpts-NOARG]}"
	_syntaxSpecVar[posCount]=$pos
}







#################################################################################################################################
### OBSOLETE Cmdline processing functions (legacy)


# OBSOLETE: use bgCmdlineParseBC or bgCmdlineParse
# usage: parseForBashCompletion --compat2 wordsVarName cwordVarName curVarName prevVarName optWordsVarName posWordsVarName posCwordsVarName "$@"
# usage: parseForBashCompletion [-o"hs:a:"] wordsVarName cwordVarName curVarName prevVarName optWordsVarName posWordsVarName  "$@"
# usage: (cont)                 <cword> [<word1> .. <wordN>]
# This function supports previous versions with a --compatN option.
# this is typically used at the top of a script's oob_printBashCompletion function to get the
# information from the current command line that makes it easy to provide bash completion suggestions.
# --compatN changes the contract with the caller slightly.
#     1) there is the extra posCwords return variable
#     2) the posWords return array now has the script name as element 0 which makes the first positional param have an index of 1.
#        This makes the index numbers of posWords the same as the $N vars that the script will know the positional params as when
#        it is called.
# See Also:
#    bgCmdlineParseBC  : newer version of parseForBashCompletion
function parseForBashCompletion()
{
	local optSpecs=""
	local compatLevel=""
	while [[ "$1" =~ ^- ]]; do case $1 in
		--compat2) compatLevel="2" ;;
		-o*) optSpecs="${1#-o}" ;;
	esac; shift; done

	# our bg_bashCompletion sourced bash completion function goes to the work of extracting the optspec from the
	# source file when possible so it sets this exported variable for us to use here. Since the standard
	# pattern that has been in use for a while passes a string literal to the getopts fucntion in the
	# main script, we do not have easy access to it.  The newest tamplate defines the optSpecs variable
	# so we do have access to it
	if [ ! "$optSpecs" ] && [ "$bgBashCompletionMechanism_optSpecs" ]; then
		optSpecs="$bgBashCompletionMechanism_optSpecs"
	fi

	local wordsVar="$1"; shift
	local cwordVar="$1"; shift
	local curVar="$1"; shift
	local prevVar="$1"; shift
	local optWordsVar="$1"; shift
	local posWordsVar="$1"; shift

	# 2014-10 changed the contract of the function call but do not want to break scripts that expect the
	# old contract. In the new template code, this variable will be the name of the caller's posCwords local var
	local posCwordsVar=""
	if [ ${compatLevel:-0} -ge 2 ]; then
		posCwordsVar="$1"; shift
	fi
	local wordsValue cwordValue curValue prevValue optWordsValue posWordsValue posCwordsValue=0

	local cwordValue="$1"; shift
	wordsValue=( "$@" )
	curValue="${wordsValue[cwordValue]}"
	((cwordValue>0)) && prevValue="${wordsValue[cwordValue-1]}"
	shift # cmd name
	while [[ "$1" =~ ^- ]]; do
		local param="$1"
		optWordsValue=( ${optWordsValue[@]} $1 )
		shift
		if [ "${#param}" == "2" ] && [[ "$optSpecs" =~ ${param:1:1}: ]] && [ $# -gt 0 ]; then
			optWordsValue=( ${optWordsValue[@]} $1 )
			shift
		fi
	done
	if [ ${compatLevel:-0} -ge 2 ]; then
		posWordsValue=( "${wordsValue[0]}" "$@" )
		[ ${#optWordsValue[@]} -lt ${cwordValue:-0} ] && posCwordsValue=$(( cwordValue - ${#optWordsValue[@]} )) || assertError
		eval $posCwordsVar=\"\$posCwordsValue\"
	else
		posWordsValue=( "$@" )
	fi

	eval $wordsVar='( "${wordsValue[@]}" )'
	eval $cwordVar=\"\$cwordValue\"
	eval $curVar=\"\$curValue\"
	eval $prevVar=\"\$prevValue\"
	eval $optWordsVar='( "${optWordsValue[@]}" )'
	eval $posWordsVar='( "${posWordsValue[@]}" )'
}
