
import bg_strings.sh ;$L1;$L2
import bg_ini.sh ;$L1;$L2


######################################################################################################
### Schema data operations  -- objectTypes (tables), columns, and ranges of values
#

# MAN(7) bgawkDataSystem
# The awkData system defines a simple text format for tabular data which can be easily queried and operated on by awk scripts.
#
# The bg-awkData command provides a way to query and perform other operations on the data from the command line. The data to be
# operated on is identified by passing bg-awkData a awkDataID which is similar to a table name.  The awkDataID is not simply a
# table name because it can identify the data in several different ways.
#
# An awkData 'table' consists of a text file containing the data (refered to as the awkDataFile) and optionally an ini style file
# that describes the structure and attributes of the table (refered to as the awkDataSchemaFile). By default, the first couple lines
# of the awkDataFile is a header that describes the column and optionally a few other attributes. That header enables a awkDataFile
# to work without a corresponding schema file. There is typically a one to one correspondence between an awkDataFile and an
# awkDataSchemaFile but there are some exceptions.
#
# Caching Host Configuration and Provisioning Information:
# Often an awkData table is used to cache some system configuration information that is stored on the host in various formats. This
# makes the information accessible in a standard way. To facilitate building and keeping the data up-to-date, a schema can specify
# a builder cmd and dependent files.  If the awkDataFile does not exist or if any of the dependent files has a more recent timestamp
# than the awkDataFile, it is considered dirty and will be rebuilt on demand.
#
# AwkData Schema Registry:
# AwkData tools can be used to access one-off files that are not registered on the host but by registering an awkDataSchemaFile
# asset on the host, the table becomes discoverable and logically becomes part of the configuration and providioning data on the
# host.
#
# This is powerful because it allows disparate systems, written by different teams with different tools, standards and practices,
# to become part of a standard object oriented state of the host. We can start thinking about the host as a uniform object oriented
# system with identity, state, and behavior which makes the host easier to automate and control.
#
# awkDataID Format:
# A fully qualified awkDataID consists of 3 parts separated by the pipe character.
#    <awkTableName>|<awkDataFile>|<awkDataSchemaFile>
# It is often valid to exclude one or two parts by leaving them empty. Trailing pipe characters can be ommitted.
#
# If the awkData table is registered on the host, then the <awkTableName> alone is sufficient to identify the table. For a registered
# awkData table the <awkDataSchemaFile> is an asset in the host manifest with an assetType="awkDataSchema" and
# assetName=<awkTableName>. This allows looking up the <awkDataSchemaFile> from the <awkTableName> and the <awkDataSchemaFile>'s
# awkDataFile attrubute points to the <awkDataFile>.
#
# It is also sufficient to only specify the <awkDataFile> if it includes at least the column header. This is tyically used when
# creating and using a one-off data file that will not be registered.
#
# It is also sufficient to only specify the <awkDataSchemaFile>. This is typically used when creating and using a one-off data file
# that will not be registered but needs to specify additional table attributes or needs to persist even when the data file is deleted.
#
# The <awkDataSchemaFile> typically specifies the <awkDataFile> so there is a one-to-one correspondence between them, but it is
# possible to create a second data table that uses the same schema by specifying both <awkDataFile> and <awkDataSchemaFile>. When
# <awkDataFile> is specified in the awkDataID, it will override the one speicied in the awkfile attribute of the <awkDataSchemaFile>.
#
#
# Example AwkDataFile:
#     $ cat -n manifestExample
#       1 package     assetType      assetName          path
#       2
#       3 bg-core     cmd            bg-collectCntr     /usr/bin/bg-collectCntr
#       4 bg-dev      cmd            bg-debugCntr       /usr/bin/bg-debugCntr
#     $
# The first line is a header line that contains the name of each column. The second line is also a header line but in this simple
# case it is empty. The data starts on the third line and continues to the end of the file. Each data line is a separate record.
# All tokens in the column header and each data line are separated by spaces and/or tabs. Whitespace in the data is escaped with
# tokens of the form %NN where NN is the hex number of the character. (a space is %20).
#
# The complete syntax of the awkDataFile is documented in man(5) bgawkDataFile
#
# Example AwkDataSchemaFile:
# $ cat -n ./lib/manifest.awkDataSchema
#    1 columns=pkg(-20) assetType(-20) assetName(-20) path
#    2 awkFile=/var/lib/bg-core/manifest
# This file uses the INI file style. Lines contains attribute definitions n the form <name>=<value>
#
# The complete syntax of the awkDataSchemaFile is documented in man(5) bgawkDataSchemaFile
#
#
# For example, an isolated txt file that
# follows the simple format can be queried with bg-awkData by using the path to the file as the awkDataID. More typically, the
# awkDataID is a single word that refers to the awkObjName (aka table name) which is registered on the host as an ini style file
# that describes the structure and attributes of the data table and the absolute path to a data file that contains the data.
#
# The standard allows one off data files that are self describing but it also allows defining the structure and attributes of the
# data file in a separate awkDataSchemaFile.
#
# The schema file can be used on its own or an admin with sufficient privilege can be register (aka install) it on the host so that
# it becomes a part of the host's configuration and provisioning system.
#
# There is normally a one to one correspondence between a awkDataFile and a awkDataSchemaFile. The awkDataSchemaFile will define
# the absolute path to the awkDataFile in its 'awkFile' attribute and the names of the the files connect them as well. The awkDataID
# is used to name both files and serves like a table name. The awkDataFile contains the table data and the awkDataSchemaFile contains
# a description of the table structure and other attributes.
#
# awkDataSchemaFile. However, it is possible to reuse the schema description of a awkDataSchemaFile by crafting a long form awkDataID


