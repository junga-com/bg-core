#!/bin/bash

import bg_template.sh  ;$L1;$L2
import bg_awkDataSchema.sh  ;$L1;$L2

# usage: awkData_query [options] <awkDataID> [ column1:value1 [ column2:value2 ... ] ] [\G]
# usage: while IFS=$'\b' read -r $colList; do ...; done < <(awkData_query -d$'\b' "$awkObjName" "$colList" ... )
# queries a cache data file and returns matching rows.
# Params:
#   <awkDataID> :
#       The object type being queried (like a table name). Can optionally include prefixes that limit the the data set to a particular scope.
#       if the --awkDataID option is specified, then this parameter must not be provided
#   <outputColumns> :
#       an ordered list of columns to include in the output. Supports several special features
#       the column name "all" expands to all columns in the order defined in the data file
#       a columns prefixed with a "-" will remove the previous occurrence of the column.
#       e.g. "all-colName1" will include all column names except colName1
#   <columnN:[op]valueN> :
#       filters the results to records that match the filter term. op can be == != ~ !~ < <= > >=
#       multiple terms are 'anded' together. additional filter terms can only narrow the results.
#   \G : if the last token on the cmd line is the literal \G , the output will be vertical with each columnName : value
#        being on the same line and a record separator line ******** Row N ******** between objects
#        This is similar to mysql client. see name mysql
# Options:
#    -C|--domID=<domID> : specify the domData to get awkData cache files from (default is the currenly select domData)
#    -c|--columns=<colList> : specify the columns to be included in the output
#    -n|--noDirtyCheck : skip the check to see if the data is dirty and needs to be rebuilt. this has no effect if -f is specified too
#    -e|--escapeOutput : leave the data fields escaped so that bash would parse output correctly into fields (i.e. spaces will be '%20')
#    -H|--header : include the column names (header) as the first line
#    -f|--forceRebuild : force a rebuild regardless of whether its dirty. this has precedence over -n
#    -r|--refresh : refresh data -- no output, do only the rebuild check and rebuild if needed
#    -F|--tblFormat <tblType> : specifies the format template that will be applied to the result set.
#         Templates are named...
#            awkDataTblFmt.<tblType>[.vert]
#         where...
#            <tblType> : default is 'txt'. 'wiki' is also a builtin type
#            [.vert]   : if the query ends in \G '.vert' is appended to the name
#         Other types can be supported by creating a template file named awkDataTblFmt.<tblType> in the system template path
#         See templateFind
#         Use 'bg-templates find awkDataTblFmt.<tblType>' to find the template that will be used on a host
#    -w : format output in wiki table syntax (default is plain text table)
#    -p : plain filter flag. makes it not use the default filter that might be set in the schema file
# TEMPLATETYPE : awkDataTblFmt.<tblType> : provides table formating for the output of awkData_query
# See Also:
#    Library bg_awkDataQueries.awk
function awkData_query()
{
	local columns escapOutput forceFlag refreshFlag noDirtyCheckFlag plainFilterFlag headerFlag outFmtType="txt"
	local awkDataID="$awkDataID" awkDataSet
	while [[ "$1" =~ ^- ]]; do case $1 in
		-c*|--columns*)    bgOptionGetOpt val: columns "$@" && shift ;;
		-n|--noDirtyCheck) noDirtyCheckFlag="-n" ;;
		-f|--forceRebuild) forceFlag="-f" ;;
		-r|--refresh)      refreshFlag="-r" ;;
		-e|--escapeOutput) escapOutput="-e" ;;
		-H|--header)       headerFlag="-H" ;;
		-F*|--tblFormat*)  bgOptionGetOpt val: outFmtType "$@" && shift ;;
		-w|--wiki)         outFmtType="wiki" ;;
		-p|--plainFilter)  plainFilterFlag="-p" ;;
		--awkDataID)   awkDataSet="1" ;;
		--awkDataID*)  bgOptionGetOpt val: awkDataID "$@" && shift; awkDataSet="1" ;;
		*)   bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	[ ! "$awkDataSet" ] && { awkDataID="${1:-$awkDataID}"; shift; }

	local verticalOutputFlag; [[ "${@: -1}" =~ [\\]?G$ ]] && { verticalOutputFlag=".vert"; set -- "${@:1:$#-1}"; }

	local filters="$*"

	assertNotEmpty awkDataID

	# columns can be specified as a part of the awkDataID term like <awkDataID>.<coluList>
	if ! [[ "$awkDataID" =~ [|] ]] && [[ "${awkDataID##/}" =~ [.] ]]; then
		columns="${awkDataID#*.}"
		awkDataID="${awkDataID%%.*}"
	fi

	local allFlag; [ "$columns" == "all" ] && allFlag="all"

	# force means rebuild the cache unconditionally and then go on to run the query
	# refresh means rebuild the cache only if its dirty and then return without doing a query
	if [ "$forceFlag" ] || [ "$refreshFlag" ]; then
		awkData_build $forceFlag "$awkDataID"
		[ "$refreshFlag" ] && return
	fi

	local outputTemplate; templateFind -R outputTemplate "awkDataTblFmt.${outFmtType}$verticalOutputFlag"
	[ ! "$outputTemplate" ] && [ "$outFmtType" != "txt" ] && assertError "unknown awkDataTblFmt type. No template for awkDataTblFmt.$outFmtType was found in the template path. Use bg-core templates types 'awkDataTblFmt' to see what types are available on this host. Adding a template named awkDataTblFmt.$outFmtType will enable this command to proceed"

	[ "$headerFlag" ] && import bg_cui.sh ;$L1;$L2

	# How this loop algorithm works. We run the lookup awk script in loop i==0 and if the awkDataID is not dirty, it rturns the data.
	# but if the awkDataID is dirty, that first run will return quickly reporting that it needs building. We call awkData_build in
	# that condition and then iterate to the next loop. If all is good, that second i==1 iteration will return the data but if it
	# also indicates that the awkDataID needs building, then we fail.
	local result i
	for ((i=0; i<2; i++)); do
		awk -v awkDataID="$awkDataID" \
			-v columns="$columns" \
			-v filters="$filters" \
			-v noDirtyCheckFlag="$noDirtyCheckFlag" \
			-v headerFlag="$headerFlag" \
			-v plainFilterFlag="$plainFilterFlag" \
			-v escapOutput="$escapOutput" \
			-v queryType="lookup" \
			-v outputTemplate="$outputTemplate" \
			-i "bg_awkDataQueries.awk" '
			BEGIN {
				### prepare the output format
				tblFmt_get(tblFmt, outputTemplate)
				#bgtraceVars("tblFmt outputTemplate csiNorm")

				### start the tabular output
				tblFmt_writeBeginning(tblFmt, schemas[awkDataID], outFields, headerFlag)
				matchCount=0
			}

			NR==1 {awkData_readHeader()}

			# for data lines matching filterExpr, write tabular rows
			NR>=dataLinePos && expr_evaluate(filterExpr) {
				tblFmt_writeRowFrom(tblFmt, "", outFields)
				matchCount++
			}

			# end the tabular output
			END {tblFmt_writeEnding(tblFmt)}
		'
		result="$?"

		if (( i==0 && (result == 3 || result == 4) )); then
			awkData_build -f "$awkDataID" || assertError
		else
			break
		fi
	done
	(( result == 3 )) && assertError -v awkDataID "The awkDataID has dirty data and could not be built"
	(( result == 4 )) && assertError -v awkDataID "The awkDataID has no data and could not be built. "

	# # for inventory items, cat their source data if conditions are met.
	# # TODO: the later part of this condition is imperfect. The awk script knows if the buider function is the inventory builder and if the filter is a key filter. Either the inventory scheams should include the file names so that the awk script can cat them or the awk script should returne out of band info to us.
	# if [ "$verticalOutputFlag" ] && [ "$allFlag" ] && [[ "$awkObjName" =~ ^(drives|equipment|location)$ ]] && (( $# == 1 )) && [[ "$1" =~ :[^~'<>!'] ]]; then
	# 	local awkObjPrimeKeyValue="${1#*:}"
	# 	import bg_inventory.sh ;$L1;$L2
	# 	inventoryShowAll "$awkObjName" "$awkObjPrimeKeyValue"
	# fi

	return $result
}




