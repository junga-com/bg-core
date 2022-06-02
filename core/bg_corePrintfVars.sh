
# Library
# Provides the printfVars function which is a generic bash variable examination functions. Many interpreted languages have functions
# that allow the programmer to simply list a series of variable names to show. This is that function in bash.
#
# This library also contains helper functions used by printfVars. They all begin with pv*. Some of them, particularly pvPrArray
# may be usefull in other contexts.
#
# Indentation:
# This is documented to help people who wish to make changes or extend printfVars.
# This is the model that is used for indentation. Note that by default, objects are displayed with Object::toString
# which has a similar but independent indentation model
#      <------------------------ pv_maxLineLen -------------------------------------------------------------->
#      <--prefix--><-- labelWidth -> < value first line ... clipped at pv_maxLineLen                         >
#     |<--------- continue width --> +<-- subsequent value lines...                                          >
#     |            foo              ='42'
#     |            myMultiLineText  ='blue'(\n)
#     |                              +'red'
#     |            myArray          []
#      <--prefix +=labelWidth -----> <--lW--> < value first line ... clipped at pv_maxLineLen
#     |<--------- continue width ----------->
#     |                             [one    ]='this and that'
#     |                             [three  ]='otherStuff'
#     |                             [myarray][]
#      <--prefix +=labelWidth --------------> <--lW--> < value first line ... clipped at pv_maxLineLen
#     |<--------- continue width -------------------->
#     |                                    [0]="zero"
#     |                                    [1]="one"
#     |                                    [2]="two"
# Note: labelWidth does not have to be large enough to align the entries.
#       Setting it to 0 will bring all the values tight against the labels
# Note: pv_prefix is a padded string whereas pv_labelWidth is an interger length
#
# Each time pvPrArray is called, it prints the label of the array using the existing pv_prefix and pv_labelWidth
# and then adds pv_labelWidth number of spaces to pv_prefix and calculates a new pv_labelWidth for its indexes
# and prints each element of the array as an attribute (name/value pair)
#


# usage: pvCalcLocalIndent <labelLength> <retVar>
# given the <labelLength> passed in and the global pv_labelWidth, calculate how big the indent should be for subsequent lines
# The returned value is clipped between 2 and 30
function pvCalcLocalIndent()
{
	local pv_cli_result=$(( (${pv_labelWidth:-0} > ${1:-0}) ? ${pv_labelWidth:-0} : ${1:-0}  ))
	returnValue "$(( (pv_cli_result>30)?30 : (pv_cli_result<2)?2 : pv_cli_result ))" "$2"
}

# usage: pvEndOneLineMode
# if there is content in the current line, a lineFeed will be written
# and pvEndOneLineMode will be cleared (enter multilineMode)
function pvEndOneLineMode()
{
	if [ "$pv_oneLineMode" ] || [ ! "$pv_atLineStart" ]; then
		[ ! "$pv_atLineStart" ] && printf "\n"
		pv_oneLineMode=""
		pv_atLineStart="1"
	fi
}

# usage: pvPrName <label> [<labelWidth>] [arrayStart|arrayIndex|normal|none]
# Format:
# <prefix><label><pad>=
function pvPrName()
{
	pvEndOneLineMode
	case ${3:-normal} in
		# Note that the formatting assumes that the field will be 1 char longer for the '=' but in the other cases we need to
		# subratract the additional number of chars that we add ([] -> -1,   []= -> -2)
		normal)             printf -- "${pv_prefix}%-*s="    "${2:-0}" "$1" ;;
		none)               printf -- "${pv_prefix}%-*s"     "${2:-0}" "" ;;
		arrayStart)         printf -- "${pv_prefix}%-*s[]"   "$((${2:-0}-1))" "$1" ;;
		arrayIndex)         printf -- "${pv_prefix}[%-*s]="  "$((${2:-0}-2))" "$1" ;;
		arrayStartRecursed) printf -- "${pv_prefix}[%-*s][]" "$((${2:-0}-2))" "$1" ;;
	esac
}