# MAN(5) bgawkDataSchemaFileFormat
# This man page describes the file format of a awkData Schema file.
#
#The data file is often considered a
# cache of some other information and may be deleted. If it has a fully functioning awkDataSchemaFile, it will be recreated automatically
# as needed.
#
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
#   .schema is appended to the whole filename and its check again for existence.
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





# usage: awkData_parseID <awkDataID> <awkTableNameVar> <awkDataFileVar> <awkDataSchemaFileVar>
# Given the <awkDataID>, return the <awkTableName> <awkDataFile> and <awkDataSchemaFile> values in the given vars passed in.
#
# An <awkDataID> is a token (without whitespace) that has up to 3 fields separated by the pipe character. Not all fields must be
# specified so this function can be used to parse the token into its 3 parts and also fill in the missing parts.
#
# Syntax:
# The full syntax is ...
#     <awkTableName>|<awkDataFile>|<awkDataSchemaFile>
# Any of the fields may be empty. Trailing pipe characters that result from one or more empty fields can be omitted.
#
# Examples:
#     manifest                # only the <awkTableName> is specified. The other two fields will be looked up from an installed
#                               asset with assetName="manifest" and assetType="awkDataSchema"
#    |/tmp/myTempData.cache   # only the data file path is specified. The table name will be considered the base name of the data file.
#                               The <awkDataSchemaFile> will remain empty as it is not alway needed.
#    ||/tmp/myTempSchema      # only the <awkDataSchemaFile> is specified. The <awkDataFile> will be retrieved from the 'awkFile'
#                               attribute inside the schema file. The <awkTableName> will be the base name of the <awkDataFile>
#    tmpManifest|/tmp/m|manifest # all 3 fields are specified to explicitly use a new data file that uses the same schema definition
#                                  as the manifest table. Because the <awkDataSchemaFile> specified is not the full path to a file,
#                                  it will be looked up the same way as when only the <awkTableName> is specified. However, since the
#                                  <awkDataFile> was also specified, the awkFile attribute in the <awkDataSchemaFile> will not be used.
# See Also:
#    awkData_getSchema      : super set of this function that goes on to read the schema attributes too
#    awkData_listAwkDataIDs : list <awkDataID> that exist on the host
function awkData_parseID()
{
	local awkDataID="$1";    [ ! "$awkDataID" ] && return 1
	local awkTableNameVar="$2"
	local awkDataFileVar="$3"
	local awkDataSchemaFileVar="$4"

	local awkTableNameValue awkDataFileValue awkDataSchemaFileValue
	stringSplit -d'|' "$awkDataID" awkTableNameValue awkDataFileValue awkDataSchemaFileValue

	# For one-off tables, the user might specify either the awkFile alone and then we glean the table name from the filename
	if [ ! "$awkTableNameValue" ]; then
		local filename="$awkDataFileValue"
		awkTableNameValue="${filename##*/}"
		awkTableNameValue="${awkTableNameValue%.*}"
	fi

	# typical case: lookup the schema from the table name
	if [ "$awkTableNameValue" ] && [ ! "$awkDataSchemaFileValue" ]; then
		awkDataSchemaFileValue="$(manifestGet -o '$4' "awkDataSchema" "$awkTableNameValue")"
		[ "$awkDataSchemaFileValue" ] || assertError -v awkdatID -v awkTableNameValue "No awkDataSchema asset installed for table name"
	fi

	# If the schemaFile field contains a simple table name, look up the schema asset
	# This is a case where the caller is crafting a new data table from an existing schema definition. The caller can assign a new
	# table name and awkFile location and an existing installed schema.
	if [[ ! "$awkDataSchemaFileValue" =~ [/.] ]] && [ ! -f "$awkDataSchemaFileValue" ]; then
		awkDataSchemaFileValue="$(manifestGet -o '$4' "awkDataSchema" "$awkDataSchemaFileValue")"
		[ "$awkDataSchemaFileValue" ] || assertError -v awkdatID "Invalid awkDataSchemaFile specified in the awkDataID. It should be either the full path to a schema file or the asset name of a installed awkDataSchema asset on the host"
	fi

	# typical case: lookup the data file from the schema file
	if [ "$awkDataSchemaFileValue" ] && [ ! "$awkDataFileValue" ]; then
		awkDataFileValue="$(gawk -F= '$1=="awkFile" {print gensub(/[[:space:]]*#.*$/,"","g",$2)}' "$awkDataSchemaFileValue")"
		[ "$awkDataFileValue" ] || assertError -v awkdatID -v awkDataSchemaFileValue "Neither the awk schema file nor the awkDataID specify the awkFile path"
	fi

	# If only the awkDataSchemaFile was specified, the awkDataFile was not available when we first tried to glean the name so check it again
	if [ ! "$awkTableNameValue" ]; then
		local filename="${awkDataFileValue:-$awkDataSchemaFileValue}"
		awkTableNameValue="${filename##*/}"
		awkTableNameValue="${awkTableNameValue%.*}"
	fi

	setReturnValue "$awkTableNameVar"      "$awkTableNameValue"
	setReturnValue "$awkDataFileVar"       "$awkDataFileValue"
	setReturnValue "$awkDataSchemaFileVar" "$awkDataSchemaFileValue"
}