# usage: values="$(awkData_getValue [<options>] <awkDataID>.<columns> filter1 [ .. filterN ])"
# usage: value="$(awkData_getValue -1 [<options>] <awkDataID>.<columns> filter1 [ .. filterN ])" || exit
# usage: awkData_getValue -R <retVal> [<options>] <awkDataID>.<columns> filter1 [ .. filterN ]
# query unique values over the specified sub-table. When <columns> is a single column name and filters specify a key match, this
# returns a single, specific cell value. The -1 option ensures that is the case by asserting an error if more than one value is
# returned. Columns can be a list of columns separated by a commas. In that case, the unique combinations of those column values
# are returned.
# Options:
#    -1  : assert that the query will not return more than one value. note: use "... || exit" if its called in a sub shell
#    -R <retVar>  : return the results in this variable as an indexed array. Note that ${<retVar>[0]} is the same as $<retVar>
#    These options are common to the other query functions
#    -C : specify the domData to get awkData cache files from (default is the currenly select domData)
#    -n : skip the check to see if the data is dirty and needs to be rebuilt. this has no effect if -f is specified too
#    -e : leave the data fields escaped (i.e. spaces will be '%20')
#    -f : force a rebuild regardless of whether its dirty. this has precedence over -n
#    -r : refresh data -- no output, do only the rebuild check
#    -p : plain filter flag. makes it not use the default filter that might be set in the schema file
# See Also:
#    awkData_countValues   : similar function that also includes a column containing the number of times each unqique value ocurs
#    awkData_query        : the most qeneral query function which returns all matching rows without combining duplicates
function awkData_getValue()
{
	local escapOutput forceFlag refreshFlag noDirtyCheckFlag plainFilterFlag assertOneFlag retVar countFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-n|--noDirtyCheck)    noDirtyCheckFlag="-n" ;;
		-f|--forceRebuild)    forceFlag="-f" ;;
		-r|--refresh)         refreshFlag="-r" ;;
		-e|--escapeOutput)    escapOutput="-e" ;;
		-p|--plainFilter)     plainFilterFlag="-p" ;;
		-1|--assertOneValue)  assertOneFlag="-1" ;;
		-R*|--retVar*)        bgOptionGetOpt val: retVar "$@" && shift; eval $retVar'=()' ;;
		--count)              countFlag="--count" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local attribute="$1"; shift
	local filters="$*"

	[[ ! "$attribute" =~ \. ]] && attribute="${attribute/:/.}"
	local awkDataID="${attribute%.*}"
	local columns="${attribute##*.}"

	# force means rebuild the cache unconditionally and then go on to run the query
	# refresh means rebuild the cache only if its dirty and then return without doing a query
	if [ "$forceFlag" ] || [ "$refreshFlag" ]; then
		awkData_build $forceFlag "$awkDataID"
		[ "$refreshFlag" ] && return
	fi

	# How this loop algorithm works. We run the lookup awk script in loop i==0 and if the awkDataID is not dirty, it rturns the data.
	# but if the awkDataID is dirty, that first run will return quickly reporting that it needs building. We call awkData_build in
	# that condition and then iterate to the next loop. If all is good, that second i==1 iteration will return the data but if it
	# also indicates that the awkDataID needs building, then we fail.
	local result i value values count
	for ((i=0; i<2; i++)); do
		while IFS=$'\b' read -r count value; do
			[ "$count" == "assertOneFlag" ] && assertError -v filters "expected one or zero values for '$attribute' but got '$values'"
			case ${countFlag}:${retVar:+retVar} in
				--count:retVar) printf -v "$retVar[${value:---}]" "%s" "$count" ;;
				       :retVar) setRef --array -a "$retVar" "$value" ;;
				--count:)       printf "%4s %s\n" "$count" "$value" ;;
				       :)       printf "%s\n" "$value" ;;
			esac
		done < <(awk -v awkDataIDList="$awkObjData" \
			-v awkDataID="$awkDataID" \
			-v columns="$columns" \
			-v filters="$filters" \
			-v noDirtyCheckFlag="$noDirtyCheckFlag" \
			-v plainFilterFlag="$plainFilterFlag" \
			-v escapOutput="$escapOutput" \
			-v queryType="getValue" \
			-v assertOneFlag="$assertOneFlag" \
			-i "bg_awkDataQueries.awk" '
			BEGIN {
				matchCount=0
				arrayCreate(matchValues)
				if (length(outFields) == 1)
					schemas[awkDataID]["colWidths"][outFields[1]]=0
			}

			NR==1 {awkData_readHeader()}

			# data lines matching filterExpr
			NR>=dataLinePos && expr_evaluate(filterExpr) {
				value=""; sep=""
				for (i in outFields) {
					value=sprintf("%s%s%*s", value, sep, schemas[awkDataID]["colWidths"][outFields[i]], denorm($outFields[i]))
					sep=" "
				}
				matchValues[value]++
				matchCount++
			}

			# write the results
			END {
				if (assertOneFlag && length(matchValues)>1) {
					print "assertOneFlag "length(matchValues)
					exit(5)
				}
				PROCINFO["sorted_in"]="@val_num_desc"
				for (value in matchValues)
					printf("%s\b%s\n", matchValues[value], value)
			}
		')
		result="$?"

		if (( i==0 && (result == 3 || result == 4) )); then
			awkData_build -f "$awkDataID" || assertError -v awkDataID
		else
			break
		fi
	done
	(( result == 3 )) && assertError -v awkDataID "The awkDataID has dirty data and could not be built"
	(( result == 4 )) && assertError -v awkDataID "The awkDataID has no data and could not be built. "
}

# usage: awkData_countValues <awkDataID>.<columns>[,col2,..colN] filter1 [ .. filterN ]
# For each unique value in the result set defined by the filters, write a line containing the number of times it
# appears and the value.
function awkData_countValues()
{
	awkData_getValue --count "$@"
}
