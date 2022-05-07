#!/bin/bash

# usage: jsonEscape <varname1> [...<varnameN>}
function jsonEscape()
{
	while [ $# -gt 0 ]; do
		[ ! "$1" ] && { shift; continue; }
		local _je_value="${!1}"
		_je_value="${_je_value//$'\\'/\\\\}" # reverse solidus
		_je_value="${_je_value//$'"'/\\\"}"  # quotation mark
		_je_value="${_je_value//$'/'/\\/}"   # solidus
		_je_value="${_je_value//$'\b'/\\b}"  # backspace
		_je_value="${_je_value//$'\f'/\\f}"  # formfeed
		_je_value="${_je_value//$'\n'/\\n}"  # linefeed
		_je_value="${_je_value//$'\r'/\\r}"  # carriage return
		_je_value="${_je_value//$'\t'/\\t}"  # horizontal tab
		printf -v $1 "%s" "$_je_value"
		shift
	done
}


# usage: jsonUnescape <varname1> [...<varnameN>}
function jsonUnescape()
{
	while [ $# -gt 0 ]; do
		[ ! "$1" ] && { shift; continue; }
		local _je_value="${!1}"
		_je_value="${_je_value//\\\"/$'"'}"  # quotation mark
		_je_value="${_je_value//\\\//$'/'}"   # solidus
		_je_value="${_je_value//\\b/$'\b'}"  # backspace
		_je_value="${_je_value//\\f/$'\f'}"  # formfeed
		_je_value="${_je_value//\\n/$'\n'}"  # linefeed
		_je_value="${_je_value//\\r/$'\r'}"  # carriage return
		_je_value="${_je_value//\\t/$'\t'}"  # horizontal tab
		_je_value="${_je_value//\\\\/$'\\'}" # reverse solidus
		printf -v $1 "%s" "$_je_value"
		shift
	done
}

# usage: jsonAwk [-T <topVarName>] [-C <countToRead>] [<script> [<file1>...<fileN>]]
# parses the json formatted input. By default it prints a line with (<jpath> <val>) for each primitive value
# read. Primitive values are the leaves and do not include Array and Objects. Array and Objects become parts in the <jpath> string.
#
# How Much is Read:
#    Well formed JSON input will consist of one json Value (often an Array or Object) but this function can also handle input
#    streams with multiple values which would result from reading multiple files. The default is to name the first top level value
#    "top" and then "top1", "top2", etc.. if others are encountered. The -T and -C can control the names of top level and also limit
#    how many are read.
# Typical Uses:
#    # this will print a line "<jpath> <value>" to stdout for each primitive value encountered.
#    jsonAwk '' file
#
#    # instead of printing a line, do something else for each value encountered.
#    jsonAwk -n '
#       function valueHook(jpath,val,valType,relName) {
#          # called for each value encountered.
#       }
#       END {
#           <process using flatData[<jpath>] and flatDataInd[] arrays>
#       }
#    ' file
#
# Algorithm:
#    1) concatenate the input into one big string w/o any "\n"
#    2) all real processing happens in the END block
#    3) tokenize the input into the 11 json primitive token types
#         *) a complicated regex matches each of the 11 primitives and inserts a \n after each
#         *) we remove extraneous whitespace so that each token is separated by exactly one \n
#         *) split the string into a jtonkens array using \n and the delimiter.
#    4) The expectToken(type) function implements a recursive descent parse. type can be a primitive
#       token or a composite (tArray, tObject, tValue)
#    5) jpath is a global that contains the fully qualified name of the current value being parsed
#         *) the -T option allows the caller to name the top level json value(s) in the input stream
#         *) the default top level name is "top","top1",..."topN"
#         *) the tArray and tObject parse cases maintain jpath
#         *) tArray appends jpath+=[<count>] for each element
#         *) tObject appends jpath+=".<name>" for each name/value pair
#    6) The function addFlattenValue(jpath, val,valType) is called after each tValue is parsed
#         *) addFlattenValue() maintains the flatData[<jpath>] and flatDataInd[] arrays.
#         *) if the type is a primitive (not Array or Object) it prints a line with "jpath val"
#         *) flatDataInd[] is the list of jpaths in the order that they were encountered.
#         *) addFlattenValue() also calls the valueHook(jpath, val,valType,relName) that can be provided in the
#            script passed into this function.
# Params:
#    <script> : an awk script to do custom processing. if the script does not include the function 'valueHook', one will be added
#               that prints "<jpath> <value>\n" for each primitive value
#    <file>  : the file to read the input from. default is to read from stdin
# Options:
#   -T <topVarName> : use this name for the jpath starting name for the top level value in the input stream
#          This can be specified multiple times to name multiple items in the stream.
#   -C <countToRead> : number of top level json values to read up to from the input stream.
#          the values are assigned the names "top","top1",..."topN"
#          reading stops when the EOF is reached so less than the number specified might be read.
#          These are read only after any values specified with  -T options so typically either
#          one or more -T options or -C is used.
#          The default <countToRead> is a very large number so that the stream is read until empty.
#          However, if at least one -T option is specified, the default becomes 0. You can specify -C
#          after the last -T.
#   -n : don't print a line for each primitive value read.
function jsonAwk()
{
	local topVarNames=() jsonValuesReadCount=100000 script noJpathOutOpt bashObjects
	while [ $# -gt 0 ]; do case $1 in
		-T*)  bgOptionGetOpt valArray: topVarNames         "$@" && shift; jsonValuesReadCount=0 ;;
		-C*)  bgOptionGetOpt val:      jsonValuesReadCount "$@" && shift ;;
		-n)  noJpathOutOpt="-n" ;;
		--bashObjects) bashObjects="--bashObjects" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	if [ ! "$1" ] || [ ! -f "$1" ]; then
		script="$1"; shift
	fi

	### if the script passed in does not define the valueHook function, add our default one that
	# prints "<jpath> <value>\n" for each primitive value.
	if [[ ! "$script" =~ function[[:space:]]*valueHook ]]; then
		script+='
			function valueHook(jpath, value, valType, relName) {}
		'
	fi
	if [[ ! "$script" =~ function[[:space:]]*eventHook ]]; then
		script+='
			function eventHook(event, p1,p2,p3,p4,p5) {}
		'
	fi

	gawk -i bg_json.awk \
		-v jsonValuesReadCount="$jsonValuesReadCount" \
		-v noJpathOutOpt="$noJpathOutOpt" \
		-v topNamesStr="${topVarNames[*]}" \
		-v bashObjects="$bashObjects" \
		"$script" $(fsExpandFiles "$@")
}


