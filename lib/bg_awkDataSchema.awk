@include "bg_core.awk"

# Library bg_awkDataSchema.awk
# Including this library will automatically initialize the schemas array to contain schemas for each of the awkDataID or awkObjData
# specified on the cmd line.
# Input:
#    -v awkDataIDList="<awkDataID1> [..<awkDataIDN>]"  : each <awkDataIDN> can be the long form or short form but not all short forms
#          are supported. The short form is supported to allow testing common awkData on the comand line.
#    -v domFolder="<domFolder>"  : if any of the awkDataIDN are short form which are relative to the domData, the domFolder must be
#          specified either with this explicit variable or in ENVIRON["domFolder"]
# Output:
# After this library is included, in any section, a script can reference the schemas[] array that contains the schema data for any
# awkDataID specified in the awkDataIDList variable on the cmd line.
# Additional schemas[<awkDataIDN>] can be added by a script by using schema_new(<awkDataIDN>, ...) or scheam_restore(<awkDataIDN>).
# Typically that is used to add derived schemas such as the allColName.
#    schemas[]
#           [<awkDataID1>][]
#           [<awkDataID2>][]
#           ...
# See Also:
#     awkData_getSchema
# Functions:
# This library provides these functions that scripts can optionally use.
#    schema_new(schemaName, columns, primeKey) : add an additional schema/table to the set being built. example, <awkObjName>.allColNames
#    data_getKeyValue(data, key, results) : When key is a simple single column name this funciton is the same as
#          data[key] (or $data[key] depending on the [_CLASS] of data) but key may be a composite key consisting of the combined
#          values of multiple columns and in that case this function returns the aggregated values. It returns the value
#          two ways...
#              result["value"]=<value1>[...,<valueN>]
#              result["term"]=<colName1>:<value1>[...,<colNameN>:<valueN>]
#    schema_addKeyAssociation(schema, primeKey, otherKeys) : this function tracks key sets of keys that are related in the data and
#          provides data structures at the end of reading all data that enumerate each unque item instance and the
#          primary and secondary keys associated with it. If the data is perfect that will be all but if there is data
#          for which the primary key is not known they will be identified as possible duplicates and any conflicting
#          records will be identified.



# process the cmd line options and create schemas entries
BEGIN {
	# if called without a file, we do not want to block reading from stdin. we are not that kind of script
	# TODO: combine the dependents of any schemas specified and push them onto the cmd line to process
	# 2019-04 bobg: moved this ARGC block from bg_libCore.awk because it messes up scripts that pipe in stdin. Maybe we should remove it
	if (ARGC<=1) {
		ARGV[ARGC++]="/dev/null"
	}

	arrayCreate(schemas)
	if (awkDataIDList) {
		spliti(awkDataIDList, awkDataIDSet)
		for (i in awkDataIDSet) {
			schema_restore(i)
		}
	}
	#printfVars("schemas")
}



#################################################################################################################################
### Misc functions


#################################################################################################################################
### Expression (expr) Class methods
# an expression is a conditional expression that can represent the 'where' clause of a query

# usage: expr_compile(exprIn, exprOut, schema)
# turn the input text expression into an expression object that can be evealuated efficiently
# expr objects are hierarchical. They can be a single field comparison or a list of expressions and'd together or a list of expr
# or'd together. This forms an expression tree.
# Params:
#     exprIn : a string or array of strings that describe the expression. This is typically a list of filter terms from the cmdline
#     exprOut : an array that will be filled in with the attributes to describe exprIn. This array will be cleared and then set.
#               exprOut["type"] will be set to one of 'operatorExpression'|'andGroup'|'orGroup'
#     schema : some components of exprIn like colNames are relative to the schema.
function expr_compile(exprIn, exprOut, schema       ,exprInAnddTerms,i,rematch,name,value,op,orNames) {
	# a list of and'd terms can be passed two ways -- as a space separated string or as an array of strings
	if (!isarray(exprIn) && exprIn ~ /[[:space:]]/) {
		split(exprIn, exprInAnddTerms)
	} else if (isarray(exprIn)) {
		arrayCopy(exprIn, exprInAnddTerms)
	}

	delete exprOut

	# list of and'd terms
	if (isarray(exprInAnddTerms) && length(exprInAnddTerms)>0) {
		exprOut["type"]="andGroup"
		arrayCreate2(exprOut, "terms")
		for (i in exprInAnddTerms) {
			if (isarray(exprInAnddTerms[i])) assert("expr_compile: expaected a string term but found an array term in list of and'd terms")
			arrayCreate2(exprOut["terms"], i)
			expr_compile(exprInAnddTerms[i], exprOut["terms"][i], schema)
		}
		return
	}

	if (exprIn~/^[[:space:]]*$/) {
		exprOut["type"]="true"
		return
	}

	if (("defCol" in schema["info"]) && exprIn !~ /[:=<>!~]/) {
		name=schema["info"]["defCol"]
		op="=="
		value=exprIn
	} else if (match(exprIn, /^([^:=<>!~]*)([:=<>!~]*)(.*)$/, rematch)) {
		name=rematch[1]
		op=rematch[2]; sub("^:","", op); if (op=="") op="=="
		value=norm(rematch[3])
	} else
		assert("expr_compile: string does not match an attribute term '"termStr"'")

	# process special colNames
	if (name=="any") {
		switch (op) {
			case ":":
				op=":~"
				value="\\y"value"\\y"
				break
			case ":!":
				op=":!~"
				value="\\y"value"\\y"
				break
			default:
				name=schema["info"]["colNames"]; gsub(/ /,",",name)
		}
	} else if (name=="key") {
		name=schema["info"]["anyKeyCols"]; gsub(/ /,",",name)
	}

	# comma separated names create an orList expression
	if (name ~ /,/) {
		split(name, orNames,",")
		delete exprOut
		exprOut["type"]="orGroup"
		arrayCreate2(exprOut, "terms")
		for (i in orNames) {
			exprOut["terms"][i]["type"]="operatorExpression"
			exprOut["terms"][i]["name"]=orNames[i]
			exprOut["terms"][i]["op"]=op
			exprOut["terms"][i]["value"]=value
			if (isarray(schema)) exprOut["terms"][i]["field"]=schema["colFields"][exprOut["terms"][i]["name"]]
		}
		return
	}

	#
	exprOut["type"]="operatorExpression"
	exprOut["name"]=name
	exprOut["op"]=op
	exprOut["value"]=value
	if (isarray(schema)) exprOut["field"]=schema["colFields"][exprOut["name"]]
}