# usage: awkData_listAwkDataIDs [<filterRegex>]
# prints a list of awkDataID names installed on this host to stdout.
# awkDataIDs are the table names of data in the bg-core configuration and provisioning system. They are installed on a host via
# assets in packages that follow the bg-ore conventions. An assetType of 'awkDataSchema' will introduce a new awkDataID using
# the assetName as the awkDataID name.
#
# A local or domain admin with sufficient privilege can also install awkDataIDs directly.
# TODO: add a reference to the command used to add awkDataIDs
#
# Params:
#    <filterRegex> : a regex that matches awkDataID names from the start (^ is automatically prepended)
# See Also:
#    awkData_parseID
function awkData_listAwkDataIDs()
{
	local filterSpec="$1"
	manifestGet -o '$3' awkDataSchema '.*'
	return
}


# usage: awkData_showSchema [<awkDataID>]
# write out all the known <awkDataID> (in the domData) and each column they support in a tree
function awkData_showSchema()
{
	local awkDataID="$1"

	if [ "$awkDataID" ]; then
		awk  \
			-v awkDataID="$awkDataID" '
			@include "bg_awkDataSchema.awk"
			END {
				printfVars2(0,awkDataID"_schema", schemas[awkDataID])
			}
		' /dev/null
	else
		local awkObjName; for awkObjName in $(awkData_listAwkDataIDs "$@"); do
			echo "$awkObjName"
			local column; for column in $(awkData_getColumns "$awkObjName"); do
				echo "   $column"
			done
		done
	fi
}

# usage: awkData_getColumns <awkDataID>
# return just the columns attrinbute of the schema.
# Note that if you need any other schema attributes or will call something that does, it is better to use awkData_getSchema
# which is about the same amount of work as this function but returns all the schema attributes in an array.
function awkData_getColumns()
{
	local awkDataID="$1"

	awk  \
		-v awkDataID="$awkDataID" '
		@include "bg_awkDataSchema.awk"
		END {
			#printfVars("schemas awkDataID")
			for (i in schemas[awkDataID]["colNames"])
				printf("%s ", schemas[awkDataID]["colNames"][i])
			printf("\n")
		}
	' /dev/null
}
