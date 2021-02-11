@include "bg_awkDataSchema.awk"

# Library
# This awk file is a complete program that returns the command line completion suggestions for argmument positions that relate to
# an awkData schema. It uses the bg_awkDataSchema.awk library to read the schema definition for the awkDataID being operated on.
# Depending on what type of completion is being specified in the parameters passed in, it maybe be able to return the results based
# only on the schema data provided by bg_awkDataSchema.awk or it may scan the schema's data file.  The awk input files are all
# specified dynamically from the awkDataIDList/awkDataID input params so this script should be invoked without any input files or
# piped data.
# Params:
#  -v cur=.. : the value of the current cmdline position being completed. This includes only the portion behind the cursor.
#  -v awkDataIDList=... : (from bg_awkDataSchema.awk) -- specify the schema to use. This library will only use one so do not specify multiple.
#  -v awkDataID=... : the short form ID of the schema specified in awkDataIDList to use (awkDataIDList typically includes long form IDs)
#  -v bcType=...
#       "attributeTerm"  : <colName><operator><value>  Attribute terms are used as either conditional expressions or assignment
#                          statements depending on the operator.
#            -v validOperators : a space separated string of which oerators can be selected for this term
#            -v planMode=... : specify a subset of valid columns based on a 'plan' for how columns are chosen
#            -v filters=...  : space separated string attributeTerms used to filter the schema data to define the current result set.
#            -v dontDoDefaultCol=... : true/false. plan -p0 can optionally include the unique values of the defCol difined in the
#               schema definition file. The idea is that those values are unique and specify the column and value in just the value.
#       "columnNames"    : select from a list of column names from the schema. Three modes (aka plans) are supportted
#            -v planMode=... : specify a subset of valid columns based on a 'plan' for how columns are chosen
#            -v filters=...  : space separated string attributeTerms used to filter the schema data to define the current result set.
#            -v dontDoDefaultCol=... : true/false. plan -p0 can optionally include the unique values of the defCol difined in the
#               schema definition file. The idea is that those values are unique and specify the column and value in just the value.
#       "columnValues"   : select from a list of unique values present in the the data
#            -v colName  : the name of the coulumn whose values are used
#            -v filters=...  : space separated string attributeTerms used to filter the schema data to define the current result set.
#       "columnList"      : build a multi-element comma separated list of column names from this schema
# Globals:
#   filterExpr : an array representing the compiled state of the 'filters' string input. Used in the match data line section and elsewhere
# See Also:
#   man(7) bg_awkDataSchema.awk
#   bcAttributeTermBegin  : complete an attributeTerm (<colNam><operator><value>)
#   bcColumnNameBegin     : complete a column name
#   bcColumnValueBegin    : complete value that is valide for this column (uses unique values already in the data)
#   bcColumnListBegin     : complete a list of column names
BEGIN {
	if (bcType && !isarray(schemas[awkDataID])) assert("awkDataID is a required parameter to this awk script")
	#bgtraceVars("schemas")
	switch (bcType) {
		case "attributeTerm"  :  bcAttributeTermBegin(schemas[awkDataID], validOperators, planMode, filters, !dontDoDefaultCol) ; break
		case "columnNames"    :  bcColumnNameBegin(   schemas[awkDataID], planMode, filters, !dontDoDefaultCol)    ; break
		case "columnValues"   :  bcColumnValueBegin(  schemas[awkDataID], filters, colName)    ; break
		case "columnList"     :  bcColumnListBegin(   schemas[awkDataID], cur)    ; break
	}
	matchCount=0
}

# usage: bcAttributeTermBegin(schema, planMode, filters, includeDefColValues)
# do the processing of for attribute term completion.
# Params:
#    schema              : the awkData schema to operate on
#    validOperators      : space separated string of operator tokens that can be selected for this term being completed.
#                          default is all comparison operators
#    planMode            : -p0|-p1|-p2  -- specifies the subset of column names to include
#    filters             : plan -p0 and -p2 require a filter set
#    includeDefColValues : true/false. plan -p0 can optionally include the unique values from the default column (defCol)
#                          configured in the schema
# See Also:
#   man(7) bg_awkDataSchema.awk
#   bcAttributeTermBegin  : complete an attributeTerm (<colNam><operator><value>)
#   bcColumnNameBegin     : complete a column name
#   bcColumnValueBegin    : complete value that is valide for this column (uses unique values already in the data)
#   bcColumnListBegin     : complete a list of column names
function bcAttributeTermBegin(schema,validOperators,planMode, filters, includeDefColValues                       ,rematch,termName,termOp,termValue) {
	if (!validOperators) validOperators=": :~ :< :> :! "

	if ( ! match(cur, /^([^:~<>!]*)([:~<>!]*)(.*)$/, rematch)) {
		print "<malformedTerm>"
		hardExit()
	}
	termName =rematch[1]
	termOp   =rematch[2]
	termValue=rematch[3]

	if (! termOp && !(termName in schema["colFields"])) {
		print "<filterTerm_columnName>"
		bcColumnNameBegin(schema, planMode, filters, includeDefColValues)
		# if a defColValue is selected, it immediately completes the attribute term
		if (includeDefColValues) selectedColValuesTerminatingChar=" "
	}
	else if (!termOp) {
		print "<filterTerm_operator>"
		print "     $(cur:"termOp")" validOperators
		hardExit()
	}
	else {
		print "<filterTerm_value>"
		print "$(cur:"termValue")"
		# if the user has not yet started typing the value, and the operator is only one char, they should also see the choice of
		# two character operators
		if (length(termOp)==1 && !termValue)
			print validOperators
		bcColumnValueBegin(schema, filters, termName)
	}
}

