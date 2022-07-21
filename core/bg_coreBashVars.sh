
# Library bg_coreBashVars.sh
####################################################################################################################
### Functions to work with bash variables of various types
# This library provides functions to work with bash variables in an intuitive way. Some of them are aliases for bash syntax
# or common idioms that are cryptic so that they are more easiely discovered.
#
# This library also has functions that treat built in bash variables as higher level types like Sest and Maps.
#
# See Also:
#     printfVars (moved to its own library)  : (core function) detect the types of the variable names passed in and print their names and values in a nice format.
#     varExists   : (core function) true if the name refers to an existing bash variable in scope
#     varIsA      : (core function) true if the name referes to a bash variable of the specified type
#     returnValue : (core function) return a single value from a function either on stdout or in a retVar if one was passed in
#     setReturnValue : (core function) optionally set the value if a parameter passed by reference if its not empty.
#     varDeRef    : (core function) get the value of a reference variable (name)
#     varToggle   : toggle the value of a variable between two constants
#     varToggleRef: ref version of toggle the value of a variable between two constants




# usage: newHeapVar [-aAilrtux] [-t|--template=<templateStr>] <retVar> [<initData1>..<initDataN>]
# This 'allocates' a new variable on the conceptual bash heap. Of course a bash script can not access its process's heap but these
# bash global variables can be used similarly to heap variables because they are in scope across function calls. Techically they
# are global variables but they have random components to their names so that they should not collide and scripts can allocate and
# free them.
#
# <retVar> is set with the name of the newly created variable. The name is analoguous to a memory address or pointer value.
# Typically, this 'pointer' to the heap variable is passed around and stored in array elements which is possible because it is a
# simple bash string. To derefernce the variable, use `local <myVar> -n $<retVar>`
#
# Options:
#    -t|--template=<templateStr>  : a string similar to that used by mktemp. It needs to have one contiguous run of X's that will be
#                                   replaced by random chars
#    -a   : to make <retVar> indexed arrays (if supported)
#    -A   : to make <retVar> associative arrays (if supported)
#    -x   : to make <retVar> export
#    -i   : to make <retVar> have the `integer' attribute
#    -l   : to convert the value of <retVar> to lower case on assignment
#    -u   : to convert the value of <retVar> to upper case on assignment
#    -r   : to make <retVar> readonly
#    -t   : to make <retVar> have the `trace' attribute
# Params:
#    <retVar>    : the name of the variable that will receive the name of the new heap variable
#    <initData1> : the initial value of the variable created. If -a or -A is specified, each bash token will be assigned to a
#          different array element.
function varNewHeapVar() { newHeapVar "$@"; }  # ALIAS:
function newHeapVar() {
	local _template="heap_XXXXXXXXX" _attributes
	while [ $# -gt 0 ]; do case $1 in
		-t*|--template*) bgOptionGetOpt val: _template "$@" && shift ;;
		-A) _attributes+="A" ;;
		-a) _attributes+="a" ;;
		-x) _attributes+="x" ;;
		-i) _attributes+="i" ;;
		-l) _attributes+="l" ;;
		-u) _attributes+="u" ;;
		-t) _attributes+="t" ;;
		-r) _attributes+="r" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local _retVar="$1"; shift

	#if [[ "$_attributes" =~ [aA] ]]; then
	if [[ "$_attributes" == *[aA]* ]]; then
		local _initialData="("
		while [ $# -gt 0 ]; do
			#if [[ "$1" =~ ^\s*\[([^]]*)\]=(.*)$ ]]; then
			if [[ "$1" == *\[*\]=* ]]; then
				local _name="${1#\[}"; _name="${_name%%]*}"
				_initialData+="['$_name']='${1#*=}' "; shift
			else
				_initialData+="'$1' "; shift
			fi
		done
		_initialData+=")"
	else
		local _initialData="$*"
	fi

	_template="heap_${_attributes:-S}_${_template#heap_}"
	#[[ ! "$_template" =~ X ]] && _template+="_XXXXXXXXX"
	[[ "$_template" != *X* ]] && _template+="_XXXXXXXXX"

	local _instanceName
	varGenVarname --template=$_template _instanceName

	declare -g$_attributes $_instanceName="$_initialData" 2>$assertOut; [ ! -s "$assertOut" ] || assertError
	returnValue "$_instanceName" $_retVar
}



# usage: varExists <varName> [.. <varNameN>]
# returns true(0) if all the vars listed on the cmd line exits
# returns false(1) if any do not exist
# See Also:
#     test -v <var>
#     ${<var>+exists}
function varExists()
{
	# at least one arg is an array element like foo[idx]
	#if [[ "$*" =~ [][] ]]; then
	if [[ "$*" == *[][]* ]]; then
		local v; for v in "$@"; do
			# this case works for any input but maybe if there are no names with [], the one declare call in the other case is faster
			local attribs; varGetAttributes "$v" attribs
			[ "$attribs" ] || return 1
		done
		return 0

	# none contain []
	else
		# the -p option prints the declaration of the variables named in "$@".
		# we throw away all output but its return value will indicate whether it succeeded in finding all the variables
		declare -p "$@" &>/dev/null
	fi
}

# usage: varGetNameRefTarget <varname>
# return the ultimate name of <varname>. If <varname> is not a nameref (-n var) it will simply return <varname> but if <varname>
# is a nameref it will return the real variable that it points to. There can be namerefs to namerefs so in that case it keeps
# going until it either finds a variable name that is not a nameref or an unitialized nameref. if it finds an unitialized nameref
# it returns the empty string.
function varGetNameRefTarget()
{
	local _gaRetValue="$1" _gaInfiniLoop=10
	local _gaGeclaration="$(declare -p "$1" 2>/dev/null)"
	while [ "${_gaGeclaration:0:10}" == "declare -n" ] && [[ "${_gaGeclaration}" == *=* ]] ; do
		_gaRetValue="${_gaGeclaration#*=\"}"; _gaRetValue="${_gaRetValue%\"}"
		_gaGeclaration="$(declare -p "$_gaRetValue" 2>/dev/null)"
		((_gaInfiniLoop-- <= 0)) && assertError
	done
	returnValue "$_gaRetValue" "$2"
}