# usage: expr_evaluate(expr,data)
# return true(1) or false(0) to indicate whether the data record matches the filter expression represeted by expr.
# Params:
#    expr  : the 'compiled' conditional expression. See expr_compile
#    data  : if data is an array, then the expression is evaluated again it where the name of each operatorExpression is used as an
#            index into data[exprTerm["name"]]. If it is null, the awk positional data $n are used ($exprTerm["field"])
function expr_evaluate(expr,data         ,i) {
	switch (expr["type"]) {
		case "true": return 1
		case "false": return 0

		case "operatorExpression":
			value=(isarray(data)) ?data[expr["name"]] :$expr["field"]
			switch (expr["op"]) {
				case "==" :  if ((value ==  expr["value"] )) {return 1}; break
				case "!"  :  if ((value !=  expr["value"] )) {return 1}; break
				case "~"  :  if ((value ~   expr["value"] )) {return 1}; break
				case "!~" :  if ((value !~  expr["value"] )) {return 1}; break
				case "<"  :  if ((value <   expr["value"] )) {return 1}; break
				case ">"  :  if ((value >   expr["value"] )) {return 1}; break
				case "<=" :  if ((value <=  expr["value"] )) {return 1}; break
				case ">=" :  if ((value >=  expr["value"] )) {return 1}; break
				default:
					assert("expr_evaluate: unknown operator '"expr["op"]"' from '"expr["name"]"' '"expr["op"]"' '"expr["value"]"'")
			}
			return 0
			break
		case "andGroup":
			for (i in expr["terms"]) {
				if ( ! expr_evaluate(expr["terms"][i])) return 0
			}
			return 1
			break
		case "orGroup":
			for (i in expr["terms"]) {
				if (expr_evaluate(expr["terms"][i])) return 1
			}
			return 0
			break
	}
	return 1
}


# usage: expr_extractColNames(expr,retSet,retArray)
# fill in retSet and retArray with the comlumn names used in the expr
# Params:
#    expr  : the 'compiled' conditional expression. See expr_compile
#    retSet   : set of unique column names like retSet[col]=""
#    retArray : array of column names like retSet[n]=col
function expr_extractColNames(expr,retSet,retArray         ,i) {
	switch (expr["type"]) {
		case "operatorExpression":
			retSet[expr["name"]]=""
			retArray[length(retArray)+1]=expr["name"]
			break
		case "andGroup":
			for (i in expr["terms"])
				expr_extractColNames(expr["terms"][i],retSet,retArray)
			break
		case "orGroup":
			for (i in expr["terms"])
				expr_extractColNames(expr["terms"][i],retSet,retArray)
			break
	}
}


#################################################################################################################################
### AwkData Class methods

# usage: awkData_readHeader()
# sets the header attributes of an awkData file from the FNR==1 line of that file
# this needs to be called during the time that the FNR==1 line is parsed into $1, $2, ... ,$FN
function awkData_readHeader() {
	version=($1!~"^[0-9]{1,2}\\.[0-9]{1,2}$") ? "" : $1
	colLinePos= (!version)? 1 : $2
	depLinePos= (!version)? 2 : $3
	dataLinePos=(!version)? 3 : $4
	buildCmd=(!version)? "" : $5
}

# usage: akwDataIDLongForm awkData_parseAwkDataID(awkDataIDShortForm|akwDataIDLongForm)
# Returns the long form of akwDataID regardless of whether the short or long form is passed in.
# Note that this implementation is not as complete as the bash implementation. Typically a bash script should pass in the long form
# always but this is useful when testing awk scripts from the command line with common awkDataID that this does support.
function awkData_parseAwkDataID(awkDataID,      awkObjName,awkFile,awkSchemaFile,schemas) {
	# already parsed
	if (awkDataID ~ /[|]/) {
		return awkDataID

	# this block is for filename that are specified as awkObjNames. If it contains a / or .
	# it can not be a valid domData awkObjName name, it must be a filename
	} else if (awkDataID ~ /[/.]/) {
		# note that the bash version of awkData_parseAwkDataID will detect if the file path matches a domData awkData and handle that correctly
		awkObjName=awkDataID; gsub(/(^.*\/)|(.cache$)(.schema$)/,"", awkObjName)
		awkFile=awkDataID; gsub(/(.cache$)(.schema$)/,"", awkFile); awkFile=awkFile".cache"
		awkSchemaFile=awkFile; sub(/.cache$/,".schema", awkSchemaFile)

	# <awkObjName> syntax
	} else {
		awkObjName=awkDataID
		arrayCreate(schemas)
		manifestGet("awkDataSchema", awkObjName, schemas)
		switch (length(schemas)) {
			case 0: assert("no awkDataSchema was found in the host manifest for awkObjName ='"awkObjName"'")
			case 1: awkSchemaFile=schemas[0]; break
			default: assert("multiple manifest entries matched for type='awkDataSchema' and name ='"awkObjName"'")
		}
	}

	return awkDataID"|"awkObjName"|"awkFile"|"awkSchemaFile
}