# usage: jsonRead [-T <name>] -A <flatArrayVar> [<file>]
# read a json stream into <flatArrayVar>[jpath]=<primitiveValue>
# see jsonAwk for description of -T and <file> / stdin input
function jsonRead()
{
	local flatArrayVar
	while [[ "$1" =~ ^- ]]; do case $1 in
		-A*) flatArrayVar="$(bgetopt "$@")" && shift ;;
	esac; shift; done
	local file="$1"

	local name value
	while read -r name value; do
		if [ "$flatArrayVar" ]; then
			local tmpRef="$flatArrayVar[$name]"
			printf -v $tmpRef "%s" "$value"
		else
			printf "%-18s = %s\n" "$name" "$value"
		fi
	done < <(
		jsonAwk $file
	)
}


# usage: $obj.fromJSON <file>
# usage: $obj.fromJSON < <(someCmd p1 p2)
# usage: $obj.fromJSON <<<"$jsonText"
# read a JSON formated stream into a bash Object. The object will reflect the structure using member objects
# and member arrays as appropriate
# Params:
#    <file> : if specified, the JSON text will be read from this file. If not, it is read from stdin
#            to read from a string use: $obj.fromJSON <<<$jsonText"
#            to read from a cmd's output use: $obj.fromJSON < <(someCmd p1 p2)
function Object::fromJSON()
{
	local file="$1"

	local name value
	while read -r name value; do
		jsonUnescape value
		#bgtraceVars -1 name value
		$this.${name#this.}="$value"
	done < <(
		jsonAwk --bashObjects -T this $file
	)
}

# TODO: write Object::toJSON. this should be pretty straight forward. Iterate its attributes, write simple attributes directly
#      and call ::toJSON on member Objects and member arrays. Not sure if Array::toJSON needs to be written b/c Object::toJSON
#      might do it all

# usage: $obj.toJSON
# Options:
#    --sys : inlude system members in the output. System members are any whose index name in 'this' starts with an '_' and also
#            all the indexes in '_this' if _this is a separate bash array
#    --indent=<padStr> : <padStr> is a string of (typically) padding (spaces or tabs) that will be written at the start of each line
#    --sep=<separator> : a separator character (or string) that will be written after the output. Typically it empty '' or ','
# See Also:
#    man(3) Object::toString
function Object::toJSON()
{
	((recurseCount++ >10)) && assertError
	local indent recordSep mode
	while [ $# -gt 0 ]; do case $1 in
		--sys)     mode="--sys"  ;;
		--all)     mode="--all"  ;;
		--indent*) bgOptionGetOpt val: indent           "$@" && shift ;;
		--sep*)    bgOptionGetOpt val: recordSep        "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# the pattern allows objDictionary to be shared among this and any recursive call that it spawns
	if ! varExists objDictionary; then
		local -A objDictionary=()
	fi

	# record that this object is being written to the json txt
	objDictionary[${_this[_OID]}]="sessionOID_${#objDictionary[@]}"

	# if the this array for this object is numeric then we write it as a JSON list [ <varlue> .. ,<varlue>] with no labels
	if [[ "${static[oidAttributes]}" == *a* ]]; then
		local tOpen='['
		local tClose=']'
		local labelsOn=""
		local myMode=""
	else
		local tOpen='{'
		local tClose='}'
		local labelsOn="yes"
		local myMode="$mode"
	fi

	# the general indent strategy is that the inside of the object (i.e. its attribute list) is indented WRT the open and close.
	# so we print the open before we increase the indent and at the end decrease the indent before we print the close.
	# This also works fine for nested objects where the current output position is after the object's name '"myobj": {'
	printf "%s" "$tOpen"
	indent+="   "

	# use getIndexes to get the memberNames. Its temping to try to use "${!this[@]}" and "${!_this[@]}" but its too complicated to
	# repeat all the edge cases and getAttributes is pretty well optimized so that when possible it just returns those constructs
	local memberNames; $_this.getIndexes $myMode -A memberNames
	local totalMemberCount="${#memberNames[@]}"
	local writtenCount="$totalMemberCount"
	local sep=","

	# this is so that an empty Object can show on one line like "{}"
	((totalMemberCount>1)) && printf "\n"

	local name value
	for name in "${memberNames[@]}"; do
		((--writtenCount == 0 )) && sep=""

		case ${name} in
			_*) value="${_this[$name]}" ;;
			*)  value="${this[$name]}"  ;;
		esac

		# JSON requires some characters to be escaped. see https://www.json.org/json-en.html
		jsonEscape value

		# print the start of the line, upt to the <value>
		printf "${indent}"
		[ "$labelsOn" ] && printf '"%s": ' "$name"

		# if its an objRef, get its _OID
		local refOID=""; IsAnObjRef $value && { GetOID "${value}" refOID || assertError; }

		# special case _OID so that we change its value to the sessionOID
		if [ "$name" == "_OID" ]; then
			printf '"%s"%s\n'  "${objDictionary[${_this[_OID]}]}" "$sep"

		# if its an object and not already in objDictionary[] which means we have not yet written out this object
		elif [ "$refOID" ] && [ ! "${objDictionary[$refOID]+exists}" ]; then
			$value.toJSON $mode --indent="$indent" --sep="$sep"

		# if its an object we have already seen
		elif [ "$refOID" ]; then
			printf '"%s"%s\n'  "${value//$refOID/${objDictionary[$refOID]}}" "$sep"

		# all other cases just write the <name> and <value>
		else
			printf '"%s"%s\n'  "$value" "$sep"
		fi
	done

	indent="${indent%"   "}"
	((totalMemberCount>1)) || indent=""
	printf "${indent}%s%s\n" "$tClose" "$recordSep"
	((recurseCount--))
}