# usage: varGetAttributes <varName> [<retVar>]
# returns the attributes that are set for <varName>.
#   '-'  If <varName> exists but has none set, '-' is returned.
#   ''   If <varName> does not exist as a variable, "" is returned
#
# NameRef Variables:
# The attributes reflect the ultimate target of the nameRef change except that an 'n' will be prepended for each indirection before
# the ultimate target variable. If the nameref is not yet initialized, a '@' will follow the 'n'
#    local -A bar;      varGetAttributes returns 'A'
#    local -n goo;      varGetAttributes returns 'n@' (unitialized nameref)
#    goo=bar;           varGetAttributes returns 'nA' (nameref to an associative Array)
#    unset bar;         varGetAttributes returns 'n'  (nameref to non-existent variable)
#    bar=5;             varGetAttributes returns 'n-' (nameref to variable with no attrbutes)
#    local -n goo2=goo; varGetAttributes returns 'nn-' (nameref a nameref to variable with no attrbutes)
#
# Indexed Variables:
# Indexed variables are array references like foo[idx].
# If the array part does not exist or idx is not an index in the array "" is returned to indicate that the variable does not exist.
# If the idx entry does exist, the attributes of the array are returned with 'A' and 'a' removed (because the indexed var is not an
# array). If 'A' or 'a' are the only attribute, then '-' is returned to indicate that it exists but have no attribute set.
#
# Params:
#    <varName> : can be a direct variable name or an indexed name like foo[idx].
#    <retVar>  : name of the variable that will receive the attributes. If empty, they will be written to stdout
#
# See Also:
#    ${<varName>@a}
function varGetAttributes()
{
	local _gaRetValue

	# this function is no slower that doing an eval like...
	#      eval _gaRetValue='${'"$1"'@a}'
	# and this function handles nested namerefs and foo[idx] type vars too

	# normal vars
	# any code called by the debugger can not use [[ =~ ]] because it clobbers BASH_REMATCH
	#if [[ "$1" =~ ^[a-zA-Z0-9_]*$ ]]; then
	if [[ "$1" != *[^a-zA-Z0-9_]* ]]; then
		local _gaGeclaration="$(declare -p "$1" 2>/dev/null)"
		_gaRetValue="${_gaGeclaration#declare -}"
		_gaRetValue="${_gaRetValue%% *}"

		#if [[ "$_gaRetValue" =~ n ]]; then
		if [[ "$_gaRetValue" == *n* ]]; then
			#if [[ "$_gaGeclaration" =~ -n\ [^=]*=\"([^\"]*)\" ]]; then
			if [[ "$_gaGeclaration" == *=* ]]; then
				local _gaRefName="${_gaGeclaration##*=}"
				_gaRefName="${_gaRefName//\"}"
				varGetAttributes "$_gaRefName" "<nameref>$2"
				return
			else
				_gaRetValue+="@"
			fi
		fi

	# foo[idx]
	#elif [[ "$1" =~ [][] ]]; then
	elif [[ "$1" == *[][]* ]]; then
		local _gaBaseVar="${1%%\[*}"
		local _gaBaseAttribs; varGetAttributes "$_gaBaseVar" _gaBaseAttribs
		#if [[ "$_gaBaseAttribs" =~ A ]]; then
		if [[ "$_gaBaseAttribs" == *A* ]]; then
			local -n _gaBaseRef="$_gaBaseVar"
			local _gaIdxPart="${1#$_gaBaseVar\[}"; _gaIdxPart="${_gaIdxPart%]}"
			#if [[ "$_gaIdxPart" =~ ^(@|\*)$ ]] || [ "${_gaBaseRef[${_gaIdxPart:-####empty###Value###}]+exists}" ]; then
			if [[ "$_gaIdxPart" == [@*] ]] || [ "${_gaBaseRef[${_gaIdxPart:-####empty###Value###}]+exists}" ]; then
				_gaRetValue="${_gaBaseAttribs//[aA]}"
				_gaRetValue="${_gaRetValue:--}"
			fi
		#elif [[ "$_gaBaseAttribs" =~ a ]]; then
		elif [[ "$_gaBaseAttribs" == *a* ]]; then
			local -n _gaBaseRef="$_gaBaseVar"
			local _gaIdxPart="${1#$_gaBaseVar\[}"; _gaIdxPart="${_gaIdxPart%]}"
			#if [[ "$_gaIdxPart" =~ ^(@|\*)$ ]] || { [[ "$_gaIdxPart" =~ ^[0-9+-][0-9+-]*$ ]] && [ "${_gaBaseRef[$_gaIdxPart]+exists}" ]; }; then
			# 2022-04 bobg: removed the '&& [[ "$_gaIdxPart" != [-]* ]]' condition because foo[-1] is legal
			if [[ "$_gaIdxPart" == [@*] ]] || { [[ "$_gaIdxPart" != *[^0-9+-]* ]]  && [[ "$_gaIdxPart" != "" ]] && [ "${_gaBaseRef[$_gaIdxPart]+exists}" ]; }; then
				_gaRetValue="${_gaBaseAttribs//[aA]}"
				_gaRetValue="${_gaRetValue:--}"
			fi
		fi
	fi

	# this strange treatment of $2 is because we want to use recursion to handle nameRefs and we cant come up with a var name that
	# we, ourselfs dont declare local
	local _gaRetVar="$2"
	while [ "${_gaRetVar:0:9}" == '<nameref>' ]; do
		_gaRetValue="n$_gaRetValue"
		_gaRetVar="${_gaRetVar#<nameref>}"
	done
	returnValue "$_gaRetValue" "$_gaRetVar"
}

