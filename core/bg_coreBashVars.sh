#!/bin/bash


# Library bg_coreBashVars.sh
####################################################################################################################
### Functions to work with bash variables of various types
# This library provides functions to work with bash variables in an intuitive way. Some of them are aliases for bash syntax
# or common idioms that are cryptic so that they are more easiely discovered.
#
# This library also has functions that treat built in bash variables as higher level types like Sest and Maps.
#
# See Also:
#     printfVars  : (core function) detect the types of the variable names passed in and print their names and values in a nice format.
#     varExists   : (core function) true if the name refers to an existing bash variable in scope
#     varIsA      : (core function) true if the name referes to a bash variable of the specified type
#     returnValue : (core function) return a single value from a function either on stdout or in a retVar if one was passed in
#     setReturnValue : (core function) optionally set the value if a parameter passed by reference if its not empty.
#     varSetRef   : (core function) set the value of a reference variable (name)
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

	if [[ "$_attributes" =~ [aA] ]]; then
		local _initialData="("
		while [ $# -gt 0 ]; do
			if [[ "$1" =~ ^\s*\[([^]]*)\]=(.*)$ ]]; then
				_initialData+="['${BASH_REMATCH[1]}']='${BASH_REMATCH[2]}' "; shift
			else
				_initialData+="'$1' "; shift
			fi
		done
		_initialData+=")"
	else
		local _initialData="$*"
	fi

	_template="heap_${_attributes:-S}_${_template#heap_}"
	[[ ! "$_template" =~ X ]] && _template+="_XXXXXXXXX"

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
	# the -p option prints the declaration of the variables named in "$@".
	# we throw away all output but its return value will indicate whether it succeeded in finding all the variables
	declare -p "$@" &>/dev/null
}