# usage: bcColumnNameBegin(schema, planMode, filters, includeDefColValues)
# complete on columns names in the schema. 3 plans for how to choose the set of names are supported
# For plans -p1 and -p2 this function will print the suggestions and hardExit
# the script. For -p0, it will queue the data file to be processed and the results will be printed from the END section.
# Plans:
#   -p0 : apply 'filters' to make a result set and include only columns that can be used to further reduce the result set.
#         if a column has more than one value represented in the result set it can be used to further specify the set.
#   -p1 : include all columns from the schema.
#   -p2 : include the columns from the schema that are not already present in the terms in the param 'filters'
# Params:
#    schema              : the awkData schema to operate on
#    planMode            : -p0|-p1|-p2  -- specifies the subset of column names to include
#    filters             : plan -p0 and -p2 require a filter set
#    includeDefColValues : true/false. plan -p0 can optionally include the unique values from the default column (defCol)
#                          configured in the schema
# See Also:
#   man(7) bg_awkDataSchema.awk
#   bcAttributeTermBegin  : complete an attributeTerm (<colNam><operator><value>)
#   bcColumnNameBegin     : complete a column name
#   bcColumnValueBegin    : complete value that is valide for this column (uses unique values already in the data)
#   bcColumnListBegin     : complete a list of column names
function bcColumnNameBegin(schema, planMode, filters, includeDefColValues                 ,i,colNamesFromFilterSet) {
	switch (planMode) {
		# -p0 is only the columns left that could further narrow the query. This means that we iterate over the result set defined by
		# applying 'filters' and include only column names where there is more than one value encountered.
		case "-p0":
			awkData_initDataScan(schema)
			expr_compile(filters, filterExpr, schema)
			colP0Processing=1
			for (i=1; i<=schema["colNF"]; i++)
				undeterminedCols[i]=""

			if (includeDefColValues) {
				if ("defCol" in schema["info"])
					bcColumnValueBegin(schema, filters, schema["info"]["defCol"])
			}
			break

		# -p1 is the complete column list from the schema
		case "-p1":
			for (i in schema["colNames"])
				printf("%s%%3A ", schema["colNames"][i])
			exit

		# -p2 is the column list from the schema minus the ones present in filters
		case "-p2":
			expr_compile(filters, filterExpr)
			expr_extractColNames(filterExpr,colNamesFromFilterSet)
			for (i in schema["colNames"]) {
				if (! (schema["colNames"][i] in colNamesFromFilterSet))
					printf("%s%%3A ", schema["colNames"][i])
			}
			printf("\n")
			exit
	}
}

# usage: bcColumnValueBegin(schema, filters, colName)
# do completion on a column's unique values present in the data
# See Also:
#   man(7) bg_awkDataSchema.awk
#   bcAttributeTermBegin  : complete an attributeTerm (<colNam><operator><value>)
#   bcColumnNameBegin     : complete a column name
#   bcColumnValueBegin    : complete value that is valide for this column (uses unique values already in the data)
#   bcColumnListBegin     : complete a list of column names
function bcColumnValueBegin(schema,filters, colName) {
	print "<"colName">"
	awkData_initDataScan(schema)
	expr_compile(filters, filterExpr, schema)
	selectedColField=schema["colFields"][colName]
}

# usage: bcColumnListBegin(schema, cur)
# build a list of colNames.
# See Also:
#   man(7) bg_awkDataSchema.awk
#   bcAttributeTermBegin  : complete an attributeTerm (<colNam><operator><value>)
#   bcColumnNameBegin     : complete a column name
#   bcColumnValueBegin    : complete value that is valide for this column (uses unique values already in the data)
#   bcColumnListBegin     : complete a list of column names
function bcColumnListBegin(schema, cur) {
	print ("<columnList> $(usingListmode ,) " schema["info"]["colNames"])
	if  (cur !~ /[,:+-]/) print("all%20")
}




#################################################################################################################################
### Data Scan Processing.

NR==1 {awkData_readHeader()}

# data lines matching filterExpr
NR>=dataLinePos && expr_evaluate(filterExpr) {
	if (colP0Processing) {
		# undeterminedCols contains the column field indexes for which we have not encountered a second value yet in the data set.
		# the value at each index starts as "", then is set to the value in the first row encountered and then if a second value is
		# encountered, that column entry is removed from undeterminedCols
		for (i in undeterminedCols) {
			# first row -- record the first value. note that "" can not in the data because we use "--" for ""
			if (undeterminedCols[i] == "")
				undeterminedCols[i]=$i

			# whenever we find a differing value for a col, move it from undeterminedCols to outputColFieldSet
			else if (undeterminedCols[i]!=$i) {
				outputColFieldSet[i]=""            # a set of the indexes
				delete undeterminedCols[i]  # we dont need to keep checking this one
			}
		}
	}

	# keep a set of the unique values in the defauld key column
	if (selectedColField)
		selectedColValues[$selectedColField]=""

	# to include <{matchCount}_matches> comment
	matchCount++
}

# print results at the end
END {
	if (colP0Processing) {
		printf("<%s_matches> ", matchCount)
		for (i in outputColFieldSet) {
			if (schemas[awkDataID]["colNames"][i])
				printf("%s"separator"%s ", schemas[awkDataID]["colNames"][i], "%3A")
		}
		printf("\n")
	}

	if (selectedColField) {
		for (i in selectedColValues)
			print i""selectedColValuesTerminatingChar
	}
}