# usage: varIsA <type1> [.. <typeN>] <varName>
# returns true(0) if the var specified on the cmd line exits as a variable with the specified attributes
# Note that this function is much slower than the varIsAMapArray, varIsANumArray, and varIsAnyArray
# Types:
#    anyOfThese=<attribs> : example anyOfThese=Aa to test if <varName> is either an associative or numeric array
#    allOfThese=<attribs> : example allOfThese=rx to test if <varName> is both readonly and exported
#    <atribs>  : allOfThese=<attribs>
#    mapArray  : alias to test if attribute 'A' is present
#    numArray  : alias to test if attribute 'a' is present
#    array     : alias to test if either attribute 'A' or 'a' is present
# See Also:
#    man(3) varIsAMapArray
#    man(3) varIsANumArray
#    man(3) varIsAnyArray
function varIsA()
{
	local anyAttribs mustAttribs
	while [ $# -gt 1 ]; do case $1 in
		mapArray|-A) anyAttribs+="A" ;;
		numArray|-a) anyAttribs+="a" ;;
		array)       anyAttribs+="Aa" ;;
		anyOfThese*) bgOptionGetOpt val: anyAttribs  "--$1" "$2" && shift ;;
		allOfThese*) bgOptionGetOpt val: mustAttribs "--$1" "$2" && shift ;;
		*)           mustAttribs+="$1" ;;
	esac; shift; done

	[ ! "$1" ] && return 1

	# the -p option prints the declaration of the variable named in "$1".
	# if the output matches "declare -A" then its an associative array
	local vima_typeDef="$(declare -p "$1" 2>/dev/null)"

	if [ ! "$anyAttribs$mustAttribs" ]; then
		[ "$vima_typeDef" ]; return
	fi

	# if its a referenece (-n) var, get the reference of the var that it points to
	if [[ "$vima_typeDef" =~ ^declare\ -[aAilrux]*n[aAilrux]*\ [^=]*=\"([^\"]*)\" ]]; then
		local vima_refVar="${BASH_REMATCH[1]}"
		[[ "$anyAttribs" =~ n ]] && return 0
		vima_typeDef="$(declare -p "$vima_refVar" 2>/dev/null)"
		mustAttribs="${mustAttribs//n}"
	else
		[[ "$mustAttribs" =~ n ]] && return 1
	fi

	if [ "$anyAttribs" ] && [[ ! "$vima_typeDef" =~ ^declare\ -[^\ ]*[$anyAttribs] ]]; then
		return 1
	fi

	local i; for ((i=0; i<${#mustAttribs}; i++)); do
		[[ "$vima_typeDef" =~ declare\ -[^\ ]*${mustAttribs:$i:1} ]] || return 1
	done
	return 0
}


# usage: varIsAMapArray <varName>
# returns true(0) if the <varName> exits with the -A attribute
function varIsAMapArray()
{
	[ "$1" ] || return 1
	local -n _via_varName="$1"
	[[ "${_via_varName@a}" =~ A ]]
}

# usage: varIsANumArray <varName>
# returns true(0) if the <varName> exits with the -a attribute
function varIsANumArray()
{
	[ "$1" ] || return 1
	local -n _via_varName="$1"
	[[ "${_via_varName@a}" =~ a ]]
}

# usage: varIsAnyArray <varName>
# returns true(0) if the <varName> exits with either the -a or -A attribute
function varIsAnyArray()
{
	[ "$1" ] || return 1
	local -n _via_varName="$1"
	[[ "${_via_varName@a}" =~ [Aa] ]]
}

# usage: varMarshal <varName> [<retVar>]
# Marshelling means converting the variable to a plain string blob in a way that it can be passed to another process and then un-marshalled
# Format Of Marshalled Data:
# The returned string will not have any $'\n' so it can be written using a line oriented protocol
# The string consists of three fields.
#   T<varName> <contents>
#   |  |       |  '---------------- any characters of arbitrary length. $'\n' are escaped to \n
#   |  |       '------------------- one space separates <varName> and <contents>
#   |  '-------------------------- varName is any bash variable name
#   '------------------------------ T (type) is one of A (associative array) a (num array) i (int) # (default)
function varMarshal()
{
	local vima_typeDef="$(declare -p "$1" 2>/dev/null)"
	# if its a referenece (-n) var, get the reference of the var that it points to
	if [[ "$vima_typeDef" =~ -n\ [^=]*=\"(.*)\" ]]; then
		local vima_refVar="${BASH_REMATCH[1]}"
		vima_typeDef="$(declare -p "$vima_refVar" 2>/dev/null)"
	fi

	if [[ "$vima_typeDef" =~ declare\ -[^\ ]*A ]]; then
		arrayToString "$1" vima_contents
		local vima_contents="A$1 $vima_contents"
	elif [[ "$vima_typeDef" =~ declare\ -[^\ ]*a ]]; then
		arrayToString "$1" vima_contents
		local vima_contents="a$1 $vima_contents"
	elif [[ "$vima_typeDef" =~ declare\ -[^\ ]*i ]]; then
		local vima_contents="i$1 ${!1}"
	else
		local vima_contents="#$1 ${!1}"
	fi
	returnValue "${vima_contents//$'\n'/\\n}" "$2"
}

# usage: varUnMarshalToGlobal <marshalledData>
# This declares the variable contained in the <marshalledData> in the global namespace and sets it value to the one contained in
# <marshalledData>
# It would be possible to unmarshall to a local var but we would need to do it in two steps so the caller can declare the names local
function varUnMarshalToGlobal()
{
	local vima_marshalledData="$*"
	local vima_type="${vima_marshalledData:0:1}"; vima_marshalledData="${vima_marshalledData:1}"
	local vima_varName="${vima_marshalledData%% *}"; vima_marshalledData="${vima_marshalledData#* }"

	case $vima_type in
		A) declare -gA $vima_varName; arrayFromString "$vima_varName" "${vima_marshalledData//\\n/$'\n'}" ;;
		a) declare -ga $vima_varName; arrayFromString "$vima_varName" "${vima_marshalledData//\\n/$'\n'}" ;;
		i) declare -gi $vima_varName; varOutput -R "$vima_varName" "${vima_marshalledData//\\n/$'\n'}" ;;
		\#) declare -g $vima_varName; varOutput -R "$vima_varName" "${vima_marshalledData//\\n/$'\n'}" ;;
		*) assertError -v data:"$1" -v type:vima_type -v varName:vima_varName "unknown type in marshalled data. The first character should be one on 'Aai-', followed immediately by the <varName> then a single space then arbitrary data" ;;
	esac
}


# usage: escapeTokens <var1> [... <varN>]
# modifies the contents of each of the variable names passed in so that they could then be passed unquoted on a command line and
# be interpretted as exactly one argument. If the content is empty, it is replaced with '--' and any whitespace characters (space,
# newline, carrigeReturn, or tab) are replaced with their $nn equivalent where nn is the two digit hex code. (%20, %0A, %0D %09)
function stringToBashToken() { escapeTokens "$@"; }
function varEscapeContents() { escapeTokens "$@"; }
function escapeTokens()
{
	while [ $# -gt 0 ]; do
		local _adnr_dataVar="$1"; shift
		assertNotEmpty _adnr_dataVar
		local _adnr_dataValue="${!_adnr_dataVar}"
		_adnr_dataValue="${_adnr_dataValue// /%20}"
		_adnr_dataValue="${_adnr_dataValue//$'\n'/%0A}"
		_adnr_dataValue="${_adnr_dataValue//$'\r'/%0D}"
		_adnr_dataValue="${_adnr_dataValue//$'\t'/%09}"
		_adnr_dataValue="${_adnr_dataValue:---}"
		printf -v $_adnr_dataVar "%s" "$_adnr_dataValue"
	done
}


# usage: unescapeTokens [-q] <var1> [... <varN>]
# modifies the contents of each variable passed in to undo what escapeTokens did and return it to normal strings that could
# be empty and could contain whitespace
# Options:
#    -q : quotes. If the resulting string contains whitespace or is an empty string, surround it with quotes
function stringFromBashToken() { unescapeTokens "$@"; } # none left
function varUnescapeContents() { unescapeTokens "$@"; }
function unescapeTokens()
{
	local quotesFlag
	if [ "$1" == "-q" ]; then
		quotesFlag='"'
		shift
	fi

	while [ $# -gt 0 ]; do
		local _adnr_dataVar="$1"; shift
		assertNotEmpty _adnr_dataVar
		local _adnr_dataValue="${!_adnr_dataVar}"
		_adnr_dataValue="${_adnr_dataValue//%20/ }"
		_adnr_dataValue="${_adnr_dataValue//%0A/$'\n'}"
		_adnr_dataValue="${_adnr_dataValue//%0a/$'\n'}"
		_adnr_dataValue="${_adnr_dataValue//%0D/$'\r'}"
		_adnr_dataValue="${_adnr_dataValue//%0d/$'\r'}"
		_adnr_dataValue="${_adnr_dataValue//%09/$'\t'}"
		[ "$_adnr_dataValue" == -- ] && _adnr_dataValue=""

		local Q="$quotesFlag"; [ "$Q" ] && [[ ! "$_adnr_dataValue" =~ [[:space:]]|(^$) ]] && Q=""

		printf -v $_adnr_dataVar "%s%s%s"  "$Q" "$_adnr_dataValue" "$Q"
	done
}



# usage: returnValue [<opt>] <value> [<varRef>]
# usage: returnValue [<opt>] <value> [<varRef>] && return
# return a value from a function. If <varRef> is provided it is returned by assigning to it otherwise <value> is written to stdout.
#
# See discussion of naming conflicts and -n support in man(3) setReturnValue
#
# This facilitates a common pattern for returning a value from a function and letting the caller decide whether to return the
# data by passing in a variable to receive the returned value or by writing it to std out. Typically, <varRef> would be passed
# in an option or the last positional param that the caller could choose to leave blank
# Note that this is meant to mimic the builtin return command but allow specifying data to be returned, but unlike the builtin
# 'return' statement, calling this can not end the function execution so it is either the last statement in the function or
# should be immediately followed by 'return'
# Examples:
#    returnValue "$data" "$2"
#    returnValue --retArray "$data" "$2"; return
# Params:
#    <value> : this is the value being returned. By default it is treated as a simple string but that can be changed via options.
#    <varRef> : this is the name of the variable to return the value in. If its empty,'-' or '--', <value> is written to stdout
# Options:
#    --string : (default) treat <value> as a literal string
#    --retArray  : treat <value> as a name of an array variable. If <value> is an associative array then <varRef> must be one too
#    --strset : treat <value> as a string containing space separated array elements
#    -q       : quiet. if <varRef> is not given, do not print <value> to stdout
# See Also:
#   man(3) returnObject : which is similar to returnValue but with special handling for object references
#   man(3) varOutput
#   man(3) setReturnValue
#   local -n <variable> (for ubuntu 14.04 and beyond, bash supports reference variables)
function returnValue()
{
	# this high-use, low level function deliberately uses a different options pattern which is slightly more efficient
	local _rv_inType="string" _rv_outType="stdout" quietFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q)       quietFlag="-q" ;;
		--retArray)  _rv_inType="array"  ;;
		--string) _rv_inType="string" ;;
		--strset) _rv_inType="strset" ;;
		*) break ;;
	esac; shift; done

	[ "$2" ] && [ "${2}" != "-" ] && [ "${2}" != "--" ] && _rv_outType="var"

	[ "${quietFlag}" ] && [ "$_rv_outType" == "stdout" ] && return 0

	case $_rv_inType:$_rv_outType in
		array:var)     arrayCopy "$1" "$2" ;;
		array:stdout)
			# TODO: consider changing this to call pvPrArray directly -- what about objDictionary?
			printfVars "$1"
			#local _rv_refName="$1[*]"
			#printf         "%s\n" "${!_rv_refName}"
			;;
		string:var)    printf -v "$2" "%s"   "$1" ;;
		string:stdout) printf         "%s\n" "$1" ;;
		strset:var)    eval $2'=($1)' ;;
		strset:stdout) printf         "%s\n" "$1" ;;
		*) assertLogicError ;;
	esac
	true
}