# usage: varGetAttributes <varName> [<retVar>]
# returns the attributes that are set for <varName>.
#   '-'  If <varName> exists but has none set, '-' is returned.
#   ''   If <varName> does not exist as a variable, "" is returned
# Indexed Variables:
# Indexed variables are array references like foo[idx].
# If the array part does not exist or idx is not an index in the array "" is returned to indicate that the variable does not exist.
# If the idx entry does exist, the attributes of the array are returned with 'A' and 'a' removed (because the indexed var is not an
# array). If 'A' or 'a' are the only attribute, then '-' is returned to indicate that it exists but have no attribute set.
# Params:
#    <varName> : can be a direct variable name or an indexed name like foo[idx].
#
# See Also:
#    ${<varName>@a}
function varGetAttributes()
{
	local ret

	# this is no faster than the declare method below (even in cases where eval is not needed)
	#eval ret='${'"$1"'@a}'

	# normal vars
	if [[ "$1" =~ ^[a-zA-Z0-9_]*$ ]]; then
		local _gaGeclaration="$(declare -p "$1" 2>/dev/null)"
		ret="${_gaGeclaration#declare -}"
		ret="${ret%% *}"

		if [[ "$ret" =~ n ]]; then
			if [[ "$_gaGeclaration" =~ -n\ [^=]*=\"([^\"]*)\" ]]; then
				local _gaRefName="${BASH_REMATCH[1]}"
				varGetAttributes "$_gaRefName" "$2"
				return
			fi
		fi

	# foo[idx]
	elif [[ "$1" =~ ^[]a-zA-Z0-9_[]*$ ]]; then
		eval '[ "${'"$1"'+exists}" ] && ret="-"'
		if [ "$ret" ]; then
			local idxRet; varGetAttributes "${1%%\[*}" idxRet
			ret="${idxRet//[aA]}"
			ret="${ret:--}"
		fi
	fi

	returnValue "$ret" "$2"
}

# usage: varIsA <type1> [.. <typeN>] <varName>
# returns true(0) if the var specified on the cmd line exits as a variable with the specified attributes
# Note that if a variable is declared without assignment, (like local -A foo) this function
# will report false until something is assigned to it.
# Options:
#    mapArray : (default) test if <varName> is an associative array
#    numArray : test if <varName> is a numeric array
#    array    : test if <varName> is either type of array
#    anyOfThese=<attribs> : example anyOfThese=Aa to test if <varName> is either an associative or numeric array
#    allOfThese=<attribs> : example allOfThese=rx to test if <varName> is both readonly and exported
function varIsAMapArray() { varIsA mapArray "$@"; }
function varIsA()
{
	local anyAttribs mustAttribs
	while [ $# -gt 1 ]; do case $1 in
		mapArray|-A) anyAttribs+="A" ;;
		numArray|-a) anyAttribs+="a" ;;
		array)       anyAttribs+="Aa" ;;
		anyOfThese*) bgOptionGetOpt val: anyAttribs  "--$1" "$2" && shift ;;
		allOfThese*) bgOptionGetOpt val: mustAttribs "--$1" "$2" && shift ;;
	esac; shift; done

	[ ! "$1" ] && return 1

	# the -p option prints the declaration of the variable named in "$1".
	# if the output matches "declare -A" then its an associative array
	local vima_typeDef="$(declare -p "$1" 2>/dev/null)"

	# if its a referenece (-n) var, get the reference of the var that it points to
	if [[ "$vima_typeDef" =~ -n\ [^=]*=\"(.*)\" ]]; then
		local vima_refVar="${BASH_REMATCH[1]}"
		[[ "$anyAttribs" =~ n ]] && return 0
		vima_typeDef="$(declare -p "$vima_refVar" 2>/dev/null)"
	else
		[[ "$mustAttribs" =~ n ]] && return 1
	fi

	[[ "$vima_typeDef" =~ declare\ -[^\ ]*[$anyAttribs] ]] || return 1

	local i; for ((i=0; i<${#mustAttribs}; i++)); do
		[[ "$vima_typeDef" =~ declare\ -[^\ ]*${mustAttribs:$i:1} ]] || return 1
	done
	return 0
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
		i) declare -gi $vima_varName; setRef "$vima_varName" "${vima_marshalledData//\\n/$'\n'}" ;;
		\#) declare -g $vima_varName; setRef "$vima_varName" "${vima_marshalledData//\\n/$'\n'}" ;;
		*) assertError -v data:"$1" -v type:vima_type -v varName:vima_varName "unknown type in marshalled data. The first character should be one on 'Aai-', followed immediately by the <varName> then a single space then arbitrary data" ;;
	esac
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
#    returnValue --array "$data" "$2"; return
# Params:
#    <value> : this is the value being returned. By default it is treated as a simple string but that can be changed via options.
#    <varRef> : this is the name of the variable to return the value in. If its empty, <value> is written to stdout
# Options:
#    --string : (default) treat <value> as a literal string
#    --array  : treat <value> as a name of an array variable. If <value> is an associative array then <varRef> must be one too
#    --strset : treat <value> as a string containing space separated array elements
#    -q       : quiet. if <varRef> is not given, do not print <value> to stdout
# See Also:
#   man(3) varSetRef
#   man(3) varOutput
#   man(3) setReturnValue
#   local -n <variable> (for ubuntu 14.04 and beyond, bash supports reference variables)
function returnValue()
{
	local _rv_inType="string" _rv_outType="stdout" quietFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q)       quietFlag="-q" ;;
		--array)  _rv_inType="array"  ;;
		--string) _rv_inType="string" ;;
		--strset) _rv_inType="strset" ;;
		*) break ;;
	esac; shift; done
	[ "$2" ] && _rv_outType="var"
	[ "$quietFlag" ] && [ "$_rv_outType" == "stdout" ] && return 0

	case $_rv_inType:$_rv_outType in
		array:var)     arrayCopy "$1" "$2" ;;
		array:stdout)
			printfVars "$1"
			#local _rv_refName="$1[*]"
			#printf         "%s\n" "${!_rv_refName}"
			;;
		string:var)    printf -v "$2" "%s"   "$1" ;;
		string:stdout) printf         "%s\n" "$1" ;;
		strset:var)    eval $2'=($1)' ;;
		strset:stdout) printf         "%s\n" "$1" ;;
	esac
	true
}