# usage: pvPrVal_single [<minFieldWidth> [<maxFieldWidth>]]
# Awk filter for output that must print on one line with a max allowed width. line ends are converted to "\n". extra input
# is removed and replaced with "...". Pipe the content into this function
# this will not allow any line ends to be output so that the output will add to the current line without advancing to the next.
# -v maxFieldWidth=<N> : the maximum number of characters that the content
# -v minFieldWidth=<N> : if the content is less than <minFieldWidth> it will be right padded to <minFieldWidth>
# Format:
# <field>  # field is printed with no lineEnds. At least minFieldWidth and at most maxFieldWidth
function pvPrVal_single() {
	gawk -v minFieldWidth="$1" -v maxFieldWidth="$2" '
		function clip(s, len) {s=(length(s) <= len) ? s : substr(s,1,len-3)"..."; return s }
		BEGIN { if (!maxFieldWidth) maxFieldWidth=64000 }
		{
			buf=buf""lineEnd""$0
			lineEnd="\n"
			if (length(buf) > maxFieldWidth) {exit}
		}
		END { printf("%-*s ", minFieldWidth,clip(buf,maxFieldWidth)) }
	'
}

# usage pvPrVal_multi <labelWidth>
# Awk filter for output that is allowed to have multiple lines. Pipe the field contents into this function
# It is assumed that the first line has already had a label output and the first column will be at len(<prefix>)+labelWidth+1
# subsequent lines if any will have that number of blank spaces then <continuePrefix> then the line content
# -v labelWidth=<N>  : the len of the label for this value so that it can line up subsequent lines.
# -v continuePrefix=<str> : a string written after <prefix> and labelWidth on the 2nd and subsequent lines
# Format:
# <prefix><labelWidth>=
# <  startAttr       >=<content ...>
#                     +<continued content ....>
function pvPrVal_multi()
{
	gawk -v prefix="$pv_prefix" -v labelWidth="${1:-pv_labelWidth}" -v maxLineLen="$pv_maxLineLen" '
		function clip(s, len) {s=(length(s) <= len) ? s : substr(s,1,len-3)"..."; return s }
		BEGIN {
			if (!maxLineLen) maxLineLen=64000
			if (!continuePrefix) continuePrefix=" +"
			totalIndent=length(prefix) + labelWidth
			firstClipLen=maxLineLen - totalIndent -1 # -1 for the quote that starts the <value> b/c the + lines up with the quote
			continueClipLen=firstClipLen - length(continuePrefix) + 1 # +1 to add it back it b/c there is no quote on these lines
		}
		NR==1 {printf("%s\n", clip($0,firstClipLen) )}
		NR>1  {printf("%s%-*s%s%s\n", prefix, labelWidth,"", continuePrefix, clip($0,continueClipLen) )}
		END {if (NR==0) printf("\n")}
	'
}


# usage: pvPrAttribute <label> <value>  [arrayStart|arrayIndex|normal]
# prints a complete name/value pair formatted acording to pv_oneLineMode
# Format:
# oneLineMode: <pvPrVal_single>  # containg <label>='<value>'
# multiline  : <pvEndOneLineMode><pvPrName><pvPrVal_multi>
function pvPrAttribute()
{
	local pv_label="$1"
	local pv_value="$2"
	local pv_style="${3:-normal}"

	case ${pv_oneLineMode:-multiline}:${pv_label:+labelExits} in
		oneline:labelExits) printf -- "%s='%s'\n" "$pv_label" "${pv_value}" | pvPrVal_single "$pv_inlineMinWidth" "$pv_inlineMaxWidth"; pv_atLineStart="" ;;
		oneline:)           printf -- "%s\n"                  "${pv_value}" | pvPrVal_single "$pv_inlineMinWidth" "$pv_inlineMaxWidth"; pv_atLineStart="" ;;

		multiline:labelExits)
			local pvl_indentWidth; pvCalcLocalIndent "${#pv_label}" pvl_indentWidth
			pvPrName "$pv_label" "$pvl_indentWidth" "$pv_style"
			echo "'$pv_value'" | pvPrVal_multi "$pvl_indentWidth"
			;;
		multiline:)
			pvPrName "$pv_label" "$pvl_indentWidth" "none"
			echo "$pv_value" | pvPrVal_multi "$pvl_indentWidth"
			;;
		*) assertLogicError
	esac
}