# usage: awkData_initDataScan(schema, where)
# add an entry in ARGV to cause awk to process the data cache file of the schema if the file exists
# If its already in the queue that has not yet begun processing it will not be added again. If this is called while processing
# that schema's data file, the file will be queued for a second pass after the first one completes.
# Params:
#    schema   : the schema that defines the awkFile
#    where    : specifies whether to add the file at the end of the queue (where==false) or insert it at the beginning (where==true('next'))
function awkData_initDataScan(schema, where                ,i) {
	# if its already queued, do not add it again.
	# But still queue it if it was in the queue earlier including if its currently being processed ARGIND+1
	for (i=ARGIND+1; i<ARGC; i++)
		if (ARGV[i] == schema["awkFile"])
			return 1

	if (fsExists(schema["awkFile"])) {
		queueFileToScan(schema["awkFile"],where)
		return 1
	} else {
		return 0
	}
}



#################################################################################################################################
### SchemaList Class methods
# The global schemas array is contains multiple schema object arrays indexed with their awkDataID short form

# usage: schemas_writeOutput()
# cause each schema object to write its data to a tmp folder and update the awkFiles if the content changed
function schemas_writeOutput(                awkDataID) {
	for (awkDataID in schemas) {
		# call the writeOutput method on each schema Polymorphically
		writeFn=schemas[awkDataID]["writeFn"]
		if (!writeFn && (awkDataID"_writeOutput" in FUNCTAB)) writeFn=awkDataID"_writeOutput"
		if (!writeFn) writeFn="schema_writeOutput"
		if (!schemas[awkDataID]["outfile"]) assert("schemas_writeOutput: schemas["awkDataID"][outfile] should not be empty.  awkDataBuildFolder="awkDataBuildFolder)
		@writeFn(schemas[awkDataID], schemas[awkDataID]["outfile"])

		# if the content changed, update the awkFile
		updateIfDifferent(schemas[awkDataID]["outfile"], schemas[awkDataID]["awkFile"])
	}
}


#################################################################################################################################
### SchemaInfo Class Constructors

# usage: schemaInfo_restore(info, awkDataID)
# restore the schema definition information from the schema file or the header data of the awkFile of the given awkDataID
function schemaInfo_restore(info, awkDataID            ,awkDataIDLongForm,awkObjData,schemaSection,tmpInColumnArray,colName,colWidth) {
	if (!awkDataID)
		assert("-v awkDataID (awk)schemaInfo_restore(): awkDataID is a required parameter")

	#awkDataID|awkObjName|awkFile|awkSchemaFile
	# 1        2          3       4
	split(awkData_parseAwkDataID(awkDataID), awkObjData, "|")
	awkDataID=awkObjData[1]

	# set the information from the parsed awkDataID
	info["noSchemaDataFound"]=1 # initially assume that we wont find any data
	info["awkDataID"]=awkDataID
	info["awkObjName"]=awkObjData[2]
	info["awkFile"]=awkObjData[3]
	info["awkSchemaFile"]=awkObjData[4]

	schemaSection=""
	while (getline < info["awkSchemaFile"]  > 0) {
		info["schemaFileRead"]="yes"
		delete info["noSchemaDataFound"]

		# section line ([ scope:servers ])
		if (NF>0 && $1~/^[[]/) {
			match($0, /^[[:space:]]*[[][[:space:]]*([^][:space:]]*)[[:space:]]*[]]/, rematch)
			schemaSection=rematch[1]
			schemaSectionScope=""
			if (schemaSection ~ "^scope:") {
				schemaSectionScope=schemaSection; sub("^scope:","",schemaSectionScope)
			}
		}

		# attribute setting line (name=value)
		if  (NF>0 && $1!~/^#/ && match($0, /^[[:space:]]*([^=[:space:]]*)[[:space:]]*=[[:space:]]*(.*)$/, rematch)) {
			if (schemaSection=="" || schemaSectionScope==info["scopeType"]) {
				info[rematch[1]]=rematch[2]
			} else if (schemaSectionScope!="") {
				info[schemaSectionScope":"rematch[1]]=rematch[2]
			} else {
				info[schemaSection":"rematch[1]]=rematch[2]
			}
		}

		if (schemaSection=="NormalizedValues" && NF>=2) {
			normValues[$1]=$2
		}
	}
	close(info["awkSchemaFile"])
	if ("schemaFileRead" in info) {
		delete info["noSchemaDataFound"]
	} else {
		FNR=0
		while (getline < info["awkFile"]  > 0) {
			FNR++
			if (FNR == 1)  {awkData_readHeader()}
			if (FNR == colLinePos)  {info["columns"]=$0}
			if (FNR == depLinePos)  {info["dependents"]=$0}
			if (FNR == buildCmd)    {info["buildCmd"]=$0}
			if (FNR >= dataLinePos)  {
				break
			}
			info["cacheFileRead"]="yes"
			delete info["noSchemaDataFound"]
		}
		close(info["awkFile"])
	}

	schemaInfo_construct(info)
}

