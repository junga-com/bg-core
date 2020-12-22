#!/bin/bash

import bg_strings.sh ;$L1;$L2
import bg_ini.sh ;$L1;$L2


######################################################################################################
### Schema data operations  -- objectTypes (tables), columns, and ranges of values
#

# MAN(5) bgawkDataSchemaFileFormat
# The awkData schema file is a way to define a awkData cache file that is persistent past the deletion
# of its actual cache file. Say the cache file is deleted because its dirty. In order for it to be rebuilt
# the metadata to know the columns and buildCmd need to be known. Sometimes it is convenient to hardcode
# that metadata in a script that will rebuild the cache file as needed whenever it runs but often its
# better to create a schema file. The presence of a schema file, even an empty one, signifies that the
# awkDataID identified by its filename should exist. If it additionally contains a buildCmd attribute
# the tools can automatically build the cache file whenever its needed.
#
# A generic buildCmd will read its input files and column name list from the schema file instead of
# hardcoding them. That way multiple schema files can use the same buildCmd to produce very different
# restults.
#
# By @including bg_awkDataSchema.awk, a script will automatically read the schema file identified in the awkObjData
# passed into it. See schema_restore() in the bg_awkDataSchema.awk library
#
# A schema file is similar to a DB table definition. That is why the columns attribute is called columns.
#
# Defintions:
#    awkObjName : the simple name of the table. No / or :. Just a word that could be a valid variable name.
#    awkDataID : the awkObjName with optional specifiers. The awkDataID value can be in the short form or the long form.
#                The short form is a consice description of the identity which may or may not be relative to the current domData
#                The long form is a string of | separated components where the first component is the short form and the other
#                components are the attributes that the identity implies which may include information derived from the current domData
#                the awkDataID short form is the natural key for identifing what to operate on.
#                The short form supports several formats.
#                See awkData_parseID
#    awkFile   : the path to the cache file that contains the data for this table (may or may not exist)
#    awkSchemaFile :  the path to the schema file that contains the definition for this table (may or may not exist)
#    dependents : file list with optional globs that are the input files to build the table
#
# Schema File Locations:
# If an awkData query function is called with an awkDataID whose cache file does not exist or is dirty,
# if a schema can be located for the awkDataID, it will be used to invoke the buildCmd to create an
# up-to-date cache file.
#
# The awkDataID of an awkData cache file that is independent of a domData is the path used to access it.
# The path may be relative or absolute so it can vary. Relative names are preserved but when compared,
# a temporary absolute path will be created to do the comparison. Indendent awkData files can have a
# schema file by placing a similarly named .schema file next to the cache file. If the cache file ends
# in .cache, .cache is replaced with .schema. If that does not produce the path of an existing file,
# .schema is appended to the whole filename and its check again for existence.
#
# AwkDataID that are a part of a domData have simple names without paths and without extensions.
# Schema files are located in $domFolder/schema/<awkDataID>.schema
# The corresponding cache file is at $domFolder/cache/*.cache
#
# Schema File Format:
# Schema files use the INI file format. see man(5) bginiFileFormat
# The awkDataID attributes are stored in ParameterSettings of the INI schema file
#  INI Sections:
# The atributes in the top level, default INI section corespond to the global scope of the domData.
# If the awkDataID is not in a domData, the scheam file can only contain the top level section.
# In the context of a domData, however, additional sections can be added to describe the cache files
# for this awkDataID that are created and stored in scope folders of the domData (e.g. servers/ or locations/)
# The attributes of the top level section are inherited at the scope level so only the attributes that
# are different need to be specified in the scope section. A typical scenario would be for the scoped
# section would specify a buildCmd and dependents input files that extract the information from source files
# collected for each scope and then the global scope (top level INI section) would use the akwDataFileMerge
# builder function to aggregate the cache files from the scope into one larger file at the global level.
#
#  AwkData Attributes:
# The schema file contains attributes of the awkDataID stored in the ParameterSettings. These attributes
# are primarily helpful to the buildCmd to influence how it creates the cache file but sometimes query
# or other operations may be influenced by these attributes too.
#
#     buildCmd  : the *nix style commandline to invoke to build the cache file. Some %<name>% template
#        variables can be used
#
#     columns   : (used by builder) whitespace separated list of column names optionally annotated with
#        a width <colname>(<width>) the optional <width> is just a hint to the builder on how to format
#        the data file. Query functions will glean this information from the spacing that the builder uses
#        when writing the column line in the cache file.  A builder often may be able to collect a large
#        number of columns but this tells it explicity which it should collect and include in the cache file.
#        Any others that it comes across will be ignored.
#     dependents: (used by builder) These will be used by most builders as the input files that it should
#        read to obtain its information to include in the cache file. Each token is a path name relative
#        to the domFolder (if not absolute). Tokens can contain wildcard adhering to linux glob standard.
#        A builder will typically copy these to the dependency line of the cache file it creates but remove
#        any that were not found to exsit and add the specific files that matched any glob patterns.
#        This attribute is therefore similar to the dependency line in the cache file but not the same thing.
#
#     defDisplayCols: a subset of column names that should be displyed by defatult in the output of query
#        operations. The actual output column list can be specified in the query command line.
#     defFilter : a row filter that is applied to query output by default. The -p (plain) option cancels this.
#     keyCol : the column whose values will be unique in the file and should be used whenever an identifying
#         name for the object represented by the data row is needed.
#     secondaryKeyCols : other columns whose values will also be unique for each row but are not the ones
#         that should be used as the default identifying name.
#     dirtyStateMethod : obsolete. you may see it in old schema files but it is now ignored.
#
# Other attributes can exist. Mostly, the builder function named in the buildCmd line determines which
# attributes are available and may be required.
#
# See Also:
#     man(1) bg-awkData
#     man(5) bgawkDataFileFormat
#     man(5) bginiFileFormat
#     man(3) awkData_parseID  : defines the supported syntax of awkDataIDs