# usage: ConstructObjectFromJson <objRefVar> <jsonText>
function ConstructObjectFromJson()
{
	local file="-"
	while [ $# -gt 0 ]; do case $1 in
		-f*|--file*)  bgOptionGetOpt val: file "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local objRefVar="$1"; shift
	local file="${1:-$file}"

	local saveFD
	exec {saveFD}<&0 < <(jsonAwk -n '
		function eventHook(event, p1,p2,p3,p4,p5                               ,relName) {
			relName=(p1 ~ /[[].*[]]/) \
				? "<arrayEl>" \
				: gensub(/^.*[.]/,"","g",p1)

			if (p1 ~ /[[].*[]]/)
				relName="<arrayEl>"
			else
				relName=gensub(/^.*[.]/,"","g",p1)
			printf("%-13s %-13s %-24s %s\n", event, relName, p1, "--")
		}
		function valueHook(jpath, value, valType, relName) {
			printf("%-13s %-13s %-24s %s\n", valType, relName, jpath, gensub(/[ ]/,"%20","g",value))
		}
	' "$file" || echo "!ERROR" )

	local -n scope; ConstructObject Object "scope"

	if [ "$bgObjectsBuiltinIsInstalled" ]; then
		bgObjects restoreObject scope
	else
		local scopeOID; GetOID $scope scopeOID

		local -a currentStack="$scope"
		local -n current="$scopeOID"
		local -A objDictionary

		local relName valType jpath value className
		while read -r  valType relName jpath value ; do
			[ "$valType" == "!ERROR" ] && assertError -v objRefVar -v file "jsonAwk returned an error reading restoration file"

			# the space==%20 escaping is not a json standard -- its because read will loose the leading spaces of value. Since value
			# is the last value, it concatenates the remaining input to the EOL but any leading spaces just become the separator between
			# it and the previous variable (jpath)
			value="${value//%20/ }"

			# now escape according to the json standard
			jsonUnescape value

			case $valType in

				startObject) className="Object" ;;&
				startList)   className="Array"  ;;&
				startObject|startList)
					currentStack=(""  "${currentStack[@]}")
					ConstructObject "$className" currentStack[0]
					if [ "$relName" == "<arrayEl>" ]; then
						current+=("$currentStack")
					else
						current[$relName]="$currentStack"
					fi

					unset -n current; local -n current; GetOID $currentStack current || assertError
					;;

				endObject|endList)
					currentStack=("${currentStack[@]:1}")
					unset -n current; local -n current; GetOID $currentStack current || assertError
					className=""
					;;
				tObject) ;;
				tArray)  ;;

				*)	if [[ "$value" =~ _bgclassCall.*sessionOID_[0-9]+ ]]; then
						:
					fi
					case $relName in
						# we don't restore 0, _OID, nor _Ref although we use them to update the dictionary with the sessionOID_<n> and new _OID
						0) ;;
						_OID) local sessionOID="$value"  ;;&
						_Ref) local partsIn=($value); local sessionOID="${partsIn[1]}" ;;&
						_Ref|_OID)
							local partsOut=($currentStack)
							objDictionary["${sessionOID}"]="${partsOut[1]}"
							objDictionary["${partsOut[1]}"]="${sessionOID}"
							;;
						_CLASS)
							static::Class::setClass $current "$value"
							;;

						_*)	# SetupObjContext <objRef> <_OIDRef> <thisRef> <_thisRef> <_vmtRef> <staticRef>
							local -n  current_sys; SetupObjContext $current "" "" current_sys
							current_sys[$relName]="$value"
							;;

						'<arrayEl>') current+=("$value") ;;
						*) current[$relName]="$value" ;;
					esac
					;;
			esac
		done
	fi


	exec <&- 0<&$saveFD

	returnObject ${scope[top]} "$objRefVar"
}
