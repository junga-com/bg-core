#!/bin/bash


# Library bg_string.sh
####################################################################################################################
### String Parsing Functions
# Summary:
#   stringSplit           : assigns a named variable list or array to sections of the input str separated by a delimiter
#                           This is a thin wrapper over read -r <name1> <name2> ... <<<"$inputStr". Either can be used.
#                           arguably, splitString has better semantics (the scripts is easier to read)
#                           This is convenient to assign variable names to a fixed number of delimeted fields
#   stringConsumeNext     : consumes a passed in string to tokenize one part at a time
#                           Two uses:
#                              1) parse a string with changing delimeters. Consume up to the first expected word or character
#                                 then consume up to the next delimeter expected after the first.
#                              2) while stringConsumeNext ...; do ...
#                                 without the -t option, this quarantees that the loop will execute n+1 times
#                                 where n is the number of times the delimeter appears. The returned token will be
#                                 empty when delimeters appear back to back or at the front or back of the input.
#   parseOneBashToken     : consumes tokens taking into account quoted whitespace similar to how bash would
#                           This is similar to stringConsumeNext but it handles bash quoted whitespace without using eval
#                           This is less efficient than other techniques but sometimes you need to do it this way for security
#   stringConsumeNextBashToken : being replaced by stringConsumeNext. it has more options and we should add those options to
#                           stringConsumeNext over time and replace this one.
#   stringParseURL        : parse a URL string with optional protocol and other components -- host, user, path
#   stringEscapeForEval   : (wrapper for printf -q) add quote chars so that bash eval will interpret the string as only data.
#   arrayToString()   (core function)
#   arrayFromString() (core function)
#   arrayCopy()       (core function)