# usage: varOutput [<options>] <value>[..<valueN>]
# output the <value> in a way that is controlled by <options>.
# This function has the semantics of "echo <value>" but an option can be added which redirects the output from stdout to assigning
# it to a variable in a variety of ways.
#
# Just like 'echo', a function can call outputValue multiple times to compose the final output. With outputValue, second and subsequent
# calls should be given the -a option so that they append to the output instead of replacing it.
#
# It is typical for a function to pass through options to outputValue so that its caller can decide how to receive the output.
# If all the options are supported, bgOptions_DoOutputVarOpts can be used to make it easier for the function author to support this
#
# This function is written so that if conflicting options are specified, the last one will take affect. This allows a function to
# change the default behavior and still allow the caller to have the final say.
#
# Options:
#    --echo               : (default behavior). echo <value> to stdout.
#    -R|--string=<retVar> : return Var. assign the remaining cmdline params into <varRef> as a single string
#    -A|--retArray=<retVar>  : arrayFlag. assign the remaining cmdline params into <varRef>[N]=$n as array elements.
#    -S*|--retSet=<retVar>   : setFlag. assign the remaining cmdline params into <varRef>[$n]="" as array indexes.
#    -a|--append : appendFlag. append to the existing value in <varRef> instead of overwriting it. Has no affect with --retSet or --echo
#    -d|--delim=<delim>   : This is the delimeter used between multiple <valueN> when the results are written to stdout or to a string.
#                           if --append is specified, it is also used between the existing value in <retVar> and the first <value1>.
#                           The <delim> Has no affect with --retArray or --retSet forms. The default is the first character of IFS.
#    -1                   : shortcut to set the delimiter to '\n' so that each <valueN> will be on a separate line.
#    +1                   : shortcut to set the delimiter to ' ' so that all the <valueN> will be on one line.
#    -f|--filters=<filters>: filters are a whitespace separated list of <value> that will be excluded from the output even if they
#                           appear on the cmdline. The motivation for this option comes from Object::getIndexes which often passes
#                           "${!_this[@]}" intom this function but we typically want to exclude '0' and '_Ref' and any other transient
#                           system member variables. Since varOutput needs to iterate the <value> list anyway, this saves functions
#                           like getIndexes from having to iterate and build a separate list from "${!_this[@]}"
# See Also:
#    man(3) returnValue # a simpler pattern when th eoutput is a scalar.
#    man(3) bgOptions_DoOutputVarOpts # helper function often used with outputValue
function outputValue() { varOutput "$@"; } # ALIAS:
function varOutput()
{
	if  [ "$bgCoreBuiltinIsInstalled" ]; then
		builtin bgCore $FUNCNAME "$@"
		return
	fi

	local _sr_appendFlag _sr_varType="--echo" _sr_varRef _sr_delim=${IFS:0:1} _sr_filters
	while [ $# -gt 0 ]; do case $1 in
		-1)                       _sr_delim=$'\n' ;;
		+1)                       _sr_delim=' ' ;;
		-a|--append)              _sr_appendFlag="-a" ;;
		+a|++append)              _sr_appendFlag="" ;;
		-R*|--string*|--retVar*)  _sr_varType="--string";   bgOptionGetOpt val: _sr_varRef "$@" && shift ;;
		-A*|--array*|--retArray*) _sr_varType="--retArray" ;   bgOptionGetOpt val: _sr_varRef "$@" && shift ;;
		-S*|--retSet*)            _sr_varType="--retSet";   bgOptionGetOpt val: _sr_varRef "$@" && shift ;;
		-e|--echo)                _sr_varType="--echo"  ;;
		-d*|--delim*)             bgOptionGetOpt val: _sr_delim "$@" && shift ;;
		-f*|--filters*)           bgOptionGetOpt val: _sr_filters "$@" && shift ;;
		--) shift; break ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# if filters were specified, remove them from the "$@" list. We do it this way because
	#   1) its much more common not to specify --filters so in that case the only extra work is checking if _sr_filters is not empty
	#   2) the rest of the code uses "$@" in multiple places so this way we dont have to apply the filter in multiple places
	if [ "$_sr_filters" ]; then
		local _sr_tempArgs=("$@")
		local _sr_i; for ((_sr_i=0; _sr_i<$#; _sr_i++)); do
			[[ " $_sr_filters " == *\ ${_sr_tempArgs[_sr_i]}\ * ]] && unset _sr_tempArgs[_sr_i]
		done
		set -- "${_sr_tempArgs[@]}"
	fi

	[ ! "$_sr_varRef" ] && [ "$_sr_varType" != "--echo" ] && return 0

	case ${_sr_varType:---string}:${_sr_appendFlag}:${_sr_delim} in
		--retSet:*)
			[ "$_sr_appendFlag" ] || { local -n _sr_varRefNR="$_sr_varRef"; _sr_varRefNR=(); }
			local i; for i in "$@"; do
				printf -v "$_sr_varRef[$i]" "%s" ""
			done
			;;

		# these use the -n syntax now because they used to use eval. If we need to be compaitble with older bashes, this will have
		# to change
		--retArray::*)   local -n __sr_varRef="$_sr_varRef" || assertError; __sr_varRef=("$@")   ;;
		--retArray:-a:*) local -n __sr_varRef="$_sr_varRef" || assertError; __sr_varRef+=("$@")  ;;

		--string::" ")   printf -v "$_sr_varRef" "%s" "$*" ;;
		--string:-a:" ") printf -v "$_sr_varRef" "%s%s%s" "${!_sr_varRef}" "${!_sr_varRef:+ }" "$*" ;;
		--string:*:*)
			[ "$_sr_appendFlag" ] || printf -v "$_sr_varRef" "%s" ""
			local _sr_sep="${!_sr_varRef:+$_sr_delim}"
			local i; for i in "$@"; do
				printf -v "$_sr_varRef" "%s%s%s" "${!_sr_varRef}" "$_sr_sep" "$i"
				_sr_sep=$_sr_delim
			done
			;;

		--echo:*:" ") echo "$*" ;;
		--echo:*:*)
			local _sr_sep=
			local i; for i in "$@"; do
				printf "%s%s" "$_sr_sep" "$i"
				_sr_sep=$_sr_delim
			done
			echo
			;;
	esac || assertError
	true
}