# usage: awkData_parseID <awkDataID> <awkObjNameVar> <awkFileVar> <awkSchemaFileVar>
# (old usage): awkData_parseID [-C <domID>] [--awkObjDataVar=<awkObjDataVar>] <awkDataID> <scopeTypeVar> <scopeNameVar> <awkObjNameVar> <awkFileVar> <awkSchemaFileVar> <awkDomFolderVar> <awkDepsRootVar>
# Given the <awkDataID>, return the <awkObjNameVar> <awkFileVar> and <awkSchemaFileVar>
#
# Supported Syntax:
# An <awkDataID> is one of these
#    Long Form:
#       <shorForm>|scopeType|scopeName|awkObjName|awkFile|awkSchemaFile|awkDomFolder|depsRoot
#    Short Form:
#       <awkObjName>
#       <path/to/cachefile>
#       <path/to/schemafile>
#       (disabled) <scopeType>:<scopeName>:<awkObjName>
#       (disabled) <scopeName>:<awkObjName>
#       (disabled) index
#       (disabled) me:<awkObjName>
#       (disabled) local:<awkObjName>
# Where
#     <awkObjName> : is the simple name of the data table without path or extension or scope modifiers
#     path/to/file :
#          if the awkDataID contains one or more '/', then it is considered to be a path to an awkData file
#          if the path refers to a <scope>./cache/ file, inside a domFolder it will treat it as such.
#     (disabled) <scopeType>:<scopeName> : is the fully qualified scope folder relative to a domData
#     (disabled) <scopeName> : (alone) is the partially qualified scope folder relative to a domData. If <scopeName>
#          is unique in the referenced domData, <scopeType> will be filled in automatically.
#     (disabled) me: : is a special scope modifier in the domData that refers to scope path returned by $(domWhoami -p)
#          note that 'me' can also be a <scopeName> so servers:me is equivalent. locations:me is the location
#          scope that represents the location where the host is located
#     (disabled) local: : is a special scope modifier that refers to a local folder that is specifically not tracked in the domData but
#          is associated with the domData.
#     (disabled) index :
#          an awkData cache file named "index" is maintained that contains all the values used in any other global awkData
#          this can be used to query by a data value and see where in the domain that value is used. This is particularely
#          helpful for serial numbers, mac address and other unique identifiers. This replaces the domIndex
#          $domFolder/cache/index
#     (disabled) <scopeType>:[:]<awkObjName> :
#          refers to all partial <awkObjName> in that scope type. The first part of an awkDataID with one : can
#          be a scopeType or a scopeName. If the word matches the short list of known scopeTypes, it is a type.
#          $domFolder/<scopeType>/*/cache/<awkObjName>.cache
#     (disabled) [:]<scopeName>:<awkObjName> :
#          refers to the specific partial scope <awkObjName>. The scopeType can be omitted if scopeName is unambiguous.
#          $domFolder/*/<scopeName>/cache/<awkObjName>.cache
# Options:
#    (disabled) -C <domID> : override the default domData to operate on. Can be domain name or folder path
#    --awkObjDataVar=<awkObjDataVar> : this is a return string that contains all the others joined with the '|' character.
#          this is often used to pass the parsed results to an awk script
# Exit Codes:
#    0(success)  : the <awkDataID> was parsed. It might not exist, but its a recognized format that can be parsed
#    1(failure)  : the <awkDataID> is not a valid form. Initially, the only invalid form is the empty string
# See Also:
#    awkData_getSchema      : super set of this function that goes on to read the schema attributes too
#    awkData_listAwkDataIDs : list <awkDataID> that exist on the host
function awkData_parseID()
{
	local ldFolder="$ldFolder" domIDOverride forceFlag awkObjDataVar quietFlag
	while [ $# -gt 0 ]; do case $1 in
		# (disabled) -C*)              bgOptionGetOpt val: domIDOverride "$@" && shift ;;
		--awkObjDataVar*) bgOptionGetOpt val: awkObjDataVar "$@" && shift ;;
		-q) quietFlag="-q" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	local awkDataID="$1";    [ ! "$awkDataID" ] && return 1
	local awkObjNameVar="$4"
	local awkFileVar="$5"
	local awkSchemaFileVar="$6"

	local scopeTypeValue scopeNameValue awkObjNameValue awkFileValue awkSchemaFileValue awkDomFolderValue awkDepsRootValue

	# we already parsed this awkDataID into its long form so just use those values
	if [[ "$awkDataID" =~ [|] ]]; then
		IFS="|" read -r awkObjNameValue awkFileValue awkSchemaFileValue <<<"$awkDataID"

	# # me: syntax allows us to specify the awkObjName that is specific to the local host and will be in
	# # the domData if the domData exists but it is quaranteed to exist regardless of whether a domData
	# # exists and whether this host has a persistent scope in the domFolder
	# # domWhoami -p is responsible for determining this path and making sure it exists
	# elif [[ "$awkDataID" =~ ^me: ]]; then
	# 	_domMethodPreamble "$domIDOverride"
	# 	scopeTypeValue="servers"
	# 	scopeNameValue="me"
	# 	awkObjNameValue="${awkDataID#me:}"
	# 	local scopeFolder; domWhoami -p -r scopeFolder
	# 	[ ! -d "$scopeFolder" ] && assertError -v awkDataID -v scopeFolder "parsing me: scope but domWhoami -p did not return a folder that exists"
	# 	awkFileValue="${scopeFolder%/}/cache/${awkObjNameValue}.cache"
	# 	awkSchemaFileValue="${ldFolder:+${ldFolder}/schema/${awkObjNameValue}.schema}"
	# 	awkSchemaFileValue="${awkSchemaFileValue:-${awkFileValue%.cache}.schema}"
	# 	# if the domWhoami -p returned a folder outside any domData because there was none selected
	# 	# should we return "" or the domFolder root of the scope folder?
	# 	awkDomFolderValue="${ldFolder}" # will be empty if there is no domData. that is correct
	# 	awkDepsRootValue="${awkDomFolderValue:-${awkFileValue%/*}}"
	#
	# # local: syntax allows us to specify the awkObjName that is specific to the local host
	# # and never stored in the domdata. It can be a host wide shared folder or a transient folder in the
	# # user's home
	# elif [[ "$awkDataID" =~ ^local: ]]; then
	# 	_domMethodPreamble "$domIDOverride"; domAssertLdFolder; awkDomFolderValue="$ldFolder"
	# 	awkObjNameValue="${awkDataID#local:}"
	# 	local scopeFolder="$awkDomFolderValue/.bglocal/localScope"
	# 	mkdir -p "$scopeFolder"
	# 	awkFileValue="${scopeFolder%/}/cache/${awkObjNameValue}.cache"
	# 	awkSchemaFileValue="${scopeFolder%/}/schema/${awkObjNameValue}.schema"
	# 	awkDepsRootValue="${awkDomFolderValue:-${awkFileValue%/*}}"
	#
	# # host: syntax allows us to specify the awkObjName that is specific to the host and not associated with a domData
	# elif [[ "$awkDataID" =~ ^host: ]]; then
	# 	awkObjNameValue="${awkDataID#host:}"
	# 	local scopeFolder="$domFolderRootPath/host"
	# 	[ ! -d "$scopeFolder" ] && fsGetUserCacheFile "userDomFolder/" scopeFolder
	# 	[ ! -d "$scopeFolder" ] && assertError "parsing host: scope but 'fsGetUserCacheFile userDomFolder/' failed to return a folder that exists"
	# 	awkFileValue="${scopeFolder%/}/cache/${awkObjNameValue}.cache"
	# 	awkSchemaFileValue="${scopeFolder%/}/schema/${awkObjNameValue}.schema"
	# 	awkDomFolderValue="${scopeFolder%/}"
	# 	awkDepsRootValue="${awkDomFolderValue:-${awkFileValue%/*}}"

	# this block is for filename that are specified as awkObjNames. If it contains a / or .
	# it can not be a valid domData awkObjName name, it must be a filename
	elif [[ "$awkDataID" =~ [/.] ]]; then
		awkObjNameValue="${awkDataID%/}"; awkObjNameValue="${awkObjNameValue##*/}"
		awkFileValue="${awkDataID}"
		awkSchemaFileValue="${awkFileValue%.cache}.schema"
		awkDepsRootValue="${awkDomFolderValue:-${awkFileValue%/*}}"

	# # <scopeType>:<scopeName>:<awkObjName> syntax
	# elif [[ "$awkDataID" =~ ^([^:]*):([^:]*):(.*)$ ]]; then
	# 	scopeTypeValue="${BASH_REMATCH[1]}"
	# 	scopeNameValue="${BASH_REMATCH[2]}"
	# 	awkObjNameValue="${BASH_REMATCH[3]}"
	# 	_domMethodPreamble "$domIDOverride"; domAssertLdFolder; awkDomFolderValue="$ldFolder"
	# 	awkFileValue="$ldFolder/$scopeTypeValue/$scopeNameValue/cache/${awkObjNameValue}.cache"
	# 	awkSchemaFileValue="$ldFolder/schema/${awkObjNameValue}.schema"
	# 	awkDepsRootValue="${awkDomFolderValue:-${awkFileValue%/*}}"
	#
	# # <scopeName>:<awkObjName> syntax
	# elif [[ "$awkDataID" =~ ^([^:]*):(.*)$ ]]; then
	# 	scopeNameValue="${BASH_REMATCH[1]}"
	# 	awkObjNameValue="${BASH_REMATCH[2]}"
	# 	domScopeGetType "$scopeNameValue" scopeTypeValue
	# 	[ ! "$quietFlag" ] && [ ! "$scopeTypeValue" ] && assertError -v awkDataID -v ldFolder -v scopeNameValue "could not resolve the <scopeName> in the specified <domFolder>"
	# 	_domMethodPreamble "$domIDOverride"; domAssertLdFolder; awkDomFolderValue="$ldFolder"
	# 	awkFileValue="$ldFolder/$scopeTypeValue/$scopeNameValue/cache/${awkObjNameValue}.cache"
	# 	awkSchemaFileValue="$ldFolder/schema/${awkObjNameValue}.schema"
	# 	awkDepsRootValue="${awkDomFolderValue:-${awkFileValue%/*}}"

	# <awkObjName> syntax
	else
		awkObjNameValue="$awkDataID"
		awkSchemaFileValue="$ldFolder/schema/${awkObjNameValue}.schema"
		awkDepsRootValue="${awkDomFolderValue:-${awkFileValue%/*}}"
	fi


	setReturnValue "$awkObjNameVar"    "$awkObjNameValue"
	setReturnValue "$awkFileVar"       "$awkFileValue"
	setReturnValue "$awkSchemaFileVar" "$awkSchemaFileValue"

	# This awkObjData value is used to pass all the parsed attributes to an awk script in a way that the script script can easily parse it
	# See schema_restore
	#                                     awkDataID ,awkObjName       ,awkFile      ,awkSchemaFile
	#                                     1          2                 3             4
	setReturnValue "$awkObjDataVar"     "$awkDataID||$awkObjNameValue|$awkFileValue|$awkSchemaFileValue"
}


