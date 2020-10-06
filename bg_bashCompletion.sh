# this files contains completion functions that implement a style of completion that delegates to the cmd

declare -gA _bgbcData


# MAN(3.bashFunction) _bgbc-complete-viaCmdDelegation
# usage: complete -F _bgbc-complete-viaCmdDelegation <cmdName>
# This is the main entry point for commands to use this bash completion mechanism
# The bash completion script installed for a command can be a simple stub that calls
# this function. This function invokes the command with the hidden -hb and -hbo command
# line switches to delegate the responsibility of producing the completion suggestions
# to the command itself.
# Cmd Invocation:
#   This function will call the script (<cmd>) in one of two ways depending on whether the user is editing an
#   option or positional param.
#     positional param:  <script> -hb <cword> <COMP_LINE>
#     optional argument: <script> -hbo <option> <cur> <cword> <COMP_LINE>
#           <option> is the single letter w/o the - (like 'v' for -v) or the complete <cur> tooken
#                    for long form options
#   bg-core style bash script commands typically call invokeOutOfBandSystem "$@" which handles these two
#   cases and calls oob_printBashCompletion() or oob_printOptBashCompletion() which is where the script
#   author actually puts the completion routines.
#
# Cmd Output:
#    The script (or any cmd) should respond to being invoked with one of the syntax described above by
#    writing a series of tokens to its standard out. The prevailing IFS (typically space, tab, newline)
#    will be used to delimit the tokens except for directives of the form \$(<directive> p1 p2 .. )
#    which can contain spaces and tabs between the (). All tokens are either suggestions or $(<directives>)
#    or comments that are surrounded by <> like <myComment>
#  Suggestions:
#    any words that would be valid for the current position being editted should be written to stdout.
#    The <cmd> does not need to eliminate ones that do not match what the user has typed so far. The list will
#    be filtered by what the user has typed so far automatically. Whitespace needs to be escaped with
#    URL encoding (i.e. space is %20)
#    Processing of Suggetions:
#       <word>%3A : this word will not terminate the postion being edited if the user chooses it. Instead
#                   the cursor will stay at the end of <word> and the completion routine will continue
#                   to be called on this word until the user types another character. When the user
#                   types space, completion will advance to the next position
#       <word>%20 : this word will terminate the postion if selected. %20 can be used to specify a space
#                   anywhere in the word but when its at the end, it has the effect of moving the user
#                   to the next position
#       auto space adding: If the end of the word is neither %3A nor %20 a space may be added automatically
#                   unless some directive is in effect that changes that default.
#       URL decoding: returned tokens are delimited by characters in the user's IFS. If you want a suggestion
#                   to include one of those characters you should replace it with its URL encoded token.
#                       space   = %20
#                       tab     = %09
#                       linefed = %0A
#       relative cur fixup: If the word being completed (cur) contains a COMP_WORDBREAKS character like
#                   = or :, this will fix up sugesstions that are relative to the beginning of the word.
#       <<token>> : ex <filename> . If a token is surronded by <> is will not be considered a suggestion
#                   but rather a comment the same as if $(comment <token>) had been used. See comment directive.
# .SH $(cur <partCur>) Directive:
#    Normally suggestions are the full words of the position being completed. This directive specifies that
#    the sggestions should be taken as a partial token relative to the start of the token already completed.
#    This works regerdless of whether a character in COMP_WORDBREAKS separates the parts.
#    For example <name>:<value>
#       At first the user selects from a list of names but after a name is selected and the : is added,
#       the user seess a list of <value> (without <name>: prefix).
#    if [[ ! "$cur" =~ : ]]; then echo "name1: name2:"; else echo "\$(cur ${cur%:*}) val1 val2 val3"
# .SH $(prefix:<word>) and $(suffix:<word>) Directives:
#    any suggestions that come after this will have <word> prepended or appended up until another directive
#    changes the prefix/suffix.
# .SH $(_filedir [-d]) Directive:
#    complete on path names relative to the user's PWD.
#    $(doFilesAndDirs) : synonym for $(_filedir)
#    $(doDirs)         : synonym for $(_filedir -d)
# .SH $(replace <token>) Directive:
#    causes the current word being editted to be replaced by <token>
#    Note that what Bash considers the current word can be a little strange and I have found no way to
#    make readline/bash change more that what it thinks is the token being edited
#    Bash's notion of the token does not include the charcters at the cursor or after. Only characters
#    behind the cursor can be changed.
#    The token that is being edited goes back to the first character that is in COMP_WORDBREAKS. Typically
#    on Ubuntu, that includes ':' and '='. So even though in "<cmd> name:value p2" "name:value" will be
#    passed to <cmd> as one argument, readline/bash completion will treat name : and value as separate
#    tomkens and depending on where the cursor is on that token, either "name" or "value" will be replaced.
# .SH $(usingListmode <separatorChar>) Directive:
#    complete a token where the user can enter multiple choices separated by the <separatorChar>.
#    For example echo "$(usingListmode ,) one two three four", will prompt the user for one of those
#    4 suggestions and then gives the user a choice to enter a , to continue or a space to end the list. Then
#    the remaining 3 suggestions , etc...
# .SH $(nextBreakChar <char>) Directive:
#    This makes it so that any suggestion that does not end in a space/%20, will give the user a choice
#    adding <char> or a space. Any suggestion that is specified with <char> at the end will not complete
#    the postion but continue calling completion on the end of that word when it is selected.
# .SH $(nospace) Directive:
#    dont add any automatic terminating spaces to suggestions. This does not changes suggestions that
#    explicitly incude a terminating %20(terminate) or %3A(dont terminate).
# .SH $(nosort) Directive:
#    Display the suggestions to the user in the order shown instead of sorting them.
#    bash prior to 4.4, not support this but on those systems, this will cause AA to be prepended to
#    comment tokens so that they are more likely to appear before real suggestions.
# .SH $(comment <token>) Directive:
#    Display <token> amoung the suggestions but in a way that it can not be choosen and the user can
#    tell that it is not a suggestion but rather information about the completion being preformed.
#    Typically this is used to indicate the cmd syntax by including the name of the parameter being
#    completed.
#    Note that <token> can be specified with this directive or by using <> to wrap the <token> instead
#    of $(). For example <filename> or <FirstName>
# .SH $(compgen <opts> ..) Directive:
#    invoke comgen routines and use the results as suggestions.
# .SH $(compopt <opts>) Directive:
#    invoke any comopt to affect the current completion. These changes are not permanent and only effect
#    the current completion run.
# .SH $(<bashFunction>) Directives:
#    if <bashFunction> is a sourced function, it is invoked, adding the results as suggestions.
#    See bash_completion project for many useful functions that are available in many distros.
#    Note that we do not support passing parameters on purpose to limit the ability of cmds to abuse
#    this interface to modify the user's environment.
# See Also:
#    invokeOutOfBandSystem
#    bgOptionsEndLoop
function _bgbc-complete-viaCmdDelegation()
{
	# disable the DEBUG trap handler while we are in this function
	builtin trap - DEBUG

	local _bgBCTracefile
	# calling __bgbc_trace will cause _bgBCTracefile to be set
	# add a blank line at the start of each completion to make the log more clear
	__bgbc_trace
	__bgbc-complete-viaCmdDelegation &>> $_bgBCTracefile

	# if this feature is turned on, re-enable the DEBUG trap handler
	if [ "$bgBashCmdHookFeature" ]; then
		builtin trap 'cmdlineHook_debugTrap' DEBUG
	fi
}

