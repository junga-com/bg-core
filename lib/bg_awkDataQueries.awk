@include "bg_awkDataSchema.awk"
@include "bg_cui.awk"

# Library 
# This awk library is part of the awkData subsystem. It brings in a BEGIN section that processes the inout variables and ultimately
# launches an awkData table scan that returns the restult set format descibed by the inputs 
#
# Return Codes:
#     0 (success) : normal operation
#     3 (dirty)   : the awkDataID is dirty so it failed before doing any query work. Set noDirtyCheckFlag to non-empty to suppress
#                   this and query dirty data
#     4 (dirty,no data) : the noDirtyCheckFlag was specified but the awkDataID file does not exist so there is no dirty data to query

BEGIN {
	if (!noDirtyCheckFlag && schema_isDirty(schema))
		hardExit(3)

	### prepare the filterExpr struct that will be used to test for matching lines for inclusion in the result set
	if (plainFilterFlag)
		expr_compile(filters, filterExpr, schemas[awkDataID])
	else
		expr_compile(filters" "schemas[awkDataID]["info"]["defFilter"], filterExpr, schemas[awkDataID])
	#bgtraceVars("filterExpr")


	### prepare the output columns
	if (!columns) columns=":"
	outColsStr=strSetExpandRelative(schemas[awkDataID]["info"]["colNames"],         # full set
	                                schemas[awkDataID]["info"]["defDisplayCols"],   # default display columns
	                                columns)                                        # relative column spec
	outCnt=split(outColsStr, outCols)
	arrayCreate(outFields)
	for (i=1; i<=outCnt; i++)
		outFields[i]=schemas[awkDataID]["colFields"][outCols[i]]


	### add the awkFile to the input file list if its not already there
	# if the awkFile does not exist, the dirtyCheck will return 3 but the dirty check could have been turned off
	if (!awkData_initDataScan(schemas[awkDataID]))
		hardExit(4)
}