# usage: schemaInfo_construct(info)
# init the required and synthetic member vars. info[] should already contain the definition of the schema - typically the
# attributes from the schema file.
function schemaInfo_construct(info            ,tmpInColumnArray,colName,colWidth) {
	info["_CLASS"]="schemaInfo"
	info["_OID"]=info["awkDataID"]
	info["0"]=awkDataID   # for compatibility when exported to bash

	# init schemaType and domData
	if (info["awkDomFolder"]) {
		info["domFolder"]=info["awkDomFolder"]   ; sub("/$","",info["domFolder"])
		info["domName"]=info["domFolder"]        ; sub("^.*/","",info["domName"])
		info["schemaType"]="domData"
	} else {
		info["schemaType"]="independent"
	}

	if (!info["defDisplayCols"]) info["defDisplayCols"]="all"

	# normalize (potentially composite) primary key
	gsub("^[[:space:]]*|[[:space:]]*$","", info["keyCol"]) # make sure no leading or trailing spaces
	gsub("[,[:space:]][,[:space:]]*","@",  info["keyCol"]) # replace each run of spaces and commas with a single @

	# make a combined list of primary and secondary keys
	info["anyKeyCols"]=info["keyCol"]" "info["secondaryKeyCols"]

	# iterate the columns, creating the synthetic attributes that are column specific
	split(info["columns"], tmpInColumnArray)
	for (i in tmpInColumnArray) {
		match(tmpInColumnArray[i], /^([^(]*)([(]([0-9-]*)[)])?$/, rematch)
		colName=rematch[1]
		colWidth=( (rematch[3]=="")?"-"length(colName):rematch[3] )

		info["colNames"]         =appendStr(info["colNames"]         , colName, " ")
		info["colWidths"]        =appendStr(info["colWidths"]        , colWidth, " ")
		info["columnsWithWidths"]=appendStr(info["columnsWithWidths"], colName"("colWidth")", " ")
		info["fmtStr"]           =appendStr(info["fmtStr"]           , "%"colWidth"s", " ")
	}
	info["colWithWidths"]=info["columnsWithWidths"]
}







#################################################################################################################################
### Schema Class Constructors

# MAN(5) bgawkSchemaClass
# The awk Schema class are functions that initialize and operate on an awk associative array which can be treated as an Object
# Instance. Instances are stored in the global schemas array which is an array of arrays (gawk extension) indexed with the schemaName
# which is typically the awkDataID that idnetifies the schema.
# An awkData Schema is a database table definition typically defined in a .schema INI file in <domFolder>/schema/<awkObjName>.schema
# An awkDataID is the awkObjName in the typical case and even when its not, you can always get the awkObjName from the awkDataID.
# Members are accessed as string array indexes like schema["memberVarName"] and the result may be a scalar or an array.
# Example:
#    schema_new(schemaName, columns, primeKey)
#    for (i in schemas[schemaName]["colNames"])
#        print schemas[schemaName]["colNames"][i]
# Member Variables:
#    ["info"][<attribName>]   : array of the raw string attributes of the schema. Any attribute added to the schema file will be accessible in this
#             array. All info members are strings so lists like "columns" will be a space separated list of columns. Often there
#             will be a member var in schema with the same name that is an awk array so that it can be operated on efficiently.
#    ["awkDataID"] : the short form that identifies the schema/table that this object represents (See awkData_parseAwkDataID)
#    ["awkObjName"]: the simple schema/table name
#    ["awkFile"]   : the path to the data file for this schema/table
#    ["awkSchemaFile"]: the path to the schema definition file
#    ["awkDomFolder"]: the path to the domData root or empty if this schema is not relative to a domData
#    ["depsRoot"]  : the root path that elements in the depedents member list are relative to
#    ["colNF"]     : scalar column count.
#    ["colNames"][<f>]  : array of column names. the index is the awk field position of the column
#    ["colFields"][<colName>] : map(array) that is the transpose of colNames. index is colName and value is the field position
#    ["colWidths"][<f>] : array of column widths. widths are used for formatting output. it is roughly the size of the largest typically value.
#    ["colTypes"][<f>]  : array of columns type where each value is primeKey|secKey|primeKeyPart
#    ["dependents"][]: array of the filespecs that match the input files for this schema. They are relative to depsRoot and can contain globs
#    ["keyCols"][]   : array of the column(s) that make of the primary key. When its not composite, it will have only one element.
#    ["secondaryKeyCols"][] : array of columns that are not the primary key but are also unique accross the data set. Each element is a
#             single column name. Composite secondary keys are not supported.
#    ["anyKeyCols"][]: array of key columns that include both primary and secondary keys. If the primary key is composite, only that entry
#             will not be a simple column name. awkData_get
#    ["data"][<rowN>][<colN>]      : a square 2d array that a builder can use to build up the table as is scans the input files. A builder does not have
#                to use this but when it does it can use some schema_* method functions to do common operations like writing the awkFile.
#    ["normKey"][<keyVal>]=<primearyKeyValue>  : an index that lets you get the primaryKey, if known for any key value (primary or secondary)
#          This is maintained by schema_addKeyAssociation as the script scans input files. It is only complete at the end of the scan.
#    ["conflictKeys"][<primeKeyVal>]=<primeKeyVal>,<primeKeyVal2>[...,<primeKeyValN>] : an index that contains each primaryKey that
#          is in conflict with one or more other primary keys because they are related through one or more secondary keys.
#          This is maintained by schema_addKeyAssociation as the script scans input files. It is only complete at the end of the scan.
#    ["srcFiles"]  :  (add to data as a synthetic column?)
#    ["associatedSecKeys"][<secKeyValue]=<secKeyVal1>[...,<secKeyValN>] : contains secondary key groups that are not (yet) associated
#          with a primary key. When ever the builder encounters attributes that have a sec key but no a prime key association is known
#          the sec key(s) are recorded in here so that later they can be merged if the prime key is later associated or can create a
#          stand alone record (which might be a dublicate)
#    ["associatedSecKeysSet"][<secKeyVal1>[...,<secKeyValN>]] : this is the transpose of associatedSecKeys.
# See Also:
#     awkData_getSchema
#     bg_awkDataSchema.awk

# usage: schema_restore(awkDataID)
# construct the schema array object from the data in an awkDataID's schema file or the header of its awkFile.
# The new object will be accessible in the global schema array as schemas[awkDataID]
# Params:
#    awkDataID : identify the awk table to restore. An awkDataID can be in multiple formats. see man(1) awkData_parseAwkDataID (bash)
# See Also:
#    schema_restore  : create the new object from the attributes defined in the schema file
#    schema_new      : create the new object from attributes specified by the script author
#    schema_construct: this constructs the logical members after the raw data is read into the array. used by schema_new and schema_restore
#    schemaInfo_*: schemaInfo is similar to schema but all its attributes are flat (scalar strings). info arrays are used to construct schema
#    bgawkSchemaClass : schema class documentation
function schema_restore(awkDataID            ,awkDataIDLongForm,awkObjData) {
	if (!awkDataID)
		assert("-v schemas[awkDataID]["info"]=<value> is a required parameter to this library")

	#awkDataID|awkObjName|awkFile|awkSchemaFile
	# 1        2          3       4
	awkDataIDLongForm=awkData_parseAwkDataID(awkDataID)
	split(awkDataIDLongForm, awkObjData, "|")
	awkDataID=awkObjData[1]

	arrayCreate2(schemas,awkDataID)
	arrayCreate2(schemas[awkDataID], "info")
	schemaInfo_restore(schemas[awkDataID]["info"], awkDataIDLongForm)

	if (! ("noSchemaDataFound" in schemas[awkDataID]["info"])) {
		schema_construct(schemas[awkDataID], schemas[awkDataID]["info"])
	}
}

# usage: schema_new(schemaName, columns, primeKey, secKeyCols)
# This constructs a new schema object awk array in the global schemas array as schemas[schemaName]
# This is similar to schema_restore but instead of getting the definition from a file that a runtime admin manages, the definition
# is provided on in the function parameters and is typically specified by teh script author but a script could get the information
# from another dynamic source.
# Params:
#    schemaName : the name of the schema is also known as the awkDataID short form
#    columns    : space separated list of the colName[(width)] present in this schema. The widths are optional
#    primeKey   : the colName or list of colNames separated with @ that make unique record values for this schema. Data with the
#                 same primeKey value is considered to be the same record.
#    secKeyCols : space separated list of colNames that have unique values in the data set. This means that the value of any of
#                 these columns identify the record. A different value means that its a different record.
# See Also:
#    schema_restore  : create the new object from the attributes defined in the schema file
#    schema_new      : create the new object from attributes specified by the script author
#    schema_construct: this constructs the members. used by schema_new and schema_restore
#    schemaInfo_*: schemaInfo is similar to schema but all its attributes are flat (scalar strings). info arrays are used to construct schema
#    bgawkSchemaClass : schema class documentation
function schema_new(schemaName, columns, primeKey, secKeyCols) {
	schemas[schemaName]["info"]["awkObjName"]=schemaName
	schemas[schemaName]["info"]["awkDataID"]=schemaName
	schemas[schemaName]["info"]["awkFile"]=getDomFolder("required")"/cache/"schemaName".cache"
	schemas[schemaName]["info"]["columns"]=columns
	schemas[schemaName]["info"]["keyCol"]=primeKey
	schemas[schemaName]["info"]["secKeyCols"]=secKeyCols

	schemaInfo_construct(schemas[schemaName]["info"])

	schema_construct(schemas[schemaName], schemas[schemaName]["info"])
}


# function schema_construct(schema, info)
# Construct a valid schema array data object. Initialize the member variables.
# this is the lower level constructor that supports schema_restore and schema_new which are more typically used in scripts.
# Params:
#     schema : the array to construct. indexes will be added that represent the member variables
#     info   : array that contains the input variables that define the schema table and are needed to construct the member vars.
#              The indexes of the info array correspond to the attributes defined in the man(5) bgawkDataSchemaFileFormat format.
#              Typically info is created by reading the shema file (see schema_restore) but it can be created directly (see schema_new)
# See Also:
#    schema_restore  : create the new object from the attributes defined in the schema file
#    schema_new      : create the new object from attributes specified by the script author
#    schema_construct: this constructs the members. used by schema_new and schema_restore
#    schemaInfo_*: schemaInfo is similar to schema but all its attributes are flat (scalar strings). info arrays are used to construct schema
#    bgawkSchemaClass : schema class documentation
function schema_construct(schema,info                ,i,tmpInColumnArray,colName,colWidth) {
	# mark this array as being a schema Class object
	schema["_CLASS"]="schema"

	# init some member vars from the info object
	schema["_OID"]=info["_OID"]
	schema["awkDataID"]=info["awkDataID"]
	schema["awkObjName"]=info["awkObjName"]
	schema["awkFile"]=info["awkFile"]
	schema["awkSchemaFile"]=info["awkSchemaFile"]
	schema["awkDomFolder"]=info["awkDomFolder"]
	schema["depsRoot"]=info["depsRoot"]
	schema["keyCol"]=info["keyCol"]
	schema["dependents"]=info["dependents"]

	# if the domFolder is not already set, it will take the value of the first schema that has one set
	if (!domFolder) domFolder=schema["awkDomFolder"]

	# members keyCols,secondaryKeyCols,anyKeyCols are set arrays to work with the keys
	spliti2(info["keyCol"],           schema, "keyCols",  "@"   ) # creates schema["keyCols"]
	spliti2(info["secondaryKeyCols"], schema, "secondaryKeyCols") # creates schema["secondaryKeyCols"]
	spliti2(info["anyKeyCols"],       schema, "anyKeyCols"      ) # creates schema["anyKeyCols"]

	# member colFields is a map to translate a column name to a field position.
	# setting _CLASS so it can be used in places that expect a Data class object and those things know to dereference the result as a field number
	schema["colFields"]["_CLASS"]="NFieldMap"

	# members col* provide information about the columns
	split2(info["colNames"]      ,schema,"colNames")
	split2(info["colWidths"]     ,schema,"colWidths")
	split2(info["colWithWidths"] ,schema,"colWithWidths")
	schema["colNF"]=length(schema["colNames"])

	# init the colFields map with the special value 'any',$0
	schema["colFields"]["any"]=0

	# iterate columns to fill in the colFields and colTypes members
	for (i in schema["colNames"]) {
		colName=schema["colNames"][i]

		# make the reverse lookup map to translate from column name to field number
		schema["colFields"][colName]=i

		# classify each column name
		if (info["keyCol"] == colName)
			schema["colTypes"][i]="primeKey"
		else if (colName in schema["secondaryKeyCols"])
			schema["colTypes"][i]="secKey"
		else if (colName in schema["keyCols"])
			schema["colTypes"][i]="primeKeyPart"
		else
			schema["colTypes"][i]=""
	}

	# Check that each component column and secondary key column exists in the column list
	for (colName in schema["keyCols"]) if ( ! (colName in schema["colFields"]) )
		assert("AwkData Schema definition error for '"info["awkObjName"]"'.  keyCol contains '"colName"' which is not a column name defined in columns attribute. schema file is '"info["awkSchemaFile"]"'")
	for (colName in schema["secondaryKeyCols"]) if ( ! (colName in schema["colFields"]) )
		assert("AwkData Schema definition error for '"info["awkObjName"]"'.  secondaryKeyCols contains '"colName"' which is not a column name defined in columns attribute. schema file is '"info["awkSchemaFile"]"'")

	# These members will be filled in by the schema_addKeyAssociation as we scan the data files.
	arrayCreate2(schema, "normKey")              # creates schema["normKey"]
	arrayCreate2(schema, "conflictKeys")         # creates schema["conflictKeys"]
	arrayCreate2(schema, "associatedSecKeys")    # creates schema["associatedSecKeys"]
	arrayCreate2(schema, "associatedSecKeysSet") # creates schema["associatedSecKeysSet"]

	arrayCreate2(schema, "data") # creates schema["data"]

	if (awkDataBuildFolder)
		schema["outfile"]=awkDataBuildFolder"/"schema["awkDataID"]".cache"

	# we want the info member to contain the shemaInfo which may contain extra attributes specified in the schema file that specific
	# builders might use but some patterns initialize the info array in-place so its already there and we don't have to copy it.
	if (!("info" in schema))
		arrayCopy2(info, schema, "info")
}



#################################################################################################################################
### Schema Class Member Functions (Methods)

# usage: schema_writeHeader(schema, outfile)
# write awkData header lines to the outfile
function schema_writeHeader(schema, outfile                ,colField) {
	if (!outfile) outfile=schema["outfile"]
	if (!outfile) assert("schema_writeHeader: outfile (and schema[outfile]) should not be empty. awkDataID="schema["awkDataID"]"  awkDataBuildFolder="awkDataBuildFolder)
	for (colField in schema["colNames"])
		printf("%*s ", schema["colWidths"][colField], schema["colNames"][colField]) > outfile
	print "" > outfile # end the columns line
	print schema["dependents"] > outfile
}

# usage: schema_writeOutput(schema, outfile)
# write the data to a staging (tmp) file
# This is the generic base Class version of the algoirthm.
#    1) uses schema["data"][<row>][<colFN>]=<value> as the data to write
#    2) calls printf for each column separately using schema["colWidths"][<colFN>] for the field widths
function schema_writeOutput(schema, outfile                ,row,colField,colName) {
	if (!outfile) outfile=schema["outfile"]
	if (!outfile) assert("schema_writeHeader: outfile (and schema[outfile]) should not be empty. awkDataID="schema["awkDataID"]"  awkDataBuildFolder="awkDataBuildFolder)
	schema_writeHeader(schema, outfile)
	PROCINFO["sorted_in"]="@ind_str_asc"
	for (row in schema["data"]) {
		PROCINFO["sorted_in"]=""
		for (colField in schema["colNames"]) {
			colName=schema["colNames"][colField]
			printf("%*s ", schema["colWidths"][colField], schema["data"][row][colName]) > outfile
		}
		printf("\n") > outfile
	}
}

# usage: schema_addKeyAssociation(schema, primeKey, otherKeys)
# This function records that the specified keys are associated with the same record. It typically means that a data file includes
# each of these keys as attributes.
# Typically after each data file is read, whatever key values are present in that data is passed into this function which
# maintains several data structures that reflect the know set of key sets that are related.
# After all data is read, the output variables allow you to iterate the set of unique, difinitve records, possible duplicate
# records and records that are in conflict because multiple primaryKeys are associated through one more more associated
# secondaryKeys.
# Params:
#    schema     : (input) the 'this' pointer. aka the awk array that contains the schema object data
#    primeKey   : (input) the value of the primary key column for the set of data if known. Empty/null is not known.
#    otherKeys  : (input) a set of values of any secondary key columns known for the set of data
#    normKey             : (output) alias for schema["normKey"]
#    conflictKeys        : (output) alias for schema["conflictKeys"]
#    srcFiles            : (output) alias for schema["srcFiles"]
#    associatedSecKeys   : (output) alias for schema["associatedSecKeys"]
#    associatedSecKeysSet: (output) alias for schema["associatedSecKeysSet"]
function schema_addKeyAssociation(schema,primeKey,otherKeys, normKey,conflictKeys,srcFiles,associatedSecKeys,associatedSecKeysSet            ,otherPrime,key,key2,secKeyPool,sep,ary, allOtherKeys, i, tmpFileList) {
	if (primeKey) {
		normKey[primeKey]=primeKey
		for (key in otherKeys) {
			if ((key in normKey) && normKey[key]!="" && normKey[key]!=primeKey) {
				otherPrime=normKey[key]
				conflictKeys[otherPrime]=appendStr(conflictKeys[otherPrime], otherPrime","primeKey)
				conflictKeys[primeKey]=conflictKeys[otherPrime]
				msg=sprintf("%s(key:%s ! %s) two primary keys are associated with the secondary key (%s)",
					schema["awkObjName"], primeKey, otherPrime, key)
				split(srcFiles[primeKey]" "srcFiles[otherPrime]" "srcFiles[key], tmpFileList)
				if (verbosity>1) {
					print msg >"/dev/stderr"
					for (i in tmpFileList) printf("\t%s\n", tmpFileList[i]) >"/dev/stderr"
				}
				if (conflictingKeysFile) printf("%s in files %s\n", msg, srcFiles[primeKey]" "srcFiles[otherPrime]" "srcFiles[key]) >> conflictingKeysFile
			}
			normKey[key]=primeKey
			if (key in associatedSecKeys) {
				split(associatedSecKeys[key], ary, ",")
				for (key2 in ary) {
					normKey[key2]=primeKey
					delete associatedSecKeys[key2]
				}
			}
		}

	# save the sec key association for possible later use
	} else if (length(otherKeys)>1) {
		# if any of the otherKey has an existing association to other sec keys, we will combine them
		# either way, allOtherKeys will become the new otherKeys that additionally has other secKeys we find
		for (key in otherKeys) {
			allOtherKeys[key]=1
			if (key in associatedSecKeys) {
				# remove the matching pool of secKeys from associatedSecKeys(Set) and merge them into allOtherKeys
				delete associatedSecKeysSet[associatedSecKeys[key]]
				split(associatedSecKeys[key], ary, ",")
				for (key2 in ary) {
					allOtherKeys[key2]=1
					delete associatedSecKeys[key2]
				}
			}
		}
		# allOtherKeys may just be the otherKeys passed in or might have had a found existing pool added in at this point
		# if there was an existing pool found it will have been removed so now we add the new (possibly combined) pool back in
		secKeyPool=join(allOtherKeys)
		associatedSecKeysSet[secKeyPool]=1
		for (key in allOtherKeys)
			associatedSecKeys[key]=secKeyPool
	}
}

function schema_isDirty(schema             ,savePWD,result) {
	# TODO: this does not account for files that existed when awkFile was built but do not now. We should read the actual deps in awkFile and use an algorithm that considers missing files to be 'newer'. The awkFile deps should contain the real file list and also the glob list?
	split2(schema["info"]["dependents"], schema, "dependentSpecs")
	savePWD=ENVIRON["PWD"]
	chdir(schema["depsRoot"])
	result=fsIsNewer(schema["dependentSpecs"], schema["awkFile"])
	chdir(savePWD)
	return result
}



#################################################################################################################################
### Data Class Methods

# usage: data_getKeyValue(data, key, results)
# Return the value of the specified <key> in <data>. If key is "name" it returns the value data["name"]. If key is a composite
# key with multiple column parts it combines the values in a comma separated list. It resturns the value two ways -- one with
# just the values and another with <colName>:<value> terms.
# Params:
#     <key>    : identifies the column(s) that make up this key. It is a list of column names separated by the "@" character.
#                A single column name is a valid key if the values in that columns are unique for every record. The combined
#                value of each key component should be unique for every record
#    <results> : an array that will be filled in with the results. Its an array so that two values can be returned
#                <results>["key"]=<key> : this records the key name (aka column name(s)) of the key so that the results array stands only
#                <results>["value"]=<keyColVal1>[..,<keyColValN>] -- each element is the value corresponding to one component column
#                <results>["term"]=<keyColName1>:<val1>[...,<keyColName2>:<val2>] -- each element is <colName>:<value> corresponding to one component column
#    <data>    : an associative array that contains one data record where the indexes are the column names. if data["_CLASS"]=="NFieldMap"
#                the values of data are deferenced with $ to get the values from the current awk line record ($1 $2 ...)
#                if _CLASS is missing or anything else, the value of data[<colName>] is used directly.
function data_getKeyValue(data, key, results,             value,keyCol,keyCols,sep) {
	results["key"]=key
	results["term"]=""; sep=""; results["value"]=""
	spliti(key, keyCols, "@")
	for (keyCol in keyCols) {
		value=data[keyCol]
		if (data["_CLASS"]=="NFieldMap") value=$value
		results["value"]=results["value"]""sep""value
		results["term"]=results["term"]""sep""keyCol":"value
		sep=","
	}
	results["term"]=(!results["term"])? "--" : results["term"]
}


#################################################################################################################################
### Table Format (TblFmt) Class Methods

# usage: tblFmt_writeBeginning(tblFmt, colNames, outFields)
# Writing a formatted tabular output is done in three parts.
#       tblFmt_writeBeginning
#            (once for each data) tblFmt_writeRowFrom
#       tblFmt_writeEnding
# This is typically called from the BEGIN section of query scripts
# Params:
#    tblFmt    : the table format description. (typically from a awkDataTblFmt.<type> template)
#    colNames  : array of column names from the schema
#    outFields : ordered array of field numbers that will be included in the output. Field number is the numeric index into the
#                data columns
function tblFmt_writeBeginning(tblFmt, schema, outFields, headerFlag) {
	printf(tblFmt["tblPre"])

	if (length(outFields)>1)
		arrayCopy2(schema["colWidths"], tblFmt,"widths")

	if (headerFlag) {
		switch (tblFmt["colLabelType"]) {
			case "header":
				# write the header row
				for (i in outFields) {field=outFields[i]; tblFmt["widths"][field]=absmax(tblFmt["widths"][field], length(schema["colNames"][field]))}
				printf(tblFmt["headerRowPre"])
				for (i in outFields) {field=outFields[i]; printf(sep""tblFmt["headerCellPre"]"%*s"tblFmt["headerCellPost"], tblFmt["widths"][field], schema["colNames"][field]) ;sep=tblFmt["cellSep"]}
				printf(tblFmt["headerRowPost"])
				break
			case "inline":
				# prepare the label data for tblFmt_writeRowFrom to use inline
				for (i in outFields) {field=outFields[i]; tblFmt["colMaxWidth"]=max(tblFmt["colMaxWidth"], length(schema["colNames"][field]))}
				for (i in outFields) {
					field=outFields[i]
					tblFmt["labels"][field]=sprintf("%-*s", tblFmt["colMaxWidth"], schema["colNames"][field])
					tblFmt["widths"][field]=0
				}
				break
		}
	}
}

# usage: tblFmt_writeRowFrom(tblFmt, data, outFields)
# Writing a formatted tabular output is done in three parts.
#       tblFmt_writeBeginning
#            (once for each data) tblFmt_writeRowFrom
#       tblFmt_writeEnding
# This is typically called from matching line sections of query scripts
# Params:
#    tblFmt : a definition that defines how the record will be written
function tblFmt_writeRowFrom(tblFmt, data, outFields                          ,i,sep,field) {
	if (tblFmt["hasFirstRowBeenWritten"]) printf(tblFmt["rowSep"])
	tblFmt["hasFirstRowBeenWritten"]=1

	printf(tblFmt["rowPre"])
	switch ((isarray(data) && length(data))":"(isarray(tblFmt["labels"]))) {
		case "1:0": for (i in outFields) {field=outFields[i]; printf(sep""tblFmt["cellPre"]"%*s"tblFmt["cellPost"], tblFmt["widths"][field], denorm(data[field])) ;sep=tblFmt["cellSep"]}; break
		case "1:1": for (i in outFields) {field=outFields[i]; printf(sep""tblFmt["headerCellPre"]"%s"tblFmt["headerCellPost"]""tblFmt["cellPre"]"%*s"tblFmt["cellPost"], tblFmt["labels"][field], tblFmt["widths"][field], denorm(data[field])) ;sep=tblFmt["cellSep"]}; break
		case "0:0": for (i in outFields) {field=outFields[i]; printf(sep""tblFmt["cellPre"]"%*s"tblFmt["cellPost"], tblFmt["widths"][field], denorm($field)) ;sep=tblFmt["cellSep"]}; break
		case "0:1": for (i in outFields) {field=outFields[i]; printf(sep""tblFmt["headerCellPre"]"%s"tblFmt["headerCellPost"]""tblFmt["cellPre"]"%*s"tblFmt["cellPost"], tblFmt["labels"][field], tblFmt["widths"][field], denorm($field)) ;sep=tblFmt["cellSep"]}; break
	}
	printf(tblFmt["rowPost"])
}


# usage: tblFmt_writeEnding(tblFmt, colNames, outFields)
# Writing a formatted tabular output is done in three parts.
#       tblFmt_writeBeginning
#            (once for each data) tblFmt_writeRowFrom
#       tblFmt_writeEnding
# This is typically called from the END section of query scripts
# Params:
#    tblFmt    : the table format description. (typically from a awkDataTblFmt.<type> template)
function tblFmt_writeEnding(tblFmt) {
	printf(tblFmt["tblPost"])
}

function tblFmt_get(tblFmt, templateFile, schema            ,rematch,name,value,fileRead) {
	cuiRealizeFmtToTerm("on")

	fileRead=0
	if (templateFile) while ( (getline line < templateFile) >0 ) {
		#<attributeName> = <attributeValue>
		if (match(line, /^[[:space:]]*([^=[:space:]]*)[[:space:]]*=[[:space:]]*(.*)$/, rematch)) {
			fileRead=1
			name=rematch[1]
			value=""stringTrimQuotes(rematch[2])
			value=""stringExpand(value)
			tblFmt[name]=value
		}
	}
	# the default table format if no template was specified or template does not exist
	if (!fileRead) {
		# a a template was specified but does not exist, warn the user
		if (templateFile) warning("table format template "templateFile"not found. using default txt format")

		tblFmt["colLabelType"] = "header"
		tblFmt["headerCellPre"] = "%csiFaint%%csiReverse%"
		tblFmt["headerCellPost"]= "%csiNorm%"
		tblFmt["headerRowPre"]   = ""
		tblFmt["headerRowPost"]  = ""
		tblFmt["cellPre"] = ""
		tblFmt["cellPost"]= ""
		tblFmt["cellSep"] = " "
		tblFmt["rowPre"]   = ""
		tblFmt["rowPost"]  = "\n"
		tblFmt["rowSep"]   = ""
	}
}