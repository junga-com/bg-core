
# Library
# Part of the awkDataSystem that contains functions for reading and manageing schemas. A schema is typically an ini style file
# with the awkDataSchema extension that is registered as an asset in the host manifest. Unregistered schema files are also supported.
# A stand alone data file is also supported without an external schema file. In that case the file starts with a brief header
# that at a minimum, lists the names of the columns.
#
# See man(7) awkDataSystem for the complete description.


import bg_ini.sh ;$L1;$L2



# MAN(7) awkDataSystem bg.awkDataSystem
# The awkData system defines a simple text format for tabular data which can be easily queried and operated on by awk scripts.
# A principle design goal is to support the simplest of files with as few requirements as possible while also allowing more
# complex behavior comparable to some features of databases.
#
# The bg-awkData command provides a way to query and perform other operations on the data from the command line. The data to be
# operated on is identified by passing bg-awkData a awkDataID which is similar to a table name.  The awkDataID is not simply a
# table name because it can identify the data in several different ways. See man(3) bg_awkDataSchema.awk for deatials on <awkDataID>
# syntax.
#
# An awkData 'table' consists of a text file containing the data (refered to as the awkDataFile) and optionally an ini style file
# that describes the structure and attributes of the table (refered to as the awkDataSchemaFile). By default, the first couple lines
# of the awkDataFile is a header that describes the column and optionally a few other attributes. That header enables a awkDataFile
# to work without a corresponding schema file.
#
# The most typical way to use the awkData system is to use a bg-dev style package project which provides a awkDataSchema asset and
# scripts in that project would use the assetName as the awkDataID when calling awkData functions.
#
# This system all support a sysadmin using the awkData tools on a one-off file that does not have a schema asset intalled on the
# system. See man(3) bg_awkDataSchema.awk for ways to specify an awkDataID for a table without an installed awkDataSchema asset.
#
# Caching Host Configuration and Provisioning Information:
# Often an awkData table is used to cache some system configuration information that is stored on the host in various formats. This
# makes the information accessible in a standard way.
#
# The author of a bg-dev style package project would create an awkDataSchema asset in the project. That schema would include the
# builder and dependents attributes information. That information makes the table become updatable on demand. If the awkDataFile
# does not exist or if any of the dependent files has a more recent timestamp than the awkDataFile, it is considered dirty and will
# be rebuilt on demand hte next time the table is accesed.
#
# This is powerful because it allows disparate systems, written by different teams with different tools, standards and practices,
# to become part of a standard object oriented state of the host. We can start thinking about the host as a uniform object oriented
# system with identity, state, and behavior which makes the host easier to automate and control.
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
# This man page describes the file format and attributes of a awkDataSystem Schema file.
# An awkDataSystem schema file is a form of database table description. It uses the ini file style structure to describe the attributes
# of an awkDataSystem data file which is a database table. An external awkDataSchemaFile is optional but common.
#
# Schema File Format:
# Schema files use the INI file format. see man(5) bginiFileFormat
# The awkDataID attributes are stored in ParameterSettings of the INI schema file
#
# AwkData Attributes:
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
# Other attributes can exist. A builder function named in the buildCmd attribute may define additional required and optional
# attributes that the awkData table can have.
#
# See Also:
#     man(1) bg-awkData
#     man(5) awkDataFileFormat
#     man(5) bgawkDataSchemaFileFormat
#     man(3) bg_awkDataSchema.awk  : defines the supported syntax of awkDataIDs