#    schemas[<awkObjName>][<attributes>]
#    schemas[<awkObjName>]["dataCols"][<colName>]["width"]
#    schemas[<awkObjName>]["dataCols"][<colName>]["fieldNum"]
#    schemas[<awkObjName>]["dataCols"][<colName>]["name"]




# usage: awkData_getSchema [-C <domID>] <awkDataID> <attribsArrayVar> [<scopeTypeVar> <scopeNameVar> <awkObjNameVar> <awkFileVar> <awkSchemaFileVar> <awkDomFolderVar> <awkDepsRootVar>]
# usage: local awkDataID="${1:-$awkDataID}"; shift; [ "$awkSchema" != "$awkDataID" ] && { local -A awkSchema=(); awkData_getSchema $domIDOverrideOpt "$awkDataID" awkSchema; }
# this is the common preamble for functions that operate on an awkDataID. (aka method functions of awkData)
# This wraps a call to awkData_parseID and in addition, loads the schema file into an array var
# read all the schema attributes into an associative array.
#    1) If a schema file exists it will be prefered.
#    2) If no schema file exists or if it does not cantain the column attribute, the header of the cache file will be read
#    3) if neither exists, the exist code is 1(false)
# if <awkDataID> contains a scope modifier, the attributes will be realized for that scope. This means
# that any attributes that are specified in a matching scope section will be promoted to overwrite
# the same attribute at the top level. Also, the <awkFile> path (data cache file) will be in the
# $domFolder/$scopeType/$scopeName/cache/ folder instead of the global $domFolder/cache/ folder
# Attributes Returned:
#    * the input to this function
#         [awkDataID]      : the identifier of the awkData being operated on.
#    * the attributes returned by awkData_parseID. These are all derived from the awkDataID alone.
#         [scopeType]     : servers|locations|etc...
#         [scopeName]     : name of folder under the scopeType/ folder
#         [awkObjName]    : the simple name of the <awkDataID>. For domData it is <awkDataID> but for a path
#                           based <awkDataID>, it is the simple base filename with path and .cache extension removed
#         [awkFile]       : the path to the cache data file which may or may not exist
#         [awkSchemaFile] : the path to the schema file which may or may not exist
#         [depsRoot]      : the folder where the dependent paths are relative to.
#    * data read from the schema file if it exists, Every attribute in the schema file will be represented in the returned array.
#      Typically a schema will include...
#         [columns]          : column names, each with optional width
#         [buildCmd]         : the command used to build the awkFile from the <dependents>
#         [dependents]       : input files to the builder. can contain wildcards. paths relative to
#         [defDisplayCols]   : default columns that query functions should include in output.
#         [keyCol]           : the column whose value uniquely identifies each data row
#         [secondaryKeyCols] : other columns that are also unque across all data rows
#         [defFilter]        : filter that query functions should use by default to exclude some rows from the output
#    * Generated, synthesized Attributes
#         [schemaType]     : domData|independent
#         [schemaFileRead] : non-empty if data was read from the schema file
#         [cacheFileRead]  : non-empty if data was read from the cache file
#         [noSchemaDataFound]: non-empty if neither the schema file nor cache file were found
#         [columnsWithWidths]: normalized version of the columns attribute where every colName has a width
#                       specifiers. The default width is the length of the colName
#         [colNames]  : normalized version of the columns attribute where each token is just the colName
#         [colWidths] : normalized version of the columns attribute where each token is just the column width
#         [anyKeyCols]: combined keyCol and secondaryKeyCols attribute. (but composite keyCol are ignored, currently)
#                       The spirit of this attribute is any column whose value is unique. Eventually it
#                       should add a composite keyCol but that is not supported now becuse there is no
#                       universal syntax to combine the keyCol columns into one token that would later
#                       be recognized as multiple, related columns
#         [fmtStr]    : a printf format string suitable for printing column header and data lines in an awkData file
#    * --processDeps: (the following are created if --processDeps option is specified)
#         [depsStatic]  : a sub list of just the dependents that do not have glob character (*?[)
#         [depsGlobs]   : a sub list of just the dependents that have glob characters (*?[)
#         [depsCurrent] : a list of the actual dependents that exist now expanding the globs
# Params:
#    <awkDataID>       : aka <awkObjName>. Identifies the thing being operated on. Any syntaxt supported by awkData_parseID
#    <attribsArrayVar> : the name of the assiciative array declared in the callers scope that will be filled in.
# Options:
#    -C <domID>    : override the default domData to operate on. Can be domain name or folder path
#    --processDeps : process the [dependents] attrubute to create [depsStatic] [depsGlobs] and [depsCurrent]
# Exit Codes:
#   0(true)  : some schema data was found, either from a schema file or the cache file header
#   1(false) : no schema data was found. the parsed awkDataID information is still returned
# See Also:
#    awkData_parseID
#    awkDataLibraryReadSchema
function awkData_getSchema()
{
	#bgtimerStartTrace -T awkData_getSchema
	local domIDOverrideOpt processDeps awkObjDataVar
	local -A _localSchemaVar
	while [ $# -gt 0 ]; do case $1 in
		-C*) bgOptionGetOpt opt: domIDOverrideOpt "$@" && shift ;;
		--awkObjDataVar*) bgOptionGetOpt val: awkObjDataVar "$@" && shift ;;
		--processDeps) processDeps="$1" ;;
		*)   bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	local awkDataIDParam="$1"
	local attribsArrayVar="${2:-_localSchemaVar}"
	local scopeTypeVar="${3:-scopeType}"        ;  [ "$3" ] || local scopeType
	local scopeNameVar="${4:-scopeName}"        ;  [ "$4" ] || local scopeName
	local awkObjNameVar="${5:-awkObjName}"      ;  [ "$5" ] || local awkObjName
	local awkFileVar="${6:-awkFile}"            ;  [ "$6" ] || local awkFile
	local awkSchemaFileVar="${7:-awkSchemaFile}";  [ "$7" ] || local awkSchemaFile
	local awkDomFolderVar="${8:-awkDomFolder}"  ;  [ "$8" ] || local awkDomFolder
	local awkDepsRootVar="${9:-awkDepsRoot}"    ;  [ "$9" ] || local awkDepsRoot
	[ ! "$awkObjDataVar" ] && { local awkObjDataValue; awkObjDataVar="awkObjDataValue"; }

	awkData_parseID $domIDOverrideOpt --awkObjDataVar="$awkObjDataVar" "$awkDataIDParam" "$scopeTypeVar" "$scopeNameVar" "$awkObjNameVar" "$awkFileVar" "$awkSchemaFileVar" "$awkDomFolderVar" "$awkDepsRootVar" || assertError

	local schemaVarsScript; IFS="" read -r -d "\0" schemaVarsScript < <(awk  \
		-v awkDataIDList="${!awkObjDataVar}" '
		@include "bg_awkDataSchema.awk"
		END {
			for (name in schemas["'"$awkDataIDParam"'"]["info"])
				print "'"$attribsArrayVar"'["name"]='\''"schemas["'"$awkDataIDParam"'"]["info"][name]"'\''"
		}
	' /dev/null)
	eval "$schemaVarsScript"

	if [ "$processDeps" ]; then
		local depsRaw schemaDeps="$attribsArrayVar[dependents]" schemaDepsGlobs="$attribsArrayVar[depsGlobs]" schemaDepsStatic="$attribsArrayVar[debsStatic]" schemaDepsCur="$attribsArrayVar[depsCurrent]"
		read -r -a depsRaw <<<"${!schemaDeps}"
		local dep; for dep in "${depsRaw[@]}"; do
			[[ "$dep" =~ [*?[] ]] && stringJoin -R "$schemaDepsGlobs" -a -e -d " " "$dep" || stringJoin -R "$schemaDepsStatic" -a -e -d " " "$dep"
		done
		stringJoin -R "$schemaDepsCur" -a -e -d " " "$(cd "${!awkDepsRootVar}"; fsExpandFiles -E ${attribsArrayValue[dependents]})" #"
	fi

	# if the user did not pass in an array var name to fill in, write the results to standard out
	if [ "$attribsArrayVar" == "_localSchemaVar" ]; then
		printfVars schema:$attribsArrayVar
	fi

	# set the exit code to indicate if schema data was found 0(true), or the array only contains parsed awkDataID attributes 1(false)
	local noSchemaDataFoundCheck="$attribsArrayVar[noSchemaDataFound]"
	[ ! "${!noSchemaDataFoundCheck}" ]
}



# usage: awkData_listAwkDataIDs [<scopeType>:][<scopeName>:][<awkDataIDSpec>]
# CRITICALTODO: there seems to be ambiguity about the intent of different callers of this function. Some want to list ids of existing
#               data files and others seem to list all the schemas that could exists at a scope requardless of whether they exist yet.
#               The typical use cases are:
#                      ""   -- just list all the known schema types (or does the caller want a list of existing ids that can be queried?)
#                      "<fullyQualified>" -- a function supports wildcards but the caller specified a specific id and we should just return that id
#                      "<wildcards>" (including specs ending with a : like <scopeType>:<scopeName>:)
# awkDataIDs are the names that identify a particular awk data schema definition at a particular scope.
#    awk data schema definition: The awkObjName is the part of the awkDataID that identifies the scheama. This schema definition
#        is the column list and other attributes that affect how the table is built and queried. The definition is typically
#        stored in the .schema file
#    scope: the data in a schema can exist at multiple domData scopes. The global scope is the default and always exists.
#        some schemas can support component scopes that combine to form the data in the global scope and an awkDataID can
#        specify one of those sub-scopes
# Params:
#    <awkDataIDSpec> : this can be any syntax accepted by awkData_parseID as an awkDataID but can also include wildcards
#         or a partial awkDataID syntax so that it matches multiple awkDataIDs
#         The special values supported:
#            'this': refers to the awkDataID that is represented in the standard variable names
#                    used in awkData_parseID and awkData_getSchema. (awkSchema[] et.all) This is used in awkData_* methods
#                    to efficiently use the exiting context being operated on.
#            'all':  (default) list all known global awkDataIDs on the host
# Options:
#    -C <domID> : override the default domData to operate on. Can be domain name or folder path
# See Also:
#    awkData_parseID
function awkData_listAwkDataIDs()
{
	local ldFolder="$ldFolder" domIDOverride forceFlag
	while [ $# -gt 0 ]; do case $1 in
		-C*) bgOptionGetOpt val: domIDOverride "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift
	done
	local awkDataID="$1"

	# if it does not comply with any syntax for enumerating multiple ids, then just return it as is.
	if [[ ! "$awkDataID" =~ (^$)|(^all$)|[*?]|:$ ]]; then
		echo "$awkDataID"
		return
	fi

	_domMethodPreamble "$domIDOverride"

	case $awkDataID in
		# The 'this' value for awkDataID means that the awkObjName specified is the one that is already reflected in the
		# awkSchema[] inheritted from the caller
		this) echo "this"; return ;;
		all)  awkDataID="" ;;
		me:*)
			awkDataID="${awkDataID#me:}"
			local scopeFolder; domWhoami -p -r scopeFolder
			if [[ "$awkDataID" =~ [*?] ]]; then
				for i in $(fsExpandFiles --baseNames $scopeFolder/cache/$awkDataID.cache); do
					echo ${i%.cache}
				done
			else
				echo "$awkDataID"
			fi
			return
			;;
		local:*)
			assertError "check this code path -- it might be ok to comment out this assert"
			awkDataID="${awkDataID#local:}"
			local scopeFolder="$domFolderRootPath/local"
			for i in $(fsExpandFiles -b $scopeFolder/cache/*.cache); do
				echo local:$i
			done
			return
			;;
	esac

	local scopeType scopeName awkObjName prefix schemaScopeMatch="."
	awkData_parseID "$awkDataID" scopeType scopeName awkObjName

	local objTypeRegEx="^\\(.*:\\)*${awkObjName:-.*}$"
	[[ "$objTypeRegEx" =~ [*?] ]] && awkObjName=""

	# indexMatch will be 'index' or '' depending on whether we are listing objects in the global scope
	local indexMatch="index"

	local cacheFolder="${ldFolder}"

	if [ "$scopeType" ]; then
		cacheFolder="$cacheFolder/$scopeType/${scopeName:-*}"
		prefix="$scopeType:${scopeName:-%scopeName%}:"
		schemaScopeMatch="\bscope:$scopeType\b"
		indexMatch=""
	fi

	# schemaMatches are awkObjNames referenced in a schema file. Since .cache files are transient, it Could
	# be that the .cache file has not yet been built but we know from the schema file that it could be built.
	local schemaMatches="$(grep -l "$schemaScopeMatch" ${ldFolder}/schema/*.schema 2>/dev/null)"


	for i in $(echo $awkObjName $schemaMatches $indexMatch; bash -c "ls -d $cacheFolder/cache/*.cache" 2>/dev/null); do
		if [[ "$prefix" =~ %scopeName% ]] && scopeName="" && [[ "$i" =~ \.cache$ ]]; then
			scopeName=${i%cache/*}
			scopeName=${scopeName%/}
			scopeName=${scopeName##*/}
		fi
		i="$(basename "$i")"
		i="${i%.cache}"
		i="${i%.schema}"
		echo "${prefix//%scopeName%/${scopeName:-*}}$i"
	done | sort -u | grep "$objTypeRegEx"
}