# usage: bgOptions_DoOutputVarOpts <retVar> <cmdLine...>
# this is used in the bgOptionsLoop of a function that accepts options that will be passed to the outputValue function to return
# the results of the function. This pattern allows the function author to write one function that supports returnning it results
# in a variety of ways that the the user of the function can choose with optional arguments when the function is called.
#
# Example:
#    function foo() {
#       local retOpts
#       while [ $# -gt 0 ]; do case $1 in
#           *)  bgOptions_DoOutputVarOpts retOpts "$@" && shift ;;&
#           *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
#       done
#       outputValue "${retOpts[@]}" one two three
#    }
#
# The outputValue function is written so that if conflicting options are specified, the last one will take affect. This allows a
# function to change the default behavior and still allow the caller to have the final say. In the above example, the outputValue
# line could be changed to ...
#       outputValue -1 "${retOpts[@]}" one two three
#       ... which makes it print each returned value on a seaparate line by default, but the caller can still specify the +1 option to
# change it back to the non -1 behavior.
#
# Options:
# These options will be supportted by a function that uses this pattern.
#    --echo               : (default behavior). echo <value> to stdout.
#    -R|--retVar=<retVar> : return Var. assign the remaining cmdline params into <varRef> as a single string
#    -A|--retArray=<retVar>  : arrayFlag. assign the remaining cmdline params into <varRef>[N]=$n as array elements.
#    -S*|--retSet=<retVar>   : setFlag. assign the remaining cmdline params into <varRef>[$n]="" as array indexes.
#    -a|--append : appendFlag. append to the existing value in <varRef> instead of overwriting it. Has no affect with --retSet or --echo
#    +a|++append : anti-appendFlag. undoes the -a option so that the value in <varRef> is overwritten. Has no affect with --retSet or --echo
#    -d|--delim=<delim>   : This is the delimeter used between multiple <valueN> when the results are written to stdout or to a string.
#                           if --append is specified, it is also used between the existing value in <retVar> and the first <value1>.
#                           The <delim> Has no affect with --retArray or --retSet forms. The default is the first character of IFS.
#    -1|+1                : set the delimiter to '\n' so that each <valueN> will be on a separate line.
function bgOptions_DoOutputVarOpts()
{
	local _do_retVar="$1"; shift
	case "$1" in
		[+-]1)            bgOptionHandled="1"; bgOptionGetOpt opt  "$_do_retVar" "$@" && return 0 ;;
		-a|--append)      bgOptionHandled="1"; bgOptionGetOpt opt  "$_do_retVar" "$@" && return 0 ;;
		+a|++append)      bgOptionHandled="1"; bgOptionGetOpt opt  "$_do_retVar" "$@" && return 0 ;;
		-R*|--string*|--retVar*)  bgOptionHandled="1"; bgOptionGetOpt opt: "$_do_retVar" "$@" && return 0 ;;
		-A*|--array*|--retArray*) bgOptionHandled="1"; bgOptionGetOpt opt: "$_do_retVar" "$@" && return 0 ;;
		-S*|--retSet*)            bgOptionHandled="1"; bgOptionGetOpt opt: "$_do_retVar" "$@" && return 0 ;;
		-e|--echo)        bgOptionHandled="1"; bgOptionGetOpt opt  "$_do_retVar" "$@" && return 0 ;;
		-d*|--delim*)     bgOptionHandled="1"; bgOptionGetOpt opt: "$_do_retVar" "$@" && return 0 ;;
		*) return 1 ;;
	esac
}