# MAN(5) awkDataFileFormat bg.awkDataFileFormat
# This documents the format of awkDataSystem data files.
# An awkDataSystem data file is a form of database table. Rows corresponds to record. Columns corresponds to attributes.
#
# A data file always needs at least a minimal schema information. The minimal schema is just a list of column names that corresponds
# to the $1..$NF fields that awk provides when operating on each line of a file. This allows queries to use column names instead of
# numbers.
#
# Simple awkDataFiles can contain all the schema information they needs in the file itself in one of two header formats which are
# described here. It is actually more common for an external schema file to exist. The format of that file is docmented in
# man(5) bgawkDataSchemaFileFormat. If an external schema exists, the data file may still contain one of the two headers or the
# schema may specify that the data file contains only data lines.
#
# No Header:
# If the noFileHeader attribute is specified in the schema, the first and all lines of the file are data lines.
# There is a shorcut to setting the noFileHeader attribute in cases where no external schema file exist. If the <awkDataFile> is
# explicitly specified in the awkDataID and it has a trailing '-', that '-' will be removed from the filename and the noFileHeader
# attribute will be set. This could be useful if you have a file from a foriegn system on which you want to use awkData tools.
#
# Standard Header:
# If the file contains header lines, they can be one of two formats. This is the most common.
# The first token of the first line of the file determines if the file contains a Standard or Extended header. If that token matches
# the regex of a version number (/^[0-9]{1,3}\\.[0-9]{1,3}(\\..*)?$/) the head is an Extended header and if it does not it is a
# Standard head.
#
# The Standard header consistes of exactly two lines.
#
# **Line 1**
# The first line is the list of column names. This corresponds to the 'columns' attribute of the schema.
# .
# **Line 2**
# The second line contains a list of dependent files. This list can be empty which effectively disables its dirty mechanism.
#
# The third and subsequent lines are data lines.
#
# Extended Header:
# If the first token of the first line of the file matches the regex of a version number the file contains an extended header.
# An extended header can have a variable number of lines.
#
# **Line 1 format**
#   <version> <colLinePos> <depLinePos> <dataLinePos> <buildCmd>
# The tokens are whitespace separated.
# **Field Meanings**
#   <version>     : The version number of the extended header.
#   <colLinePos>  : the line number in the file (NR) that contains the column list (which is the same as the first line of the
#                   Standard header)
#   <depLinePos>  : the line number in the file (NR) that contains the dependents list (which is the same as the second line of the
#                   Standard header)
#   <dataLinePos> : the line number in the file (NR) that contains the first data line. This allows inserting a variable number of
#                   header lines that could contain anything.
#   <buildCmd>    : The cmdline that when executed would rebuild this data file possibly picking up new records.
#
# As of the time of this writing, the extended header is not used but defining it means that future formats that we might want to
# add in the future can maintain compatibility with the data files that we create today. The header version number allows us the
# ultimate freedom that if we update this code to know about a future version, we could support existing files along side a completely
# new file format.
#
#
# Data Lines:
# The data portion of the awkDataFile consists of lines which contain data fields separated by whitespace whose values corresponds
# to the columns names. Typically all the rows will have the same number of fields but it is not an error for one or all of the
# lines to have a different number of fields. If it has less fields that column names, the column at the end will be considered to
# have empty values. If it has more, the extra fields are ignored.
#
# Since the values on each line are separated by whitespace, they can not contain whitespace so whitespace and any other characters
# that would be problematic (such as non-ascii or non-printable characters)
#
# See Also:
#    man(7) awkDataSystem
#    man(5) bgawkDataSchemaFileFormat















# usage: awkData_listAwkObjNames [<filterRegex>]
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
#    man(7) awkDataSystem
function awkData_listAwkObjNames()
{
	local filterSpec="$1"
	manifestGet -o '$3' awkDataSchema '.*'
	return
}


# usage: awkData_tableInfo [<awkDataID>]
# write out all the known <awkObjName> installed in the host manifest and the column they contain in a two level tree
function awkData_tableInfo()
{
	local awkDataID="$1"

	if [ "$awkDataID" ]; then
		gawk  \
			-v awkDataID="$awkDataID" '
			@include "bg_awkDataSchema.awk"
			END {
				printfVars2(awkDataID"_schema", schemas[awkDataID])
			}
		' /dev/null
	else
		gawk -i bg_awkDataSchema.awk \
			-v awkDataIDList="$(awkData_listAwkObjNames)" '
			BEGIN {
				for (awkObj in schemas) {
					print(awkObj)
					for (i in schemas[awkObj]["colNames"])
						print("   "schemas[awkObj]["colNames"][i])
				}
			}
		'
	fi
}