# usage: varOutput [<options>] <value>[..<valueN>]
# output the <value> in a way that is controlled by <options>. This is similar to varSetRef but the call syntax is different.
# This function has the semantics of "echo <value>" but an option can redirect the output from stdout to assigning it to <retVar>
#
# Options:
#    -R|--string=<retVar> : return Var. assign the remaining cmdline params into <varRef> as a single string
#    -A|--array=<retVar>  : arrayFlag. assign the remaining cmdline params into <varRef>[N]=$n as array elements.
#    -S*|--set=<retVar>   : setFlag. assign the remaining cmdline params into <varRef>[$n]="" as array indexes.
#    --echo               : (default behavior). echo <value> to stdout.
#    -a|--append : appendFlag. append to the existing value in <varRef> instead of overwriting it. Has no affect with --set or --echo
#    -d|--delim=<delim>   : default is the first character of IFS. This is the delimeter used between multiple <valueN> and between
#                           the first <value1> and the existing value in <retVar> if --append is specified.  Has no affect with
#                           --array or --set.
# See Also:
#    man(3) varSetRef
#    man(3) returnValue
function outputValue() { varOutput "$@"; } # ALIAS:
function varOutput()
{
	local _sr_appendFlag _sr_varType="--echo" _sr_varRef _sr_delim=${IFS:0:1}
	while [ $# -gt 0 ]; do case $1 in
		+1)               _sr_delim=$'\n' ;;
		-a|--append)      _sr_appendFlag="-a" ;;
		-R*|--string*)    _sr_varType="--string";   bgOptionGetOpt val: _sr_varRef "$@" && shift ;;
		-A*|--array*)     _sr_varType="--array" ;   bgOptionGetOpt val: _sr_varRef "$@" && shift ;;
		-S*|--set*)       _sr_varType="--set"   ;   bgOptionGetOpt val: _sr_varRef "$@" && shift ;;
		-e|--echo)        _sr_varType="--echo"  ;;
		-d*|--delim*)     bgOptionGetOpt val: _sr_delim "$@" && shift ;;
		--) shift; break ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	[ ! "$_sr_varRef" ] && [ "$_sr_varType" != "--echo" ] && return 0

	case ${_sr_varType:---string}:${_sr_appendFlag}:${_sr_delim} in
		--set:*)
			[ "$_sr_appendFlag" ] || { local -n _sr_varRefNR="$_sr_varRef"; _sr_varRefNR=(); }
			local i; for i in "$@"; do
				printf -v "$_sr_varRef[$i]" "%s" ""
			done
			;;

		# these use the -n syntax now because they used to use eval. If we need to be compaitble with older bashes, this will have
		# to change
		--array::*)   local -n __sr_varRef="$_sr_varRef"; __sr_varRef=("$@") ;;
		--array:-a:*) local -n __sr_varRef="$_sr_varRef"; __sr_varRef+=("$@") ;;

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
# Options:
#    -a|--append : appendFlag. append the string or array value
#    --array     : arrayFlag. assign the remaining cmdline params into <varRef>[N] as array elements.
#                  W/o -a it replaces existing elements.
# See Also:
#   returnValue -- similar to this function but input order is reversed and if the return var is not set
#                  it writes it to stdout. i.e. returnValue mimics a function that always returns one value
#   local -n <variable> (for ubuntu 14.04 and beyond) allows direct manipulation of the varName
#   arrayCopy  -- does a similar thing for arrays (=)
#   arraryAdd  -- does a similar thing for array (+=)
#   stringJoin -- -a mode does similar but appends to the varName (+=)
#   varSetRef (aka setRef)
function setReturnValue()
{
	varSetRef "$@"
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


# usage: varSetRef [-a] [--array|--set] <varRef> <value...>
# See http://mywiki.wooledge.org/BashFAQ/048#line-120 for a discussion of why varRefs are problematic.
# This sets the <varRef> with <value> only if it is not empty.
# Note that this is an alternative using local -n varName. Each have tradeoffs.
# Equivalent Statements:
#    varSetRef            foo 42 yo    becomes=>  foo="42 yo"
#    varSetRef --array    foo 42 yo    becomes=>  foo=(42 yo)
#    varSetRef -a         foo 42 yo    becomes=>  foo+="42 yo"
#    varSetRef --array -a foo 42 yo    becomes=>  foo+=(42 yo)
#    varSetRef --set      foo 42 yo    becomes=>  foo+=("42 yo")
#    varSetRef --echo     foo 42 yo    becomes=>  echo "42 yo"
# Options:
#    -a|--append : appendFlag. append to the existing value in <varRef> instead of overwriting it. Has no effect with --set or --echo
#    --array     : arrayFlag. assign the remaining cmdline params into <varRef>[N] as array elements.
#                  W/o -a it replaces existing elements.
#    --set       : setFlag. assign the remaining cmdline params into <varRef>[$n]="" as array indexes.
#    --echo      : dont assign to foo. Instead, echo to stdout. This supports functions that may return in a variable or may write to stdout
#
# See Also:
#   man(3) varOutput
#   man(3) setReturnValue
#   man(3) returnValue
#   local -n <variable>=<varRef> (for ubuntu 14.04 and beyond) allows direct manipulation of the varRef
#   arrayCopy  -- does a similar thing for two arrays (<varRef>=(<varRef2>))
#   arraryAdd  -- does a similar thing for two arrays (<varRef>+=(<varRef2>))
#   stringJoin -- -a mode does similar but also adds a separator
#   http://mywiki.wooledge.org/BashFAQ/048#line-120
#   https://wiki.bash-hackers.org/scripting/bashchanges?s[]=versions
#   https://wiki.bash-hackers.org/internals/shell_options
function setRef() { varSetRef "$@"; }
function varSetRef()
{
	local _sr_appendFlag _sr_varType
	while [[ "$1" =~ ^- ]]; do case $1 in
		-a|--append) _sr_appendFlag="-a" ;;
		--string)    _sr_varType="--string" ;;
		--array)     _sr_varType="--array" ;;
		--set)       _sr_varType="--set" ;;
		--echo)      _sr_varType="--echo" ;;
	esac; shift; done
	local sr_varRef="$1"; shift

	[ ! "$sr_varRef" ] && [ "$_sr_varType" != "--echo" ] && return 0

	case ${_sr_varType:---string}:$_sr_appendFlag in
		--set:*)
			while [ $# -gt 0 ]; do
				printf -v "$sr_varRef[$1]" "%s" ""
				shift
			done
			;;

		# these use the -n syntax now because they used to use eval. If we need to be compaitble with older bashes, this will have
		# to change
		--array:)    local -n _sr_varRef="$sr_varRef"; _sr_varRef=("$@")  ;;
		--array:-a)  local -n _sr_varRef="$sr_varRef"; _sr_varRef+=("$@") ;;

		--string:)   printf -v "$sr_varRef" "%s" "$*" ;;
		--string:-a) printf -v "$sr_varRef" "%s%s" "${!sr_varRef}" "$*" ;;

		--echo:*) echo "$*" ;;
	esac || assertError
	true
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
function arrayToBashTokens()
{
	local -a aa_keys='("${!'"$1"'[@]}")'
	local aa_key; for aa_key in "${aa_keys[@]}"; do
		stringToBashToken "${1}[$aa_key]"
	done
}