# usage: setReturnValue <varRef> <value>
# Assign a value to an output variable that was passed into a function. If the variable name is empty,
# do nothing.
#
# The name of this function is meant to make functions easier to read. Other functions might do
# the same thing but this one should be used when a function has multiple output params that it
# sets the values of. It replaces the cryptic [ "$varRef" ] && printf -v "$varRef" "%s" "$value"
# Note that after Ubuntu 12.04 support is dropped, consider local -n <varRef> instead
# Naming Conflicts:
# Note that bash does not have a notion of passing local scoped variables by reference so this technique
# is it literally pass the name of the variable in the callers scope and have the function set that variable.
# If the function declares the same variable name local, then this function will not work.
# A popular alternative to this technique is the upvar pattern but that requires some ugly syntax to use.
# In practice, I find that avoiding conflicting names is not that hard. Variable names tend to conflict
# because they resprent some common idea in both the calling scope and the called scope. The convention used
# in these libraries is that when a reference var is passed in, the local variable that holds that return
# var is suffixed with *Var and the local working variable for its value is suffixed with *Value. This eliminates
# most conflicts except for nested calls where the same variable is passed through multiple levels. When
# calling a function with a reference *Var,  the caller should be aware that if they use a variable that ends
# in *Var or *Value, it could be a problem. To further aid in the caller avoiding a conflict, the usage
# line of the function is visible in the man(3) page and function authors should use the actual *Var name
# in the usage description as is declared local in the function.
#
# For very general functions where the name of the passed in variable could really be anything and the
# caller should never have to worry about it, the convention is for the function to prefix all local
# variables with _<initials>_* where initials are the initials or other abreviation of the function name.
#
# No solution is ideal, but I find that this technique provides a good compromise of readable scripts
# and reliable scripts.
#
# See Also:
#   returnValue -- similar to this function but input order is reversed and if the return var is not set
#                  it writes it to stdout. i.e. returnValue mimics a function that always returns one value
#   local -n <variable> (for ubuntu 14.04 and beyond) allows direct manipulation of the varName
#   arrayCopy  -- does a similar thing for arrays (=)
#   arraryAdd  -- does a similar thing for array (+=)
#   stringJoin -- -a mode does similar but appends to the varName (+=)
#   varOutput
function setReturnValue()
{
	[ $# -ne 2 ] && assertError -v argCount:-l$# -v args:-l"$*" "invalid arguments. setReturnValue must be called with 2 parameters. Consider using varOutput"
	[ "${1:0:1}" == "-" ] && assertError "invalid option. setReturnValue does not accept any options"
	if [ "$1" ]; then
		varOutput -R "$@"
	fi
}

# usage: setExitCode <exitCode>
# set the exit code at the end of a code block -- particularly useful in trap code blocks
# typically you would use 'return <exitCode>' in a function and 'exit <exitCode>' in the main script
# but in a debug trap, you need to set the exit code to 0,1, or 2 but return is not valid in a trap
# and exit will exit the shell
function setExitCode()
{
	return $1
}



# usage: varDeRef <variableReference> [<retVar>]
# This returns the value contained in the variable refered to by <variableReference>
# The ${!var} syntax is generally used for this but that can not be used for arrays
# This is usefull for arrays where the the array name and index are typically separate. To use the
# ${!name} syntax, the variable name must have both the array and subscript (name="$arrayRef[indexVal]")
# The local -n ary=$arrayRef feature is better so this function is only usefull for code that still
# supports BASH without -n (ubuntu 12.04)
# Example:
#    local -A animalLegs=([dog]=4 [cat]=4 [monkey]=2 [snake]=0)
#    local myMapVar=animalLegs  # typically this is a variable passed to a function
#    deRef $myMapVar[dog]          # echos 4 to stdout
#    deRef $myMapVar[dog] legCnt   # sets legCnt to 4
function deRef() { varDeRef "$@"; }
function varDeRef()
{
	# the _dr_value assignment step is needed in case $1 contains [@] to prevent returnValue from seeing it as multiple params
	local _dr_value="${!1}"
	returnValue "$_dr_value" "$2"
}


# usage: varSet <varName> <value...>
# assigns <value...> to a simple (string) variable name
# See Also;
#   varSetAdd -- similar names but varSetAdd refers to the data structure 'Set' and this function refers to the verb 'to Set'
function varSet()
{
	local sr_varRef="$1"; shift
	[ ! "$sr_varRef" ] &&  return 1
	printf -v "$sr_varRef" "%s" "$*"
}

# usage: varGet <varName> [<retVar>]
# returns the value contained in the simple (string) <varName>. This is a wrapper over the ${!<varName>} syntax.  For simple
# variables that syntax is prefered but this function exists for completeness.
function varGet()
{
	local sr_varRef="$1"; shift
	[ ! "$sr_varRef" ] &&  return 1
	returnValue "${!sr_varRef}" $1
}


# usage: arrayToBashTokens <varName>
# modifies each element in the array so that it would be interpreted as exactly one bash token if subject to bash word splitting
# empty strings are replaced with '--' and whitespace in the strings are replaced with their %nn equivalent where nn is their two
# digit ascii hex code.
function arrayEscapeValues() { arrayToBashTokens "$@"; }
function arrayToBashTokens()
{
	local -a aa_keys='("${!'"$1"'[@]}")'
	local aa_key; for aa_key in "${aa_keys[@]}"; do
		escapeTokens "${1}[$aa_key]"
	done
}


# usage: arrayFromBashTokens <varName>
# modifies each element in the array to undo what arrayToBashTokens did and return it to normal strings that could be empty and
# could contain whitespace
function arrayUnEscapeValues() { arrayFromBashTokens "$@"; }
function arrayFromBashTokens()
{
	local -a aa_keys='("${!'"$1"'[@]}")'
	local aa_key; for aa_key in "${aa_keys[@]}"; do
		unescapeTokens "${1}[$aa_key]"
	done
}

# usage: arraySet <varName> <index> <value>
# sets the array element like <varName>[<index>]=<value>
function arraySet()
{
	local aa_varRef="$1[$2]"; shift 2
	printf -v "$aa_varRef" "%s" "$*"
}

# usage: arrayGet <varName> <index> [<retVar>]
# returns the array element like ${<varName>[<index>]}
function arrayGet()
{
	local aa_varRef="$1[$2]"; shift 2
	returnValue "${!aa_varRef}" $1
}

# usage: arrayExistsAt <varName> <index>
# the exit code reflects whether element <index> exists in <varName>
function arrayExistsAt()
{
	[[ ! "$2" =~ ^[+-]?[0-9]*$ ]] && ! varIsA mapArray "$1" && return 1
	local aa_varRef="$1[$2]"; shift 2
	[ "${!aa_varRef+exists}" ]
}

# usage: arrayPush <varName> <value...>
# grows the array by 1 setting the new element's value
function arrayPush()
{
	local aa_varRef="$1"; shift
	varOutput -a --retArray "$aa_varRef" "$*"
}

# usage: arrayPop <varName> <retVar>
# remove the last element and return its value
function arrayPop()
{
	local -n aa_varRef; aa_varRef="$1" || assertError -v varName:aa_varRef "varName is invalid. can not create reference"; shift
	local aa_value="${aa_varRef[@]: -1}"
	aa_varRef=("${aa_varRef[@]: 0 : ${#aa_varRef[@]}-1}")
	returnValue "$aa_value" $1
}

# usage: arrayShift <varName> <value...>
# grows the array by inserting <value> at the start
function arrayShift()
{
	local -n aa_varRef; aa_varRef="$1" || assertError -v varName:aa_varRef "varName is invalid. can not create reference"; shift
	aa_varRef=("$@" "${aa_varRef[@]}")
}

# usage: arrayUnshift <varName> <retVar>
# remove the first element and return its value
function arrayUnshift()
{
	local -n aa_varRef; aa_varRef="$1" || assertError -v varName:aa_varRef "varName is invalid. can not create reference"; shift
	local aa_value="${aa_varRef[@]:0:1}"
	aa_varRef=("${aa_varRef[@]:1}")
	returnValue "$aa_value" $1
}

# usage: arrayFind <varName> <value> [<retVar>]
function arrayFind()
{
	local -n aa_varRef; aa_varRef="$1" || assertError -v varName:aa_varRef "varName is invalid. can not create reference"; shift
	local _i; for _i in "${!aa_varRef[@]}"; do
		if [ "${aa_varRef[$_i]}" == "$2" ]; then
			returnValue "$_i" "$3"
		fi
	done
}

# usage: arrayDelete <varName> <value>
# remove a value from a numeric array
function arrayDelete()
{
	local -n aa_varRef; aa_varRef="$1" || assertError -v varName:aa_varRef "varName is invalid. can not create reference"
	local _i; for _i in "${!aa_varRef[@]}"; do
		if [ "${aa_varRef[$_i]}" == "$2" ]; then
			unset aa_varRef[$_i]
		fi
	done
	# re-index so that they are consequetive
	aa_varRef=("${aa_varRef[@]}")
}


# usage: arrayClear <varName>
function arrayClear()
{
	local -n aa_varRef; aa_varRef="$1" || assertError -v varName:aa_varRef "varName is invalid. can not create reference"; shift
	aa_varRef=();
}

# usage: arraySize <varName> [<retVar>]
# returns the number of elements
function arraySize()
{
	local -n aa_varRef; aa_varRef="$1" || assertError -v varName:aa_varRef "varName is invalid. can not create reference"; shift
	returnValue "${#aa_varRef[@]}" $1
}


# usage: setAdd <setVarName> <key> [...<keyN>]
# part of a family of functions that use the keys of an associateive array as a Set data structure
# Example:
#    local -A mySet
#    setAdd mySet dog
#    setHas mySet dog && echo "this should print"
#    setHas mySet car && echo "this should not print"
#    setDelete mySet dog
#    setHas mySet dog && echo "now this wont print either b/c dog gone"
function varSetAdd() { setAdd "$@"; }
function setAdd()
{
	local sr_varRef="$1"; shift
	[ ! "$sr_varRef" ] &&  return 1

	while [ $# -gt 0 ]; do
		printf -v "$sr_varRef["${1:-emtptKey}"]" "%s" "1"
		shift
	done
}

# usage: setHas <setVarName> <key>
# part of a family of functions that use the keys of an associateive array as a Set data structure
# Example:
#    local -A mySet
#    setAdd mySet dog
#    setHas mySet dog && echo "this should print"
#    setHas mySet car && echo "this should not print"
#    setDelete mySet dog
#    setHas mySet dog && echo "now this wont print either b/c dog gone"
function varSetHas() { setHas "$@"; }
function setHas()
{
	local sr_varRef="$1"
	local sr_key="${2:-emtptKey}"
	[ ! "$sr_varRef" ] &&  return 1
	local sr_tmpname="$sr_varRef[$sr_key]"
	[ "${!sr_tmpname+exists}" ]
}

# usage: setDelete <setVarName> <key> [..<keyN>]
# part of a family of functions that use the keys of an associateive array as a Set data structure
# Example:
#    local -A mySet
#    setAdd mySet dog
#    setHas mySet dog && echo "this should print"
#    setHas mySet car && echo "this should not print"
#    setDelete mySet dog
#    setHas mySet dog && echo "now this wont print either b/c dog gone"
function varSetDelete() { setDelete "$@"; }
function setDelete()
{
	local sr_varRef="$1"; shift
	[ ! "$sr_varRef" ] &&  return 1
	while [ $# -gt 0 ]; do
		local sr_key="${1:-emtptKey}"; shift
		local sr_tmpname="$sr_varRef[$sr_key]"
		unset "$sr_tmpname"
	done
}

# usage: setClear <setVarName>
# part of a family of functions that use the keys of an associateive array as a Set data structure
# Example:
#    local -A mySet
#    setAdd mySet dog
#    setHas mySet dog && echo "this should print"
#    setHas mySet car && echo "this should not print"
#    setDelete mySet dog
#    setHas mySet dog && echo "now this wont print either b/c dog gone"
function varSetClear() { setClear "$@"; }
function setClear()
{
	arrayClear "$@"
}

# usage: setClear <setVarName>
# part of a family of functions that use the keys of an associateive array as a Set data structure
# Example:
#    local -A mySet
#    setAdd mySet dog
#    setHas mySet dog && echo "this should print"
#    setHas mySet car && echo "this should not print"
#    setDelete mySet dog
#    setHas mySet dog && echo "now this wont print either b/c dog gone"
function varSetSize() { setSize "$@"; }
function setSize()
{
	arraySize "$@"
}



# usage: mapSet <mapVarName> <key> <value...>
function varMapSet() { mapSet "$@"; }
function mapSet() {
	local separatorChar appendFlag
	while [ $# -gt 0 ]; do case $1 in
		-a|--append)  appendFlag="-a" ;;
		-d*) bgOptionGetOpt val: separatorChar "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local sr_varRef="$1"; shift
	local sr_key="${1:-emtptKey}"; shift
	[ ! "$sr_varRef" ] &&  return 1
	local sr_mapDeref="$sr_varRef[$sr_key]"
	if [ "$appendFlag" ]; then
		printf -v "$sr_mapDeref" "%s%s%s" "${!sr_mapDeref}" "${!sr_mapDeref:+$separatorChar}" "$*"
	else
		printf -v "$sr_mapDeref" "%s" "$*"
	fi
}

# usage: mapGet <mapVarName> <key> [<retVar>]
function varMapGet() { mapGet "$@"; }
function mapGet() {
	local sr_varRef="$1"
	local sr_key="${2:-emtptKey}"
	[ ! "$sr_varRef" ] &&  return 1
	varDeRef "$sr_varRef[$sr_key]" "$3"
}

# usage: mapGetValues  [<outputValueOptions>] <mapVarName>
function varMapGetValues() { mapGetValues "$@"; }
function mapGetValues() {
	local retOpts
	while [ $# -gt 0 ]; do case $1 in
		*)  bgOptions_DoOutputVarOpts retOpts "$@" && shift ;;&
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local sr_tmpname="$1[@]"
	outputValue "${retOpts[@]}"  "${!sr_tmpname}"
}

# usage: mapGetKeys  [<outputValueOptions>] <mapVarName>
function varMapGetKeys() { mapGetKeys "$@"; }
function mapGetKeys() {
	local retOpts
	while [ $# -gt 0 ]; do case $1 in
		*)  bgOptions_DoOutputVarOpts retOpts "$@" && shift ;;&
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	# SECURITY: the varExists line is meant to prevent ACE in the eval
	varExists "$1" || assertError
	eval 'outputValue "${retOpts[@]}"  "${!'"$1"'[@]}"'
}


# usage: mapDelete <mapVarName> <key>
function varMapDelete() { mapDelete "$@"; }
function mapDelete() {
	local sr_varRef="$1"
	local sr_key="${2:-emtptKey}"
	[ ! "$sr_varRef" ] &&  return 1
	unset "$sr_varRef[$sr_key]"
}

# usage: mapClear <mapVarName>
function varMapClear() { mapClear "$@"; }
function mapClear()
{
	arrayClear "$@"
}

function varMapSize() { mapSize "$@"; }
function mapSize()
{
	arraySize "$@"
}


# usage: varToggle <variable> <value1> <value2>
# This returns <value1> or <value2> on stdout depending on the current value in <varToggle>
function varToggle()
{
	local vtr_variable="$1"
	local vtr_value1="$2"
	local vtr_value2="$3"
	if [ "${vtr_variable}" != "$vtr_value1" ]; then
		echo "$vtr_value1"
	else
		echo "$vtr_value2"
	fi
}

# usage: varToggleRef <variableRef> <value1> <value2>
# This sets the <optVariableRef> with <value1> or <value2> depending on if the current value is not <value1>
# Each time it is called, the value will toggle/alternate between the two values
function varToggleRef()
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


# usage: varGenVarname  [-t|--template=<templateStr>] [-l|--length=<n>] [-c|--charClass=<n>] <varName>
# Create a random id (aka name) quickly. The first character will always be 'a' so that using
# the alnum ch class the result is valid for names that can not start with a number
# Params:
#    <varName>  : the name of the variable that the result will be returned in. if "", the result is written to stdout
# Options:
#    -t|--template=<templateStr>  : a string similar to that used by mktemp. It needs to have one contiguous run of X's that will be
#                                   replaced by random chars
#    -l|--length=<n>  : the length of the returned <varName>. Ignored if --template is provided
#    -c|--charClass=<n>  : the characters that will be used in the <varName>. The string is the syntaxt that can be inside regex []
#                        e.g. 'a-z' '[:xdigit:]'  'abc[:digit:]', etc...
function genRandomIDRef() { varGenVarname "$@"; }
function genRandomID() { varGenVarname "$@"; }
function varGenVarname()
{
	local _template _length _charClass
	while [ $# -gt 0 ]; do case $1 in
		-t*|--template*)  bgOptionGetOpt val: _template  "$@" && shift ;;
		-l*|--length*)    bgOptionGetOpt val: _length    "$@" && shift ;;
		-c*|--charClass*) bgOptionGetOpt val: _charClass "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local resultVarName="$1"

	_length="${_length:-${2:-9}}"
	# note the character classes like :alnum: are faster but alnum was sometimes returning chars that are not valid bash variable names
	# the LC_ALL=C should fix that but not sure if it does so to be conservative, we make the default "0-9a-zA-Z"
	local _charClass="${_charClass:-${3:-0-9a-zA-Z}}"

	if [ "$_template" ]; then
		local xes="${_template//[^X]}"
		_length=${#xes}
	else
		((_length--))
	fi

	declare -gA __varGenVarname_randomBuffer
	while [ ${#__varGenVarname_randomBuffer[$_charClass]} -lt $_length ]; do
		local chunk; read -t1 -N20 chunk </dev/urandom
		LC_ALL=C __varGenVarname_randomBuffer[$_charClass]+="${chunk//[^$_charClass]}"
	done

	local _randoValue="${__varGenVarname_randomBuffer[$_charClass]:0:$_length}"
	__varGenVarname_randomBuffer[$_charClass]="${__varGenVarname_randomBuffer[$_charClass]:$_length}"

	if [ "$_template" ]; then
		returnValue "${_template/$xes/$_randoValue}" $resultVarName
	else
		returnValue "a${_randoValue}" $resultVarName
	fi
}




# usage: printfTable [--horizontal] <colVar1>[..<colVarN>]
# given a list of array valriable names, print a table. The variable names are the columns of the table. The union of all keys/indexes
# are the rows of the table. Each cell is the value of the array variable from that column subscripted with the index from that row.
# If ColName[RowName] does not exist (including the case where ColName is a numeric array and RowName is an alpha-numeric word),
# the cell willl contain '<unset>'
# Prarms:
#    <colVarN>  : the name of an array variable to include in the table. It can any type of bash variable. Scalar vars are treated
#                 like a numeric array with a single index [0]
# Options:
#    --horizontal  : transpose the table so that variable names will be the rows and indexes will be the columns
function printfTable()
{
	local _ptOrientation="vert"
	while [ $# -gt 0 ]; do case $1 in
		--horizontal) _ptOrientation="hor" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local _ptColList=("$@")

	local _ptCol _ptTblLength=0 _ptType
	local -A _ptRows
	for _ptCol in "${_ptColList[@]}"; do
		local _ptSize; arraySize "$_ptCol" _ptSize
		((_ptTblLength = (_ptTblLength>_ptSize) ? (_ptTblLength) : (_ptSize) ))
		if varIsA mapArray "$_ptCol"; then
			mapGetKeys -a -S _ptRows "$_ptCol"
			[ "$_ptType" == "numArray" ] && _ptType="mixed"
			_ptType="${_ptType:-mapArray}"
		elif varIsA numArray "$_ptCol"; then
			mapGetKeys -a -S _ptRows "$_ptCol"
			[ "$_ptType" == "mapArray" ] && _ptType="mixed"
			_ptType="${_ptType:-numArray}"
		else
			_ptRows[0]=
		fi
	done

	# get the _ptRowList. If all the vars are numeric arrays, make sure that they are in order
	local _ptRowList
	if [ "$_ptType" == "numArray" ]; then
		local _ptI; for ((_ptI=0; _ptI<_ptTblLength; _ptI++)); do
			if [ "${_ptRows[$_ptI]+exists}" ]; then
				unset _ptRows[$_ptI]
				_ptRowList+=($_ptI)
			fi
		done
		_ptRowList+=("${!_ptRows[@]}")
	else
		_ptRowList=("${!_ptRows[@]}")
	fi

	if [ "$_ptOrientation" == 'vert' ]; then
		{
			local _ptValue
			echo "_ | ${_ptColList[*]}"
			local _ptRow; for _ptRow in "${_ptRowList[@]}"; do
				_ptValue="$_ptRow"
				escapeTokens _ptValue
				echo -n "[$_ptValue] | "
				for _ptCol in "${_ptColList[@]}"; do
					_ptValue="<unset>"
					if arrayExistsAt  "$_ptCol" "$_ptRow"; then
						arrayGet "$_ptCol" "$_ptRow" _ptValue
						escapeTokens _ptValue
					fi
					echo -n "$_ptValue "
				done
				echo
			done
		} | column -e -t | gawk 'NR==1 {print gensub(/^_/," ","g"); next}   NR==2 {print gensub(/./,"-","g")} {print $0}'

	else
		{
			local _ptValue
			echo -n "_ | "
			local _ptRow; for _ptRow in "${_ptRowList[@]}"; do
				_ptValue="$_ptRow"
				escapeTokens _ptValue
				echo -n "[$_ptValue] "
			done
			echo

			for _ptCol in "${_ptColList[@]}"; do
				echo -n "$_ptCol | "
				local _ptRow; for _ptRow in "${_ptRowList[@]}"; do
					_ptValue="<unset>"
					if arrayExistsAt  "$_ptCol" "$_ptRow"; then
						arrayGet "$_ptCol" "$_ptRow" _ptValue
						escapeTokens _ptValue
					fi
					echo -n "$_ptValue "
				done
				echo
			done
		} | column -e -t | gawk 'NR==1 {print gensub(/^_/," ","g"); next}   NR==2 {print gensub(/./,"-","g")} {print $0}'
	fi
}
