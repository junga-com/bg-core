#!/bin/bash


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
#       function valueHook(jpath,val,valType) {
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
#         *) addFlattenValue() also calls the valueHook(jpath, val,valType) that can be provided in the
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
			function valueHook(jpath, value, valType) {}
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
#
function Object::toJSON()
{
	local indent
	while [ $# -gt 0 ]; do case $1 in
		--indent*)  bgOptionGetOpt val: indent "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	printf "${indent}{\n"
	indent+="   "

	local count="${#this[@]}"
	local sep=","
	for name in "${!this[@]}"; do
		((count-- == )) && sep=""
		printf "${indent}"'"%s": "%s"%s\n' "$name" "${this[$name]}"
	done

	indent="${indent%"   "}"
	printf "${indent}}\n"
}