# usage: arrayFromBashTokens <varName>
# modifies each element in the array to undo what arrayToBashTokens did and return it to normal strings that could be empty and
# could contain whitespace
function arrayFromBashTokens()
{
	local -a aa_keys='("${!'"$1"'[@]}")'
	local aa_key; for aa_key in "${aa_keys[@]}"; do
		stringFromBashToken "${1}[$aa_key]"
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

# usage: arrayPush <varName> <value...>
# grows the array by 1 setting the new element's value
function arrayPush()
{
	local aa_varRef="$1"; shift
	varSetRef -a --array "$aa_varRef" "$*"
}

# usage: arrayPop <varName> <retVar>
# remove the last element and return its value
function arrayPop()
{
	local -n aa_varRef="$1"; shift
	local aa_value="${aa_varRef[@]: -1}"
	aa_varRef=("${aa_varRef[@]: 0 : ${#aa_varRef[@]}-1}")
	returnValue "$aa_value" $1
}

# usage: arrayShift <varName> <value...>
# grows the array by inserting <value> at the start
function arrayShift()
{
	local -n aa_varRef="$1"; shift
	aa_varRef=("$@" "${aa_varRef[@]}")
}

# usage: arrayUnshift <varName> <retVar>
# remove the first element and return its value
function arrayUnshift()
{
	local -n aa_varRef="$1"; shift
	local aa_value="${aa_varRef[@]:0:1}"
	aa_varRef=("${aa_varRef[@]:1}")
	returnValue "$aa_value" $1
}

# usage: arrayClear <varName>
function arrayClear()
{
	local -n aa_varRef="$1"; shift
	aa_varRef=();
}

# usage: arraySize <varName> [<retVar>]
# returns the number of elements
function arraySize()
{
	local -n aa_varRef="$1"; shift
	returnValue "${#aa_varRef[@]}" $1
}


# usage: setAdd <setVarName> <key> [...<keyN>]
# uses the keys of an associateive array as a Set data structure
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
# uses the keys of an associateive array as a Set data structure
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

# usage: setDelete <setVarName> <key>
# uses the keys of an associateive array as a Set data structure
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
	local sr_varRef="$1"
	local sr_key="${2:-emtptKey}"
	[ ! "$sr_varRef" ] &&  return 1
	local sr_tmpname="$sr_varRef[$sr_key]"
	unset "$sr_tmpname"
}