# usage: awkData_showSchema [<awkDataID>]
# write out all the known <awkDataID> (in the domData) and each column they support in a tree
function awkDataCache_showSchema() { awkData_showSchema "$@"; }
function awkData_showSchema()
{
	local awkObjName; for awkObjName in $(awkData_listAwkDataIDs "$@"); do
		echo "$awkObjName"
		local column; for column in $(awkData_getColumns "$awkObjName"); do
			echo "   $column"
		done
	done
}

# usage: awkData_getColumns <awkDataID>
# return just the columns attrinbute of the schema.
# Note that if you need any other schema attributes or will call something that does, it is better to use awkData_getSchema
# which is about the same amount of work as this function but returns all the schema attributes in an array.
function awkData_getColumns()
{
	local domIDOverrideOpt
	while [[ "$1" =~ ^- ]]; do case $1 in
		-C*) bgOptionGetOpt opt: domIDOverrideOpt "$@" && shift ;;
	esac; shift; done
	local awkDataID="$1"

	if ! varIsA mapArray awkSchema || [ "${awkSchema["awkDataID"]}" != "$awkDataID" ]; then
		local -A awkSchema
		awkData_getSchema $domIDOverrideOpt "$awkDataID" awkSchema
	fi

	echo "${awkSchema["colNames"]}"
}

# usage: awkData_createSchema <templateFile> <schemaName>
function awkData_createSchema()
{
	local templateFile="$1"
	local schemaName="${2:-${templateFile##*/}}"
	templateExpand --interactive "$templateFile" /dom/schema/${schemaName%.schema}.schema
}