# usage: pvPrArray <label> <arrayVar>
# Global Vars:
#    pv_prefix
#    pv_labelWidth
#
# Format:
# <pvEndOneLineMode>
# <prefix><pvPrName>
# <prefix><indent><pvPrAttribute>
# <prefix>...
# <prefix><indent><pvPrAttribute>
function pvPrArray()
{
	local pvl_label="$1"
	local -n pvl_array="$2"
	local pvla_value="$3"
	local pvl_startLabelStyle=arrayStart; [ "${FUNCNAME[1]}" != "printfVars" ] && pvl_startLabelStyle="arrayStartRecursed"

	local canonicalOID; varGetNameRefTarget "$2" "canonicalOID"
	if [ ! "$pv_noNestFlag" ] && [ "${pv_objDictionary[$canonicalOID]+isSeen}" ]; then
		if [ "${pvla_value:0:12}" == "_bgclassCall" ]; then
			pvPrAttribute "$pvl_label" " <objRef to '${pv_objDictionary[$2]}'>" "arrayIndex"
		elif [ "${pvla_value:0:5}" == "heap_" ]; then
			pvPrAttribute "$pvl_label" "<array reference to '${pv_objDictionary[$2]}'>" "arrayIndex"
		else
			pvPrAttribute "$pvl_label" "<supressing repeated array '${pv_objDictionary[$2]}'>" "arrayIndex"
		fi
		return
	fi
	pv_objDictionary[$canonicalOID]="$pvl_label"

	### print the label using the current value of pv_prefix and pv_labelWidth
	pvEndOneLineMode
	pvPrName "${pvl_label}" "0" "$pvl_startLabelStyle"; printf "\n"

	### calculate the new indent frame vars pv_prefix and pv_labelWidth
	# we purposely hide the pv_prefix pv_labelWidth variable from the calling scope so that the helper functions will see our values
	# while printing the array elements and then automatically go back to the previous values when we exit

	# the old pv_labelWidth might be 0 if the previous frame was not aligning, but we want to use a value that will make the elements
	# of the array indent at least some and get as lose as possible to making them align with the label.
	local pv_labelWidthNew; pvCalcLocalIndent "${#pvl_label}" pv_labelWidthNew
	local pv_labelWidth="$pv_labelWidthNew"

	# purposely hide the higher scope pv_prefix,
	# append pv_labelWidth number of spaces to pv_prefix because that is our new base column.
	local pv_prefix="$pv_prefix"; printf -v pv_prefix "%s%-*s" "$pv_prefix" "$pv_labelWidth" ""

	# purposely hide the higher scope pv_labelWidth,
	# now that the current pv_labelWidth is absorbed into pv_prefix, change it to reflect aligning our index name labels (with [])
	local pv_labelWidth=0 pvl_index
	for pvl_index in "${!pvl_array[@]}"; do
		[ ${pv_labelWidth:-0} -lt ${#pvl_index} ] && pv_labelWidth=${#pvl_index}
	done
	((pv_labelWidth+=2)) # +2 for the [] we add to the lable when its an arrayIndex

	# iterate over the indexes, printing each attribute.
	# Note that we never have to recurse into printfVars because array elements can only be strings. possibly containing an <objRef>
	for pvl_index in "${!pvl_array[@]}"; do
		if [ ! "$pv_noNestFlag" ] && [[ "${pvl_array[$pvl_index]}" == heap_*[aA]*_* ]]; then
			pvPrArray "$pvl_index" "${pvl_array[$pvl_index]}" "${pvl_array[$pvl_index]}"
		elif [ ! "$pv_noNestFlag" ] && [ "${pvl_array[$pvl_index]:0:12}" == "_bgclassCall" ]; then
			local pvl_elementValue; bgread "" pvl_elementValue "" <<<"${pvl_array[$pvl_index]}"
			pvPrArray "$pvl_index" "$pvl_elementValue" "${pvl_array[$pvl_index]}"
		else
			pvPrAttribute "$pvl_index" "${pvl_array[$pvl_index]}"  "arrayIndex"
		fi
	done
}


# usage: printfVars [ <varSpec1> ... <varSpecN> ]
# print a list of variable information to stdout
# Provides the printfVars function which is a generic bash variable examination functions. Many interpreted languages have functions
# that allow the programmer to simply list a series of variable names to show. This is that function in bash.
#
# This is used by the bgtraceVars debug command but its also useful for various formatted text output
# Unlike most function, options can appear anywhere and options with a value can not have a space between opt and value.
# options only effect the variables after it
#
# Variable Interpretation:
# Variables name are examined to see how best to display them.
# Bash Variable Attributes Examination...
# varGetAttributes is called on the variable name to get <attrib> which is a string of attribute letters that are set on the variable
# or '-' if its a variable but has no attributes set.
#    <attrib>==""   (not a variable) : prints as a literal as if it were prefixed with -l
#    <attrib>=~[aA] (array variable) : prints as <varName>[] and then each element is treated as a new variable name and printed with an additional
#                      indent. In bash array elements can not be arrays or namerefs but if their content matches a heap array variable
#                      name or an <objRef> as described below, they are interpreted as such.
#    <anything else>(simple variable) : prints as <varName>='<value>'
# Content Examination...
#    begins with '_bgclassCall...' it is treated as an <objRef> and its toString method is invoked.
#    begins with 'heap_*[aA]_*' it is treated as an array. Note that this test is really only useful for array elements which can
#         not be arrays but this convention allows nested arrays in bash.
#
#
# Params:
# <varSpecN> : all arguments can be an option or a variable name or another word. Note that this is unlike most functions where
# options to the function itself must appear first. All options begin with a '-' and are described in the Options section below.
# The cmdline can be thought of as a script the executes in the order given. Each options or directive only affects the variable
# that come after it.
# Special Words...
#    "" or "\n"      : write a blank line. this is used to make vertical whitespace. with -1 you
#                      can use this to specify where line breaks happen in a list
#    "  "            : a string only whitespace sets the indent prefix used on all output to follow. It shorthand for --prefix="  "
# Any <varSpecN> that does not match an option or one of the special words is interpreted as a variable name.
#
# Options:
# Unlike most function, options can appear anywhere and options with a value can not have a space between opt and value.
# options only effect the variables after it
#   -l<string> : literal string. print <string> without any interpretation
#   -wN : set width. This works differently based on the prevailing line mode (multiline or oneline)
#         multiline: set the prefered minWidth of labels. This can be used to align the '=' sign of output. Note that this function
#                    operates in one pass of the command line arguments so it does not automatically set this
#         oneline:   set the minimum width of just the next field to be printed.
#   -1  : display vars on one line. array/object variables can not be displayed in a single line so the first array encountered
#         will reset to multiline mode as if a +1 was specified
#   +1  : display vars on multiple lines. this is the default. it undoes the -1 effect
#   --prefix=<prefix>  : add this <prefix> to the start of all subsequent output lines up to another --prefix is seen.
#   --noObjects : display the underlying object associative array as if it were not an object
#   --noNest: this is similar to --noObjects except that also prevents following member variable which are objects or heap arrays.
#          so that only the elements of arrays specified on the cmdline will be shown
#   --plain : do not look into the value to follow <objRef> and heap vars
#   --maxLineLen=<n> : in multilineMode clip all output lines to at most <n> characters. Does not affect oneLineMode output.
#   --table=<var> : use the printfTable function to output <var>
function printfVars()
{
	local pv_prefix                # This string is the start of every line printed. Moves the *entire* output over. set with --prefix or "    "
	local pv_labelWidth            # pads <name> field and adds to indent of subsequentLines  set by -w in multiline mode or the len of 1st array/obj name.
	local pv_maxLineLen=64000      # if any line exceeds this length it will be clipped to this length with the last 3 chars replaced with '...'
	local pv_inlineMinWidth        # (-w) minimum field len of the next "<name>='<value>'" field in pv_onelineMode
	local pv_inlineMaxWidth        # maximum field len of "<name>='<value>'" fields in pv_onelineMode
	local pv_oneLineMode           # single valued items are printed on one line. Does not affect arrays and objects but a bug messes up the first line
	local pv_atLineStart=1         # in multiline mode each iteration ends with the cursor at the start of a new line but in oneLineMode after something is written its not at the start
	local pv_noNestFlag            # --noNest, don't not recurse into any arrays or objects
	local pv_plainFlag             # --plain, dont look into the value to follow <objRef> and heap vars
	local pv_noObjectsFlag         # --noObjects. when set, this function simply pirnt the value of <objRef>s instead of calling their Object::toString method
	local pv_objOpts=()            # options to pass through to Object::toString

	# if the bg_objects.sh library is not loaded, turn off object detection
	type -t _bgclassCall &>/dev/null || pv_noObjectsFlag="1"

	# this pattern allows pv_objDictionary to be shared among this and any recursive call that it spawns
	if ! varExists pv_objDictionary; then
		local -A pv_objDictionary=()
	fi

	if [ -t 1 ] && type -t import &>/dev/null; then
		import -q bg_cui.sh ;$L1;$L2 && {
			cuiGetTerminalDimension -q "" pv_maxLineLen
		}
	fi

	local pv_term
	for pv_term in "$@"; do
		# proccess options
		case ${pv_term:-:empty:} in
			--table=*)    	printfTable ${pv_term#--table=}; pv_atLineStart="1"; continue ;;
			--prefix=*)   	pv_prefix="${pv_term#--prefix=}";                    continue ;;
			-l*)          	pvPrAttribute "" "${pv_term#-l}";                    continue ;;
			-1)           	pv_oneLineMode="oneline";                            continue ;;
			+1)           	pvEndOneLineMode;                                    continue ;;
			--noNest)       pv_noNestFlag="--noNest";                            continue ;;
			--plain)        pv_plainFlag="--plain";                              continue ;;
			--noObjects)  	pv_noObjectsFlag="--noObjects";                      continue ;;
			:empty:)      	printf "\n"; pv_atLineStart="1";                     continue ;;
			'\n')         	printf "\n"; pv_atLineStart="1";                     continue ;;
			-w*)          	if [ "$pv_oneLineMode" ]; then
				          		pv_inlineMinWidth="${pv_term#-w}"
				          	else
				          		pv_labelWidth="${pv_term#-w}"
				          	fi
				          	continue
				          	;;
			--maxLineLen=*)	pv_maxLineLen="${pv_term#--maxLineLen=}"
							[[ "$pv_maxLineLen" == *[^0-9]* ]] && assertError -v maxLineLen:pv_maxLineLen  "invalid value for --maxLineLen= option. must be positive integer"
							continue
							;;
		esac

		# "     " is shorthand for --prefix="     " in multilineMode but we just output it in oneLineMode
		if [[ "$pv_term" =~ ^[[:space:]]*$ ]]; then
			[ ! "$pv_oneLineMode" ] && pv_prefix="$pv_term"
			[   "$pv_oneLineMode" ] && { printf -- "$pv_term"; pv_atLineStart=""; }
			continue
		fi

		# this separates myLabel:myVarname taking care not to mistake myArrayVar[lib:bg_lib.sh] for it
		local pv_varname="$pv_term"
		local pv_label="$pv_term"
		if [[ "$pv_term" =~ ^[^[]*: ]]; then
			pv_varname="${pv_varname##*:}"
			pv_label="${pv_label%:*}"

			# <label>:-l"<literal string>"
			if [[ "$pv_varname" =~ ^-l ]]; then
				pvPrAttribute "$pv_label" "${pv_varname#-l}"
				continue
			fi
		fi


		# assume its a variable name and get its attributes. pv_type will be empty if its not a variable. If its a nameref pv_type
		# will include one or more n's (one fore each indirection) followed by the attribtues of the target variable
		local pv_type; varGetAttributes "$pv_varname" pv_type

		# case where the term is not a variable name
		if [ ! "$pv_type" ]; then
			# foo:bar where bar is not a variable name
			[ "$pv_label" == "$pv_varname" ] && pv_label=""
			pvPrAttribute "$pv_label" "$pv_varname"

		# case where it contains an object reference and we are doing object integration
	elif [ ! "$pv_plainFlag" ] && [ ! "${pv_noObjectsFlag}" ]  && [[ ! "$pv_varname" =~ [[][@*][]] ]]  && [ "${!pv_varname:0:12}" == "_bgclassCall" ]; then
			pvEndOneLineMode
			Try:
				${!pv_varname}.toString "${pv_objOpts[@]}" --title="${pv_varname}"
			Catch: && {
				# Note that a bug prevents this Catch from getting called when stepping through the debugger. It seems that the
				# catch resumes after the objEval.
				# in debugger when the watch window printfVars sees an object reference that has been created with NewObject,
				# toString failed on that object. added this try/catch but the catch did not execute.
				pvPrAttribute "$pv_label" "<error in '${!pv_varname}.toString --title=${pv_varname}' call>"
				printfVars ${!catch*}
			}

		# if its an array, iterate its content
		elif [[ "$pv_type" == *[aA]* ]]; then
			pvPrArray "$pv_label" "$pv_varname" ""

		# if its a string var that contains an <objRef> and we are not doing objects (--noObjects) do it as an array
		elif [ ! "$pv_plainFlag" ] &&  [ "${!pv_varname:0:12}" == "_bgclassCall" ]; then
			local pv_oid; bgread "" pv_oid "" <<<"${!pv_varname}"
			pvPrArray "$pv_label" "$pv_oid" "${!pv_varname}"

		# if its a string var that contains a heap var array
		elif [ ! "$pv_plainFlag" ] && [[ "${!pv_varname}" == heap_*[aA]*_* ]]; then
			pvPrAttribute "$pv_label" "${!pv_varname}"
			pvPrArray "$pv_label" "${!pv_varname}" "${!pv_varname}"

		# default case is to treat it as a variable name. we already handled the case where pv_varname is not a variable (pv_type="")
		else
			pvPrAttribute "$pv_label" "${!pv_varname}"
		fi

		pv_inlineMinWidth="0"
	done

	[ "$pv_oneLineMode" ] && printf "\n"
	true
}