# usage: setClear <setVarName>
# uses the keys of an associateive array as a Set data structure
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
# uses the keys of an associateive array as a Set data structure
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


# usage: printfVars [ <varSpec1> ... <varSpecN> ]
# print a list of variable specifications to stdout
# This is used by the bgtraceVars debug command but its also useful for various formatted text output
# Unlike most function, options can appear anywhere and options with a value can not have a space between opt and value.
# options only effect the variables after it
# Params:
#   <varSpecN> : a variable name to print or an option. It formats differently based on what it is
#        not a variable  : simply prints the content of <dataN>. prefix it with -l to make make its not interpretted as a var name
#        simple variable : prints <varName>='<value>'
#        array variable  : prints <varName>[]
#                                 <varName>[idx1]='<value>'
#                                 ...
#                                 <varName>[idxN]='<value>'
#        object ref      : calls the bgtrace -m -s method on the object
#        "" or "\n"      : write a blank line. this is used to make vertical whitespace. with -1 you
#                          can use this to specify where line breaks happen in a list
#        "  "            : a string only whitespace sets the indent prefix used on all output to follow.
#        <option>        : options begin with '-'. see below.
# Options:
#   -l<string> : literal string. print <string> without any interpretation
#   -wN : set the width of the variable name field. this can be used to align a group of variables.
#   -1  : display vars on one line. this suppresses the \n after each <varSpecN> output
#   +1  : display vars on multiple lines. this is the default. it undoes the -1 effect so that a \n is output after each <varSpecN>
function printfVars()
{
	local pv_nameColWidth pv_inlineFieldWidth="0" pv_indexColWidth oneLineMode pv_lineEnding="\n"
	local pv_prefix pv_noObjectsFlag

	function _printfVars_printValue()
	{
		local name="$1"; shift
		local value="$*"
		case ${oneLineMode:-multiline}:${name:+nameExits} in
			# common processing for all oneline:* -- note the ;;&
			oneline:*)
				if [[ "$value" =~ $'\n' ]]; then
					value="${value//$'\n'*/ \n...}"
				fi
				;;&
			oneline:nameExits)
				printf "%s=%-*s " "$name" ${pv_inlineFieldWidth:-0} "'${value}'"
				;;
			oneline:)
				printf "%-*s " ${pv_inlineFieldWidth:-0} "${value}"
				;;
			multiline:nameExits)
				local nameColWidth=$(( (${pv_nameColWidth:-0} > ${#name}) ? ${pv_nameColWidth:-0} : ${#name}  ))
				printf "${pv_prefix}%-*s='%s'${pv_lineEnding}" ${nameColWidth:-0} "$name" "${value}" \
					| awk '
						NR>1 {printf("'"${pv_prefix}"'%-*s  ", '"${nameColWidth:-0}"', "")}
						{print $0}
					'
				;;
			multiline:)
				printf "${pv_prefix}%-*s${pv_lineEnding}" ${pv_nameColWidth:-0} "${value}" \
					| awk '
						NR>1 {printf("'"${pv_prefix}"'  ")}
						{print $0}
					'
				;;
		esac
	}

	local pv_term pv_varname pv_tmpRef pv_label
	for pv_term in "$@"; do

		if [[ "$pv_term" =~ ^-w ]]; then
			if [ "$oneLineMode" ]; then
				pv_inlineFieldWidth="${pv_term#-w}"
			else
				pv_nameColWidth="${pv_term#-w}"
			fi
			continue
		fi
		if [[ "$pv_term" =~ ^-l ]]; then
			_printfVars_printValue "" "${pv_term#-l}"
			continue
		fi
		if [ "$pv_term" == "-1" ]; then
			oneLineMode="oneline"
			pv_lineEnding=" "
			continue
		fi
		if [ "$pv_term" == "+1" ]; then
			oneLineMode=""
			pv_lineEnding="\n"
			printf "\n"
			continue
		fi

		if [ "$pv_term" == "--noObjects" ]; then
			pv_noObjectsFlag="1"
			continue
		fi

		# "" or "\n" means output a newline
		if [ ! "$pv_term" ] || [ "$pv_term" == "\n" ] ; then
			printf "\n"
			continue
		fi

		# "   "  means set the indent for new lines
		if [[ "$pv_term" =~ ^[[:space:]]*$ ]]; then
			pv_prefix="$pv_term"
			[ "$oneLineMode" ] && printf "$pv_term"
			continue
		fi


		# "<objRef>.bgtrace [<opts]"  means to call the object's bgtrace method
		if [[ "$pv_term" =~ [.]bgtrace([\ ]|$) ]]; then
			local pv_namePart="${pv_term%%.bgtrace*}"
			printf "${pv_prefix}%s " "$pv_namePart"
			ObjEval  $pv_term | awk '{print '"${pv_prefix}"'$0}'
			continue
		fi

		# this separates myLabel:myVarname taking care not to mistake myArrayVar[lib:bg_lib.sh] for it
		pv_varname="$pv_term"
		pv_label="$pv_term"
		if [[ "$pv_term" =~ ^[^[]*: ]]; then
			pv_varname="${pv_varname##*:}"
			pv_label="${pv_label%:*}"
			if [[ "$pv_varname" =~ ^-l ]]; then
				_printfVars_printValue "$pv_label" "${pv_varname#-l}"
				continue
			fi
		fi

		# assume its a variable name and get its declaration. Should be "" if its not a var name
		# if its a referenece (-n) var, get the reference of the var that it points to
		local pv_type; varGetAttributes "$pv_varname" pv_type
		# local pv_type="$(declare -p "$pv_varname" 2>/dev/null)"
		# [[ "$pv_type" =~ -n\ [^=]*=\"(.*)\" ]] && pv_type="$(declare -p "${BASH_REMATCH[1]}" 2>/dev/null)"
		if [ ! "$pv_type" ]; then
			{ varIsA array ${pv_varname%%[[]*} || [[ "$pv_varname" =~ [[][@*][]]$ ]]; } && pv_type="-"
		fi

		# the term is not a variable name
		if [ ! "$pv_type" ]; then
			if [ "$pv_label" == "$pv_varname" ]; then
				# if its a simple token that is not a var name, we used to print it as an empty var because of the bash bug that
				# uninitialized declared vars would not be detectable as being declared. In circa 5.x, that is fixed so now we
				# treat it as a literal.
				_printfVars_printValue "" "${pv_varname}"
			else
				# foo:bar where bar is not a variable name
				_printfVars_printValue "$pv_label" "$pv_varname"
			fi

		# it its an object reference, invoke its .bgtrace method
		elif [ ! "$pv_noObjectsFlag" ] && [[ ! "$pv_varname" =~ [[] ]] && [ "${!pv_varname:0:12}" == "_bgclassCall" ]; then
			Try:
				objEval "$pv_varname.toString --title=${pv_varname}"
			Catch: && {
				# Note that a bug prevents this Catch from getting called when stepping through the debugger. It seems that the
				# catch resumes after the objEval.
				# in debugger when the watch window printfVars sees an object reference that has been created with NewObject,
				# toString failed on that object. added this try/catch but the catch did not execute.
				_printfVars_printValue "$pv_label" "<error in Object::toString call>"
			}

		# if its an array, iterate its content
		elif [[ "$pv_type" =~ [aA] ]]; then
			pv_nameColWidth="${pv_nameColWidth:-${#pv_label}}"
			printf "${pv_prefix}%-*s[]${pv_lineEnding}" ${pv_nameColWidth:-0} "$pv_label"
			eval local indexes='("${!'"$pv_varname"'[@]}")'
			pv_indexColWidth=0; for index in "${indexes[@]}"; do
				[ "${pv_lineEnding}" == "\n" ] && [ ${pv_indexColWidth:-0} -lt ${#index} ] && pv_indexColWidth=${#index}
			done
			for index in "${indexes[@]}"; do
				pv_tmpRef="$pv_varname[$index]"
				printf "${pv_prefix}%-*s[%-*s]='%s'${pv_lineEnding}" ${pv_nameColWidth:-0} "" "${pv_indexColWidth:-0}"  "$index"   "${!pv_tmpRef}" \
					| awk '
						NR>1 {printf("'"${pv_prefix}"'%-*s[%-*s] +"), '"${pv_nameColWidth:-0}"', "",  '"${pv_indexColWidth:-0}"', ""}
						{print $0}
					'
			done

		# default case is to treat it as a variable name
		else
			_printfVars_printValue "$pv_label" "${!pv_varname}"
		fi
		pv_inlineFieldWidth="0"
	done
	if [ "$pv_lineEnding" != "\n" ]; then
		printf "\n"
	fi
}
