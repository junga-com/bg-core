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


# usage: bgBCParse <optSpecs> <cword> <cmdName> [<p1> ... <pN>]
# usage: bgBCParse "<glean>" "$@"; set -- "${posWords[@]:1}"
# usage: bgBCParse "fvqC:" "$@"; set -- "${posWords[@]:1}"
# This typically used from inside a oob_printBashCompletion() callback function to parse the cmdline sent by the
# _bgbc-complete-viaCmdDelegation completion function into a set of well known variables used by the completion routine.
# The caller passes in <optSpecs> which describes the options accepted by the script's cmdline syntax and passes through the
# arguments passed into oob_printBashCompletion as "$@".
# Params:
#    <optSpecs>  : a string that contains the accepted options like "ab:c" (see man getopt). If its value is "<glean>" then the
#         source script will be scanned to glean the option syntax spec from the standard while/case loop that follows the
#         invokeOutOfBandSystem call.
#    Note: the remainder of the parameters follow the syntax of the arguments passed to the command by _bgbc-complete-viaCmdDelegation
#    <cword> : the token position in the cmdline that the user is currently completing.
#    <cmdName> : ($0) the name of the command whose commandline is being completed
#    <pN>  : ($N) parameters on the command line being completed
#
# Return Scope Vars:
# The invokeOutOfBandSystem function declares these variables which this function fills in so when this function is called from
# the oob_printBashCompletion() callback, it does not have to declare these variables and can use them after calling this funciton.
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
#    $options[<opt>]=<value> : output associative array. Indexes of this array are the options specified on the cmdline line according to
#         the <optSpecs> and the corresponding value is the option's argument if it has one or the option repeated if it does not.
#         This is provided in case the script needs to vary the suggestions based on what options the user has specified so far.
#         The caller can test any option by looking it up in this array to see if its non-empty.
#    $posWords[<n>] $posCwords: this is words[] with the optional arguments removed so that <n> corresponds to the consistent
#         position regardless of how many optional arguments and their arguments have been specified on the cmd line.
#         $posCwords is the index into this array of the token currently being completed. If an optional argument is being
#         completed. $posCwords will be 0
#    $optWords[] : this is the leading part of $words[] that contains the optional arguments and their arguments.
#    $words[<n>] $cword : words[] is an array of the entire cmdline. [0] is the command. cword is the index of into
#         this array of the current position being completed
#    $prev : $prev is the token before the one being completed. This is provided because the bash_completion project makes it
#         available but it is not typically used because other variables provide better information.
# See Also:
#    invokeOutOfBandSystem
#    parseForBashCompletion : (being replaced by bgBCParse) this is the long time function that script's printBashCompletion used.
function bgBCParse()
{
	# these are the args to this (bgBCParse) function
	local optSpecs="$1"; shift
	cword="$1"; shift
	words=( "$@" )

	local -A syntaxSpec=()
	if [ "$optSpecs" == "<glean>" ]; then
		local name value
		while IFS="," read -r name value; do
			syntaxSpec[$name]="$value"
			if [[ "$name" =~ ^-- ]] && [[ "$value" =~ ^\< ]]; then
				syntaxSpec[options]+=" $name=%3A "
			elif [[ "$name" =~ ^-[^-]$ ]] && [[ "$value" =~ ^\< ]]; then
				syntaxSpec[options]+=" $name%3A "
			else
				syntaxSpec[options]+=" $name "
			fi
		done < <(awk '
			@include "bg_libCore.awk"
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
	else
		while [ "$optSpecs" ]; do
			if [ "${optSpecs:1:1}" == ":" ]; then
				syntaxSpec[-${optSpecs:0:1}]="<argument>"
				syntaxSpec[options]+=" -${optSpecs:0:1}%3A "
				optSpecs="${optSpecs:2}"
			else
				syntaxSpec[-${optSpecs:0:1}]="NOARG"
				syntaxSpec[options]+=" -${optSpecs:0:1} "
				optSpecs="${optSpecs:1}"
			fi
		done
	fi

	options=()

	cur="${words[${cword:-1}]}"

	shift # cmd name

	local _bcp_optPos=0
	while [[ "$1" =~ ^- ]]; do
		local _bcp_opt="$1"; shift; ((_bcp_optPos++))
		optWords+=("$_bcp_opt")

		# if the user is currently completing an option word, we send some BC output and set opt to indicate that to the caller.
		# We interpret the token a little differently based on whether the user is on this token
		if ((_bcp_optPos==cword)); then
			if [[ "${syntaxSpec[${_bcp_opt:0:2}]}" =~ ^\< ]]; then
				opt="${_bcp_opt:0:2}"
				cur="${_bcp_opt:2}"
				echo "\$(cur:$cur) ${syntaxSpec[${_bcp_opt:0:2}]}"
			elif match "$_bcp_opt" "^(--[^=])=(.*)$" rematch; then
				opt="${rematch[1]}"
				cur="${rematch[2]}"
				echo "\$(cur:$cur) ${syntaxSpec[$opt]:-<argument>}"
			else
				echo "<options> ${syntaxSpec[options]}"
				opt="@options"
			fi

		# when the user is not completing this option token we interpret whether it has a parameter or not based more on the form of
		# the token than on the spec.
		else
			if [[ "$_bcp_opt" =~ ^-[^-]. ]]; then
				options[${_bcp_opt:0:2}]="${_bcp_opt:2}"
			elif match "$_bcp_opt" "^(--[^=])=(.*)$" rematch; then
				options[${rematch[1]}]="${rematch[2]}"
			else
				# we don't check for the complete form here because that is in common below
				options[$_bcp_opt]="$_bcp_opt"
			fi

			# now determine if the next token should be interpreted as the argument to this option. Note that if the user's cursor is on the
			# option and the option is complete and requires an argument, we really dont know but the most common case is that the user has
			# just completed the option and has not yet entered a separate token
			# if _bcp_opt is an exact option token that requires an argument, consume next arg position as the argument
			if [[ "${syntaxSpec[$_bcp_opt]}" =~ ^\< ]]; then
				options[$_bcp_opt]="$1"
				optWords+=("$1")
				shift; ((_bcp_optPos++))
				# if the user is completing the argument of an option is a separate token, set opt to indicate that to the caller
				# the caller will not distuigish between one and two token option w/ arg
			 	if ((_bcp_optPos==cword)); then
					echo "${syntaxSpec[$_bcp_opt]}"
					opt="$_bcp_opt"
				fi
			fi
		fi
	done

	posWords=( "${words[0]}" "$@" )
	posCwords=$(( (_bcp_optPos<cword) ?(cword-_bcp_optPos) :0 ))
}


# usage: parseForBashCompletion --compat2 wordsVarName cwordVarName curVarName prevVarName optWordsVarName posWordsVarName posCwordsVarName "$@"
# usage: parseForBashCompletion [-o"hs:a:"] wordsVarName cwordVarName curVarName prevVarName optWordsVarName posWordsVarName  "$@"
# usage: (cont)                 <cword> [<word1> .. <wordN>]
# This function supports previous versions with a --compatN option.
# this is typically used at the top of a script's printBashCompletion function to get the
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