# see _bgbc-complete-viaCmdDelegation
function __bgbc-complete-viaCmdDelegation()
{
	type -t bgtimerStart &>/dev/null && bgtimerStart
	declare -gA _bgbcData

	# we make our own token array and position vars by parsing COMP_LINE and COMP_POINT directly
	# because both bash (COMP_WORDS,CWORD) and bash_completion project (words,cword) have mistakes in
 	# how they diviate from the bash grammer parsing. (words,cword) fixes the COMP_WORDBREAKS issue
	# but not quoting when a quote begins after a COMP_WORDBREAKS char.
	local cmd="" cmdTokens=() cmdTokensWOEsc=() cmdPos=0 cmdPrev="" cmdCur="" curBehindCusor curWhole curWRTBash curFixedBase cmdWordBreakCorrection=""
	__bgbc_parseCOMPLINE

	# the TLS cur var is a convention from the bash_completion project which we embrace. Its the logical
	# token being completed. We allow the $cmd to change cur by removing a prefix which means that the
	# removed prefix is fixed and not be subject to any further change and the suggestions will only
	# replace the new cur.  All the routines written for the bash_completion project should work.
	local cur="$cmdCur"

	# replace COMP_WORDS and COMP_CWORD with our version in case we call some function that relies on them
	# they will handle quoting correctly
	COMP_WORDS=("${cmdTokens[@]}")
	CWORD="$cmdPos"

	# declare aliases for the bash_completion project's names in case we call any BC functions from
	# other projects. (note that because we changed COMP_WORDS, those functions will see correct quoting)
	local prev="$cmdPrev" words=("${cmdTokens[@]}") cword="$cmdPos"

	# check to see if we are processing the same position as last time (still on the same position)
	local bcID="${cword} ${words[*]:0:${cword}} <cur> ${words[*]:${cword}+1}"
	if [ "${_bgbcData[lastbcID]}" == "$bcID" ]; then
		# if this is a repeated tab, and caching is enabled, just return the results we already created last time
		if [ ! "${_bgbcData[noCache]}" ] && [ "${_bgbcData[lastCur]}" == "${words[$cword]}" ]; then
			IFS=$'\b' eval 'COMPREPLY=(${_bgbcData[lastCOMPREPLY]})'
			__bgbc_trace --timer "repeating saved bcID='$bcID' cur='${_bgbcData[lastCur]}'"
			return
		fi
	else
		# clear last* because we are starting a new position or maybe a new command
		for i in "${!_bgbcData[@]}"; do
			[[ "$i" =~ ^last ]] && unset _bgbcData[$i]
		done
	fi


	# init the COMPREPLY return value to empty. The only output of a completion routine is the COMPREPLY var.
	# Typically there are 2 ways things get added to COMPREPLY in this function.
	#   1) $(<directives>) specified by the <cmd> output runs comgen or other standard completion
	#      routines whose output is put directly in COMPREPLY.
	#   2) suggestions generated from the options code below or in the output of the <cmd> get put in
	#      cmdOutputWords which gets processed into validWords which gets processed and added to COMPREPLY
	COMPREPLY=()

	# If this is set, this one token will take precendent over any other suggestions might be present
	# to become the token that the user is entering at the current position. It is not checked to see
	# if it matches cur. It will replace cur completely. This can be used with the $(cur:<newCur>)
	# directive to replace only part of the current token. Note that the cur directive can reduce the
	# amount of the current token that gets replaced but can not increase it beyoond its original value
	# which is what readline/bash think is the entire token being edited.
	local COMPREPLY_override=""
	local COMPREPLY_overrideFlag=""

	# when routines want to indicate that a suggestion should terminate the current postion an move on
	# they can add this sufix. Some things like usingListmode will set this to empty so that it can
	# control the termination
	local bcTerminatingChar=" "

	# validWords is where we collect suggestion so that we can process them separately before merging
	# into COMPREPLY
	local validWords=()

	# comments is where we collect the informational tokens that are not suggestions but instead
	# descriptions of the syntax and any other information to communicate to the user.
	# comments tokens are surrounded by <>
	local comments=()

	# declare the state vars for the usingListMode feature
	local usingListmodeMode="" usingListmodePreviousElementsRE="" usingListModeRemainingElements=()

	# if lastModesEnabled are set for this position and the user entered @<tab>, short circuit this run to remove the @
	local modeCommandsWritten
	if [ "${_bgbcData[lastModesEnabled]}" ] && __bgbc_processAdvancedMode; then
		return
	fi

	# nosort is introdeced in bash 4.4 (Ubuntu 18.04). We make it the default. \$(sort) directive undoes it
	# in 4.3 and prior, commentsSortPrefix makes comments appear (almost) first
	compopt -o nosort 2>/dev/null || commentsSortPrefix="AA"

	### First Stage Processing of the <cmd> output
	# invoke the $cmd -hb and do the initial processing staging on its output.
	# The command output can contain both $(<directives>) and suggestions.
	# Some <directives> are needed because there are compgen and bash_completion project functionality
	# that we will like to reuse but can only be invoked the bash sourced environment as opposed to
	# a child process that we run the $cmd in.
	# Other $(<directives>) communicate how this function should interpret or process the suggestions
	# returned.
	# This stage separates the <directives> and the suggestions into validWords().
	# and invokes them to fill in COMPREPLY directly
	# doing some feature processing like prefix and suffix additions.
	local prefix suffix doFilesDirsFlag skipValidWords usingListmodeFlag nextBreakChar commentsSortPrefix nospaceFlag removePrefix
	local removeSuffix
	local token; while read -r token; do
		[ ! "$token" ] && continue;
		token="${token//%20/ }"
		case $token in
			# Anything that is not a suggestion is wrapped in $(<directive>) so that they can not collide
			# with suggestions.
			'$('*')')
				[[ "$token" =~ ^[[:space:]]*\$\(([^:\ \)]*)[:[:space:]]*([^\)]*)\)[[:space:]]*$ ]]
				local directiveSpec="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
				local directive="${BASH_REMATCH[1]}"
				local directiveArgs="${BASH_REMATCH[2]}"
				set -- "${BASH_REMATCH[2]}"
				#local rematch=("${BASH_REMATCH[@]}"); bgtraceVars token rematch
				local count="${#COMPREPLY[@]}"
				case $directive in
					# These are the suggestion modifiers that change how the suggestions are processed while they are in effect
					prefix)       prefix="$*"; __bgbc_trace -v "applying prefix '$prefix'" ;;
					suffix)       suffix="$*"; __bgbc_trace -v "applying suffix '$suffix'" ;;
					removePrefix) removePrefix="$*";  ;;
					removeSuffix) removeSuffix="$*";  ;;

					# $(cur <partBeingCompleted>) specifies a suffix of the current token position
					# that is logically being completed. The suggestions will be relative to this and
					# when a suggestion or prefix matches, only the <partBeingCompleted> suffix of the
					# $cur word will be replaced. If <partBeingCompleted> is empty, the suggestion will
					# be appended to $cur
					cur)
						directiveSpec="$directiveArgs"
						__bgbc_trace -v "applying $directiveSpec directive"
						__bgbc_setLogicalCur "$directiveArgs"
						;;

					# usage: $(comment <msg>)
					comment)
						comments+=("$directiveArgs")
						;;

					# usage: $(usingListmode <separatorChar> [--dynamicMode])
					# List mode allows the user to select multiple items from the suggestions sent from the script separated by the
					# <separatorChar>. The default is that choices are removed from the suggestions after they are selected in the
					# list but --dynamicMode changes that so that the user can select the same value multiple times.
					usingListmode)
						__bgbc_trace -v "applying usingListmode with breakChar='$1'"
						__bgbc_usingListMode "$1"
						;;

					# this makes the specified character a breakChar (regardless of whether its in COMP_WORDBREAKS)
					# It means that by default, the current word being completed will stop and not go to
					# the next position.
					# If the current completed word ends with niether this breakChar nor a space (%20),
					# the user will be prompted to either enter the breakChar to enter the next part of
					# the token or space to move on to the next position.
					# if the word ends in a space(%20) it will automatically move on to the next position.
					# if it ends in the breakChar it will automatically move on to completing the next part.
					nextBreakChar)
						nextBreakChar="$1"
						__bgbc_trace -v "setting nextBreakChar='$nextBreakChar'"
						;;

					# $(replace <word>) causes the current word being editted to be replaced by <word>
					# What Bash considers the current word is a little strange. Is the characters behind
					# the cursor back to the first COMP_WORDBREAKS character. Since that includes = and :
					# the entire word that will be the positional param when the <cmd> is invoked may
					# not be replaced. Also the charater at the cursor and after will not be removed.
					replace)
						COMPREPLY_override="$directiveArgs"
						COMPREPLY_overrideFlag="1"
						compopt -o nospace
						__bgbc_trace "\$(replace) overriding everything else to set the token to '$directiveArgs'"
						;;

					# $(nospace) makes the default not to add a space to words. Like compopt -o nospace
					# except this controls this function's algorithm to add spaces. A particular suggestion
					# can still end in %20 to have a space at the end.
					nospace)
						nospaceFlag="1"
						;;

					# $(nosort) causes bash not to sort the suggestions so that we can controll the order
					# prior to bash 4.4 nosort was not supported. If -o nosort returns an error we set
					# the commentsSortPrefix="AA" so that comments appear first which is one reason we
					# want to control the order.
					nosort)
						compopt -o nosort 2>/dev/null || commentsSortPrefix="AA"
						;;

					# $(sort) causes bash not  sort the suggestions
					# prior to bash 4.4 sort is the only option. Post 4.4 we make nosort the default.
					sort)
						compopt +o nosort 2>/dev/null
						commentsSortPrefix=""
						;;

					# $(enableModes) advanced mode is where the user can type a @ to toggle the mode between basic and
					# advanced modes. The script can query the mode in _bgbcData[lastMode] and offer different suggestions
					enableModes)
						local modeList="${*:-basic advanced}"
						_bgbcData[lastModesEnabled]="${modeList}"
						[ ! "${_bgbcData[lastMode]}" ] && _bgbcData[lastMode]="${modeList%% *}"
						;;

					# The $(<directive>) statements below generally bypass validWords and its special processing
					# by putting the results directly in COMPREPLY. They can override validWords completely if
					# needed by setting skipValidWords="1"

					# these invoke the builtin file / dir completion routines
					_filedir*-d|doDirs*) doFilesDirsFlag="-d" ;&
					_filedir|doFilesAndDirs*)
						__bgbc_trace  "applying $directiveSpec directive doFilesDirsFlag='$doFilesDirsFlag'"

						if [[ ! "$cur" =~ / ]]; then
							local parentPart=""
							local childPart="$cur"
						else
							local parentPart="${cur%/*}"
							local childPart="${cur##*/}"
						fi
						local -A dirs=()
						local tmp; while read -r tmp; do
							tmp="${tmp#$parentPart/}"
							dirs[$tmp]="$tmp/"
							validWords+=("$tmp/%3A")
						done < <(compgen -d -- "$cur")
						[ "$doFilesDirsFlag" != "-d" ] && while read -r tmp; do
							tmp="${tmp#$parentPart/}"
							[ ! "${dirs[$tmp]}" ] && validWords+=("${tmp}${bcTerminatingChar}")
						done < <(compgen -f -- "$cur")
						__bgbc_setLogicalCur "$childPart"

						[ "$usingListmodeFlag" ] && usingListmodeMode="dynamic"
						;;

					# run compgen. We need to protect against arbitrary code execution so that a program
					# cant change the user's PATH.
					compgen)
						__bgbc_trace -v "running 'compgen $directiveArgs'"
						COMPREPLY+=( $(compgen $directiveArgs) )
						;;

					# run compopt.
					compopt' '*)
						__bgbc_trace -v "running 'compopt $directiveArgs'"
						compopt $directiveArgs
						;;

					# $(<sourcedFunction>) run <sourcedFunction> to populate COMPREPLY
					# note that most completion functions do not require any arguments. We do not
					# support passing any arguments because we are not sure if there will be any sourced
					# functions that could be abused to change the user's environment. Because this
					# function is sourced, it should be regarded as running at a higher priviledge
					# than the $cmd that the user is executing because we don't want that cmd to be able
					# to confuse this deputy into changing the users persistent environment which
					# is something that a cmd can not do.
					*)	if [[ "$(type -t "$directiveSpec")" =~ ^(function)$ ]]; then
							__bgbc_trace -v "running '${args[@]}'"
							"$directiveSpec"
						else
							__bgbc_trace "ignoring '$directiveSpec' since it it not a sourced function. note we do not allow passing parameters"
						fi
						;;
				esac
				count=$((${#COMPREPLY[@]} - count))
				[ ${count:-0} -gt 0 ] && __bgbc_trace "\$($directiveSpec) directive: added '$count' suggestions"
				;;

			# <comment>: words that are wrapped in <> are not suggestions but provide information about
			# the syntax being completed.
			'<'*'>') comments+=("${token}") ;;

			# case for legacy cur: syntax
			cur:*)
				__bgbc_trace "!!!! $cmd uses the depreciated cur: syntax. It should be changed to \\\$(cur:...)"
				__bgbc_trace -v "applying cur: directive"
				__bgbc_setLogicalCur "${directiveSpec#cur[: $]}"
				;;

			# these are the raw suggestions from the command
			*)	token="${token#$removePrefix}"
				token="${token%$removeSuffix}"
				validWords+=("${prefix}${token}${suffix}")
				;;
		esac
	done < <(
		export _bgbcDataStr="$(__bgbc_arrayToString _bgbcData)"
		export bgDebuggerOn=""
		export bgTracingOn=file:$_bgBCTracefile
		$cmd -hb "$cmdPos" "${cmdTokensWOEsc[@]}" 2>>$_bgBCTracefile | sed "$_bgSedTokenizingScript"
# CRITICALTODO: update invokeOutOfBandSystem et all parsing to remove quotes like 'name:"that and that'
	)
	local cmdReturnedSuggestionCount="${#validWords[@]}"

	__bgbc_trace -v "(1) validWordsCount='${#validWords[@]}' COMPREPLYCount='${#COMPREPLY[@]}'"

	# Typically, foreign suggestions are _filedir or other registered completion functions. Its not
	# certain at this time whether we should always treat them just like suggestions returned directly
	# into validWords or if we want to provide separate processing paths.
	__bgbc_processForeignSuggestions
	__bgbc_trace -v "(2) validWordsCount='${#validWords[@]}' COMPREPLYCount='${#COMPREPLY[@]}'"

	# note that typically __bgbc_processAdvancedMode will be detected and proccessed before the script is invoked and this line
	# will not be reached, but if the user types @<tab> at a new position, the lastModesEnabled won't be set yet because we need
	# to invoke the script at the current position once to know that modes are enabled and which modes are enabled for this position
	if [ "${_bgbcData[lastModesEnabled]}" ] && __bgbc_processAdvancedMode; then
		return
	fi

	### Second Stage Processing of the <cmd> output
	if [ ! "$skipValidWords" ] && [ ${#validWords[@]} -gt 0 ]; then
		# The validWords array now contains just the suggestions from the <cmd> output. We support some
		# extended syntax for what those suggestions can be so that its easier for the <cmd>.
		# The most notable is the feature that each suggestion can specify whether it will complete the
		# current position if it is choosen by the user.
		__bgbc_processValidWords

		### add our validWords to the COMPREPLY
		# at this point, the COMPREPLY might already be populated  by one of the <directives> or it might
		# be empty. Likewise, validWords may or may not be empty. But if there are any suggestions in
		# validWords, they will be supersets of curBehindCusor (aka cur) so they will coexist with any words in
		# COMPREPLY already.
		COMPREPLY+=("${validWords[@]}")
		__bgbc_trace -v "(3) validWordsCount='${#validWords[@]}' COMPREPLYCount='${#COMPREPLY[@]}'"
	fi


	__bgbc_finalizeCOMPREPLY
	__bgbc_trace -v "(4) validWordsCount='${#validWords[@]}' COMPREPLYCount='${#COMPREPLY[@]}'"

	__bgbc_traceVars -v COMPREPLY
	__bgbc_trace -v "(5) validWordsCount='${#validWords[@]}' COMPREPLYCount='${#COMPREPLY[@]}'"

	# save this state for next time
	_bgbcData[lastbcID]="$bcID"
	_bgbcData[lastCur]="${words[$cword]}"
	IFS=$'\b' eval '_bgbcData[lastCOMPREPLY]="${COMPREPLY[*]}"'

	__bgbc_trace --timer "invoked '$cmd -hb "$cmdPos" <COMPLINE>' produced '$cmdReturnedSuggestionCount' suggestions, '${#COMPREPLY[@]}' after processing and filtering with cur='$cur' "
}



# usage: __bgbc_processAdvancedMode
# Act on the user pressing @<tab>  and @modename<tab>
# This sequence will cause the _bgbcData[lastMode] setting to toggle and the @ will be removed from the cmdline
# Note that this is called once early (before the script invocation) and once late (after).
# Exit Code:
#    0(true) : the user did press a @<tab> which was processed and no further processing should be done
#    1(false): normal case. no action is being taking. mode is staying the same. proceed with processing
function __bgbc_processAdvancedMode()
{
	local lastMode="${_bgbcData[lastMode]}"
	if [[ "$curBehindCusor" =~ @$ ]]; then
		__bgbc_varToggleRef _bgbcData[lastMode] ${_bgbcData[lastModesEnabled]:-advanced basic}
		COMPREPLY_override="${curBehindCusor%@}"

	elif [[ "$curBehindCusor" =~  ^@(${_bgbcData[lastModesEnabled]// /|})$ ]]; then
		_bgbcData[lastMode]="${curBehindCusor#@}"
		COMPREPLY_override=" "

	else
		if [ ! "$modeCommandsWritten" ]; then
			modeCommandsWritten="1"
			local matchingCommands=()
			local modeCommands=(${_bgbcData[lastModesEnabled]})
			for i in "${!modeCommands[@]}"; do
				modeCommands[$i]="@${modeCommands[$i]}"
				[[ "${modeCommands[$i]}" =~ ^"$cur" ]] && matchingCommands+=("${modeCommands[$i]}")
				[ "${modeCommands[$i]}" == "@${_bgbcData[lastMode]}" ] && modeCommands[$i]="@<${_bgbcData[lastMode]}>"
			done
			if (( ${#matchingCommands[*]} == 1 )); then
				_bgbcData[lastMode]="${matchingCommands[0]#@}"
				COMPREPLY_override=" "
			else
				validWords+=("${modeCommands[@]}")
				return 1
			fi
		else
			return 1
		fi
	fi

	__bgbc_trace "changing mode from '$lastMode' to '${_bgbcData[lastMode]}' modes='${_bgbcData[lastModesEnabled]:-advanced basic}'"
	COMPREPLY_overrideFlag="1"
	compopt -o nospace
	COMPREPLY=("${COMPREPLY_override:- }")
	return 0
}

# usage: __bgbc_processForeignSuggestions
# at this point COMPREPLY should contain suggestions from $(<directives>) like _filedir but not our cmd's
# native suggestions that might be aprt of a feature that requires special processing.
function __bgbc_processForeignSuggestions()
{
	# its not certain yet whether some things will need seaprate processing paths. For now we dump them
	# into validWords with the rest
	validWords+=("${COMPREPLY[@]}")
	COMPREPLY=()
}


# usage: __bgbc_usingListMode <listSeparatorChar> [--dynamicMode]
# This is the first real feature that requires multiple stages of behavior -- init, per suggestion, and
# post processing the filtered suggestion list.
# If there are more, we should make these plugin objects with methods.
# For now this is called from the directive handler and sets a flag and the other code is emebded in the
# processing path and is activated if the flag is set.
function __bgbc_usingListMode()
{
	nextBreakChar="$1"
	usingListmodeMode="${2#--}"
	usingListmodeFlag="1"
	bcTerminatingChar=""
	# this regex that matches the elements already in the list but not the last one that is being completed now.
	if [[ "$curBehindCusor" =~ ${nextBreakChar} ]]; then
		usingListmodePreviousElementsRE="${curBehindCusor%${nextBreakChar}*}"
		__bgbc_setLogicalCur "${curBehindCusor##*${nextBreakChar}}"
	fi
	usingListmodePreviousElementsRE="^(${usingListmodePreviousElementsRE//$nextBreakChar/'|'})$"
}


# usage: __bgbc_processValidWords
# validWords is the array that we use to hold the suggestions returned from a script's -hb invocation.
# the stdout of the script -hb is filtered by _bgSedTokenizingScript and placed in cmdOutputWords.
# Those words can contains $(<directives>) and suggestion words. Directives are ran and produce suggestions
# into COMPREPLY. Suggestions from  cmdOutputWords are put in validWords and then this function does
# the extra processing on them
# Processing Features:
#    * ending spaces: when a suggestion is completely matched, if it has a trailing space, the user
#         will be placed at the next argument position. If it does not have a trailing space, the user's
#         prompt will remain at the end of the position a further tabs can sugest additional endings.
#         compopt -o nospace applies to all suggestions or none. This function supports
#         putting a %3A (nospace) or %3B (add space) to each suggestion so that some can have spaces
#         added and some can not.
#    * piece wise completion: The script can let the user complete parts of the word at a time. For example
#         when completing <name>:<value>, the use can choose <name> and then choose a <value> that is
#         specific to name instead of seeing all combinations of <name>:<value> at once. : is well supported
#         because its in the COMP_WORDBREAKS but , and other separators are not. We can not change
#         COMP_WORDBREAKS without effecting other completion scripts.
#         This function supports the script declaring where to do the partial completion by returning
#         a new $cur that the results are relative to. This function will fix up the suggestions accordingly
#         based on whether any separators are in COMP_WORDBREAKS. When they are not in COMP_WORDBREAKS
#         it does not work as well but its better than nothing and when bash fixes this, they will
#         work better.
#    * escaping: spaces and other special characters can be escaped with %20 style tokens. Those tokens
#         are better than '\ ' style because they pass through an arbitrary number of word splitting
#         without change.
function __bgbc_processValidWords()
{
	# our processing handles spaces
	compopt -o nospace
	[ "$usingListmodeFlag" ] || __bgbc_traceVars -v comments validWords

	__bgbc_detectAndCorrectSuggestionsRelativeToWrongCur

	local couldBeCompleteFlag
	local i; for i in "${!validWords[@]}"; do
		### first process the three types of endings that will determine whether it should have a space
		# at the end that will determine whether it is a complete token or if the user should be left
		# at the end to consider additional suffixes

		# %3A at the end means it should not have an ending space so we get a chance to add more
		if [[ "${validWords[$i]}" =~ %3A$ ]]; then
			validWords[$i]="${validWords[$i]//%3A}";

		# suggestions will get a trailing space which will cause the cursor to go on to the next position
		# by default but if it ends in the nextBreakChar it will stay so that the user can complete the
			# next part of the token.
		elif [[ ! "${validWords[$i]}" =~ \ $ ]] && [[ ! "${nextBreakChar}" ]] && [ ! "$nospaceFlag" ]; then
			validWords[$i]="${validWords[$i]} ";
		fi

		# replace all %20 with escaped spaces
		validWords[$i]="${validWords[$i]//%20/\\ }";
		# replace all ! with \!
		validWords[$i]="${validWords[$i]//!/\\!}";

		### usingListmode feature. remove suggestions that are already in the list.
		if [ "$usingListmodeFlag" ] && [ "$usingListmodeMode" != "dynamic" ]; then
			if [[ "${validWords[$i]}" =~ $usingListmodePreviousElementsRE ]]; then
				unset validWords[$i]
			else
				usingListModeRemainingElements+=("${validWords[$i]}")
			fi
		fi

		### remove non-matching entries
		# we can not use 'compgen -W <words> -- $cur' because it only accepts <words> as a single paramter
		# for which it does IFS word splitting and that ruins our space endings.
		if [[ "${validWords[$i]}" != "$cur"* ]]; then
			unset validWords[$i]
		fi

		### note if cur is one of the suggestions (there could be others that are longer too)
		if [ "${validWords[$i]}" == "$cur" ]; then
			couldBeCompleteFlag="1"
		fi
	done


	if [ "$usingListmodeFlag" ]; then
		__bgbc_traceVars -v -l"validWords       :${validWords[*]}" -l"usingListModeRemainingElements:${usingListModeRemainingElements[*]}"
		# when editting a list, each time the user completes the current element in the list, we give
		# the user a choice to add another element from the set of usingListModeRemainingElements.
		if [ ${#validWords[@]} -eq  1 ] && [ "$cur" == "${validWords[*]}" ]; then
			local terminator; [ ${#usingListModeRemainingElements[@]} -eq 1 ] && terminator=" "
			local element; for element in "${usingListModeRemainingElements[@]}"; do
				[ "$cur" != "$element" ] && validWords+=("${nextBreakChar}${element}${terminator}")
			done
			[ "$usingListmodeMode" == "dynamic" ] && validWords+=("${validWords[*]}${nextBreakChar}")
		fi
		if [ ${#usingListModeRemainingElements[@]} -eq 1 ]; then
			validWords=("${validWords[*]} ")
		fi
		__bgbc_traceVars -v -l"validWords       :${validWords[*]}"
	fi

	# if a nextBreakChar has been specifed and cur matches a complete suggestion, add the option for nextBreakChar
	if [ "$nextBreakChar" ]; then
		if (( ${#validWords[@]} == 1 )); then
			[[ "${validWords[*]}" =~ [\ $nextBreakChar]$ ]] || validWords=("${validWords[*]}$nextBreakChar")
		elif [ "$couldBeCompleteFlag" ]; then
			validWords+=("${cur}$nextBreakChar")
		fi
	fi
}


function __bgbc_detectAndCorrectSuggestionsRelativeToWrongCur()
{
	__bgbc_trace -v "testing suggetiong fixup with curFixedBase='$curFixedBase'"
	local i; for i in "${!validWords[@]}"; do
		[[ "${validWords[$i]}" =~ ^$curFixedBase ]] || return
	done

	__bgbc_trace -v "removing curFixedBase='$curFixedBase'"
	local i; for i in "${!validWords[@]}"; do
		validWords[$i]=${validWords[$i]#$curFixedBase}
	done
}

# usage: __bgbc_finalizeCOMPREPLY
# Do the processing of COMPREPLY to make completion work correctly with bash's strange notion of COMP_WORDBREAKS
# and implement various extra features.
# COMP_WORDBREAKS Correction:
#    This library isolates the bash completion routine authors from having to deal with unusual arg
#    parsing. The rule of this library is that the COMP_LINE is parsed into token the same as bash will
#    parse it when invoking the cmd. $1 $2 .. $n will correspond to cmdTokens[1] cmdTokens[2] etc..
#    This means that our notion of the token that is being editted will be different than bash's notion
#    when either the token contains COMP_WORDBREAKS chacters or the completion routine author uses our
#    facility to do step wise, partial completion.
#    This funciton will ...
#       1) detect when the cursor should be advanced and set COMPREPLY to exactly one entry that bash
#          will replace its notion of the token being edited with. We translate that entry so that it
#          is relative to what bash thinks the token is if its different from what it logically is.
#       2) normally readline will just display as suggestions each entry in COMPREPLY so we can display
#          the logical next part that we want the user to choose from even if it does not correspond to
#          what readline/bash think that we are editing. But if all the tokens in COMPREPLY have a common
#          root prefix, readline will replace the current token with that prefix. If our notion of the
#          token being edited is different from readline/bash's notion, this results in readline
#          overwriting the wrong thing. So this function detects that stiuation and adds a '>' entry
#          to make sure that there is no common root.
# Features:
#    ? : if the user enters a ?<tab> it invokes our help system to display help information.
#    comments : is an array that holds information about the current completion. Typically the <paramName>
#         being entered. These are included in the COMPREPLY when appropriate but ensured not to effect
#         the selection of suggestions. An attempt is made to order comments first. Pre bash 4.4 there
#         is no explicit control over sort order.
# Input:
#    COMPREPLY  : all the suggestions should be added at this point
#    comments   : comment tokens that are surrounded with <> should be in this array
# Output:
#    COMPREPLY : contents will be maniplulated to achieve the correct effect.
function __bgbc_finalizeCOMPREPLY()
{
	### detect if there is a logical common root in the remaining suggestions that shold advance the
	# cursor/token being completed.
	local newCur="${cur}"

	# pick any word to be $anotherWord. We will lengthen newCur by the common root between cur and anotherWord
	# but at each new letter we compare against all the entries so it does not matter which we choose.
	# note: COMPREPLY can be sparse so [0] wont always work
	local anotherWord; for i in "${!COMPREPLY[@]}"; do anotherWord="${COMPREPLY[$i]}"; break; done

	# this is the algorithm to find the longest newCur that is a prefix of all entries
	local i j; for ((i=1; i<=$(( ${#anotherWord}-${#cur} )); i++)); do
		newCur="${cur}${anotherWord:${#cur}:$i}"
		local isCommonToAll="1"
		for j in "${!COMPREPLY[@]}"; do
			[[ ! "${COMPREPLY[$j]}" =~ ^$newCur ]] && { isCommonToAll=""; break; }
		done
		if [ ! "$isCommonToAll" ]; then
			newCur="${newCur:0:-1}"
			break
		fi
	done


	# replace feature. If set, this token will override all the other suggestions to make this the
	# token on the cmd line
	if [ "$COMPREPLY_overrideFlag" ]; then
		newCur="${COMPREPLY_override#<EMPTY>}"
	fi


	# if we made newCur longer, make readline advance to the newCur position
	# Note that we may have more to complete. We sometimes deliberatley dont return some valid choices
	# because we want readline to advance the token to want we are returning. That is ok because then
	# next <tab> will show those entries again. This works b/c of the way readline does not show new
	# suggestions in the same pass that it advances the token.
	# We always do this stemming ourselves even is cases when we could let readline do it so that our
	# comment feature can know when it needs to supress them so that readline will advance. Also, in
	# cases where cmdWordBreakCorrection is not empty, readline would show the suggestions relative to
	# the wrong partial token
	if [ "$newCur" != "$cur" ]; then
		local theWord="${newCur}"
		__bgbc_translateTokenToWRTBash theWord
		COMPREPLY=("$theWord")
		return
	fi

	# from this point on, we know that we are not advancing the cursor/token so everything in the
	# COMPREPLY will just be shown to the user and needs not to make readline change the cmd line.

	# record the count now before we add any non-suggestion, informational entries
	local remainingSuggestionsCount="${#COMPREPLY[@]}"

	# comment feature
	# if in the end, we have multiple entries, we are not advancing the token so its safe to add the comments
	# for the user to see
	COMPREPLY=("${comments[@]/#/$commentsSortPrefix}" "${COMPREPLY[@]}")

	# mode toggle commands. If cur is empty add the @<mode> suggestions, if not, add @
	# if [ ! "$curBehindCusor" ]; then
	# 	COMPREPLY+=(${_bgbcData[lastModesEnabled]/#/@})
	# else
	# 	COMPREPLY+=("@")
	# fi


	# help system feature
	# if ? is right behind the cursor and its not matching a suggestion, invoke help
	if [ ${remainingSuggestionsCount:-0} -eq 0 ] && [ "${COMP_LINE:$COMP_POINT-1:1}" == "?" ]; then
		COMPREPLY=(
			">" "<see_man_bg-overviewBashCompletion>"
		)
	fi

	# The case where we are advancing the cursor/token already returned above.
	# So now we have to stop readline/bash from doing any automatic cursor advancement on a common
	# prefix because it will get it wrong.
	# If there is a common prefix, we add '>' so that there won't be
	local -A firstLetters=()
	for j in "${!COMPREPLY[@]}"; do
		firstLetters[${COMPREPLY[$j]:0:1}]="1"
	done
	if [ ${#firstLetters[@]} -eq 1 ]; then
		COMPREPLY+=(">")
	fi
}


# This sed script puts one token per line, recognizing that $(<directive>) is one token
# even if it contains whitespace
_bgSedTokenizingScript='
	:start
	# insert line feeds before and after the $(<directive>) but if not found, start the next cycle (T)
	s/[$][(][^)]*[)]/\n&\n/g;   t processFoundDirective

	# lines without matches get tokens separated to lines
	s/[ \t]\+/\n/g

	b end
	:processFoundDirective

	# isolate the first line, process it, print it, and remove it
	h;  s/\n.*$//;  s/[ \t]\+/\n/g;  s/^\n\|\n$//g;  p; g;  s/^[^\n]*\n//

	# isolate the next line, replace IFS characters, print it, remove it; leave last line in pattern buffer
	h;  s/\n.*$//;  s/[ \t]\+/%20/g;  p; s/.*//; x; s/^[^\n]*\n//

	# there might be another $(<directive>) in the remainder so jump back to the start
	t start; b start

	:end
	s/\n\n/\n/; s/^\n\|\n$//g
	/^[ \t]*$/d
'

# usage: __bgbc_trace ...
# this is similar to the bgtrace* family of functions but BC functions should not source all the bg-core
# functions into the user's envirnoment so a similar, stripped down version is included so that the
# _bgbc-complete-viaCmdDelegation function can trace its activities.
# This will only write to the default /tmp/bgtrace.out destination and only if it already exists.
# Use 'bg-debugCntr trace on' to create that file and monitor BC activity with 'tail -f /tmp/bgtrace.out'
function __bgbc_trace()
{
	declare -gA _bgbcData
	[ "$1" == "-v" ] && { shift; [ "${_bgbcData[tracingDetail]}" != "verbose" ] && return; }

	local timerFlag; [ "$1" == "--timer" ] && { timerFlag="--timer"; shift; }
	if type -t _bgtrace &>/dev/null; then
		_bgBCTracefile="$(_bgtrace --getDestination)"
	fi

	if [ ! "$_bgBCTracefile" ] && [ -w "/tmp/bgtrace.out" ]; then
		_bgBCTracefile="/tmp/bgtrace.out"
	fi

	_bgBCTracefile="${_bgBCTracefile:-"/dev/null"}"

	local msg="$*"
	if [ "$timerFlag" ] && type -t bgtimerPrint &>/dev/null; then
		msg=$(bgtimerPrint $msg)
	fi

	echo -e "$msg" >> $_bgBCTracefile
}

# usage: __bgbc_traceVars ...
function __bgbc_traceVars()
{
	declare -gA _bgbcData
	[ "$1" == "-v" ] && { shift; [ "${_bgbcData[tracingDetail]}" != "verbose" ] && return; }
	type -t bgtraceVars &>/dev/null && bgtraceVars "$@"
}

# usage: complete -F _bgbc-complete-traceCompletion bcTest
# This is a helper utility to see the raw input that a script is provided for BC in the bgtrace output
# Its illustrates how special characters are handled by bash and by the bash_completion project's
# _get_comp_words_by_ref -n ",=:" function.
# To use, create an (empty) file called bcTest
#     $ source /usr/lib/bg_core.sh   # so that the script has access to bctraceVars
#     $ source bg-debugCntr trace on:  # send trace output to /tmp/bgtrace.out (tail -f /tmp/bgtrace.out in another term)
#     $ touch bcTest
#     $ chmod a+x bcTest
#     $ complete -F _bgbc-complete-traceCompletion ./bcTest
#     $ ./bcTest <tab><tab>
# See Also:
#    _bgbc-complete-traceCompletionWithTOKEN
function _bgbc-complete-traceCompletion()
{
	local _bgBCTracefile
	# CRITICALTODO: see below
	# SECURITY: consider if we should protect users on production machines from sourcing bg_core in dev mode
	[ "$(type -t bgtraceVars)" != "function" ] && source /usr/lib/bg_core.sh
	! bgtraceIsActive && bgtraceTurnOn on:
	__bgbc_traceVars "" "" -l"### Tab Press $RANDOM ######################################"

	# do the standard processing of the COMP data
	local cur prev cword words=()
	_get_comp_words_by_ref -n ",:=" cur prev cword words

	local cmdTokens=() cmdPos=0
	__bgbc_parseCOMPLINE

	local remainingCompVars v; for v in ${!COMP*}; do
		[[ ! "$v" =~ ^(COMP_WORDBREAKS|COMP_WORDS|COMP_CWORD|COMP_LINE|COMP_POINT|COMPIZ_CONFIG_PROFILE)$ ]] && remainingCompVars+=" $v "
	done
	__bgbc_traceVars -1 -l"??? " $remainingCompVars;

	__bgbc_trace "COMP_WORDBREAKS='${COMP_WORDBREAKS//$'\n'/'\n'}'"

	local ruler="012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"
	local blank="                                                                                          "
	__bgbc_trace "           ${cmdPoints}  <- ${cmdPointsAry[*]}"
	__bgbc_trace "           ${ruler:0:${COMP_POINT}}^${ruler: ${COMP_POINT}+1 : ${#COMP_LINE}-${COMP_POINT}}"
	__bgbc_trace "COMP_LINE='$COMP_LINE'"
	__bgbc_trace "           ${blank:0:${COMP_POINT}}^ <-COMP_POINT='$COMP_POINT'"
	local cwordLine; printf -v cwordLine "           %*s%s <- COMP_CWORD" "$((COMP_POINT))" "" "$COMP_CWORD"; __bgbc_trace "$cwordLine"
	local cwordLine; printf -v cwordLine "           %*s%s <- cword" "$((COMP_POINT))" "" "$cword"; __bgbc_trace "$cwordLine"
	local cwordLine; printf -v cwordLine "           %*s%s <- cmdPos" "$((COMP_POINT))" "" "$cmdPos"; __bgbc_trace "$cwordLine"
	__bgbc_trace "          '$COMP_LINE'"

	local line="COMP_WORDS=";
	for ((i=0; i<${#COMP_WORDS[@]}; i++)); do
		printf -v line "%s[%s]'%s' " "$line" "$i" "${COMP_WORDS[$i]}"
	done
	__bgbc_trace "$line"

	local line="words     =";
	for ((i=0; i<${#words[@]}; i++)); do
		printf -v line "%s[%s]'%s' " "$line" "$i" "${words[$i]}"
	done
	__bgbc_trace "$line"

	local line="cmdTokens =";
	for ((i=0; i<${#cmdTokens[@]}; i++)); do
		printf -v line "%s[%s]'%s' " "$line" "$i" "${cmdTokens[$i]}"
	done
	__bgbc_trace "$line"

	__bgbc_traceVars -1 prev cur
	__bgbc_traceVars -1 cmdPrev cmdCur
}

# usage: complete -F _bgbc-complete-traceCompletionWithTOKEN bcTest
# This is a helper utility to see the behaior of Bash in terms of what it considers the current token
# being editted during BC.
# it is the same as _bgbc-complete-traceCompletion but it also sets the COMPREPLY with exactly one entry "${bgTraceBCToken:-TOKEN}"
# Set bgTraceBCToken if you want to test something other than 'TOKEN'
# Setting COMPREPLY to a single entry will cause bash to unconditionally replace the current section
# being completed with TOKEN so that you can see the extent of what bash will replace. In terms that
# contain :,= it is not obvious what will be replaced especially when the cursor is in the middle of
# a word. The current value of COMP_WORDBREAKS will effect the results
# See Also:
#    _bgbc-complete-traceCompletion
#    COMP_WORDBREAKS
function _bgbc-complete-traceCompletionWithTOKEN()
{
	_bgbc-complete-traceCompletion
	COMPREPLY=("TOKEN")
	#COMPREPLY=("one:two")
}



function __bgbc_parseCOMPLINE()
{
	# init the output vars. The calling scope should declare these local
	cmd=""
	cmdTokens=()
	cmdTokensWOEsc=()
	cmdPos=0
	cmdPrev=""
	cmdCur=""
	curBehindCusor=""
	curWhole=""
	curWRTBash=""
	curFixedBase=""

	# these two are just for debugging info
	cmdPoints=""
	cmdPointsAry=()

	local subjValue="$COMP_LINE"
	local subjPoint=0
	local tokenLeadSpace=""
	local tokenValue=""
	local tokenValueWOEsc=""
	while [ "$subjValue" ]; do
		__bgbc_parseCOMPLINE_ConsumeOneToken
		if [ ${cmdPos} -eq 0 ]; then
			# cursor is in the whitespace between two tokens
			if (( COMP_POINT < subjPoint+${#tokenLeadSpace}  )); then
				cmdPos="${#cmdTokens[@]}"
				cmdPrev="${cmdTokens[@]: -1}"
				cmdTokens+=("")
				cmdTokensWOEsc+=("")

			# cursor is in this token
			elif (( COMP_POINT <= subjPoint + ${#tokenLeadSpace} + ${#tokenValue}  )); then
				cmdPrev="${cmdTokens[@]: -1}"
				cmdCur="${tokenValue:0:$((COMP_POINT - subjPoint -${#tokenLeadSpace} ))}"
				curBehindCusor="$cmdCur"
				curWhole="${tokenValue}"
				cmdPos="${#cmdTokens[@]}"
			fi
		fi

		# maintain these for debugging output
		cmdPointsAry+=("|" "$((subjPoint+${#tokenLeadSpace}))"  "$((subjPoint + ${#tokenLeadSpace} + ${#tokenValue}))")
		local posLabel="-"; ((${#cmdTokens[@]}<10)) && posLabel="${#cmdTokens[@]}"
		cmdPoints+="${tokenLeadSpace//?/_}${tokenValue//?/$posLabel}"

		# now add it
		cmdTokens+=("$tokenValue")
		cmdTokensWOEsc+=("$tokenValueWOEsc")
		((subjPoint+=(${#tokenLeadSpace} + ${#tokenValue})))
	done

	cmd=${cmdTokens[0]}
	curWRTBash="${curBehindCusor##*[$COMP_WORDBREAKS]}"
	__bgbc_setLogicalCur "$cmdCur"
}

# usage __bgbc_setLogicalCur <newCur>
# cmdWordBreakCorrection is how we implement multipart token completions and also how we correct for
# the difference between two interpretations of COMP_WORDBREAKS chars.
# Correcting For Bash's mistake:
#    Bash completion (incorrectly) thinks that characters like :=, split the term into multiple BC positional tokens.
#    Everyone else thinks that commands have whitespace delimited arguments acording to bash word splitting.
#    BC authors that use this function can always work in the world of the tokens corresponding to the
#    $1 $2 .. tokens that the cmd will see. In addition, they can specify that within a token, they want
#    the user to complete one part at a time where the parts are delimited in arbitrary places.
#    But when we return a COMPREPLY that has only one entry so that BASH will replace the current token
#    with that entry, Bash's notion of what to replace will be different from our notion of what to replace
#    if the existing part of the token contains a character listed in COMP_WORDBREAKS.
#    bash will replace only the last subset of the positional token from behind the users cursor back
#    to the previous COMP_WORDBREAKS character. The $cmdWordBreakCorrection modification be different depending
#    on whether the token has any COMP_WORDBREAKS characters.
# Implementing Our Multi-part Token Completion.
#    cmdWordBreakCorrection also is part if our multi-part completion mechanism that is triggered by the
#    $(cur:<suffixToComplete>) directive. The command tells us what suffix of the current token is
#    being completed. The suggestions will only be relative to it and when we replace the current
#    token with new text, we will only replace that suffix.
# Examples:
#    # ex. where ':' is in COMP_WORDBREAKS but ',' is not but $cmd is treating , as a breakChar
#    disk:/var/foo.img,fixed <- curWhole    <- this is the real $n token that the $cmd will see
#                       ^ <- COMP_POINT (cursor position)
#    disk:/var/foo.img,f  <- curBehindCusor <- this is the part of $n behind the cursor that can be replaced
#                      f  <- cur            <- this is the logical suffix being completed, specified by $cmd
#         /var/foo.img,f  <- curWRTBash     <- this is what Bash considers as the token being completed
#         /var/foo.img,   <- cmdWordBreakCorrection
#    # ex. where '=' is in COMP_WORDBREAKS but $cmd is not treating is special.
#    code=somethig <- curWhole   <- this is the real $n token that the $cmd will see
#            ^ <- COMP_POINT (cursor position)
#    code=som  <- curBehindCusor <- this is the part of $n behind the cursor that can be replaced
#    code=som  <- cur            <- this is the logical suffix being completed, specified by $cmd
#         som  <- curWRTBash     <- this is what Bash considers as the token being completed
#    code=     <- cmdWordBreakCorrection
function __bgbc_setLogicalCur()
{
	cur="$1"
	curFixedBase="${curBehindCusor%$cur}"
	if [ ${#cur} -gt ${#curWRTBash} ]; then
		# subtract the correction. <cmd> passed us full suggestions but bash won't interpret it that way
		# b/c cur contains a character in COMP_WORDBREAKS so its going to treat it as relative to that
		cmdWordBreakCorrection="${cur%$curWRTBash}"
		__bgbc_trace "set new cur to '$cur' cmdWordBreakCorrection is now '+$cmdWordBreakCorrection'"
	elif [ ${#cur} -lt ${#curWRTBash} ]; then
		# add the correction. <cmd> passed us relative suggestions but bash won't interpret it that way
		# b/c it does not align with a character in COMP_WORDBREAKS
		cmdWordBreakCorrection="${curWRTBash%$cur}"
		__bgbc_trace "set new cur to '$cur' cmdWordBreakCorrection is now '-$cmdWordBreakCorrection'"
	else
		cmdWordBreakCorrection=""
		__bgbc_trace "set new cur to '$cur' cmdWordBreakCorrection is now off"
	fi
}

# usage: __bgbc_translateTokenToWRTBash <varname>
# see __bgbc_setLogicalCur
function __bgbc_translateTokenToWRTBash()
{
	if [ ${#cur} -gt ${#curWRTBash} ]; then
		printf -v "$1" "%s" "${!1/#$cmdWordBreakCorrection}"
	elif [ ${#cur} -lt ${#curWRTBash} ]; then
		printf -v "$1" "%s" "${!1/#/$cmdWordBreakCorrection}"
	fi
}

# each time this gets called it does this:
#    tokenLeadSpace : is filled in with any run of leading whitespace that is at the start of subjValue
#    tokenValue     : is filled in with the next bash grammar token
#    subjValue      : tokenLeadSpace and tokenValue are removed from the front
# See Also:
#    stringConsumeNextBashToken : which is the original source for this function. We copied and made
#        it specific to this library so that we dont have to source that library into the user's environment
function __bgbc_parseCOMPLINE_ConsumeOneToken()
{
	local metaChars=$'|&;()<> \t'
	local metaCharsPlusSpecial="${metaChars}'"$'\n"'
	local breakChars="${metaCharsPlusSpecial}"

	tokenValue=""
	tokenValueWOEsc=""
	local inQuote first="1" needsToContinue
	while [ "$subjValue" ] && { [ "$first" ] || [ "$inQuote" ] || [ "$needsToContinue" ]; }; do
		[[ "${subjValue}" =~ ^([ $'\t']*)([^$breakChars]*)([$breakChars]|$) ]]
		local rematch=("${BASH_REMATCH[@]}")
		#bgtraceVars -1 subjValue first inQuote needsToContinue +1 rematch
		local m0_all="${rematch[0]}"
		local m1_leadSp="${rematch[1]}"
		local m2_data="${rematch[2]}"
		local m3_breackCh="${rematch[3]}"
		[[ "$m3_breackCh" =~ [[:space:]] ]] && [ "$m2_data" == "" ] && { m1_leadSp+="$m3_breackCh"; m3_breackCh=""; }

		# only the first lead space can
		if [ "$first" ]; then
			first=""
			tokenLeadSpace="${m1_leadSp}"
		fi

		# set preceedingBackslash if the character previous to breakCh is an odd number of \
		local lookbackSlashCount=0; while [ "${m2_data: -$((lookbackSlashCount+1)):1}" == "\\" ]; do (( lookbackSlashCount++ ));  done
		local preceedingBackslash=""; (( lookbackSlashCount%2 == 1 )) && preceedingBackslash="preceedingBackslash"

		needsToContinue="" # clear this each loop
		case ${inQuote:-notInQuote}:${preceedingBackslash}:${m3_breackCh:-EOS} in
			## handle double quotes
			# note that this case excludes the case of preceedingBackslash
			notInQuote::\")  # start double
				inQuote='"';   breakChars=$'"\n' # now only match on the ending " or EOS any \n to see if it was escaped
				tokenValue+="${m2_data}${m3_breackCh}"
				tokenValueWOEsc+="${m2_data}"
				subjValue="${subjValue#"${m0_all}"}"
				[ ! "${subjValue}" ] && { returnCode=4; }
				;;
				# note that this case excludes the case of preceedingBackslash
			\"::\")          # end double
				inQuote='';    breakChars="${metaCharsPlusSpecial}"
				tokenValue+="${m1_leadSp}${m2_data}${m3_breackCh}"
				tokenValueWOEsc+="${m1_leadSp}${m2_data}"
				subjValue="${subjValue#"${m0_all}"}"
				[[ ! "${subjValue}" =~ ^([$metaChars]|$)  ]] && { needsToContinue="1"; }
				;;
			\":preceedingBackslash:EOS) # unmatched double with a \ at the end
				tokenValue+="${m1_leadSp}${m2_data}"
				tokenValueWOEsc+="${m1_leadSp}${m2_data%\\}"
				subjValue="${subjValue#"${m0_all}"}"
				returnCode=4
				;;
			\"::EOS)        # unmatched double
				tokenValue+="${m1_leadSp}${m2_data}"$'\n'
				tokenValueWOEsc+="${m1_leadSp}${m2_data}"$'\n'
				subjValue="${subjValue#"${m0_all}"}"
				returnCode=4
				;;

			## handle single quotes
			notInQuote::\')  # start single
				inQuote="'";   breakChars="'" # now only match on the ending ' or EOS
				tokenValue+="${m2_data}${m3_breackCh}"
				tokenValueWOEsc+="${m2_data}"
				subjValue="${subjValue#"${m0_all}"}"
				[ ! "${subjValue}" ] && { returnCode=3; }
				;;
			# note that since \ is not special inside single quote, this case matches the :preceedingBackslash term
			\':*:\')         # end single
				inQuote='';    breakChars="${metaCharsPlusSpecial}"
				tokenValue+="${m1_leadSp}${m2_data}${m3_breackCh}"
				tokenValueWOEsc+="${m1_leadSp}${m2_data}"
				subjValue="${subjValue#"${m0_all}"}"
				[[ ! "${subjValue}" =~ ^([$metaChars]|$)  ]] && { needsToContinue="1"; }
				;;
			# note that since \ is not special inside single quote, this case matches the :preceedingBackslash term
			\':*:EOS)        # unmatched single
				tokenValue+="${m1_leadSp}${m2_data}"$'\n'
				tokenValueWOEsc+="${m1_leadSp}${m2_data}"$'\n'
				subjValue="${subjValue#"${m0_all}"}"
				returnCode=3
				;;


			## handle breakChars preceeded by a \

			# \ at EOS is line continuation but we do not have the next \n to remove so return 2 to caller.
			# this supports line oriented callers to know that they should just continue with the next line.
			# note that open quotes at EOS take precedence over this and are handled above
			*:preceedingBackslash:EOS)
				# Note that unlike stringConsumeNextBashToken, we do not remove escape sequences.
				# this function is just about determining the token/whitespace boundries
				tokenValue+="${m2_data}"
				tokenValueWOEsc+="${m2_data%\\}"
				subjValue="${subjValue#"${m0_all}"}"
				returnCode=2
				;;

			# \ before \n is the continuation charater to join the next line. remove the \\n and continue
			*:preceedingBackslash:\n)
				# Note that unlike stringConsumeNextBashToken, we do not remove escape sequences.
				# this function is just about determining the token/whitespace boundries
				# \ + \n is still special in that the \n is still considered whitespace but it just signifies
				# that COMP_LINE is continuing onto the next line. Inside a single quote \n is data
				tokenValue+="${m2_data}"
				tokenValueWOEsc+="${m2_data%\\}"
				subjValue="${subjValue#"${m0_all}"}"
				[[ ! "${subjValue}" =~ ^([$metaChars]|$)  ]] && { needsToContinue="1"; }
				;;

			# remove the \ and continue. The effect is that breakChar was not special and it is added
			# in the token as any other data character.
			# Note: the single quote case above handles \ in single quote which are not specail
			*:preceedingBackslash:*)
				# Note that unlike stringConsumeNextBashToken, we do not remove escape sequences.
				# this function is just about determining the token/whitespace boundries
				tokenValue+="${m2_data}${m3_breackCh}"
				tokenValueWOEsc+="${m2_data%\\}${m3_breackCh}"
				subjValue="${subjValue#"${m0_all}"}"
				[ ! "${subjValue}" ] && { returnCode=0; }
				[[ ! "${subjValue}" =~ ^([$metaChars]|$)  ]] && { needsToContinue="1"; }
				;;

			## 'normal' case
			# note: if the metaCharacter was the first character in subjValue we consume and return it
			# as the next token. otherwise the metaCharacter is left at the start of the subjValue
			notInQuote:*:*)
				tokenValue+="${m2_data:-${m3_breackCh}}"
				tokenValueWOEsc+="${m2_data:-${m3_breackCh}}"
				subjValue="${subjValue#"${m1_leadSp}${m2_data:-${m3_breackCh}}"}"
				returnCode=0
				;;
			*) assertLogicError ;;
		esac
	done
}


# usage: __bgbc_arrayToString <arrayVarName>
# This is the __bgbcc_ version of the bg_core*.sh function
# See Also:
#    arrayToString
#    arrayFromString
function __bgbc_arrayToString()
{
	local results="$(declare -p "$1" 2>/dev/null)"
	results="${results#*\(}"
	echo "${results%\)*}"
}

# usage: __bgbc_varToggleRef <variableRef> <value1> <value2>
# This is the __bgbcc_ version of the bg_core*.sh function
# See Also:
#     varToggleRef : bg_core*.sh function
function __bgbc_varToggleRef()
{
	local vtr_variableRef="$1"
	local vtr_value1="$2"
	local vtr_value2="$3"
	if [ "${!vtr_variableRef}" != "$vtr_value1" ]; then
		printf -v "$vtr_variableRef" "%s" "$vtr_value1"
	else
		printf -v "$vtr_variableRef" "%s" "$vtr_value2"
	fi
}
