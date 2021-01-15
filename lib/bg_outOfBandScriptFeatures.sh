#!/bin/bash

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

#################################################################################################################################
### Cmdline processing Method 1 of Spec based cmdline Processing.
# This should merge into Method 2. Method one is characterized by the spec being defined by the script author and the values of
# the spec are the variable names that will receive the cmdline data

# OBSOLETE? see method 2 functions in this file like bgBCParse
# usage: bgOptionsParse <cmdlineSpecVar> "$@"
# Method 1
# This parses the command line in "$@" according the to spec passed in via <cmdlineSpec>
# See Also:
#    bgOptionsParseBC : do command line completion based on the same <cmdlineSpecVar>
function bgOptionsParse()
{
	local cmdlineSpecVar="$1"; shift
	local -A cmdlineSpecValue; arrayCopy "$cmdlineSpecVar" cmdlineSpecValue
	local spec type
	while [ $# -gt 0 ]; do
		for spec in "${!cmdlineSpecValue[@]}"; do
			# note that $spec might have an '*' so we have to iterate
			if [[ "$1" == $spec ]]; then
				type="val"; [[ "$spec" =~ [*]$ ]] && type+=":"
				bgOptionGetOpt $type "${cmdlineSpecValue[$spec]}" "$@" && shift
				break;
			fi
		done
		bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"
		shift
	done
	unset spec type
	local positionalParamsValue=("$@")
	arrayCopy positionalParamsValue "${cmdlineSpecValue[positionalParamsVar]}"
}

# usage: bgOptionsParseBC <cmdlineSpecVar> <prev> <cur>
# Method 1
# Performs option completion according to the <cmdlineSpecVar> and the position being completed
# Params:
#    <cmdlineSpecVar> : an array that describes the variable names that will be populated from the cmdline.
#         Example: <cmdlineSpecVar>[-f]="forceFlag"       # option w/o arg
#         Example: <cmdlineSpecVar>[-C*]="domIDOverride"  # option with arg
function completeOptionsSpec() { bgOptionsParseBC "$@"; }
function bgOptionsParseBC()
{
	local cmdlineSpecVar="$1"; shift
	local prev="$1"; shift
	local cur="$1"; shift
	local -A cmdlineSpecValue; arrayCopy "$cmdlineSpecVar" cmdlineSpecValue
	unset cmdlineSpecValue[positionalParamsVar]

	local spec; for spec in "${!cmdlineSpecValue[@]}"; do
		if [[ "$prev" == $spec ]]; then
			if [[ "$spec" =~ [*]$ ]] && [ ${#prev} -eq $((${#spec}-1)) ]; then
				echo "> <${cmdlineSpecValue[$spec]}>"
				return
			fi
		fi
	done

	for spec in "${!cmdlineSpecValue[@]}"; do
		if [[ "$cur" == $spec ]]; then
			if [[ "$spec" =~ [*]$ ]] && [ ${#cur} -qe $((${#spec}-1)) ]; then
				echo "> <${cmdlineSpecValue[$spec]}>"
				return
			fi
		fi
	done

	if [ "$cur" ]; then
		echo "${!cmdlineSpecValue[@]}"
	else
		echo "- <options>"
	fi
}


#################################################################################################################################
### Cmdline processing Method 2 of Spec based cmdline Processing.
# This method is characterized by using the usage: syntax string to initialize the Spec array.
# the usage syntax compliles into an array structure that is similar to the Method 1 but the values indicate if the option has an arg

# usage: parseSyntaxSpecString <syntaxSpecVar> <cmdlineSyntaxString>
# Method 2
# This parses a syntax string that is typical in function usage: statements into an associative array that describes the call
# signature of the function. That <syntaxSpecVar> array can be used for bash comdline completion or to process function arguments
# into local variables for the function to use.
# Sample:
#    cmdlineSyntaxString='[-t <templateFolder>] [-o <outputFolder>] [--dry-run] [-q|--quiet] <sourceFileSpec>'
#    syntaxSpec[-t]=<templateFolder>
#    syntaxSpec[-o]=<outputFolder>
#    syntaxSpec[--dry-run]=NOARG
#    syntaxSpec[-q]=NOARG
#    syntaxSpec[--quiet]=NOARG
#    syntaxSpec[pos0]=<sourceFileSpec>
# Params:
#    <syntaxSpecVar> : an associative array that will be cleared and then filled in with the information that describes the syntax
#    <cmdlineSyntaxString> : the syntax string that describes the call signature of the function.
function parseSyntaxSpecString()
{
	local syntaxSpecVar="$1"; shift
	local cmdlineSyntaxString="$1"; shift

	local assertErrorContext=(-v cmdlineSyntaxString -v "string left":tmpStr)
	local -A _psss_syntaxSpec=()
	local posCount=1 token delim
	local tmpStr="$cmdlineSyntaxString"
	while stringConsumeNextAny token delim tmpStr "[^<[]*" "[<[]"; do
		local name="" opt="" argument=""
		if [ "$delim" == "<" ]; then
			stringConsumeNextAny name delim tmpStr '[^>]*' '>' || assertError "bad syntax grammar description"
			_psss_syntaxSpec[pos$((posCount++))]="<${name}>"
		elif [ "$delim" == "[" ]; then
			local rematch; match "$tmpStr" "^(-[^]< ]*)[[:space:]]*(<[^]>]*>)?[]]" rematch || assertError "bad syntax grammar description"
			local optStr="${rematch[1]}"
			argument="${rematch[2]}"
			local opts; IFS="|" read -ra opts <<<"$optStr"
			for opt in "${opts[@]}"; do
				_psss_syntaxSpec[${opt:-<empty>}]="${argument:-NOARG}"
				_psss_syntaxSpec[options]+=" ${opt}"
			done
			tmpStr="${tmpStr#${rematch[0]}}"
		fi
	done
	arrayCopy -o _psss_syntaxSpec $syntaxSpecVar
}


# usage: bcFromSyntaxString <cmdlineSyntaxString> <cword> <cmdName_word0> <word1> .. <wordN>
# Method 2
# This performs bash command line completion on the words passed in according to the syntax described in
# <cmdlineSyntaxString>
# Example:
# completeSyntax '[-t <templateFolder>] [-o <outputFolder>] [--dry-run] [-q|--quiet] <sourceFileSpec>'
# Params:
#     <cmdlineSyntaxString> : a syntax string that is typical in the usage: comment of bg-core style bash functions
# Options:
#    -r|--removePosCount <removePosCount> : when the syntax in <cmdlineSyntaxString> is for a sub command, it applies to only a
#            subset of the commandline passed in. This can used ignore this many of the input words to sync up with the syntax.
#            This assumes that the command name is the zero'th word so it leaves it and removes <removePosCount> words after it.
function completeFromSyntaxString() { bcFromSyntaxString "$@"; }
function bcFromSyntaxString()
{
	local removePosCount=0
	while [ $# -gt 0 ]; do case $1 in
		-r*|--removePosCount*) bgOptionGetOpt val: removePosCount "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local cmdlineSyntaxString="$1"; shift
	local cword="$(($1-removePosCount))"; shift
	local words=("${@:0:1}" "${@:$removePosCount+1}")  # using the ${0:..} syntax cause the zero'th entry to be included. "$@" does not

	local -A syntaxSpec=()
	parseSyntaxSpecString syntaxSpec "$cmdlineSyntaxString"

	local optPos=0 rematch
	set -- "${words[@]:1}"
	while [[ "$1" =~ ^- ]]; do
		((optPos++))
		if ((optPos==cword)); then
			if [[ "${syntaxSpec[${1:0:2}]}" =~ ^\< ]]; then
				echo "\$(cur:${1:2}) ${syntaxSpec[${1:0:2}]}"
			elif match "$1" "^(--[^=])=(.*)$" rematch; then
				echo "\$(cur:${rematch[2]}) ${syntaxSpec[${rematch[1]}]}"
			else
				echo "<options> ${syntaxSpec[options]}"
			fi
			return
		fi
		if [[ "${syntaxSpec[$1]}" =~ ^\< ]]; then
		 	if ((optPos+1==cword)); then
				echo "<optArg> ${syntaxSpec[$1]}"
				return
			fi
			shift
		fi
		shift
	done
	((optPos<cword)) || assertLogicError -v optPos -v cword
	local posCwords=$((cword-optPos))
	echo "${syntaxSpec[pos${posCwords}]}"
	[ "${syntaxSpec[options]}" ] && echo "\$(comment -<options>)"
}


#######################################################################################################################################
### BASH Cmdline Option Processing Helper functions

#function bgOptionsEndLoop  moved to bg_corelibsMisc.sh
#function bgOptionGetOpt    moved to bg_corelibsMisc.sh

# OBSOLETE: use bgOptionGetOpt instead
# usage: bgetopt <cmd line ...>
# usage: myoptionName=$(bgetopt "$@") && shift
# this is used to remove the next option from the $@ input parameters when the option has a required parameter
function bgetopt()
{
	if [[ "$1" =~ ^-.$ ]]; then
		echo "$2"
		return 0
	else
		echo "${1:2}"
		return 1
	fi
}


# usage: bgBCParse <optSpecs> <cword> <cmdName> [<arg1> ... <argN>]
#        bgBCParse "<glean>" "$@"; set -- "${posWords[@]:1}"
#        bgBCParse "fvqC:"   "$@"; set -- "${posWords[@]:1}"
# This separtates the cmdline sent to it into an options part and positional part. A typical pattern reflected in the second usage
# example is that after calling this, the option words that this function identifies are shifted off the "$@" variables.
#
# This function only removes leading options. When a cmd supports sub cmds, its common for options to appear later in the arguments
# also but those options dont belong to the first group being parsed now and in the general case the <optSpec> for those options
# would be different.
#
# The caller passes in <optSpecs> which describes the options that will be expected. It really only needs to know which options
# require arguments so that it can determine where the positional arguments start (b/c otherwise the option arg can look like the
# first positional arg)
#
# If <optSpecs> contains the special value "<glean>", the script that is being invoked will be read to look for a stadard options
# processing loop in order to set the <optSpecs> from that.
#
# This function is typically used from inside oob_printBashCompletion() callback functions. This function will output to stdout the
# basic completion syntax for the options specified in <optSpecs>. It also sets various variables that can then be used by the caller
# to provide additional suggestions for the arguments of options and for positional parameters.
#
# Params:
#    <optSpecs>  : a string that contains the accepted options like "ab:c" (see man getopt). If its value is "<glean>" then the
#         source script will be scanned to glean the option syntax spec from the standard while/case loop that follows the
#         invokeOutOfBandSystem call.
#    <cword> : the token position in the cmdline that the user is currently completing.
#    <cmdName> : ($0) the name of the command whose commandline is being completed
#    <argN>  : ($[0-9]) parameters on the command line
# Note that typically, 2nd and subsequent arguments are passed through from the parmeters of the surrounding function like "$@"
#
# Return Scope Vars:
# This function returns its results in these well-known variables. The caller can declare these local before calling this function
# to prevent them from becomeing global variables. The invokeOutOfBandSystem function does that so when used inside an oob_* callback
# you dont need to.
#    $options[<opt>]=<value> : output associative array. Indexes of this array are the options specified on the cmdline line according to
#         the <optSpecs> and the corresponding value is the option's argument if it has one or the option repeated if it does not.
#         This is provided in case the script needs to vary the suggestions based on what options the user has specified so far.
#         The caller can test any option by looking it up in this array to see if its non-empty.
#    $posWords[<n>]: this is words[] with the optional arguments removed so that <n> corresponds to the consistent
#         position regardless of how many optional arguments and their arguments have been specified on the cmd line.
#         $posCwords is the index into this array of the token currently being completed.
#    $posCwords: is the index into $posWords of the word being completed. If it is 0, it means an option is being completed.
#    $optWords[] : this is the leading part of $words[] that contains the optional arguments and their arguments.
#    $words[<n>] $cword : words[] is an array of the entire cmdline. [0] is the command. cword is the index of into
#         this array of the current position being completed
#    $cword : the value passed into this function is returned in a variable. Its the position being completed before options are
#             taken into account.
#    $cur : $cur is the current word being completed. It contains only the text behind the cursor which is the text that is
#         subject to change. Its coresponding word in words[$cword] will contain the whole word that is on the command line
#    $opt : indicates if an option or its required argument is being completed. If its empty, a positional param is being
#         completed. It will contain one of these values.
#         ""         : if $opt is the empty string, the user is completing a positional argument (not an optional argument)
#         "@options" : the  user is completing an option but has not yet typed enough characters to identify which option. The
#                      suggestions are the list of supported options. This is case is typically handled suficiently by this
#                      function and the caller typically does not have to respond to this case but can add additional suggestions.
#         <option>   : if $opt contains the name of an option, that option requires an argument that is being completed. The
#                      caller typically handles this case to provide the valid suggestions for this option's argument.
#    $prev : $prev is the token before the one being completed. This is provided because the bash_completion project makes it
#         available but it is not typically used because other variables provide better information.
# See Also:
#    bgCmdlineParse  : separates options similar to this function but does not do BC.
#    invokeOutOfBandSystem
#    parseForBashCompletion : (being replaced by bgBCParse) this is the long time function that script's oob_printBashCompletion used.
function bgBCParse()
{
	# remove and process the args to this function, leaving the cmdline being parsed in "$@"
	local optSpecs="$1"; shift
	cword="$1"; shift
	words=( "$@" )
	shift # cmdName ($0)
	cur=""
	prev=""
	options=()
	completingType=""
	optWords=()
	posWords=()
	posCwords=0

	varIsAMapArray options || assertError "The caller must 'declare -A options' before calling bgBCParse"

	local -A syntaxSpec=()
	bgMakeUsageSpec "$optSpecs" syntaxSpec

	cur="${words[$cword]}"
	((cword>1)) && prev="${words[$(( $cword-1 ))]}"

	### this loop consumes the options and their arguments from the front end of the parameter list
	local cmdlinePos=0
	while [[ "$1" =~ ^- ]]; do
		local _bcp_opt="$1"; shift; ((cmdlinePos++))
		optWords+=("$_bcp_opt")

		# this block means that the word being completed is in the options section of the cmdline
		# we send some BC output and also set the output variable 'opt' so that the caller can easily add information when 'opt' is
		# being completed.
		# Note that we interpret the token a little differently based on whether the user is on this token
		if ((cmdlinePos==cword)); then
			# if we are completing the argument part of a short option. (i.e. '-f...')
			if [[ "${syntaxSpec[${_bcp_opt:0:2}]}" =~ ^\< ]]; then
				opt="${_bcp_opt:0:2}"
				cur="${_bcp_opt:2}"
				completingType="${syntaxSpec[$opt]:-<argument>}"
				echo "\$(cur:$cur) ${syntaxSpec[$opt]:-<argument>}"
				options[$opt]="$cur"
			# if we are completing the argument part of a long option in one token. (i.e. '--file=...')
			elif match "$_bcp_opt" "^(--[^=]*)=(.*)$" rematch; then
				opt="${rematch[1]}"
				cur="${rematch[2]}"
				completingType="${syntaxSpec[$opt]:-<argument>}"
				echo "\$(cur:$cur) ${syntaxSpec[$opt]:-<argument>}"
				options[$opt]="$cur"
			# we must still be completing the option itself
			else
				echo "<options> ${syntaxSpec[options]}"
				opt="@options"
			fi

		# when the user is not completing this option token we interpret whether it has a parameter or not based more on the form of
		# the token than on the spec. This lets the user add a -f<filename> or --file=<filename> style argument even if it does not
		# match our syntaxSpec and it will not mess up the remainder of the cmdline interpretation
		else
			if [[ "$_bcp_opt" =~ ^-[^-]. ]]; then
				options[${_bcp_opt:0:2}]="${_bcp_opt:2}"
			elif match "$_bcp_opt" "^(--[^=])=(.*)$" rematch; then
				options[${rematch[1]}]="${rematch[2]}"
			else
				options[$_bcp_opt]="$_bcp_opt"

				# now determine if the next token should be interpreted as the argument to this option. Note that if the user's cursor is on the
				# option and the option is complete and requires an argument, we really dont know but the most common case is that the user has
				# just completed the option and has not yet entered a separate token
				# if _bcp_opt is an exact option token that requires an argument, consume next arg position as the argument
				if [[ "${syntaxSpec[$_bcp_opt]}" =~ ^\< ]]; then
					options[$_bcp_opt]="$1"
					optWords+=("$1")
					shift; ((cmdlinePos++))
					# if the user is completing the argument of an option is a separate token, set opt to indicate that to the caller
					# the caller will not distuigish between one and two token option w/ arg
				 	if ((cmdlinePos==cword)); then
						echo "${syntaxSpec[$_bcp_opt]}"
						opt="$_bcp_opt"
					fi
				fi
			fi
		fi
	done

	posWords=( "${words[0]}" "$@" )
	posCwords=$(( (cmdlinePos<cword) ?(cword - cmdlinePos) :0 ))

	# if the user is beginning the first positional argument, let them know that there are options availble if they enter '-'
	if [ ${posCwords:-0} -eq 1 ] && [ ! "$cur" ]; then
		echo "<optionsAvailable> -%3A  \$(emptyIsAnOption)"
	fi

	# if the user is completing a positional argument
	if [ ${posCwords:-0} -gt 0 ] && [ ${posCwords:-0} -le ${syntaxSpec[posCount]} ]; then
		echo "${syntaxSpec[$posCwords]}"
		[ "${syntaxSpec[$posCwords]:0:1}" == "<" ] && completingType="${syntaxSpec[$posCwords]%% *}"
	fi
}



# usage: bgCmdlineParse <optSpecs> [<arg1> ... <argN>]
#        bgCmdlineParse "fvqC:" "$@"; shift "${options["shiftCount"]}"
# This separtates the cmdline sent to it into an options part and positional part. A typical pattern reflected in the second usage
# example is that after calling this, the option words that this function identifies are shifted off the "$@" variables.
#
# This function only removes leading options. When a cmd supports sub cmds, its common for options to appear later in the arguments
# also but those options dont belong to the first group being parsed now and in the general case the <optSpec> for those options
# would be different.
#
# The caller passes in <optSpecs> which describes the options that will be expected. It really only needs to know which options
# require arguments so that it can determine where the positional arguments start (b/c otherwise the option arg can look like the
# first positional arg)
#
# If <optSpecs> contains the special value "<glean>", the script that is being invoked will be read to look for a stadard options
# processing loop in order to set the <optSpecs> from that.
#
# Params:
#    <optSpecs>  : a string that contains the accepted options like "ab:c" (see man getopt). If its value is "<glean>" then the
#         source script will be scanned to glean the option syntax spec from the standard while/case loop that follows the
#         invokeOutOfBandSystem call.
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
#    bgBCParse  : separates options similar to this function but also produces bash completion output and returns additional variables
function bgCmdlineParse()
{
	local optSpecs="$1"; shift
	local words=( "$0" "$@" )

	options=()
	varIsAMapArray options || assertError "The caller must 'declare -A options' before calling bgBCParse"

	local -A syntaxSpec=()
	bgMakeUsageSpec "$optSpecs" syntaxSpec

	local _bcp_optPos=0
	while [[ "$1" =~ ^- ]]; do
		local _bcp_opt="$1"; shift; ((_bcp_optPos++))

		# short opt with arg, no space between opt and arg (like -fmyfile.txt) so its one token
		if [[ "$_bcp_opt" =~ ^-[^-]. ]]; then
			options[${_bcp_opt:0:2}]="${_bcp_opt:2}"

		# long opt with arg with = between opt and arg so its one token
		elif match "$_bcp_opt" "^(--[^=]*)=(.*)$" rematch; then
			options[${rematch[1]}]="${rematch[2]}"

		# a short or long option by itself but it requires an arg
		elif [[ "${syntaxSpec[$_bcp_opt]}" =~ ^\< ]]; then
			options[$_bcp_opt]="$1"
			optWords+=("$1")
			shift; ((_bcp_optPos++))

		# a short option without an arg, by itself
		elif [[ "$_bcp_opt" =~ ^-[^-]$ ]]; then
			options[$_bcp_opt]="$_bcp_opt"

		# a long option without an arg, by itself
		elif [[ "$_bcp_opt" =~ ^-- ]]; then
			options[$_bcp_opt]="$_bcp_opt"

		# whats left over must be a string of short options strung together
		else
			_bcp_opt="${_bcp_opt#-}"
			while [ ${#_bcp_opt} -gt 0 ]; do
				local shortOpt="${_bcp_opt:0:1}"; _bcp_opt="${_bcp_opt:1}"
				if [[ "${syntaxSpec["-$shortOpt"]}" =~ ^\< ]]; then
					options["-$shortOpt"]="${_bcp_opt}"
				else
					options["-$shortOpt"]="-$shortOpt"
				fi
			done
		fi
	done

	options["shiftCount"]="$_bcp_optPos"
}

# usage: bgMakeUsageSpec <optSpecs> <syntaxSpecVar>
# this populates the <syntaxSpecVar> associative array return variable with entries that reflect the options in <optSpecs>
#
# Output:
# The <syntaxSpecVar> associative array will have elements added to it to reflect the options from <optSpecs>.
#    <syntaxSpecVar>[options]  : is a sting containing space separated list of all valid options suitable for output of a  bash
#             completion function.
#    <syntaxSpecVar>[posCount]=<N>  : is the number of positional arguments that the spec includes.
#    <syntaxSpecVar>[<opt>]=NOARG|<argName>  : The index is a valid long or short option (like syntaxSpec[-v]). the value indicates
#             if this option requirs an argument and if so what its name is. <argument> is the default name.
#    <syntaxSpecVar>[<N>]=<argName>|val1|val2...  : <N> is the position number (1,2,3...), up to the value of posCount. The value
#             is a list of tokens separated by the | char. If the token is surrounded by <> it is the name of the argument,
#             otherwise its a possible value
#
# Params:
#    <optSpecs>  : this is a string in the format specified by getopts. Its a list of single characters that are valid options.
#                  If a character is followed by : then it will require an argument. Option arguments may or may not have a space
#                  separating them from their option.
#    <syntaxSpecVar> : the name of an associative array (local -A) variable declared by the caller that will receive the output of
#                  this function.
# See Also:
#    man(1) getopt for the description of "optstring" format
function bgMakeUsageSpec() {
	local optSpecs="$1"
	local -n _syntaxSpecVar="$2"
	_syntaxSpecVar=()
	local cmdlineSyntax="$optSpecs"
	local assertErrorContext+="-v cmdlineSyntax"
	if [[ "$optSpecs" =~ \<glean\> ]]; then
		optSpecs="${optSpecs//\<glean\>/ }"
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
		done < <(awk '
			@include "bg_core.awk"
			/invokeOutOfBandSystem/ {trigger=1}
			/^done|^esac/ {trigger=0}
			# 	-C*|--domID*)      bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
			#	-n|--noDirtyCheck) bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
			trigger && /^[[:space:]]*-/ {
				match($0, /^[[:space:]](-[^)]*)[)](.*)$/, rematch)
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
	local defaultIs="optspec"
	local pos=0
	while [ "$optSpecs" ]; do
		# if we see anything execpt these characters its not a simple optspec string (at least from this point forward)
		[[ "${optSpecs:0:1}" =~ [^a-zA-Z0-9] ]] && defaultIs="newSyntax"

		# advance over spaces to the next start character
		if [ "${optSpecs:0:1}" == " " ]; then
			optSpecs="${optSpecs:1}"

		# [-f|--file=<txtFile>]
		# this consists of three parts, each of which is optional. shortOpt, longOpt, and argument.
		elif [ "${optSpecs:0:1}" == "[" ]; then
			optSpecs="${optSpecs:1}"
			local oneOptSpec="${optSpecs%%]*}"
			optSpecs="${optSpecs#*]}"
			[[ "$oneOptSpec" =~ ^(-[^-|<])?\|?(--[^<|=]*)?=?(<[^>]*\>)?$ ]] || assertError -v invalidSpec:oneOptSpec "invalid option specification. "
			local shortOpt="${BASH_REMATCH[1]}"
			local longOpt="${BASH_REMATCH[2]}"
			local arg="${BASH_REMATCH[3]}"
			if [ "${shortOpt}" ]; then
				_syntaxSpecVar[${shortOpt}]="${arg:-NOARG}"
				_syntaxSpecVar[options]+=" ${shortOpt}${arg:+%3A} "
			fi
			if [ "${longOpt}" ]; then
				_syntaxSpecVar[${longOpt}]="${arg:-NOARG}"
				_syntaxSpecVar[options]+=" ${longOpt}${arg:+=%3A} "
			fi

		# f: or f<txtFile>
		elif [[ "${optSpecs}" =~ ^[^\ ][:\<] ]]; then
			local opt="${optSpecs:0:1}"; optSpecs="${optSpecs:1}"
			_syntaxSpecVar[-${opt}]="<argument>"
			_syntaxSpecVar[options]+=" -${opt}%3A "

			[ "${optSpecs:0:1}" == ":" ] && optSpecs="${optSpecs:1}"
			if [ "${optSpecs:0:1}" == "<" ]; then
				_syntaxSpecVar[-${opt}]="${optSpecs%%>*}>"
				optSpecs="${optSpecs#*>}"
			fi

		# in optspec mode assume that this is a single short option without an argument
		elif [ "$defaultIs" == "optspec" ]; then
			_syntaxSpecVar[-${optSpecs:0:1}]="NOARG"
			_syntaxSpecVar[options]+=" -${optSpecs:0:1} "
			optSpecs="${optSpecs:1}"

		# in newSyntax mode this is a positional argument
		# <argName>val1|val2
		# This is a list of one or more tokens separated by the | char. If one of the tokens is surrounded by <> is it the
		# name of the position. Other tokens are possible values.
		else
			local posArg="${optSpecs%% *}"
			optSpecs="${optSpecs#$posArg}"
			[[ "$posArg" =~ ^([<][^>[:space:]]*[>])?(\|[^\|[:space:]]*)*$ ]] || assertError -v posArg "invalid positional argument syntax"

			((pos++))
			_syntaxSpecVar[$pos]="${posArg//\|/ }"
		fi
	done

	_syntaxSpecVar[posCount]=$pos
}


# OBSOLETE: use bgBCParse or bgCmdlineParse
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
#    bgBCParse  : newer version of parseForBashCompletion
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
		[ ${#optWordsValue[@]} -lt ${cwordValue:-0} ] && posCwordsValue=$(( cwordValue - ${#optWordsValue[@]} ))
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



#######################################################################################################################################
### OS Package Management hooks

# usage: _bcPostInstall <pkgName>
# this is meant to be put in the postinst script of packages that include bash autocompletion scripts
# it copies the BC scripts into the correct folder based on what version of bash is present.
# Newer systems put the scripts in /usr/share/bash-completion/completions/ where they will be auto loaded
# Older systems put the scripts in /etc/bash_completion.d
function _bcPostInstall()
{
	local pkgName="$1"

	# if the package is virtually installed, don't do it.
	[[ "$bgLibPath" =~ $pkgName ]] && return

	local destFolder
	if [ -d /usr/share/bash-completion/completions/ ]; then
		destFolder="/usr/share/bash-completion/completions"
	else
		destFolder="/etc/bash_completion.d/"
	fi

	local bcScript
	for bcScript in $(fsExpandFiles /usr/share/${pkgName}/bashCompletion/*); do
		cp "$bcScript" "$destFolder"
	done
}
