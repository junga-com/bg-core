
######################################################################################################
### Command Completion (BC) Functions

#function awkData_bcAwkDataID()
#function awkData_bcAttributeTerm()
#function awkData_bcColumnList()
#function awkData_bcColumnValues()
#function awkData_bcColumnNames()

# usage: completeAwkDataQueryTerms [--cur=<cur>] <awkDataID> <cword> <filterTerm1>..<filterTermN>
function completeAwkDataQueryTerms() {
	local cur
	while [ $# -gt 0 ]; do case $1 in
		--cur*) bgOptionGetOpt val: cur "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local awkDatID="$1"; shift
	local cword="$1"; shift

	local completedFilterTerms=()
	if [ ${cword:-0} -gt 1 ]; then
		completedFilterTerms=("${@:1:$cword}")
	fi

	completeAwkDataAttributeTerm --filter "$awkDatID" "$cur" "${completedFilterTerms[@]}"
}

# usage: awkData_bcAwkDataID <cur>
# complete an awkDataID term in a bash completion function. awkDataID can be one of several syntaxes.
# an awkDataID identifies the awk data schema (aka db table) and optionally a scope (subset of rows in a shard)
# See Also:
#    awkDataCache_parseAwkDataID for details on the supported syntax
function completeAwkDataID() { awkData_bcAwkDataID "$@"; }
function awkData_bcAwkDataID()
{
	local ldFolder="$ldFolder" domIDOverride
	while [ $# -gt 0 ]; do case $1 in
		-C*) bgOptionGetOpt val: domIDOverride "$@" && shift ;;
		*)   bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	_domMethodPreamble "$domIDOverride"

	local cur="${1:-$cur}"

	# let the user select between basic and advaced modes
	echo "\$(enableModes: basic advanced)" #" @basic @advanced"
	case ${_bgbcData[lastMode]:-basic} in
		basic)
			echo "<tableName>"
			awkData_listAwkObjNames
			if [ "$cur" ]; then
				echo "\$(doFilesAndDirs)"
			fi
			return
			;;
		advanced)
			local partCount="${cur//[^:]}"; partCount="${#partCount}"
			local scopeList="servers locations"
			echo "<awkDataID> <me:tbl> <local:tbl> <${scopeList// /|}:...> <<scopeName>:tbl> <pathToCacheFile>"
			if (( partCount == 0 )); then
				awkData_listAwkObjNames
				if [ "$cur" ]; then
					echo "me:%3A local:%3A ${scopeList[@]/%/:%3A}"
					echo "\$(doFilesAndDirs)"
					echo "\$(suffix :%3A)"; domScopeList
				fi

			else
				local scopeType scopeName awkObjName
				stringSplit -d":" "$cur" scopeType scopeName awkObjName

				# me: and local:
				if [[ "$scopeType" =~ ^(me|local)$ ]]; then
					echo "\$(cur:${cur#$scopeType:})"
					awkData_listAwkObjNames "$scopeType:"

				# <scopeType>:
				elif [[ "$scopeType" =~ ^(${scopeList// /|})$ ]]; then
					case $partCount in
						1)	echo "\$(cur:${cur#$scopeType:}) \$(nextBreakChar :)"
							domScopeList -t "$scopeType"
							;;
						2)	echo "\$(cur:${cur#$scopeType:$scopeName:})"
							awkData_listAwkObjNames "$scopeType:$scopeName:"
							;;
					esac

				# <scopeName>:
				else
					scopeName="$scopeType"
					domScopeGetType "$scopeName" scopeType
					echo "\$(cur:${cur#$scopeName:})"
					echo "\$(removePrefix:$scopeType:$scopeName:)"; awkData_listAwkObjNames "$scopeType:$scopeName:"; echo "\$(removePrefix:)"
				fi
			fi
			;;
	esac
}

# usage: awkData_bcColumnList <awkDataID> <cur>
# complete an awkData column list in a bash completion function. A column list is a token separated list of column names
# where the token can be one of [,:+-]
function completeAwkDataColumnList() { awkData_bcColumnList "$@"; }  # ALIAS
function awkData_bcColumnList()
{
	local ldFolder="$ldFolder" domIDOverrideOpt
	while [ $# -gt 0 ]; do case $1 in
		-C*) bgOptionGetOpt opt: domIDOverrideOpt "$@" && shift ;;
		*)   bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	local awkDataID="${1:-$awkDataID}"; shift;
	local cur="$1"; shift

	awk -v awkDataID="$awkDataID" \
		-v cur="$cur" \
		-v bcType="columnList" \
		-f "bg_awkDataBC.awk"
}