# usage: stringSplit [-d delimChar] [-t] [-a] <inputStr> <varName1> [ ... <varNameN> ]
# assigns sections of the input str separated by a delimiter to a list of named variables or array elements
# This is a thin wrapper over IFS="$delimChar" read -r <name1> <name2> ... <<<"$inputStr".
# arguably, splitString has better semantics than the read syntax which makes scripts easier to read.
# It also works in Ubuntu 12.04 which the read ysntax does not.
# Added features over read <varlist> <<<"$inputStr""
#  * if not enough variables are specified, the extra tokens in the input string are ignored instead
#    of being concatenated into the last var.
#  * if any <varName> is the empty string "", that position is ignored
#  * -t can be used to trim each returned part
# Options:
#    -d <delimChar> : single char to use to split the string
#    -t             : trim flag. remove whitespace from ends of returned tokens
#    -a <aryVarName>: assign each token to array elements of <aryVarName> starting at 0. ignore any <varNameN>
# See Also:
#    comment at top of bg_strings.sh
#    stringSplit       : use to split a string when the parts are delimeted with the same, single char
#    stringConsumeNext : use to split a string when the parts are delimeted with different tokens
#                        i.e. the delimeter needs to be a string and can be different for each part
#    stringConsumeNextBashToken : use when the string can contain quoted tokens. This is much less
#                        efficient than stringConsumeNext
#    stringParseURL    : dedicated stringSplit for URL parts
function splitString() { stringSplit "$@"; }
function stringSplit()
{
	local delim="$IFS" trimFlag="" arrayFlag ssVarNames__

	# the string 's' might start with a '-' so we can not use getopts or assume that ^- is an option
	while [[ "$1" =~ ^((-t)|(-a.*)|(-d.{0,1})|(-td.{0,1})|--)$ ]]; do case $1 in
		-t)   trimFlag="1" ;;
		-d)   delim=$2; shift ;;
		-d*)  delim=${1#-d} ;;
		-td)  delim=$2; shift; trimFlag="1" ;;
		-td*) delim=${1#-td}; trimFlag="1" ;;
		-a)   arrayFlag="-a"; ssVarNames__="$2"; shift ;;
		-a*)  arrayFlag="-a"; ssVarNames__="${1#-a}" ;;
		--)   shift; break ;;
	esac; shift; done

	local ssSubj__="$1"; [ $# -gt 0 ] && shift

	# make a list of names, replacing any empty names "" with ssThrowAwayGJFHJIIE__ so that it eats a spot
	local ssThrowAwayGJFHJIIE__
	while [ $# -gt 0 ]; do
		ssVarNames__="$ssVarNames__ ${1:-ssThrowAwayGJFHJIIE__}"
		shift
	done

	if lsbBashVersionAtLeast 4.0.0; then
		IFS="$delim" read -r $arrayFlag $ssVarNames__ ssThrowAwayGJFHJIIE__ <<< "$ssSubj__"
	else
		## !!! wierd ubuntu 12.04 bug. related to < <(cmd...) coprocs and IFS="<d>" cmd ... In some cases, the IFS is ignored.
		local IFSSave="$IFS"
		IFS="$delim"
		local -a ssParts__
		read -r -a ssParts__ <<< "$ssSubj__"
		IFS="$IFSSave"

		if [ "$arrayFlag" ]; then
			eval $ssVarNames__='("${ssParts__[@]}")'
		else
			local ssCount__=0
			local ssVarName__; for ssVarName__ in $ssVarNames__; do
				printf -v "$ssVarName__" "%s"  "${ssParts__[$((ssCount__++))]}"
			done
		fi
	fi

	if [ "$trimFlag" ]; then
		local vname__
		for vname__ in $ssVarNames__; do
			read $vname__ <<< "${!vname__}"
		done
	fi
}


# usage: stringConsumeNext <tokenVar> <inputStrVar> [<delim>]
# This consumes a string by removing one token at a time. <tokenVar> <inputStrVar> are the names of valiables in the caller's
# scope. As the string is consumed, <inputStrVar> gets smaller <tokenVar> is overwritten with the next part.
# If the <delim> is not found, the entire value of <inputStrVar> is consumed and set into <tokenVar>.
# It is quaranteed that if the return value is true(0) something was consumed so that it can be used as a while condition
# without risk of an infinite loop.
#
# Note: that the order of <tokenVar> <inputStrVar> is meant to mimic an assignment statement.
#
# Normally, the <delim> string is consumed and discarded on each call. <tokenVar> will contain the text up to but not including
# the <delim>.
#
# The -t|--returnDelimeter option changes the behavior so that each call consumes and returns either non-empty text that preceeds
# <delim> (or the whole string if <delim> is not found) or <delim> itself if <delim> is at the start of the string.
# If its called with the same <delim> each time, it will alternate between returning the text between delimiters and the
# delimeters.
#
# When parsing a string, its common to change the delimiter as you go.
# Example:
#     local str="one%two%three" token
#     while stringConsumeNext token str "%"; do
#        echo "token='$token'"
#     done
#
#     local str="one:two=three four <> " token
#     stringConsumeNext token str ":"    # 'one'
#     stringConsumeNext token str "="    # 'two'
#     stringConsumeNext token str "four" # 'three '
# Params:
#    <inputStrVar> : remove one token from the front of this string variable (passed as the variable name)
#    <tokenVar>    : place the removed token into this string variable (passed as the variable name)
#    <delim>       : the character or str to identify where the token ends.
# Options:
#    -t|--returnDelimeter : return the <delim> as a token. If delim is not the first position, the
#          text up to the delim or EOS is returned. If delim is the first position in the string, it
#          is returned as the token.
#          <delim> and so on.
# Exit Codes:
#    0 (success) : something was consumed <tokenVar> has been set with a new value and <inputStrVar> is shorter.
#    1 (failed)  : the <inputStrVar> was empty at the start of the call so nothing could be consumed
#    2 (failed)  : the <delim> was passed in empty so the matched token is the empty string and nothing
#                  nothing was consumed from <inputStrVar>. This is an non-zero to make infinite loops less likely
# See Also:
#    comment at top of bg_strings.sh
#    stringSplit       : use to split a string when the parts are delimeted with the same, single char
#    stringConsumeNext : use to split a string when the parts are delimeted with different tokens
#                        i.e. the delimeter needs to be a string and can be different for each part
#    stringConsumeNextBashToken : use when the string can contain quoted tokens. This is much less
#                        efficient than stringConsumeNext
#    stringParseURL    : dedicated stringSplit for URL parts
function stringConsumeNext()
{
	local retDelimFlag
	while [ $# -gt 0 ]; do case $1 in
		-t|--returnDelimeter) retDelimFlag="-t" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local scop_tokenVar="$1"
	local scop_inputStrVar="$2"
	local scop_delim="${3:-/}"

	# these two constructs allow of to treat the input params as read/write reference valiables.
	# Note: printf -v<varName> ... writes its output into <varName> like an assignment
	# ${!varName} -- the ! means return the value of the variable whose name is contained in varName

	# empty string on input -- nothing left to consume
	if [ ! "${!scop_inputStrVar}" ]; then
		printf -v "$scop_tokenVar" "%s" ""
		return 1

	# user passed in an empty delim which matches the empty string at the front so won't consume anything
	elif [ ! "$scop_delim" ]; then
		printf -v "$scop_tokenVar" "%s" ""
		return 2

	# main algorithm:
	else
		# get the token part. it will never include the delim. it will be empty if delim was at the start of input
		printf -v "$scop_tokenVar"    "%s" "${!scop_inputStrVar%%${scop_delim}*}"

		# in retDelimFlag mode, when the delim was at the start, we need to manually stuff it in the token
		# we need to do it now so that all the returned token content will be subtracted from the front of the input
		# in retDelimFlag mode, its true that the input string is only ever consumed by removing what we returned
		[ "$retDelimFlag" ] && [ ! "${!scop_tokenVar}" ] && printf -v "$scop_tokenVar" "%s" "${scop_delim}"

		# now consume the new token off the front of our input. It can only be empty in !retDelimFlag mode and in
		# that mode, we will consume the delimiter in the last step.
		printf -v "$scop_inputStrVar" "%s" "${!scop_inputStrVar#${!scop_tokenVar}}"

		# if not in retDelimFlag mode, we need to consume the delimiter we just used to delimit the
		# token we removed and throw it away
		[ ! "$retDelimFlag" ] && printf -v "$scop_inputStrVar" "%s" "${!scop_inputStrVar#${scop_delim}}"
	fi
	return 0
}



# usage: stringConsumeNextAny <tokenVar> <matchedDelimVar> <inputStrVar> <tokenRe> <delimRE>
# like stringConsumeNext except it takes two regex to define the token and delim.
# Each successful call will consume both a token and delimeter from the input string. The match criteria
# is "^($tokenRE)($delimRE)". Either tokenRE or delimRE may match the empty string but if both do it
# will return a failure return code because nothing was consumed.
# Options:
#    --doQuotes          : treat single and double quotes as escaping the characters inbeteen so that
#                          they will not match the delimRE.
# Exit Codes:
#    0 (success) : something was consumed, <tokenVar> and <matchedDelimVar> have been set and <inputStrVar> is shorter.
#    1 (failed)  : the <inputStrVar> was empty at the start of the call so nothing could be consumed
#    2 (failed)  : the <delimRE> passed in is empty so the matched token is the empty string and nothing
#                  nothing was consumed from <inputStrVar>. This is an non-zero to make infinite loops less likely
#    3 (failed)  : <delimRE> did not match anything in the inputStr
function stringConsumeNextAny()
{
	local doQuotes ignoreWS
	while [ $# -gt 0 ]; do case $1 in
		--doQuotes) doQuotes="--doQuotes" ;;
			--ignoreWS) ignoreWS="[[:space:]]*" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local scop_tokenVar="$1"; shift
	local scop_matchedDelimVar="$1"; shift
	local scop_inputStrVar="$1"; shift
	local scop_tokenRE="$1"; shift
	local scop_delimRE="$1"; shift
	[ $# -eq 0 ] || assertError -VleftOver:"$*" "too many parameters passed"

	[ "$doQuotes" ] && assertError "--doQuotes option is not yet implemented"

	# empty string on input -- nothing left to consume
	if [ ! "${!scop_inputStrVar}" ]; then
		printf -v "$scop_tokenVar"        "%s" ""
		printf -v "$scop_matchedDelimVar" "%s" ""
		return 1
	fi

	### regex match
	if [[ ! "${!scop_inputStrVar}" =~ ^($ignoreWS)($scop_tokenRE)($ignoreWS)($scop_delimRE)($ignoreWS) ]]; then
		printf -v "$scop_tokenVar"        "%s" ""
		printf -v "$scop_matchedDelimVar" "%s" ""
		return 3
	fi
	local rematch=("${BASH_REMATCH[@]}")

	# return the results
	printf -v "$scop_tokenVar"        "%s" "${rematch[2]}"
	printf -v "$scop_matchedDelimVar" "%s" "${rematch[4]}"
	printf -v "$scop_inputStrVar"     "%s" "${!scop_inputStrVar#${rematch[0]}}"
	return 0
}



# usage: stringConsumeNextBashToken strVarName tokenVarName
# this parses the str input as BASH grammer and returns the first token in tokenVarName and removes it
# from strVarName. See
#
# SECURITY: parseOneBashToken is a security sensitive function. We rely on this function to parse
#     callback code strings so that we can ensure that we are executing a single function or external
#     command whose name we can filter based on security policy. Using "eval $cmd" allows "myCmd p1; ls"
#     where ls can be arbitrary commands.
# Options:
#   -q : keep quotes. normally single and double quotes are removed from the returned token but this
#        causes them to remain.
#   (not active)-r : reverse. consume the token from the end of the string instead of from the start
#   --cont 2|3|4 : continue parsing with context init to notIQuote(2) or inside a single(3) or double(4) quote
#        if a line oriented parser is using this function, it may encounter a quote that starts
#        on line and ends on another line. We will ruturn 3 or 4 on the line that started the quote
#        and the parser should continue reading lines and calling us with the --cont option  to indicate
#        that the new subj string is starting in a quote.
#        Also, the input lines might include a continuation char (\) at the end of line and we retunr 2
# Return codes:
#    0 : a token was removed from strVarName and assigned to tokenVarName
#    1 : no token was set because strVarName was already empty. this is the normal loop termination
#    2 : error: the last character was a \ indicating that there should be a continued line
#    3 : error: unmatched single quote. reached end on input without finding a closing '
#        the results up to EOS are returned in tokenVarName
#    4 : error: unmatched double quote. reached end on input without finding a closing "
#        the results up to EOS are returned in tokenVarName
# See Also:
#    comment at top of bg_strings.sh
#    stringSplit       : use to split a string when the parts are delimeted with the same, single char
#    stringConsumeNext : use to split a string when the parts are delimeted with different tokens
#                        i.e. the delimeter needs to be a string and can be different for each part
#    stringConsumeNextBashToken : use when the string can contain quoted tokens. This is much less
#                        efficient than stringConsumeNext
#    stringParseURL    : dedicated stringSplit for URL parts
#    __bgbc_parseCOMPLINE_ConsumeOneToken : this is a forked copy of stringConsumeNextBashToken for
#            use in bash completion which does not source this library
function parseOneBashToken() { stringConsumeNextBashToken "$@"; }
function stringConsumeNextBashToken()
{
	local metaChars=$'|&;()<> \t'
	local metaCharsPlusSpecial="${metaChars}'"$'\n"'
	local breakChars="${metaCharsPlusSpecial}"
	local inQuote done keepQuotes reverseFlag
	local returnCode=1 # this will be the code if subjValue is empty unless --cont changes it
	while [[ "$1" =~ ^- ]]; do case $1 in
		# template %set directive uses --cont when a previous call to us returned 2,3,4 to indicate that
		# it should read the next line and continue the statement.
		--cont) case $2 in
				2) : ;; # line continuation -- nothing special for us but for consistency of the caller we allow this
				3) inQuote="'";   breakChars="'";      returnCode=3 ;;
				4) inQuote='"';   breakChars=$'"\n';   returnCode=4 ;;
				*) assertError "unknown continuation (--cont $2)"
			esac
			shift
			;;
		-q) keepQuotes="" ;;
		-r) reverseFlag="-r" ;;
	esac; shift; done
	local subjVarName="$1"
	local tokenVarName="$2"

	local subjValue="${!subjVarName}"
	local tokenValue=""

	# if we are called with an empty subject return an error code which is 1, 3, or 4 based on the --cont option
	if [ ! "$subjValue" ]; then
		setReturnValue "$tokenVarName" "$tokenValue"
		return $returnCode
	fi

	# all the cases below should set the returnCode so if we try to return 99 we can assertLogicError
	returnCode=99

	# this will only loop if it encounters a single or double quoted string.
	# each regex match gets a token followed by a breakChar or the end of string (EOS)
	# breakChars is the set of breakChar to match. When not in a quote, it is all the BASH metaCharacters
	# plus the single and double quote chars and \n. While in a quote, we set breakChars to just the
	# corresponding quote character and \n so that the metaCharacters will be ignored while in the quote.
	# $ (EOS) is always matched so we will consume up to the EOS no matter what
	#bgtraceVars "" ""
	while [ "$subjValue" ] && [ ! "$done" ]; do
		# this regex will always match so either [1](the token) or [2](a metachar) or both will be non-empty
		[[ "${subjValue}" =~ ^([ $'\t']*)([^$breakChars]*)([$breakChars]|$) ]]
		local rematch=("${BASH_REMATCH[@]}")
		#bgtraceVars subjValue rematch
		local m0_all="${rematch[0]}"
		local m1_leadSp="${rematch[1]}"
		local m2_data="${rematch[2]}"
		local m3_breackCh="${rematch[3]}"

		# set preceedingBackslash if the character previous to breakCh is an odd number of \
		local lookbackSlashCount=0; while [ "${m2_data: -$((lookbackSlashCount+1)):1}" == "\\" ]; do (( lookbackSlashCount++ ));  done
		local preceedingBackslash=""; (( lookbackSlashCount%2 == 1 )) && preceedingBackslash="preceedingBackslash"

		case ${inQuote:-notInQuote}:${preceedingBackslash}:${m3_breackCh:-EOS} in
			## handle double quotes
			notInQuote::\")  # start double
				inQuote='"';   breakChars=$'"\n' # now only match on the ending " or EOS any \n to see if it was escaped
				tokenValue+="${m2_data}${keepQuotes:+${m3_breackCh}}"
				subjValue="${subjValue#"${m0_all}"}"
				[ ! "${subjValue}" ] && { returnCode=4; done=1; }
				;;
			\"::\")          # end double
				inQuote='';    breakChars="${metaCharsPlusSpecial}"
				tokenValue+="${m1_leadSp}${m2_data}${keepQuotes:+${m3_breackCh}}"
				subjValue="${subjValue#"${m0_all}"}"
				[[ "${subjValue}" =~ ^([$metaChars]|$)  ]] && { returnCode=0; done=1; }
				;;
			\":preceedingBackslash:EOS) # unmatched double with a \ at the end
				tokenValue+="${m1_leadSp}${m2_data%\\}"
				subjValue="${subjValue#"${m0_all}"}"
				returnCode=4; done="1"
				;;
			\"::EOS)        # unmatched double
				tokenValue+="${m1_leadSp}${m2_data}"$'\n'
				subjValue="${subjValue#"${m0_all}"}"
				returnCode=4; done="1"
				;;

			## handle single quotes
			notInQuote::\')  # start single
				inQuote="'";   breakChars="'" # now only match on the ending ' or EOS
				tokenValue+="${m2_data}${keepQuotes:+${m3_breackCh}}"
				subjValue="${subjValue#"${m0_all}"}"
				[ ! "${subjValue}" ] && { returnCode=3; done=1; }
				;;
			# note that since \ is not special inside single quote, this case matches the :preceedingBackslash term
			\':*:\')         # end single
				inQuote='';    breakChars="${metaCharsPlusSpecial}"
				tokenValue+="${m1_leadSp}${m2_data}${keepQuotes:+${m3_breackCh}}"
				subjValue="${subjValue#"${m0_all}"}"
				[[ "${subjValue}" =~ ^([$metaChars]|$)  ]] && { returnCode=0; done=1; }
				;;
			# note that since \ is not special inside single quote, this case matches the :preceedingBackslash term
			\':*:EOS)        # unmatched single
				tokenValue+="${m1_leadSp}${m2_data}"$'\n'
				subjValue="${subjValue#"${m0_all}"}"
				returnCode=3
				;;


			## handle breakChars preceeded by a \

			# \ at EOS is line continuation but we do not have the next \n to remove so return 2 to caller.
			# this supports line oriented callers to know that they should just continue with the next line.
			# note that open quotes at EOS take precedence over this and are handled above
			*:preceedingBackslash:EOS)
				# baskslash is removed from the output
				tokenValue+="${m2_data%\\}"
				subjValue="${subjValue#"${m0_all}"}"
				returnCode=2; done="1"
				;;

			# \ before \n is the continuation charater to join the next line. remove the \\n and continue
			*:preceedingBackslash:\n)
				# baskslash and \n are removed from the output
				tokenValue+="${m2_data%\\}"
				subjValue="${subjValue#"${m0_all}"}"
				;;

			# remove the \ and continue. The effect is that breakChar was not special and it left in
			# the token as any other data character.
			# Note: the single quote case above handles \ in single quote which are not specail
			*:preceedingBackslash:*)
				# baskslash is removed from the output but m3_breackCh is added to output
				tokenValue+="${m2_data%\\}${m3_breackCh}"
				subjValue="${subjValue#"${m0_all}"}"
				[ ! "${subjValue}" ] && { returnCode=0; done=1; }
				;;

			## 'normal' case
			# note: if the metaCharacter was the first character in subjValue we consume and return it
			# as the next token. otherwise the metaCharacter is left at the start of the subjValue
			notInQuote:*:*)
				tokenValue+="${m2_data:-${m3_breackCh}}"
				subjValue="${subjValue#"${m1_leadSp}${m2_data:-${m3_breackCh}}"}"
				returnCode=0; done="1"
				;;
			*) assertLogicError ;;
		esac
	done

	setReturnValue "$subjVarName"  "$subjValue"
	setReturnValue "$tokenVarName" "$tokenValue"
	[ "$returnCode" == "99" ] && assertError -V case:"${inQuote:-notInQuote}:${preceedingBackslash}:${m3_breackCh:-EOS}" "logic error -- some case did not set the returnCode"
	return $returnCode
}