# usage: awkData_bcAttributeTerm <awkDataID> <cur> [<completedTerm1> .. <completedTermN>]
# complete an awkData attribute term in a bash completion function
# Attribute Term Format:
#    <colName>:[<operator>]<colValue>
#    <operator> can be
#        =        : assignment (only one that is not a comparison operator)
#        <empty>  : is equal
#        !        : is not equal
#        ~        : regex comparison
#        <,>, <=, >= : les/greater then comparisons
#        !<compOp> : negates a comparison operator
#        <>        : alternate not equals to !=
# cur is the current term being built.
# Options:
#    -C <domFolder> : use a different domData to locate <awkDataID>
#    --filter : filter term mode. builds The attribute being completed in the context of a comparison condition.
#          Shortcut for -p0, and sets the validOperators any comparison op
#    --set : 'set' mode, as in 'assignment'. The attribute is being completed in the context of a 'set' statement.
#          Shortcut for -p2, -x and sets the validOperators to only ":="
#    Lower Level Options...
#    --validOperators : the space separted list of valid operators for this term
#    -p[123] : the comNames plan to use when completing the colName part.
#    -x  : suppress the default col values when completing the colName part
function completeAwkDataAttributeTerm()  { awkData_bcAttributeTerm "$@"; }
function awkData_bcAttributeTerm()
{
	local ldFolder="$ldFolder" domIDOverrideOpt dontDoDefaultCol planMode validOperators
	while [ $# -gt 0 ]; do case $1 in
		-C*) bgOptionGetOpt opt: domIDOverrideOpt "$@" && shift ;;
		-x) dontDoDefaultCol="-x" ;;
		-p*) planMode="$1" ;;
		--filter)
				planMode="-p0"
				validOperators="" # default is all comparison ops
				;;
		--set)	planMode="-p2"
				validOperators=":="
				dontDoDefaultCol="-x"
				;;
		--validOperators*) bgOptionGetOpt val: validOperators "$@" && shift ;;
		*)   bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	local awkDataID="${1:-$awkDataID}"; shift
	local cur="$1"; shift

	# make completedTerms, excluding the current term being completed and things that dont look like a term
	local completedTerms=()
	while [ $# -gt 0 ]; do
		[ "$1" != "$cur" ] && [[ ! "$1" =~ ^- ]] && [[ "$1" =~ : ]] && completedTerms+=("$1")
	shift; done

	awk -v awkDataID="$awkDataID" \
		-v cur="$cur" \
		-v bcType="attributeTerm" \
			-v planMode="${planMode:--p0}" \
			-v dontDoDefaultCol="${dontDoDefaultCol}" \
			-v validOperators="$validOperators" \
			-v filters="${completedTerms[*]}" \
		-f "bg_awkDataBC.awk"
}


# usage: awkData_bcColumnNames [-C <domID>] [-x] [-p<N>] <awkDataID> [ filter1:value1 [ filter1:value2 ... ] ]
# complete a column name from the <awkDataID> schema. 3 plans are supportted that specificy which subset of column names to
# return based on the data.
# Options:
#    -C <domFolder> : use a different domData to locate <awkDataID>
#    -p0 : plan0 -- 'filterMode' return only columns that have differing values in the result set left. These are the cols that
#          can be used to reduce the set further
#    -p1 : plan1 -- 'simple mode' (default) just return the complete list of columns unconditionally.
#    -p2 : plan2 -- 'assignment mode'. return the list of columns minus the ones that appear in filter list.  Note that a plain
#          column list is a valid filter list too. When the filter list is empty, this is the same as -p1
#    -x  : (now the default) suppress the default col values when completing the colName part
#    +x|--completeOnDefualtValues  : complete on the default column values as well as column names
function completeAwkDataColumnNames()  { awkData_bcColumnNames "$@"; }
function awkData_bcColumnNames()
{
	local ldFolder="$ldFolder" domIDOverrideOpt dontDoDefaultCol="-x" planMode validOperators
	while [ $# -gt 0 ]; do case $1 in
		-C*) bgOptionGetOpt opt: domIDOverrideOpt "$@" && shift ;;
		-x) dontDoDefaultCol="-x" ;;
		+x|--completeOnDefualtValues) dontDoDefaultCol="" ;;
		-p*) planMode="$1" ;;
		*)   bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	local awkDataID="${1:-$awkDataID}"; shift

	# make completedTerms, excluding the current term being completed and things that dont look like a term
	local completedTerms=()
	while [ $# -gt 0 ]; do
		[ "$1" != "$cur" ] && [[ ! "$1" =~ ^- ]] && [[ "$1" =~ : ]] && completedTerms+=("$1")
	shift; done

	awk -v awkDataID="$awkDataID" \
		-v cur="$cur" \
		-v bcType="columnNames" \
			-v planMode="${planMode:--p1}" \
			-v filters="${completedTerms[*]}" \
			-v dontDoDefaultCol="${dontDoDefaultCol}" \
		-f "bg_awkDataBC.awk"
}



# usage: awkData_bcColumnValues  [-p<N>]  <awkDataID> <colName> [ filter1:value1 [ filter1:value2 ... ] ]
# complete an awkData column value in a bash completion function. The possible values are the unique values found in the data
# in <colName>.  If <filter>:value terms are spicified, only the unique values found in the result set after applying those
# filters are returned.
# Options:
#    -C <domFolder> : use a different domData to locate <awkDataID>
function completeAwkObjColumnValues() { awkData_bcColumnValues "$@"; }
function awkData_bcColumnValues()
{
	local ldFolder="$ldFolder" domIDOverrideOpt
	while [ $# -gt 0 ]; do case $1 in
		-C*) bgOptionGetOpt opt: domIDOverrideOpt "$@" && shift ;;
		*)   bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	local awkDataID="${1:-$awkDataID}"; shift;
	local colName="$1"; shift

	# make completedTerms, excluding the current term being completed and things that dont look like a term
	local completedTerms=()
	while [ $# -gt 0 ]; do
		[ "$1" != "$cur" ] && [[ ! "$1" =~ ^- ]] && [[ "$1" =~ : ]] && completedTerms+=("$1")
	shift; done

	awk -v awkDataID="$awkDataID" \
		-v cur="$cur" \
		-v bcType="columnValues" \
			-v colName="$colName" \
			-v filters="${completedTerms[*]}" \
		-f "bg_awkDataBC.awk"
}


# CRITICALTODO: add .awk files to the code grep. maybe that just entails adding it to the makefile as code files