# OBSOLETE: use stringConsumeNext instead (only used by stringParseURL)
# usage: parseOneStringPart [-i] stringVarName delimiter tokenVarName
# Params:
#    'stringVarName' ref var with the string to parse. will be modified.
#    'delimiter'     string that separates the token. multiple chars match exactly (not a char set)
#    'tokenVarName'  ref var that will receive the parsed token removed from the front of the string.
# Return values:
#    'stringVarName' has token and delimiter removed from front. or empty if delim not found
#    'tokenVarName'  will contain what ever is removed from string minus the delimiter.
#    exit code is success(0) if stringVarName is non-empty when passed in and failure(1) if it is empty.
#    This facilitates calling this function in a while loop.
# Options:
#    -d don't consume delimiter. causes delimiter left in the string
#    -i case insensitive. causes delimiter to be matched without regard to case.
#    -t trim token. causes token to be trimmed of whitespace front and back.
#    -g greedy flag. makes it consume up to the last ocurrence of the delim instead of the first
# Description:
#    This function removes the first part of the var string passed in, up to
#    but not including the first occurrence of the delimiter string and
#    returns that to the caller in the variable whose name is 'tokenVarName'.
#    The strng passed in is modified to remove that part and the delimiter.
#
#    stringVarName and tokenVarName are non-const (ie. writable) parameters. this is implemented
#    by passing in the name of the variable instead of the value of the variable. In practice this
#    means that when you call this function, you leave off the leading "$" of these variables.
#    It also means that this function should not be called in a sub process with ( )
#
#    If delimiter is " ", all strings of whitespace are counted as one delimiter and leading
#    and trailing whitespace is ignored. However, this does not take into account quoting of
#    whitespace so parseOneBashToken does this type of parsing better.
#
#    -c (dontConsumeLast) if delimiter is not present, take nothing
#
#    Example:
#    line="bob, sue, barbara, eddy"
#    while parseOneStringPart line "," mytoken; do
#         echo "part='$mytoken'"    # part='bob'   (first iteration)
#         echo "line='$line'"         # line=' sue, barbara, eddy'   (first iteration)
#    done
# See Also:
#    stringConsumeNext
function parseOneStringPart()
{
	local saveEG=$(shopt  -p nocasematch); shopt -q -u nocasematch
	local trimFlag=""
	local leaveDelim=""
	local insensitive=""
	local dontConsumeLast=""
	local greedyFlag=""
	local OPTIND
	while getopts  "ditcg" flag; do
		case $flag in
			d) leaveDelim="1"  ;;
			i) insensitive="-i"; shopt -q -s nocasematch  ;;
			t) trimFlag="1"  ;;
			c) dontConsumeLast="1" ;;
			g) greedyFlag="-g" ;;
		esac
	done
	shift $((OPTIND-1)); unset OPTIND

	# we use __ in the working var names because we want to minimize the chance of hiding the global vars
	local subjVarName="$1"
	local subj__="${!subjVarName}"
	local delim="${2:- }"
	local tokenVarName="$3"
	local token__

	# if the delim is " " treat it like white space
	# this removes leading whitespace and it reduces the next string of whitespace to one space
	if [ "$delim" == " " ] && [ ! "$greedyFlag" ]; then
		subj__="$(echo "$subj__" | tr "\n\t" "  " | sed -e 's/^ *//; s/ *$//; s/  */ /g')"
	fi

	# if an empty subject was passed in (after reducing whitespace if needed), we return false(1) so that
	# the standard loop pattern works. i.e. if we can not return a token for processing we return false
	if [ "$subj__" == "" ]; then
		eval $tokenVarName=\"\" || assertError -v subjVarName -v delim -v tokenVarName "eval assignment error"
		return 1
	fi

	# if there is no occurrence of delim, chop off the whole string. otherwise split on the delim
	# note that we already set or unset the the nocaseglob shopt to make this case sensitive or insensitive
	if ! [[ "${subj__}" =~ ${delim} ]]; then
		if [ "$dontConsumeLast" ]; then
			token__=""
		else
			token__="$subj__"
		fi
	else
		local lowToken
		if [ "$insensitive" ]; then
			local tmpSub="${subj__,,}"
			local tmpDelim="${delim,,}"
		else
			local tmpSub="$subj__"
			local tmpDelim="$delim"
		fi

		case $greedyFlag:${#delim} in
			:*)   lowToken="${tmpSub%%$tmpDelim*}" ;;
			-g:*) lowToken="${tmpSub%$tmpDelim*}" ;;
		esac
		token__="${subj__:0:${#lowToken}}"
	fi

	# consume the token and optionally the delim from the input string
	subj__="${subj__:${#token__}}"
	[ ! "$leaveDelim" ] && [ ${#token__} -gt 0 ] && subj__="${subj__:${#delim}}"

	[ "$trimFlag" ] && token__="$(trimString "$token__")"

	# return the variables
	eval $tokenVarName=\$token__
	eval $subjVarName=\$subj__

	eval $saveEG
	return 0
}

# usage: stringParseURL [-p defaultProtocol] "url" protocolVarName userVarName passwordVarName hostVarName portVarName resourceVarName parametersVarName
# parses the statndard URL format with extensions for non standard, slightly different protocols. The -p option allows specifying that the string
# complies with a certain protocols's format even if the string leaves out the explicit protocol part.
# TODO: make this function invoke helper functions by protocol to do the actual parsing so that you can extend it by definng a new protocol helper
#       function
# See Also:
#    comment at top of bg_strings.sh
#    stringSplit       : use to split a string when the parts are delimeted with the same, single char
#    stringConsumeNext : use to split a string when the parts are delimeted with different tokens
#                        i.e. the delimeter needs to be a string and can be different for each part
#    stringConsumeNextBashToken : use when the string can contain quoted tokens. This is much less
#                        efficient than stringConsumeNext
#    stringParseURL    : dedicated stringSplit for URL parts
function parseURL() { stringParseURL "$@"; }
function stringParseURL()
{
	local defProtocol=""
	local hostDelimeter=""
	local hostDelimeterIsGenerous=""
	while [[ "$1" =~ ^- ]]; do
		case $1 in
			-p)  shift; defProtocol="$1" ;;
			-p*) defProtocol="${1#-p}" ;;
		esac
		shift
	done

	local url="$1"
	local protocolVarName="$2"
	local userVarName="$3"
	local passwordVarName="$4"
	local hostVarName="$5"
	local portVarName="$6"
	local resourceVarName="$7"
	local parametersVarName="$8"
	local __protocol="" __user="" __password="" __host="" __port="" __resource="" __parameters=""

	local parseURL="$url"
	if [[ "$parseURL" =~ :// ]]; then
		parseOneStringPart parseURL "://" __protocol
	else
		__protocol="$defProtocol"
	fi

	local hostToken
	case $__protocol in
		sshfs*|smb*|nfs*)
			parseOneStringPart -c -g parseURL ":" hostToken
			;;
		ssh*)
			parseOneStringPart -g parseURL ":" hostToken
			;;
		file*) hostToken="localhost" ;;
		*)
			parseOneStringPart parseURL "/" hostToken
			;;
	esac

	parseOneStringPart parseURL "\?" __resource
	parseOneStringPart parseURL " " __parameters

	if [[ "$hostToken" =~ [@] ]]; then
		local userToken
		parseOneStringPart hostToken "@" userToken
		parseOneStringPart userToken ":" __user
		__password="$userToken"
	fi

	local primaryHostPort
	parseOneStringPart hostToken "," primaryHostPort
	splitString -d : "$primaryHostPort" __host __port

	[ "$protocolVarName" ]   && eval $protocolVarName=\"$__protocol\"
	[ "$userVarName" ]       && eval $userVarName=\"$__user\"
	[ "$passwordVarName" ]   && eval $passwordVarName=\"$__password\"
	[ "$hostVarName" ]       && eval $hostVarName=\"$__host\"
	[ "$portVarName" ]       && eval $portVarName=\"$__port\"
	[ "$resourceVarName" ]   && eval $resourceVarName=\"$__resource\"
	[ "$parametersVarName" ] && eval $parametersVarName=\"$__parameters\"
}

# usage: stringEscapeForEval <stringVar>
# this prepares data so that it will stay the same if passed through eval.
# Also, eval will not recognize special characters like ; to break out of data and into code space
function stringEscapeForEval()
{
	local stringVar="$1"
	printf -v $stringVar "%q" "$*"
}

# usage: stringEscapeForRegex <stringVar>
# this prepares data so that it will be interpretted in a regex string as data.
# put another way, it escapes the special regex characters
function stringEscapeForRegex()
{
	local stringVar="$1"
	for sefr_ch in '[' '{' '|' '+' '(' ')' '*' '.' '?' '<' '$'; do
		printf -v $stringVar "%s" "${!stringVar//[$sefr_ch]/[$sefr_ch]}"
	done
	printf -v $stringVar "%s" "${!stringVar//^/[^]}"
	printf -v $stringVar "%s" "${!stringVar//\\/\\\\}"
}











#MAN(5)
####################################################################################################################
### String Manipulation Functions
# Summary:
# stringInsert   : insert one string into another at an index position
# stringJoin     : assemble a bash argument list (like "$@" or "${myArray[@]}") into a single string where the elements
#                  are separated by an arbitrary delimiter. Will not add superfulous delimiters -- never at front nor back.
#


# usage: stringInsert <strVar> <pos> <toInsert>
# insert <toInsert> into <strVar> at <pos>
function stringInsert()
{
	local strVar="$1"
	local pos="$2"
	local toInsert="$3"
	local strValue="${!strVar}"
	printf -v "$strVar" "%s%s%s" "${strValue:0:$pos}" "$toInsert" "${strValue:$pos}"
}


# usage: stringJoin [-R <resultStrVar>] [-d <separator>] [-e] [-a] <element1> [ ... <elementN> ]
# joins the elements together into one string using <separator> to delimit them.
# avoids leading and trailing <separator>
# Params:
#     <element> : a string. each element will be separated by <separator>
# Options:
#     -R <resultStrVar> : (R)eturn the result in this variable name instead of stdout
#     -v <resultStrVar> : alias for -R to be similar to printf -v
#     -d <separator> : (aka delimiter). a string that will appear between each <element> in the result
#                       The default for separator is ","
#     -e  : do not allow empty elements in the results which would result in multiple <separators> in a row
#     -a  : append to the value in <resultStrVar> instead of replacing it. has no effect if -R is not specified
# See Also:
#   arrayJoin
#   arrayAdd
#   varSetRef -- this man page lists all similar functions
function stringJoin()
{
	local sj_resultValue resultStrVar="sj_resultValue" separator="," allowEmptyElements="1" appendMode
	while [ $# -gt 0 ]; do case $1 in
		-v*) bgOptionGetOpt val: resultStrVar "$@" && shift; assertNotEmpty resultStrVar ;;
		-R*) bgOptionGetOpt val: resultStrVar "$@" && shift; assertNotEmpty resultStrVar ;;
		-d*) bgOptionGetOpt val: separator "$@" && shift ;;
		-e)  allowEmptyElements="" ;;
		-a)  appendMode="-a" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	separator="${separator//\\n/$'\n'}"

	# initialize the result to empty string unless we are appending
	[ ! "$appendMode" ] && printf -v $resultStrVar "%s" ""

	if [ "$allowEmptyElements" ]; then
		local firstElement="${!resultStrVar}"
		if [ ! "$appendMode" ] || [ ! "$firstElement" ]; then
			firstElement="$1"
			[ $# -gt 0 ] && shift
		fi

		# the ${@/#/$separator} term adds the separator to the start (#) of every element
		if [ "$firstElement" ] || [ $# -gt 0 ]; then
			printf -v "$resultStrVar" "%s" "$firstElement${@/#/$separator}" || assertError
		fi
	else
		local tmpSep=""; [ "${!resultStrVar}" ] && tmpSep="$separator"
		while [ $# -gt 0 ]; do
			if [ "$1" != "" ]; then
				printf -v $resultStrVar "%s%s%s" "${!resultStrVar}" "${tmpSep}" "${1}"
				tmpSep="$separator"
			fi
			shift
		done
	fi

	[ "$resultStrVar" == "sj_resultValue" ] && echo "$sj_resultValue"
}















#MAN(5)
####################################################################################################################
### Array Manipulation Functions
# Summary:
# arrayCopy       : (core function) copy one bash array to another
# arrayReverse    : reverse the order of a -a numeric array#
# arrayTranspose  : swap the index and values of an associative array
# arrayToString   : (wrapper for declare -p) returns a string that can later be used to create a new array with the same contents.
# arrayJoin       : join either the indexes or values of an array into a delimited string list
# arrayAdd        : add an element to an -a array when you have the array var name ref

#function arrayCopy() moved to bg_libCore.sh

# usage: arrayReverse <arrayVar>
# reverse the order of a -a numeric array
function arrayReverse()
{
	local arrayVar="$1"; assertNotEmpty arrayVar

	# this function still support ubuntu 12.04 which does not have the -n ref
	eval '
		local -a tmp=()
		for (( i = ${#'$arrayVar'[@]}-1; i >= 0; i-- )); do
			tmp+=("${'$arrayVar'[$i]}")
		done
		'$arrayVar'=("${tmp[@]}")
	'
}

# usage: arrayTranspose [-d<delimChar>] <inputArrayVar> <ouputArrayVar>
# The output Array will be filled in with the the transposition if the input array
# The transposition swaps the index and values.
# If the input contains data with no repeated values, then each input element will correspond to
# one output element.
# If the multiple inputArray elements have the same value, they will produce one element in the outputArray
# whose value is a string list separated by <delim> containing each index value.
# So that the transitive property will be preservered, any inputArray value that contains the <delim> character
# will be split and produce a separate outputArray element for each string list value
function arrayTranspose()
{
	local delimChar="," overwriteDestFlag
	while [ $# -gt 0 ]; do case $1 in
		-d*) bgOptionGetOpt val: delimChar "$@" && shift ;;
		-o) overwriteDestFlag="1" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local _at_InputArrayVar="$1"; assertNotEmpty _at_InputArrayVar
	local _at_OuputArrayVar="$2"; assertNotEmpty _at_OuputArrayVar

	# this function still supports ubuntu 12.04 which does not have the -n ref
	eval '
		[ "'$overwriteDestFlag'" ] && '$_at_OuputArrayVar'=()
		local index; for index in "${!'$_at_InputArrayVar'[@]}"; do
			local value="${'$_at_InputArrayVar'[$index]}"
			local valueList; IFS="$delimChar" read -a valueList <<<"$value"
			for value in "${valueList[@]}"; do
				stringJoin -d "$delimChar" -e -a -R '$_at_OuputArrayVar'[$value] "$index"
			done
		done
	'
}

#function arrayToString() moved to bg_libCore.sh
#function arrayFromString() moved to bg_libCore.sh

# usage: arrayJoin [-i] [-d<delimStr>] <arrayVarName> <retVar>
# join the elements of <arrayVarName> into a string with <delimStr> separating each element value
# Params:
#    <arrayVarName> : the name of an array variable
#    <retVar>       : the name of a string variable that will be filled in with the results.
#                      if <retVar> is empty, the results are echo'd to stdout
# Options:
#    -d <delimStr>  : use <delimStr> in between each element
#    -i             : join the index of each element instead of the values
# See Also:
#    stringJoin
function arrayJoin()
{
	local delimStr="," indexFlag retValue
	while [ $# -gt 0 ]; do case $1 in
		-d*) bgOptionGetOpt val: delimStr "$@" && shift ;;
		-i)  indexFlag="!" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local arrayVarName="${1//[^a-zA-Z0-9_]}"; assertNotEmpty arrayVarName
	local retVar="${2:-retValue}"

	# only the first char of IFS is used as a separator. If delimStr is multiple chars, we use the bell char
	# as the IFS separator and then after, search and replace it
	local delimChar="${delimStr:0:1}"
	[ ${#delimStr} -gt 1 ] && delimChar=$'\a'

	if lsbBashVersionAtLeast 4.0.0; then
		IFS="$delimChar" eval $retVar='"${'${indexFlag}${arrayVarName}'[*]}"'
	else
		local IFSSave="$IFS"
		IFS="$delimChar"
		eval $retVar='"${'${indexFlag}${arrayVarName}'[*]}"'
		IFS="$IFSSave"
	fi

	[ ${#delimStr} -gt 1 ] && eval $retVar='"${'$retVar'//$delimChar/$delimStr}"'

	[ "$retVar" == "retValue" ] && 	echo "${retValue}"
}

# usage: arrayAdd <arrayVarName> <element>
# add <element> to the array variable named by <arrayVarName>
# This allows <arrayVarName>+=("<element>") when <arrayVarName> is a variable name instead of a reference
# When local -n support can be assumed (ubunutu 14.04 and beyond) it could be used as an alternative.
# Params:
#    <arrayVarName> : name of a variable to add <element> to
#    <element>      : the value (not the name of a variable) to add
# See Also:
#   varSetRef -- this man page lists all similar functions
function arrayAdd()
{
	eval "$1"'+=("'"$2"'")'
}



#MAN(5)
####################################################################################################################
### Attributes Manipulation Functions
# Attributes are a concept of stroing a name/value field data in a string that is a single bash token
# They are used on many command line sysntax.
# See Also:
#    awkData
# Summary:
# splitAttribute     : parse an attribute token into name/value fields
# attributesAddToMap : adds a list of attribute tokens into an associative array (map)

# usage: splitAttribute [-q] [-T] [-t <defType>] <attrToken> <nameVar> <valueVar>
# a common pattern used in bg-lib tools is to represent an attribute as "type:value"
# value may contain spaces and if it does it must be quoted or escaped so that together,
# the term will be one bash token.
#
# Either type or value can be empty. e.g. "type:"  or  ":value"
# If there is no : separator, the whole token is taken as the value and the type is not specified.
# If the type is not specified the default type will be set if provided.
# If the type is unknown at the end of the function it will either return a non-zero exit code or assertError
#
# Options:
#    -t <defType> : if the attribute token does not contain a type it will use this value
#    -q : normally if the type is unknown, it will assert an error. With -q it will be quiet and continue
#         by using "return 1" instead of "assertError"
#    -T : trim. trim whitespace from ends of type and value
function splitAttribute()
{
	local defType="" quietMode=""
	while [ $# -gt 0 ]; do case $1 in
		-t*) bgOptionGetOpt val: defType "$@" && shift ;;
		-q) quietMode="-q" ;;
		-T) trimFlag="-T" ;;
		--) shift; break ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local attrToken="$1"
	local typeVar="$2"
	local valueVar="$3"

	local typeValue="$defType"
	[[ "$attrToken" =~ .: ]] && typeValue="${attrToken%%:*}"

	local valueValue="${attrToken#*:}"

	if [ "$trimFlag" ]; then
		while [ "${typeValue:0:1}" == " " ]; do typeValue="${typeValue:1}"; done
		while [ "${typeValue: -1}" == " " ]; do typeValue="${typeValue:0:-1}"; done
		while [ "${valueValue:0:1}" == " " ]; do valueValue="${valueValue:1}"; done
		while [ "${valueValue: -1}" == " " ]; do valueValue="${valueValue:0:-1}"; done
	fi

	[ "$typeVar" ]  && eval $typeVar="\$typeValue"
	[ "$valueVar" ] && eval $valueVar="\$valueValue"

	if [ "$typeValue" == "" ]; then
		[ "$quietMode" ] && return 1 || assertError "ambiguous type for attribute '$attrToken'"
	fi
	return 0
}




# usage: attributesAddToMap [-t <defType>] <attribMapVar> <attrTermList...>
# This accepts the name of a map of attributes and parses and adds each attribTerm to it
# Params:
#    attribMapVar  : the name of a map (associative array) to add the attributes into.
#    attrTermList  : list of attribute terms like "attrType1:value1 attrType2:value2 ... attrTypeN:valueN"
# Options:
#    -t <defType>  : if a term in the list omits the attrType1: prefix this will be used as that value's type
#                    if -t is not specified, the type will be "--" which is the bg-lib escaped version of ""
#    -m            : allow multiple occurrences of the same type. normally if attrType is already in the map
#                    the function fails with an error message.
function attributesAddToMap()
{
	local defType="" quietMode=""
	while [ $# -gt 0 ]; do case $1 in
		-t*) bgOptionGetOpt val: defType "$@" && shift ;;
		-m) allowMultiplesFlag="-m" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local attribMapVar="$1"; [ $# -gt 0 ] && shift

	local defaultEncounted=""
	while [ $# -gt 0 ]; do
		local attrTerm="$1"; shift

		local attrType="${defType:---}"
		[[ "$attrTerm" =~ .: ]] && attrType="${attrTerm%%:*}"

		local attrValue="${attrTerm#*:}"

		if [ ! "$allowMultiplesFlag" ]; then
			local thisElemExpr="$attribMapVar[$attrType]"
			[ "${!thisElemExpr}" ] && assertError "duplicate attribute type encountered in list (${attrType/--/<defaultType>}):${!thisElemExpr}"
		fi

		eval $attribMapVar[$attrType]=\$attrValue
	done
}

# attributesMapToList : converts a bash associative array (map) to a string of space separated attribute terms
# usage: attributesMapToList [-t <defType>] <attribMapVar>
# converts a bash associative array (map) to a string of space separated attribute terms
function attributesMapToList()
{
	local defType="" quietMode=""
	while [ $# -gt 0 ]; do case $1 in
		-t*) bgOptionGetOpt val: defType "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local attribMapVar="$1"; [ $# -gt 0 ] && shift
	local -a attribMapKeys='(${!'"$attribMapVar"'[@]})'

	local result defValue
	local attribType; for attribType in "${attribMapKeys[@]}"; do
		local aryElementName="$attribMapVar[$attribType]"
		local attrValue="${!aryElementName}"
		if [ "$attribType" == "$defType" ]; then
			defValue="$attrValue"
		else
			result="$result${result:+ }$attribType:$attrValue"
		fi
	done
	result="$defValue${defValue:+ }$result"
	echo "$result"
}



# usage: parseDebControlFile <attribMapVar> <debControlFileText> [ .. <debControlFileTextN>]
# Debian defines a format for name value pair information in a simple text file. It is used for various information in packages.
# This parses one or more controlFile text strings passed in and sets the elements of the associative array that is passed in
# A single attribute pair like name:value is a a valid controlFile text. Accepting multiple controlFile text strings give the
# caller the option to pass in the individual attributes one per parameter.
# Params:
#     <attribMapVar>    : the name of the associative array in the caller's scope that will be filled in
#     <debControlFileText> : a string that would be a valid debian controlFile.
#              as an extension, line can contain leading tabs (but not spaces). This allows writing inline control file data
#              in a multi line string that is indented with the script instead of starting in the first column
#              After tab removal Lines begin with either a letter or a space
#                 (letter) -- "<name>:<value>"
#                 (space)  -- " <valueContinued>"
function parseDebControlFile()
{
	local attribMapVar="$1"; [ $# -gt 0 ] && shift; assertNotEmpty attribMapVar
	local line name value
	while [ $# -gt 0 ]; do
		local lastAttrib=""
		while IFS="" read -r line; do
			# as an extension, we remove all leading tabs (but not spaces)
			while [ "${line:0:1}" == $'\t' ]; do line="${line:1}"; done

			# spaces append the current line to the last value.
			if [ "${line:0:1}" == " " ]; then
				[ "$lastAttrib" ] && printf -v $lastAttrib "%s\n%s" "${!lastAttrib}" "${line# }"
			else
				splitAttribute -q -T "$line" lastAttrib value
				if [ "$lastAttrib" ]; then
					lastAttrib="$attribMapVar[$lastAttrib]"
					printf -v $lastAttrib "%s" "$value"
				fi
			fi
		done <<<"$1"
		shift
	done
}

# usage: toDebControlFile <attribMapVar>
# Debian defines a format for name value pair information in a simple text file. It is used for various information in packages.
# This writes the attributes stored in an associative array in the debian controlFile format to stdout
# Params:
#     <attribMapVar>    : the name of the associative array in the caller's scope that contains the attributes
function toDebControlFile()
{
	local attribMapVar="$1"; [ $# -gt 0 ] && shift; assertNotEmpty attribMapVar
	local -a attribMapKeys='(${!'"$attribMapVar"'[@]})'

	local attrib value
	for attrib in "${attribMapKeys[@]}"; do
		local attribElementRef="$attribMapVar[$attrib]"
		value="${!attribElementRef}"
		if [[ ! "$value" =~ $'\n' ]]; then
			echo "$attrib: $value"
		else
			echo "$attrib: $value" | awk 'NR>1 {printf " "}  {print $0}'
		fi
	done
}








####################################################################################################################
### String Formating Functions

# add double quotes if the str contains whitespace. This is used for formatting command lines
function quoteIfNeeded()
{
	if [[ "$1" =~ \  ]]; then
		echo "\"$1\""
	else
		echo "$1"
	fi
}

# usage: stringTrimQuotes [-l|-r] -i <strVar>
# usage: stringTrimQuotes [-l|-r] <str>
# remove one occurrence of either single or double quotes from both ends only if they are on both ends
# Options:
#   -i : inplace. interpret the param as a variable name and modify it directly instead of writting the
#        modified string on stdout
#   -d : double quotes only. only operate on double quotes
#   -s : single quotes only. only operate on single quotes
function stringTrimQuotes()
{
	local inplaceFlag="" doSingles="1" doDoubles="1" retVar
	while [[ "$1" =~ ^- ]]; do case  $1 in
		-i)  inplaceFlag="-i" ;;
		-d)  doSingles="" ;; # doubles only
		-s)  doDoubles="" ;; # singles only
	esac; shift; done
	local s="$1"; [ "$inplaceFlag" ] && s="${!1}"
	[ "$inplaceFlag" ] && retVar="$1"

	if [ "doDoubles" ] && [[ "$s" =~ ^\".*\"$ ]]; then
		s="${s#\"}"
		s="${s%\"}"
	fi
	if [ "doSingles" ] && [[ "$s" =~ ^\'.*\'$ ]]; then
		s="${s#\'}"
		s="${s%\'}"
	fi
	returnValue "$s" "$retVar"
}

# usage: stringTrim -i <strVar>
# usage: s=$(stringTrim <str>)
# remove whitespace from the the ends of <str>
# Options:
#   -i : inplace. interpret the param as a variable name and modify it directly instead of writting the
#        modified string on stdout
#   -b : (default) trim both left and right.
#   -l : left only. only trim the left side
#   -r : right only. only trim the right side
#   -m : middle. in addition to left/right/both, -m will replace runs of interior whitespace with a single space
function trimString() { stringTrim "$@"; }
function stringTrim()
{
	local inplaceFlag _st_strVar doRight="1" doLeft="1" doMiddle
 	while [[ "$1" =~ ^- ]]; do case  $1 in
 		-i)  inplaceFlag="-i" ;;
		-l)  doRight="" ;;
		-r)  doLeft="" ;;
		-m)  doMiddle="1" ;;
 	esac; shift; done
	local _st_strValue="$1"; [ "$inplaceFlag" ] && _st_strValue="${!1}"
	[ "$inplaceFlag" ] && _st_strVar="$1"

	[ "$doLeft" ]   && { [[ "$_st_strValue" =~ ^[[:space:]]*(.*)$ ]] && _st_strValue="${BASH_REMATCH[1]}"; }
	[ "$doRight" ]  && while [[ "$_st_strValue" =~ [[:space:]]$ ]]; do _st_strValue="${_st_strValue:0:-1}"; done
	# TODO: consider using local trailingWS="${_st_strValue##*[^[:space:]]}"; _st_strValue="${_st_strValue%$trailingWS}. tested this in a terminal but dont want to take time to change this function at the momment"

	[ "$doMiddle" ] && while [[ "$_st_strValue" =~ [^[:space:]][[:space:]][[:space:]]|[[:space:]][[:space:]][^[:space:]] ]]; do _st_strValue="${_st_strValue//[[:space:]][[:space:]]/ }"; done

	returnValue "$_st_strValue" "$_st_strVar"
}

# OBSOLETE: use stringTrim -l instead
# usage: s=$(trimStringL "s")
# remove whitespace on left end
function stringTrimL() { trimStringL "$@"; }
function trimStringL()
{
	local s="$1"
	while [[ "$s" =~ ^[[:space:]] ]]; do s="${s:1}"; done
	echo "$s"
	return

	# 2015-06 bg: this method was slow
	#local s="$1"
	#local saveEG=$(shopt  -p extglob); shopt -q -s extglob
	#s="${s##+([[:space:]])}"
	#eval $saveEG
	#echo "$s"
}

# OBSOLETE: use stringTrim -r instead
# usage: s=$(trimStringR "s")
# remove whitespace on right end
function stringTrimR() { trimStringR "$@"; }
function trimStringR()
{
	local s="$1"
	while [[ "$s" =~ [[:space:]]$ ]]; do s="${s:0:-1}"; done
	echo "$s"
	return

	# 2015-06 bg: this method was slow
	#local s="$1"
	#local saveEG=$(shopt  -p extglob); shopt -q -s extglob
	#s="${s%%+([[:space:]])}"
	#eval $saveEG
	#echo "$s"
}

# usage: $(stringNumToHuman numberOfBytes)
#returns numberOfBytes as 3.5 GB, 50 MB, etc...
function numToHuman() { stringNumToHuman "$@"; }
function stringNumToHuman()
{
	local decimalFlag=""
	while getopts  "d" flag; do
		case $flag in
			d) decimalFlag="1"  ;;
		esac
	done
	shift $((OPTIND-1)); unset OPTIND

	echo $1 $decimalFlag | awk '
		{sum=$1; decimalFlag=$2}
		END {
			if (decimalFlag==1) {
				split("B K M G T P",type);
				type[1]=""
			}
			else
				split("B KB MB GB TB PB",type);
			for(i=5;y < 1 ;i--)
				if (decimalFlag==1)
					y = sum / (10^(i*3));
				else
					y = sum / (1000* 2^(10*(i-1)));
			printf " %.1f %s\n", int(y*10+0.5)/10.0,  type[i+2]
		}'
}

# usage: stringShorten [-j <justificationType> ] [-R <retVar>] <length> <string ... >
# shortens the <string> to no more than <length> characters. This is often used to display long strings
# in limitted space. The result will be a string that is no more that <length> chacters and any newlines
# will be converted to space.
# Params:
#   <length> : the number of characters that the <string> will be shortened to
#   <string ...> : <string> is the remainder of the command line ($* after length is shifted out).
# Options"
#   -j <justificationType> : how to remove any extra length.
#         left  : keep the left side. truncate at <length>-1 and make '$' the last character to indicate
#                 that the string was shortened
#         right : keep the right side. make '@' the first character to indicate that the string was
#                 shortened
#         fuzzy : The fuzzy justification attempts to use the bash tokens separation to spread out
#                 the removal so that some meaning can still be gleaned. tokens that have / are assumed
#                 to be paths and the middle path components are removed first
#   -R <retVar>
function strShorten() { stringShorten "$@"; }
function stringShorten()
{
	local _just="left" _retVar
	while [[ "$1" =~ ^- ]]; do case  $1 in
		-j*) bgOptionGetOpt val: _just "$@" && shift ;;
		-R*) bgOptionGetOpt val: _retVar "$@" && shift ;;
	esac; shift; done
	local _length="$1"; [ $# -gt 0 ] && shift
	local _str="${*//$'\n'}"
	stringTrim -i _str

	local reduceCount=$(( ${#_str} - _length ))
	if [ ${reduceCount:-0} -gt 0 ]; then
		case $_just in
			left)  _str="${_str:0:$((_length-1))}$" ;;
			right) _str="@${_str: -$((_length-1))}" ;;

			fuzzy)
				local tokens=("${@//$'\n'/ }")

				# how much reduction would there be from replacing the middle path components with ...
				local reduction=0
				local pathTokenCount=0
				for ((i=0; i<${#tokens[@]}; i++)); do
					local token="${tokens[$i]/#\//$'\a'}"; token="${token/%\//$'\a'}"
					local parts; stringSplit -d "/" -a parts "${token}"
					if [ ${#parts[@]} -gt 2 ]; then
						((pathTokenCount++))
						local middle="${parts[@]:1:${#parts[@]}-2}"
						(( reduction+=(${#middle}-3) ))
					fi
				done

				# if some reduction would be had, do it
				if [ ${pathTokenCount:-0} -gt 0 ] && [ ${reduction:-0} -gt 0 ]; then
					local reductionPercent=$(( reduceCount*100 / reduction +1 ))
					_str=""
					for ((i=0; i<${#tokens[@]}; i++)); do
						local token="${tokens[$i]/#\//$'\a'}"; token="${token/%\//$'\a'}"
						local parts; stringSplit -d "/" -a parts "${token}"
						if [ ${#parts[@]} -gt 2 ]; then
							local elipsedTerm="..."
							local middle; IFS='/' eval 'middle="${parts[@]:1:${#parts[@]}-2}"'
							local keepCount=$(((${#middle}-3) - (${#middle}-3)*reductionPercent/100 ))
							if [ ${keepCount:-0} -gt 0 ]; then
								local left=$((keepCount/2))
								elipsedTerm="${middle:0:$left}...${middle: -$((keepCount-left))}"
							fi
							_str+="${_str:+ }${parts[0]}/$elipsedTerm/${parts[@]: -1}"
							_str="${_str//$'\a'/\/}"
						else
							_str+="${_str:+ }${tokens[$i]}"
						fi
					done
				fi

				# if its still not short enough, do left justification
				[ ${#_str} -gt ${_length} ] && _str="${_str:0:$((_length-1))}$"
				;;
			*) assertError "unknown justification type '$just'"
		esac
	fi

	returnValue "$_str" "$_retVar"
}


# usage: stringRemoveLeadingIndents <msg>
# This formatter removes leading tabs similar to <<-EOS .. so that you can pass in multiline text and still indent it
# with the source code.
function strRemoveLeadingIndents() { stringRemoveLeadingIndents "$@"; }
function stringRemoveLeadingIndents()
{
	local msg="$1"
	type -t awk &>/dev/null && awk '
		BEGIN {
			# start if off larger than it should ever be
			for (i=1;i<100;i++) leadingTabsToRemove+="\t";
			lineStart=1
			lastNonBlank=0
		}
		# if the first line is empty, skip it when we output
		NR==1 && $0~"^$" {lineStart=2}

		{
			data[NR]=$0
			if (NF>0) lastNonBlank=NR
		}
		# not the first line and not a empty line (not all whitespace)
		# reduce the leadingTabsToRemove to fit any line with content
		NR!=1 && $0~"[^[:space:]]" && $0!~"^"leadingTabsToRemove {
			leadingTabsToRemove=$0; sub("[^\t].*$","",leadingTabsToRemove)
		}
		# display the content with undesired whitespace removed
		END {
			for (i=lineStart; i<=lastNonBlank; i++) {
				line=data[i]
				sub("^"leadingTabsToRemove,"",line)
				print line
			}
		}
	' <<< "$msg"
}




####################################################################################################################
###  set functions using words in a string.
# * words can be separated by ',', ':' or whitespace (including newlines)
# * newlines are generally accepted in input sets but are always removed in the output set.
# * words can not include whitespace, ':' or ',' or any character that bash uses to break tokens on the command line
# * words can not be empty. strings of delimiters like ,,, are treated like one delimiter
# * The normallized form of set is words separated by one ' ' and no space at the beginning or end.
# * To pass a set as a parameter to a function or command, use $(strSetEscape "$set") which will make the set
#   separate words with ',' so that the whole set reads as one bash token.
# * iterate a set with "for element in $set; do ...."

# usage: newSet="$(strSetNormalize "set")"
# Replaces all strings of <delimSet> with the prefered delim which is the first character in <delimSet>
# and removes any strings of <delimSet> at the start and end of the set
# This function is the same as strSetEscape except the default <delimSet> is reorded to have the space first
# preserves order (works with ordered sets)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [ ,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetNormalize()
{
	local delims=" ,: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done
	local preferedDelim="${delims:0:1}"

	# we don't want to sort -u so that this works on ordered sets so we use grep -v "^$" to sequences of \n\n
	echo "${1}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | grep -v "^$" | tr "\n" "$preferedDelim" | sed -e 's/ *$//'
}

# usage: newSet="$(strSetEscape "set")"
# Escape is useful to make the entire strSet parse as one bash word even if it is not quoted
# Replaces all strings of <delimSet> with the prefered delim which is the first character in <delimSet>
# and removes any strings of <delimSet> at the start and end of the set
# This function is the same as strSetNormalize except the default <delimSet> is reorded to have the comma first
# preserves order (works with ordered sets)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
#                     If you specify the first character as one that bash break words on, it won't work as "Escape" anymore
function strSetEscape()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done
	local preferedDelim="${delims:0:1}"

	# we don't want to sort -u so that this works on ordered sets so we use grep -v "^$" to sequences of \n\n
	echo "${1}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | grep -v "^$" | tr "\n" "$preferedDelim" | sed -e 's/,$//'
}

# usage: count="$(strSetCount "set")"
# return the number of elements in the set.
# preserves order (works with ordered sets)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetCount()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done

	if [ ! "$1" ]; then
		echo 0
		return
	fi

	# sed converts to one element per line, wc -l counts them
	echo  "${1}" | sed -e 's/^['"$delims"']*//; s/['"$delims"']*$//; s/['"$delims"']['"$delims"']*/\n/g' | wc -l
}


# usage: strSetAdd [-n] [-d <delims>] -S <setVar> <elementsToAdd> [... <elementsToAddN>]
# usage: newSet="$(strSetAdd [-d <delims>] <set> <elementsToAdd> [... <elementsToAddN>])"
# adds an element to the end of the set, but only if its not already in the set
# preserves order (works with ordered sets) if -o is specified or if -n is not specified
# Params:
#   <elementsToAdd> : one or more elements. elements can span multiple parameter positions. parameter positions delimit elements
#               and <delims> inside each param further delimits elemnets
#   <set> : in the second form, the set is passed in as one parameter posistion.
# Options:
#   -S <setVar> : operate on the string var <setVar>. If  -S is not specified, the set value is passed in as "$1" and returned on stdout
#   -d <delims> : <delims> is a set of characters that are all valid element separators. The first is used when joining elements
#   -n : normalize the set. removes dupes and uses the first char in <delims> as the separtor
#   -o : order. preserve the order of the set. This is only needed if -n is specified. otherwise it preseves the order anyway
function strSetAdd()
{
	local delims=" ,:\t\n" _ssa_set setVar="_ssa_set" normFlag preseveOrderFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		-S)  setVar="$2"; shift ;;
		-n)  normFlag="-n" ;;
		-o)  preseveOrderFlag="-o" ;;
		--)  break ;;
	esac; shift; done
	[ "$setVar" == "_ssa_set" ] && _ssa_set="$1" && [ $# -gt 0 ] && shift

	delims="${delims:- \t\n}"
	delims="${delims//\\n/$'\n'}"
	delims="${delims//\\t/$'\t'}"
	local firstDelim="${delims:0:1}"

	local _ssa_toAddArray
	while [ $# -gt 0 ]; do
		local _ssa_toAddArrayTmp; IFS="$delims" read -d "" -r -a _ssa_toAddArrayTmp <<<"$1"
		[ ${#_ssa_toAddArrayTmp[@]} -gt 0 ] && _ssa_toAddArrayTmp[${#_ssa_toAddArrayTmp[@]}-1]="${_ssa_toAddArrayTmp[${#_ssa_toAddArrayTmp[@]}-1]%$'\n'}"
		_ssa_toAddArray+=("${_ssa_toAddArrayTmp[@]}")
		shift
	done

	local sep=""

	# this is the fastest implementation for a common case
	if [ ! "$normFlag" ]; then
		local elToAdd; for elToAdd in "${_ssa_toAddArray[@]}"; do
			if [ "$elToAdd" ] && [[ ! "${firstDelim}${!setVar}${firstDelim}" =~ [$delims]$elToAdd[$delims] ]]; then
				[ "${!setVar}" ] && sep="$firstDelim"
				[ ! "$found" ] && printf -v "$setVar" "%s%s%s"  "${!setVar}" "$sep" "$elToAdd"
			fi
		done


	# if we are going to normalize it anyway, just add it to the end and normalize will take care of dupes
	elif [ "$normFlag" ] && [ ! "$preseveOrderFlag" ]; then
		local -A _ssa_setSet
		local _ssa_setArray; IFS="$delims" read -d "" -r -a _ssa_setArray <<<"${!setVar}"
		[ ${#_ssa_setArray[@]} -gt 0 ] && _ssa_setArray[${#_ssa_setArray[@]}-1]="${_ssa_setArray[${#_ssa_setArray[@]}-1]%$'\n'}"
		local el; for el in "${_ssa_setArray[@]}" "${_ssa_toAddArray[@]}"; do
			[ "$el" ] && _ssa_setSet["$el"]="1"
		done
		arrayJoin -i -d "$firstDelim" _ssa_setSet "$setVar"

	# if we are going to normalize it and preserver order we need to printf the new set as we go
	elif [ "$normFlag" ]; then
		local -A _ssa_setSet
		local _ssa_setArray; IFS="$delims" read -d "" -r -a _ssa_setArray <<<"${!setVar}"
		[ ${#_ssa_setArray[@]} -gt 0 ] && _ssa_setArray[${#_ssa_setArray[@]}-1]="${_ssa_setArray[${#_ssa_setArray[@]}-1]%$'\n'}"
		printf -v "$setVar" "%s"  ""
		local el; for el in "${_ssa_setArray[@]}" "${_ssa_toAddArray[@]}"; do
			if [ "$el" ] && [ ! "${_ssa_setSet["$el"]+exists}" ]; then
				_ssa_setSet["$el"]="1"
				printf -v "$setVar" "%s%s%s"  "${!setVar}" "$sep" "$el"
				sep="$firstDelim"
			fi
		done
	fi

	# if setVar is our local var (not set with -S), write the set to stdout
	[ "$setVar" == "_ssa_set" ] && echo "${!setVar}"
}

# usage: newSet="$(strSetRemove "set" oneElement)"
# removes 'oneElement' from the set. If 'oneElement' does not exist, the set will be returned unchanged
# 'oneElement' can be a regex to remove potentially multiple elements. The regex must match the entire
# element -- i.e. there is an implied ^ $ surrounding the oneElement
# preserves order (works with ordered sets)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetRemove()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done

	# sed converts to one element per line, grep removes, tr converts it back to one line again
	echo "${1}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | grep -v "^$2$" | tr "\n" " " | sed -e 's/ *$//'
}

# usage: newSet="$(strSetFilter "set" filterRegEx)"
# returns a set with only elements from "set" that match filterRegEx. Unlike strSetRemove, the filterRegex
# does not have an implicit anchors -- ^ $
# preserves order (works with ordered sets)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetFilter()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done

	# sed converts to one element per line, grep removes, tr converts it bask to one line again
	echo "${1}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | grep  "$2" | tr "\n" " " | sed -e 's/ *$//'
}

# usage: if strSetIsMember "set" oneElement; then ...
# preserves order (works with ordered sets)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetIsMember()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done

	# the grep -q will set the exit code.
	echo "${1}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | grep -q "^$2$"
}

# usage: strSetGetIndex "set" <element>
# returns the 1 based index of oneElement in the the set. 0 if the specified element is not in the set
# preserves order (works with ordered sets)
function strSetGetIndex()
{
	local set="$1"
	local element="$2"
	local i=1
	for e in $set; do
		if [ "$e" == "$element" ]; then
			echo $i
			return
		fi
		(( i++ ))
	done
	echo 0
}

# usage: strSetExpandRelative <fullSet> <defSet> <relativeSet>
# This facilitates describing a set by specifying how it differs from a default, base set
# The relative set is read left to right and elements that have special meaning are acted upon.
# Special Elements:
#  <firstChar>: if the first non whitespace character of relativeSet is a delimiter [-+,:], then defSet is used
#               as the initial starting point of the result set. If not, the result set starts off empty.
#     'all'   : an element named 'all' is replaced by the entire fullSet
#     -element: an element starting with '-' will remove all instances of that element from the set
#     +element: an element starting with '+' is treated normally -- that element will exist at that position
# Delimiters:
#     '-' and '+' will delimit elements so it is not necessary to also use a : or , or ' ' but it is ok to do so
# Params:
#    <fullSet> : this is the entire set of possible values. The special element 'all' refers to this set.
#        fullSet is generally a fixed set determined during development.
#    <defSet>  : this is the default set. This can be a set of common elements, excluding elements that are less seldom
#        of interest. The user can add back in elements by using +<elementName> in the relateSet or further reduce the
#        set by using -<elementName>. defSet is generally a fixed set determined during development.
#        The defSet can use the same special elements as the relativeSet but it is relative to fullSet. i.e. if defSet
#        begins with a delimiter, the fullSet is prepended to it.
#    <relativeSet> : relativeSet is generally a set that the user can specify at runtime. The user
#        can specify the result set relative to defaultSet (by starting relativeSet with one of [-+,:])
#         or relative to the fullSet by starting relativeSet with "all,...", or relative to the empty
#        set by starting relativeSet with a non-delimiter character and not specifying 'all'
# Examples of RelativeSet:
#     "+"            : use the default set as it is
#     "+foo-bar"     : start with the default set and add 'foo' and remove 'bar'
#     "-mac"         : start with the default set and remove 'name'
#     "-ip+ip"       : removing and re-adding the same element has the effect of moving it to the end of the list
#     "all"          : use all possible elements in the result set
#     "all-mac"      : use all possible elements except 'mac'
#     "name,mac"     : use just "name" and "mac" in the result set
#     "name"         : just "name"
#     ""             : make the result set empty -- no elements
# preserves order (works with ordered sets)
function strSetExpandRelative()
{
	local fullSet="${1//$'\n'/ }"
	local defSet="${2:-:}"
	local relativeSet="${3:-:}"

	# expand the relative properties of defSet->fullSet and relativeSet->defSet
	[[ "$defSet" =~ ^[\ \t]*[-+,:] ]] && defSet="${fullSet} ${defSet}"
	[[ "$relativeSet" =~ ^[\ \t]*[-+,:] ]] && relativeSet="${defSet} ${relativeSet}"

	# expand any ocurances of "all"
	local resultSet=" $(echo "$relativeSet" | sed -e 's/\ball\b/'"$fullSet"'/g') "

	# note that we pad the ends with a space so that we can use spaces to delimit whole words
	# in the search and replace sub functions -- ${resultSet/ $column / }
	set -- $resultSet
	resultSet=" $* "

	# normalize the delimiters. [:,+-] can all be used as delimiters. Of them, only - needs special processing.
	# replace [:,+] with a space and add a space to the front of -. Now the list will be space separated and any element that is
	# to be subtracted will have a leading -.
	resultSet="${resultSet//-/ -}"
	resultSet="${resultSet//[:,+]/ }"

	# iterate the resultSet, removing the negated columns
	local column; for column in $resultSet; do
		if [[ "$column" =~ ^- ]]; then
			# first remove the negated directive
			resultSet="${resultSet/$column / }"
			# then remove the first ocurrence of that column from the resultSet
			resultSet="${resultSet/ ${column#-} / }"
		fi
	done

	# 'set -- .." sets the positional params and we use it to normalize the result so that each element has exactly one space
	# and leading and trailing spaces are removed
	set -- $resultSet
	echo "$@"
}



# usage: strSetExpandRangeNotation <fullSet> <rangeSpec> [<normMapVar>]
# returns a new strSet populated with the elements specified in the <rangeSpec> string which can contain range notation similar to cron specs
# Range Notation:
#     *                            : all elements
#     <element>,<element>...       : comma separated list
#     <leftElement>-<rightElement> : all elements between <leftElement> and <rightElement> inclusive.
#     /<inc>                       : skip every <inc> elements in the range that preceeds it
function strSetExpandRangeNotation()
{
	local fullSet="$1"
	local rangeSpec="$2"
	local normMapVar="$3"

	# if a normalization map was not provided, create one from fullSet. This results in the normaizationensuring that each listed element is
	# in the <fullSet>
	if [ ! "$normMapVar" ]; then
		normMapVar="normMap"
		local -A normMap
		local i; for i in ${fullSet//[:,]/ }; do
			normMap[$i]="$i"
		done
	fi

	local retSet rangeInc normLookup isInRange

	splitString -d"/" "$rangeSpec" rangeSpec rangeInc
	if [ "$rangeSpec" == "*" ]; then
		retSet="$fullSet"
	else
		local term left right i
		for term in ${rangeSpec//,/ }; do
			if [[ "$term" =~ - ]]; then
				local left right
				splitString -d"-" -t "$term" left right
				normLookup="$normMapVar[$left]"  left="${!normLookup}";  assertNotEmpty left  "unknown element in left part of '$term'"
				normLookup="$normMapVar[$right]" right="${!normLookup}"; assertNotEmpty right "unknown element in right part of '$term'"
				isInRange=""
				for i in $fullSet; do
					[ "$i" == "$left" ] && isInRange="1"
					[ "$isInRange" ] && retSet+="${retSet:+ }$i"
					[ "$i" == "$right" ] && isInRange=""
				done
			else
				normLookup="$normMapVar[$term]"  left="${!normLookup}";  assertNotEmpty left  "unknown element '$term'"
				retSet+="${retSet:+ }$left"
			fi
		done
	fi

	if [ ${rangeInc:-1} -gt 1 ]; then
		# if there is a single element in the return set and the inc is greater than 1, we interpret it as an offest to the inc so
		local offset=0
		if [[ ! "$retSet" =~ \  ]]; then
			local fullSetArray=($fullSet)
			for i in "${!fullSetArray[@]}"; do
				[ "$retSet" == "${fullSetArray[$i]}" ] && offset="$i"
			done
			offset=$(( offset % rangeInc ))
			retSet="$fullSet"
		fi

		local retSetArray=($retSet)
		retSet=""
		for ((i=offset; i<${#retSetArray[@]}; i+=$rangeInc)); do
			retSet+="${retSet:+ }${retSetArray[$i]}"
		done
	fi

	echo "$retSet"
}




# usage: newSet="$(strSetSort <set>)"
# reorders the set in default sort order and removes duplicates
# looses orig order from set (dont use with an ordered set)
# Params:
#     <set> : a single string (usually quoted) that contains the elements
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetSort()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done
	# sed converts to one element per line, sort sorts, tr converts it bask to one line again
	echo "${1}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | sort -u | tr "\n" " " | sed -e 's/ *$//'
}

# usage: newSet="$(strSetSubtract <set1> <set2>)"
# make a new set with the elements that belong to set1 but not set2
# looses orig order from set (dont use with an ordered set)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetSubtract()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done

	# comm usage: comm -whichSet  file1 file2
	# -23 outputs only elements unique to file1 (subtract file2 from file1)
	# -13 outputs only elements unique to file2 (subtract file1 from file2)
	# -12 outputs only elements in both file1 and file2 (intersection)
	comm -23 \
		<(echo "${1}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | sort -u) \
		<(echo "${2}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | sort -u) \
		| tr "\n" " " | sed -e 's/ *$//'
}

# usage: newSet="$(strSetUnion "set1" "set2")"
# make a new set with all the elements of both sets and no duplicates
# looses orig order from set (dont use with an ordered set)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetUnion()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done

	# echo combines them (with dupes), sed converts both sets to one element per line, sort -u removes dupes, tr converts it bask to one line again
	echo "${1} ${2}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | sort -u | tr "\n" " " | sed -e 's/ *$//'
}

# usage: newSet="$(strSetIntersection "set1" "set2")"
# make a new set with only elements that appear in both sets
# looses orig order from set (dont use with an ordered set)
# Options:
#     -d <delimSet> : the delimSet  used to break <set> into elements. [,: \t] by defualt.
#                     Note that the first character is the prefered delim
function strSetIntersection()
{
	local delims=",: \t"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d)  delims="$2"; shift ;;
		-d*) delims="${1#-d}" ;;
		--)  break ;;
	esac; shift; done

	# echo combines them (with dupes),
	# sed converts both sets to one element per line
	# sort and uniq -d leaves only lines that appear more that once (they were in both sets)
	# tr converts it bask to one line again
	(
		echo "${1}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | sort -u
		echo "${2}" | sed -e 's/['"$delims"']['"$delims"']*/\n/g' | sort -u
	) | sort | uniq -d | tr "\n" " " | sed -e 's/ *$//'
}






####################################################################################################################
### Path Manipulation Functions

# usage: pathGetCommon <path1> <path2>
# compare the two paths from left to right and return the prefix that is common to both.
# put another way, it returns the folder with the longest path that is a parent of both paths
# Example:
#    p1 = /var/lib/foo/data
#    p2 = /var/lib/bar/five/fee
#   out = /var/lib/
function pathGetCommon()
{
	local p1="$1"
	local p2="$2"
	local t1="" t2="" out="" finished=""

	stringConsumeNext -t t1 p1 "/" || finished="1"
	stringConsumeNext -t t2 p2 "/" || finished="1"

	while [ "$t1" == "$t2" ] && [ ! "$finished" ]; do
		out="${out}${t1}"
		stringConsumeNext -t t1 p1 "/" || finished="1"
		stringConsumeNext -t t2 p2 "/" || finished="1"
	done

	[ "$out" ] && echo "$out"
}


# usage: pathGetCanonStr -e <path>  [<retVar>]
# usage: canoPath="$(pathGetCanonStr "path")"
# return the canonical version of <path> without requiring that any part of it exists.
#
# Note that starting in Ubuntu 16.04, the realpath core gnu util is much more capable including
#       logical/physical symlink mode
# Note that "readlink -f" does something similar but expands any symlinks in the path. It also requires
# that all folders in the path must exist or it returns empty string. This function does not expand
# symlinks so that the logical path names are preserved but does simplify the path to its canonical form
#
# This is a pure string manipulation and does not reference the filesystem tree except for
# the -e option to turn a relative path into a absolute path.
# Often you want the full path relative to the current folder which is what the -e option does
#
# Params:
#    <retVar> : return the result in this variable name. default is to write result to stdout
# Options:
#    -e : use the environment to make a relative path absolute. If the path does not start with /
#         it will be prepended with either $home if it begins with ~ or $PWD. It does not matter
#         if the resulting path exists or not.
# Output:
#    if path is invalid the empty string will be returned and the exit code is 1
#    otherwise the canonical version is returned on stdout and the exit code is 0
#    if -e id specified the returned path will be absolute
#    The second param <retVar> is specified, it will be set with the value. otherwise the value
#    is written to stdout
# What it does:
#    removes any './', '//' sequences
#    removes any trailing /
#    process ../  by removing the previous part, handling adjacent ../../
#        if the path begins with /../ it is an invalid path because there is no previous part to remove
#        if the path begins with ../ it is relative to something this function can not know and any
#            leading ../../... sequences will not be removed
function pathGetCanonStr()
{
	local envFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-e) envFlag="1" ;;
	esac; shift; done
	local _pgcs_path="$1"
	local _pgcs_retVar="$2"

	if [ "$envFlag" ]; then
		[[ "$_pgcs_path" =~ ^~ ]] && _pgcs_path="$HOME/${_pgcs_path#\~}"
		if [ ! "$_pgcs_path" ] || [[ "$_pgcs_path" =~ ^[^/] ]]; then
			_pgcs_path="$(pwd)/${_pgcs_path}"
		fi
	fi

	_pgcs_path="$(echo "$_pgcs_path" | sed '
		# replace // with /
		s|//|/|g

		# remove all the single . folders
		:z
		s|^\./||g     # remove the leading "./"
		s|/\./|/|g    # replace /./ with /
		s|/\.$|/|g    # replace trailing /. with /
		tz

		# the challenge of ../ processing is making a regex that matches "<something>" as long as its not ".." alone (single dots have already been removed)
		# so this logic replaces .. folders with \v, does the /../ processing and then puts the .. back
		:y
		s|^\.\./|\v/|g
		s|/\.\./|/\v/|g
		s|/\.\.$|/\v|g
		ty

		# pop up the ../ by pairing them with a <something>/ before the ../ where <something> is not ".."
		:x
		s|/[^/\v]\+/\v/|/|g    # replace  /<something>/../  with /
		s|/[^/\v]\+/\v$|/|g    # replace  /<something>/..$ sequences with /
		s|^[^/\v]\+/\v/||g     # remove   ^<something>/../ sequences
		s|^[^/\v]\+/\v||g      # remove   ^<something>/../ sequences
		s|^/\v||g              # remove   ^/../.. sequences  (note this is kind of incorrect because we are going up past root, but linux allows it)
		tx

		# putting back the ..
		s|\v|..|g

		# removes the trailing / only if its not just "/"
		s|\(..*\)/$|\1|
	')"
	returnValue "$_pgcs_path" "$_pgcs_retVar"
	[ "$_pgcs_path" ]
}


# usage: pathCompare [-e] <p1> <p2>
# compares two paths taking into account path globing (i.e. *)
# Options:
#    -e : pathGetCanonStr each path first which removes things that dont effect the meaning (like extra / "//" )
#         and also makes the paths absolute.
function pathCompare()
{
	local envFlag=""
	while [[ "$1" =~ ^- ]]; do case $1 in
		-e) envFlag="1" ;;
	esac; shift; done
	# remove a trailing / because the presense of a trailing / or not does not change the meaning of the path
	local p1="${1%/}"
	local p2="${2%/}"

	if [ "$envFlag" ]; then
		p1="$(pathGetCanonStr -e "$p1")"
		p2="$(pathGetCanonStr -e "$p2")"
	fi

	# use the == op of [[ ]] because it understands * globing -- i.e "/var/*" is equal to "/var/lib"
	# replace spaces in the paths with '\ ' which escapes them so that [[ ]] does not break the tokens on spaces
	[[ ${p1// /\\ } == ${p2// /\\ } ]]
}


# usage: pathGetRelativeLinkContents <linkFrom> <linkTo> [<retVar>]
# returns the relative path that would make a symlink at <linkFrom> point to the filessysem object at <linkTo>
# linkFrom and linkTo do not need to be absolute, but they do need to be relative to the same PWD so that they
# have a command path. this does not necessarily mean that they have any common parts in there strings.
# Params:
#    <linkFrom> : The path where a symlink cound be created. If this is a folder, its where an unamed symlink
#                 in that folder could be created.
#    <linkTo>   : The file or folder where the symlink will point to.
#    <retVar>   : if provided, the result is returned in this variable instead of stdout
function pathGetRelativeLinkContents()
{
	local linkFrom="$1"
	local linkTo="$2"

	# if linkFrom ends in a / its a folder location. Put a dummy link name b/c the alogorithm assumes its a link
	[[ "$linkFrom" =~ /$ ]] && linkFrom+="linkFilename"

	local commonPath="$(pathGetCommon "$linkFrom" "$linkTo")"

	# if there is no common path, and either contains a protocol part, there path parts might still be
	# relative so parse out everything but the path part of the URLs and try again.
	# TODO: take into account if the users are different and the resource paths are relative they have different PWD
	if [ ! "$commonPath" ]; then
 		local host1 host2
 		[[ "${linkFrom}" =~ [:] ]] && parseURL "$linkFrom" "" "" "" host1 "" linkFrom
 		[[ "${linkTo}" =~ [:] ]]   && parseURL "$linkTo"   "" "" "" host2 "" linkTo

		# if they refer to different hosts, they have nothing in common
		[ "$host1" ] && [ "$host2" ] && [ "$host1" != "$host2" ] && return

		# now restart with the paths now that niether have the host/protocol
		commonPath="$(pathGetCommon "$linkFrom" "$linkTo")"
	fi

	# if there is still no common path, and niether are absolute, assume that they are both relative to the PWD and add ./
	if [ ! "$commonPath" ] && [ "${linkFrom:0:1}" != "/" ] && [ "${linkTo:0:1}" != "/" ]; then
		commonPath="./"
		linkFrom="./$linkFrom"
		linkTo="./$linkTo"
	fi

	# if there is still no common path but one of them is absolute, we have to make the other one absoute using the PWD
	# note that if both are absolute, commonPath could not be empty (it would be at least "/")
	if [ ! "$commonPath" ]; then
		# TODO: it seems that we should call pathGetCanonStr on both unconditionally here but I don't want to test that now
		[ "${linkFrom:0:1}" == "/" ] && linkTo="$(pathGetCanonStr -e "$linkTo")"
		[ "${linkTo:0:1}" == "/" ] && linkFrom="$(pathGetCanonStr -e "$linkFrom")"
		commonPath="$(pathGetCommon "$linkFrom" "$linkTo")"
	fi

	local linkFromRel="${linkFrom#${commonPath%/}}"; linkFromRel="${linkFromRel#/}"
	local linkToRel="${linkTo#${commonPath%/}}"; linkToRel="${linkToRel#/}"

	# the first -e statement turns all the leading folders ("something>/") into ../
	# the second -e statement removes the filename of the link
	local result="$(echo "$linkFromRel" | sed -e 's|[^/][^/]*/|\.\./|g' -e 's|/*[^/]*$||')"
	returnValue "$result${result:+/}$linkToRel" "$3"
}


######################################################################################################################################################
### Wiki formatting functions


function wikiMakeOverflowText()
{
	local displayLength="$1"
	local fullText="$2"
	echo "{{H:title|$fullText|${fullText:0:$displayLength}}}"
}

# usage: wikiEchoFixedLine <lineLength> <line text ... >
# Use this like 'echo' but in a wiki text, it produces code that shows the first 'lineLength' characters and then the rest in a tool tip.
function wikiEchoFixedLine()
{
	local lineLength="$1"; [ $# -gt 0 ] && shift
	local lineLengthWithElipses="$(( lineLength-3 ))"
	local fullText="$@"
	local dispText="$fullText"

	local isLong=""
	if [ ${#fullText} -gt ${lineLength:-130} ]; then
		isLong="1"
		dispText="${fullText:0:$lineLengthWithElipses}..."
	fi
	dispText="${dispText// /&nbsp;}"
	dispText="${dispText//-/&#8209;}"
	if [ "$isLong" ]; then
		echo "{{H:title|$fullText|$dispText}}<br/>"
	else
		echo "$dispText<br/>"
	fi
}
