#!/bin/bash

import bg_bgawk.sh  ;$L1;$L2

# this is a generic hidden user config that any script can use to store config
iniUserConfFile=~/.bg-lib.conf


# man(5) bginiFileFormat
# The INI file Format is a common format used in configuration files on multiple operating systems.
# There are many variations but there are core aspects that most have in common.
# The tools in the bg-lib and dependent libraries often read and write INI formated configuration files
# They use the principle of being conversative in what they write and liberal in what they accept when
# reading.
#
# Basic Format:
# An INI file is line oriented. Extensions that continue lines exist but might not be understood by all tools.
# Each line is
#    * whitespace -- 0 or more space or tabs
#    * comment   -- first non-whitespace character is #
#    * section name -- [<sectionName>]
#    * parameter setting -- <paramName>=<value>
# An INI consists of one or more sections, each with 0 or more parameter settings.
# The top of the file, before the first section name line is the default section and always exists but
# is considered empty if no parameter setting lines appear before the first section line.
# The names of settings are typically unique within the section that they apear but that is not absolute.
# If a parameter name appears more than once in a section it may be interprete by some readers as an
# array/list of multiple values.
#
# bg-lib Conventions:
# The bg_ini.sh librabry provides functions to read and write INI files. The rest of the sections in
# this man page describe conventions that these tools adhere to. Libraries and scripts that dependend
# bg-lib should attempt to comply with these conventions.
#
# Foriegn Config Files:
# The bg_ini.sh tools can be used to work with foreign INI file config files whose specification is
# determined by the project that owns that file. In that case the conventions of that file format should
# be observed and the bg_ini.sh tools should only be used with that file if they can be coherced to
# comply with those conventions using optional arguments.
#
# A typical variation may be that ":" is used to delimit the setting name and value instead of "="
#
# Default/Top Section Name:
# The section that appears before the first section line can be refered to with either an empty string
# or a single period character as its section name. The "." section name is supported to allow recording
# the section name in places where a whitespace is use to delimit the tokens. Also, "--" is accepted as an alias for the top section
# because of its similar use in awk data files.
#
# Any config file that does not use "[ <sectionName> ]" lines can be thought of as an INI file where only the top section has
# content.
#
# Detailed Line Formats:
# Section Lines...
# When sections are written...
#   1) the [ will be the first character of the line
#   2) a single space will follow the [
#   3) the ] will be the last character of the line
#   4) a single space will preceed the ]
#   5) the section name will not have leading nor trailing whitespace
#   6) the section name will not be allowed to contain the "]" character but all other characters and middle whitespace are allowed
#
# When sections are read...
# Since INI config files can be hand edited, those conventions are not required when reading.
#   * optional extra whitespace can be added or removed from anywhere except in the middle of the section name.
#   * the section name may be enclosed in single or double quotes and they will be removed. Quote chars that are not matching on
#     the ends or appear in the interior will not be removed. Whitespace inside the quotes will not be removed so that is a way to
#     support section names with leading or trailing whitespace
#
# ParameterSetting Lines...
# When ParameterSetting are written...
#    1) no leading whitespace
#    2) the <paramName> will not have any leading or trailing whitespace.
#    3) the <paramName> will be followed by a single delimeter character (defatul =) with no whitespace.
#    4) <value> will immediately follow the delimeter with whitespace preserved.
#    5) if a comment is specified, a # character is appended and the comment follows.
#       note that the <value> may contain # characters in which case comments can be ambiguous.
# When sections are read...
#   * 0 or more whitespace can surround the <value> and delimiter tokens.
#
# Comment Lines...
# When Comment are written...
#    1) the # is always the first character on the line.
# When Comment are read...
#    * any line whose first non-whitespace char is a # is considered a comment line.
#
# Nested Sections:
# Sections are inherently flat. Each section name line ends the previous section and starts a new section.
# All these physical sections form a single, flat list of sections.
#
# It is common to store section hierarchical nesting information in the section name itself.
# The bg-lib convention is to use the : character to speparate parts of the section name.
# This allows command to identify an operate on groups of sections as if they are hierarchical.
# Given these sections...
#    [ subnet:192.168.0/24 ]
#    [ subnet:172.16.0.0/16 ]
#    [ ip:192.168.22.3 ]
# ... you could query all the subnet sections or ip sections and then access the parameter settings inside
# each section to get the information on each.
#
# ParameterSetting Line Comments:
# Comments can be added to the end of ParameterSetting lines. The comment text can not include a # character.
# When read, the default is to consider the last # on the line with any preceeding whitespace to be the start
# of the command and is not part of the <value>
# When ParameterSetting lines are updated with new values, any comment that is on that line will be preserved.
#
# See Also:
#     man(5) bg-ini




# AWKLIB : awkLibINIFiles : provides iniSection, iniParamName, iniValue, and iniLineType variables
# This awk library string can be included in an awk script and any script that apears after it can
# rely on a set of ini* variables to be defined while processing each line.
# The default delimiter for settings lines in "=". You can change the delimiter by adding a cmd line
# option '-v iniDelim="<delim>"'. A line's first ocurance of iniDelim will separate <iniParamName> and
# iniValue therefore iniParamName can not contain iniDelim but iniValue can.
# Input Variables:
#    iniTargetSection: a section to focus on. inTarget will be true only when processing this section. Several special values are recognized
#              "<sectName>"   : <sectName> matches the word inbetween bracket on section lines.
#              "." or "--"    : matches the top section before the first section line
#              ""             : (empty string) matches no section and inTarget will never be true
#              "]all"         : matches all sections so that inTarget always be true
#    iniDelim        : default is "=". This character is used to separate the iniParamName from the iniValue. Only the first occruence
#                      is recognized so the iniValue may contain iniDelim but the iniParamName may not. Whitespace before and after the
#                      iniDelim is ignored and will not be part of the iniParamName or iniValue. Trailing whitespace at the end of iniValue
#                      will also be ignored but whitespec in the middle of iniValue will be preserved
#                      Note that the full line is always available in $0 so a script can do different parsing if it wants.
# Provided Variables:
#    iniSection      : the section name that the current line is in or empty string, "", if its before the first section header line
#    iniSectionNorm  : the section name that the current line is in or "." if its before the first section header line
#    iniParamName    : the name of the parameter (using iniDelim to parse) for the current line or empty if current line is not a setting
#    iniValue        : the vaue of the parameter (using iniDelim to parse) for the current line or empty if current line is not a setting
#    iniLineType     : the type of line of the current line
#            "comment"    : the first non-whitespace character is a "#".
#            "whitespace" : the line is empty or contains only whitespace
#            "section"    : the line is a section header of the form "[ <sectionName> ]"
#            "setting"    : the line is not any of the other lines. Note that this means that the line might not contain a iniDelim
#    inTarget        : true(1) or false(0) indicating if the current line is in the section specified in iniTargetSection
awkLibINIFiles='
	#'"$awkDataLibrary"'
	BEGIN {
		# if the caller does not set iniTargetSection with -v iniTargetSection="", we set it to a
		# value that is not likely to be a real section. If the caller wants to specify the top/empty
		# section, they must use iniTargetSection="." or iniTargetSection="--"
		iniTargetSection=(iniTargetSection=="")?"]!#<noSection>#!":iniTargetSection
		iniTargetSection=(iniTargetSection=="." || iniTargetSection=="--")?"":iniTargetSection
		#bgtrace("lib begin")
	}
	BEGINFILE {
		iniSection=""
		iniSectionNorm="."
		iniDelim=(iniDelim=="")?"=":iniDelim
		inTarget=(iniTargetSection=="" || iniTargetSection=="]all")?1:0
		#bgtrace("lib beginfile")
		#bgtrace("iniTargetSection="iniTargetSection)
	}
	{iniLineType=""; iniParamName=""; iniValue=""}
	$1~"^[[]" && $NF~"[]]$" {
		iniSection=$0
		gsub("((^[[:space:]]*[[][[:space:]]*)|([[:space:]]*[]][[:space:]]*$))","", iniSection)
		if (iniSection ~ /(^".*"$)|(^'\''.*'\''$)/)
			iniSection=substr(iniSection,2,length($0)-2)
		iniSectionNorm=(iniSection!="")?iniSection:"."
		iniLineType="section"
		inTarget=(iniTargetSection==iniSection || iniTargetSection=="]all")?1:0
		##bgtrace("lib section")
	}
	$0~"^[[:space:]]*$" {iniLineType="whitespace"}
	$0~"^[[:space:]]*#" {iniLineType="comment"}
	iniLineType == "" {
		iniLineType="setting"
		iniParamName=$0; gsub("((^[[:space:]]*)|([[:space:]]*"iniDelim".*$))","", iniParamName)
		iniValue=$0;     gsub("(^[^"iniDelim"]*"iniDelim"[[:space:]]*)|([[:space:]]*)$","", iniValue)
		#bgtrace("lib setting")
	}
'

# usage: cat $file | escapeIniSectionData
# This facilitates storing arbitrary data in an INI section of a file
# this is a filter that escapes data that looks like ini section headers so that the
# data can be stored in a ini section.
# replaceIniSection and getIniSection do this internally, using this function and unescapeIniSectionData
#  so you normally do not need to call this directly
function escapeIniSectionData()
{
	# insert the string "#!(esc)" before any line that looks like section header
	sed -e 's/^[ \t]*\[.*\]/#!(esc)&/' <&0
}

# usage: <readDataFromSection> | unescapeIniSectionData
# This facilitates storing arbitrary data in an INI section of a file
# this is a filter that undoes the escaping that escapeIniSectionData does.
# see man escapeIniSectionData
function unescapeIniSectionData()
{
	# remove the string "#!(esc)" if it appears at the start of any line
	sed -e 's/^#!(esc)\([ \t]*\[\)/\1/' <&0
}


##################################################################################################################
### Ini Section Functions
# INI Sections can be used for multiple purposes. They can contain INI parameters (name/value pairs separated by an = sign)
# other name/value formats or arbitrary text data


# usage: iniSectionExists <iniFile> <sectionName>
# returns exit code 0 if the section exists or 1 if it does not
# Params:
#     <iniFile>     : filename and path to an ini formatted file
#     <sectionName> : name of an INI style section in the file. (e.g. a line like '[ <sectionName> ]')
#                     if <sectionName> is an empty string or "." or "--", it refers to the section from the
#                     start of a file to the first [ <sectionName> ] line.
#                     This top/emptyName section is consider to exist if there is at least one parameter/setting
#                     line before the first section line
function iniSectionExists()
{
	local verboseFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-v)  verboseFlag="-v" ;;
	esac; shift; done
	local iniFile="$1"
	local sectionName="$2"

	awk -v iniTargetSection="${sectionName:---}"  '
		'"$awkLibINIFiles"'

		# the top/empty section does not have a section line so we consider it to exist if there is
		# at least one setting line in it. In this condition, when iniLineType=="section", it will be the actual section line for targetSection
		inTarget && ( iniLineType=="setting" || iniLineType=="section") {
			found=1
			exit (found)?0:1
		}
		END {
			exit (found)?0:1
		}
	' $(fsExpandFiles -f $iniFile)
	local result=$?
	return $result
}

# usage: assertINISectionExists <inifile> <sectionName> <errorDescription>
# If the specified section in the <inifile> does not exist, an exception will be raised. see assertError
function assertINISectionExists()
{
	if ! iniSectionExists "$1" "$2"; then
		local data="$1 $2"
		shift 2
		assertError "${*:-the ini section '$data' should exist}"
	fi
}

# usage: assertINISectionNotExists <inifile> <sectionName> <errorDescription>
# If the specified section in the <inifile> *does* exist, an exception will be raised. see assertError
function assertINISectionNotExists()
{
	if iniSectionExists "$1" "$2"; then
		local data="$1 $2"
		shift 2
		assertError "${*:-the ini section '$data' should not exist}"
	fi
}



# usage: iniSectionList <inifile> [<grepRegEx>]
# returns a list of section names matching the filter expression. If grepRegEx is not specified, all sections are returned
function listIniSection() { iniSectionList "$@"; }
function iniSectionList()
{
	local iniFile="$1"; assertNotEmpty iniFile
	local filterRegex="${2:-".*"}"

	awk '
		'"$awkLibINIFiles"'
		iniLineType=="setting" && iniSection="" {print "."};
		iniLineType=="section" {print iniSection};
	' $(fsExpandFiles -f $iniFile) | grep "^$filterRegex$"
}

# usage: iniSectionGet <iniFile> <sectionName>
# writes the lines from <iniFile> that are in the sectionName section to stdout
# Params:
#     <iniFile>     : filename and path to an ini formatted file
#     <sectionName> : name of an INI style section in the file. (e.g. a line like '[ <sectionName> ]')
#                     if <sectionName> is an empty string or "." or "--", it refers to the section from the
#                     start of a file to the first [ <sectionName> ] line.
# Options:
#    -p : include the header too.
function getIniSection() { iniSectionGet "$@"; }
function iniSectionGet()
{
	local includeSectionHeaderToo
	while [[ "$1" =~ ^- ]]; do case $1 in
		-p) includeSectionHeaderToo="1" ;;
	esac; shift; done
	local iniFile="$1"
	local sectionName="$2"

	awk -v iniTargetSection="${sectionName:---}"  '
		'"$awkLibINIFiles"'

		inTarget {
			if (iniLineType!="section" || "'"$includeSectionHeaderToo"'")
				print $0
		}

	' $(fsExpandFiles -f $iniFile) | unescapeIniSectionData
}

# usage: iniSectionRemove [-p] <inifile> <sectionName>
# removes the lines in the <iniFile> corresponding to the specified <sectionName>
# Options:
#    -p : leaves the <sectionName> header but remove all lines from it. This effectively removes it but keeps its
#         position in the file for when params are added back into the section
function removeIniSection() { iniSectionRemove "$@"; }
function iniSectionRemove()
{
	local deleteSectionHeaderToo="1"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-p) deleteSectionHeaderToo="" ;;
	esac; shift; done

	local iniFile="$1"; assertNotEmpty iniFile
	local sectionName="$2"

	[ -e "$iniFile" ] || return 0

	bgawk -i -n -v iniTargetSection="${sectionName:---}" '
		'"$awkLibINIFiles"'

		inTarget && iniLineType=="section" && ! "'"$deleteSectionHeaderToo"'" {
			print $0
		}

		! inTarget {
			print $0
		}

	' "$iniFile"
}



# usage: cat $file | iniSectionReplace <inifile> <sectionName>
# replaces all lines in <sectionName> in <inifile> with the lines read on stdin
function replaceIniSection() { iniSectionReplace "$@"; }
function iniSectionReplace()
{
	local iniFile="$1"
	local sectionName="$2"

	escapeIniSectionData <&0 | bgawk -i -n -v iniTargetSection="${sectionName:---}" '
		'"$awkLibINIFiles"'

		BEGINFILE {
			if (inTarget) {
				hit=1
				while (getline line < "/dev/stdin")
					print line;
			}
		}

		inTarget && iniLineType=="section" {
			print $0
			hit=1
			while (getline line < "/dev/stdin")
				print line;
			next
		}

		! inTarget {
			print $0
		}

		END {
			if (! hit) {
				printf("[ %s ]\n", iniTargetSection);
				while (getline line < "/dev/stdin")
					print line;
			}
		}
	' "$iniFile"
}

# usage: cr_iniSectionNotExists <filename> <sectionName>
# declares that the ini section should not exist
# apply removes the section
function cr_iniSectionNotExists()
{
	case $objectMethod in
		objectVars) echo "filename sectionName " ;;
		construct)
			filename="$1"
			sectionName="$2"
			displayName="$filename:[$sectionName] should not exist"
			;;

		check) ! iniSectionExists "$filename" "$sectionName" ;;
		apply) removeIniSection -i "$filename" "$sectionName" ;;

		*) cr_baseClass "$@" ;;
	esac
}






##################################################################################################################
### Ini Parameter Functions
# INI Parameters are name/value pairs that are separated by the = sign. They can appear in a file with or without
# INI Sections. A file w/o INI Sections is the same as the top section of a file before the fist INI section. In
# both cases these INI Parameter functions use "." or "" as the section name.



# usage: iniParamExists <inifile> <sectionName> <paramName>
# returns true if the file contains the given parmamName in the given section.
# Note that a param is considered to exist if the ini file has a line that sets it to the empty string so a parameter
# can exist and be equal to "".
# If you need to know the existing value is AND whether it exists or not, its efficient to use getIniParam
# specifying a default value that is not a valid value that could be set in the file. If it returns the default value
# then the param does not exist. Any other value including "" means that a line does exist in the file
function iniParamExists()
{
	local verboseFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-v)  verboseFlag="-v" ;;
	esac; shift; done

	local iniFile="$1"
	local sectionNameRaw="$2"
	local paramNameRaw="$3"; assertNotEmpty paramNameRaw

	[ -s "$iniFile" ] || return 1

	local existingValue="$(getIniParam "$iniFile" "$sectionNameRaw" "$paramNameRaw" "|!@#NOTEXISTS#@!|")"

	[ "$verboseFlag" ] && echo "$existingValue"

	# set return code to true if its set to anything in the file (even "") so that the default value was not returned
	[ "$existingValue" != "|!@#NOTEXISTS#@!|" ]
}

# usage: assertINIParamExists <inifile> sectionName paramName "error description to display if it fails"
function assertINIParamExists()
{
	if ! iniParamExists "$1" "$2" "$3"; then
		local msg="the ini parameter should exist. \n\tfile:$1\n\tsect:[$2]\n\tname:$3"
		shift 3
		assertError "${*:-$msg}"
	fi
}

# usage: assertINIParamNotExists <inifile> <sectionName> <paramName> "error description to display if it fails"
function assertINIParamNotExists()
{
	if iniParamExists "$1" "$2" "$3"; then
		local msg="the ini parameter should not exist. \n\tfile:$1\n\tsect:[$2]\n\tname:$3"
		shift 3
		assertError "${*:-$msg}"
	fi
}


# usage: iniParamList <iniFile> <sectionName> [<regexFilter>]
# list the existing params in the section
function listIniParam() { iniParamList "$@"; }
function iniParamList()
{
	local iniFile="$1"; assertNotEmpty iniFile
	local sectionName="$2"
	local filterRegex="${3:-".*"}"

	awk -v iniTargetSection="${sectionName:---}"  '
		'"$awkLibINIFiles"'

		inTarget && iniLineType=="setting" {print iniParamName}

	' $(fsExpandFiles -f $iniFile) | grep "^$filterRegex$"
}


# usage: iniParamGet [-R<retVar>] [-a] [-t] [-x] <inifile> <sectionName>|. <paramName> [ <defaultValue> ]
# retrieves an ini style setting from a config file. See man(5) bginiFileFormat for details of the file format.
#
# Params:
#    <inifile>     : filename of config file. Can be a comma separated list of config files in which case the value of the first file
#                    that defines <sectionName> <paramName> will be used or <defaultValue> if none define it
#    <sectionName> : only settings in this section will be considered. the same <paramName> can exist in multi sections
#                    Use "." or "" or "--" to indicate settings at the top of the file before any section start
#    <paramName>   : the name of the setting in the section. This is an exact match of the text to the left of the = with whitespace removed
#    <defaultValue> : if the setting does not exist, this value is returned. Note that if the setting exists and has no text to the
#           right of the =, its value is logically set to the empty string. In this case, "" is returned and not <defaultValue>
#
# Options:
#    -R <retVar>    : return the value in this variable name instead of on stdout
#    -d <delimChar> : default is "=". set the character used to separate name and value on settings lines
#    -a  : if the value does not exist, add the default value to the <inifile> (requires write privilege and might prompt for a sudo password)
#    -t  : expand the value as a template before returning it. If the value has "%<varName>%" tokens they will be replaced by the
#          value of bash environment variables of the same name. See man(5) bgTemplateFileFormat for the full supported syntax
#    -x  : suppress section padding. if -a is specified and a new section is added this is passed through to iniParamSet.
#
# Return Codes:
#      0 (true)  : the parameter was found in the config file(s) and returned
#      1 (false) : the parameter was not found and the default value was returned
# See Also:
#    man(5) bginiFileFormat
#    man(5) bgTemplateFileFormat
function getIniParam() { iniParamGet "$@"; }
function iniParamGet() { iniParamGetNewImpl "$@"; }
function iniParamGetOldImpl()
{
	local addFlag templateFlag retVar
	local sectPad=""
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R*) bgOptionGetOpt val: retVar "$@" && shift ;;
		-a)  addFlag="-a" ;;
		-t)  templateFlag="-t" ;;
		-x)  sectPad="-x" ;;
	esac; shift; done

	# we handle multiple <inifile> searches by defering to a helper function that calls us back
	# with single files
	if [[ "$1" =~ , ]]; then
		_getIniParamMultipleFiles $addFlag $templateFlag "$@"
		return
	fi

	local iniFile="$1"
	local sectionNameRaw="$2"
	local sectionName="${2//\//\\/}" # replace all "/" with "\/"
	local paramNameRaw="$3"
	local paramName="${3//\//\\/}" # replace all "/" with "\/"
	local defaultValue="$4"

	assertNotEmpty paramName

	if [ ! -f "$iniFile" ]; then
		if [ "$addFlag" ]; then
			setIniParam $sectPad "$iniFile" "$sectionNameRaw" "$paramNameRaw" "$defaultValue"
		fi

		[ "$templateFlag" ] && defaultValue="$(expandString2 "$defaultValue")"
		[ "$retVar" ] && eval $retVar='"$defaultValue"' || echo "$defaultValue"
		return 3
	fi

	if [ ! -r "$iniFile" ]; then
		echo "error: can not read from file '$iniFile'" >&2

		[ "$templateFlag" ] && defaultValue="$(expandString2 "$defaultValue")"
		[ "$retVar" ] && eval $retVar='"$defaultValue"' || echo "$defaultValue"
		exit 1
	fi


	local startLinePattern=""
	if [ ! "$sectionName" ] || [ "$sectionName" == "." ]; then
		startLinePattern="1{/[ \t]*[[]/q}; 1"
	else
		startLinePattern="/^[ \t]*[[ \t]*$sectionName[ \t]*][ \t]*$/"
	fi

	local endLinePattern="/^[ \t]*\[.*\][ \t]*$/"

	# the format of the sed command is...
	# /StartLinePattern/,/EndLinePattern/ s/regExForLineWithNameSaved/SavedName $paramValue/
	# The startLinePattern matches the sectionName start line
	# The EndLinePattern matches all section lines which includes the next section line that ends our section

	# 2015-01 bg this version won't handle escaped double quotes
	#	local value=$(sed -n -e '
	#		'"$startLinePattern"','"$endLinePattern"' s/^\([ \t]*'"$paramName"'[ \t]*=\)[ \t"]*\([^"#]*\).*\([ \t]*#.*\)*$/=\2/p
	#	' $iniFile)

	# 2015-01 bg tried using eval to solve " quote interpretation (i.e. # inside "" -- problems are:
	#    1) space around equal causes syntax error : solution -> sed -e 's/[ \t]*=[ \t]*/=/g'
	#    2) special chars "' " ; \ | > < ` $ & ( ) " : solution -> no good solution. we can not control the quoting standard
	#               of foreign config files so we would have to filter and escape those characters with a sed filter. might be better to
	#               parse the line completely as data
	#local value=$(eval "$(sed -n -e ''"$startLinePattern"','"$endLinePattern"' s/^[ \t]*'"$paramName"'[ \t]*=.*$/&/p' $iniFile| sed -e 's/[ \t]*=[ \t]*/=/g')"; eval echo '${!paramName-=}')

	# 2015-01 bg hybrid verison:
	# get the raw data from the char after = to end of line
	local value=$(sed -n -e ''"$startLinePattern"','"$endLinePattern"' s/^\([ \t]*'"$paramName"'[ \t]*=\)\(.*\)$/=\2/p' $iniFile)

	# We don't want to use the default if the value is defined and empty so the sed script prepends an extra '=' to the value if
	# it was found so that its never empty.
	if [ ! "$value" ]; then
		if [ "$addFlag" ]; then
			setIniParam $sectPad "$iniFile" "$sectionNameRaw" "$paramNameRaw" "$defaultValue"
		fi
		value="$defaultValue"
		[ "$templateFlag" ] && value="$(expandString2 "$value")"
		[ "$retVar" ] && eval $retVar='"$value"' || echo "$value"
		return 0
	else
		# since it was found, we need to remove the '='. This works fine even if the value is = because the first = is always extra
		value="${value#=}"
		# if the value is quoted, try eval. If not quoted or eval fails, we parse manually
		if [[ ! "$value" =~ ^[\ \t]*[\"\'] ]]; then
			value="${value%#*}"
			value="$(trimString "$value")"
		else
			while [[ "$value" =~ ^[\ \t] ]]; do value="${value:1}"; done
			local value2
			if ! value2="$(if eval $paramName=$value 2>/dev/null ; then echo ${!paramName}; else exit 4; fi)"; then
				value="${value%#*}"
				value="$(trimString "$value")"
			else
				value="$value2"
			fi
		fi
	fi

	[ "$templateFlag" ] && value="$(expandString2 "$value")"
	[ "$retVar" ] && eval $retVar='"$value"' || echo "$value"
}

function iniParamGetNewImpl()
{
	local ipg_addFlag ipg_iniDelim ipg_templateFlag retVar ipg_sectPad
	while [[ "$1" =~ ^- ]]; do case $1 in
		-R*) bgOptionGetOpt val: retVar       "$@" && shift ;;
		-d*) bgOptionGetOpt val: ipg_iniDelim "$@" && shift ;;
		-a)  ipg_addFlag="-a" ;;
		-t)  ipg_templateFlag="-t" ;;
		-x)  ipg_sectPad="-x" ;;
	esac; shift; done
	local ipg_iniFileSpec="$1"
	local ipg_sectionName="$2"
	local ipg_paramName="$3";  assertNotEmpty ipg_paramName
	local ipg_defaultValue="$4"

	local -a ipg_iniFiles; fsExpandFiles -f -A ipg_iniFiles ${ipg_iniFileSpec//,/ }

	local ipg_value ipg_foundInFile

	# if no file(s) exist to read from
	if [ "${ipg_iniFiles[*]}" == "/dev/null" ]; then
		ipg_value="$ipg_defaultValue"

	# normal case that at least one existing file was specified
	else
		read -r ipg_foundInFile ipg_value < <(bgsudo "${ipg_iniFiles[@]/#/-r}" -p"reading conf file ${ipg_iniFiles[*]##*/} [sudo]:"  awk \
			-v iniTargetSection="${ipg_sectionName:---}" \
			-v defaultValue="$ipg_defaultValue" \
			-v iniDelim="$ipg_iniDelim" \
			-v paramName="$ipg_paramName" '
			'"$awkLibINIFiles"'

			inTarget && iniLineType=="setting" && iniParamName==paramName {
				print "1 "iniValue
				found=1
				exit
			}

			END {
				if (!found)
					print "0 "defaultValue
				exit (found)?0:1
			}
		' "${ipg_iniFiles[@]}")
	fi

	if [ ! "$ipg_foundInFile" ] && [ "$ipg_addFlag" ]; then
		setIniParam $ipg_sectPad "$ipg_iniFileSpec" "$ipg_sectionName" "$ipg_paramName" "$ipg_defaultValue"
	fi

	if [ "$ipg_templateFlag" ]; then
		templateExpandStr -R "$retVar" "$ipg_value"
	else
		returnValue "$ipg_value" "$retVar"
	fi

	# set the return code
	[ "${ipg_foundInFile}" == "1" ]
}




# usage: getAllIniParams [-t] [-A <retArrayName>] [-P <retPrefix>] <inifile> [<sectionName>]
# retrieves a set of the ini style settings from a config file. The default is to print them to stdout but if either -A or -P
# is specified, the output will be returned in the specified variable(s) and there will be nothing written to stdout.
#
# Params:
#    <inifile>     : filename of config file. Can be a comma separated list of config files in which case the value of the first file
#                    that defines <sectionName> <paramName> will be used or <defaultValue> if none define it
#    <sectionName> : If specified, only params in that section will be returned and names will NOT be prefixed with the <sectionName>
# Options:
#    -t  : expand the value as a template before returning it
#    -A <retArrayName> : <retArrayName> is the name of an associative array (local -A <retArrayName>)
#          that will be filled in with the values <retArrayName>[[sect.]name]=value
#    -P <retPrefix>    : the values will be returned in variables named like <retPrefix>_[<sect>_]<name>=<value>
#          special characters in <sect> and <name> in the the conig file are replaced with _ so that they make valid
#          variable names. so this is only practical with files that use simple names
function getAllIniParams() { iniParamGetAll "$@"; }
function iniParamGetAll()
{
	local templateFlag retArray retArray
	while [[ "$1" =~ ^- ]]; do case $1 in
		-t)  templateFlag="-t" ;;
		-A*) bgOptionGetOpt val: retArray "$@" && shift ;;
		-P*) bgOptionGetOpt val: retPrefix "$@" && shift; retPrefix="${retPrefix%_}_" ;;
	esac; shift; done

	local iniFile="$1"
	local sectionName="$2"

	if [ ! -f "$iniFile" ]; then
		return 3
	fi

	[ ! -r "$iniFile" ] && assertError "can not read from file '$iniFile'" >&2

	while read -r name value; do
		if [ "$name" == "__ReT_info__" ]; then
			nameColWidth="$value"
		elif [ "$retArray$retPrefix" ]; then
			[ "$retArray" ]  && eval $retArray[\$name]='"$value"'
			[ "$retPrefix" ] && declare -g $retPrefix${name//[.$;<>|:() ]/_}='"$value"'
		else
			printf "%-${nameColWidth:-13}s = %s\n" "$name" "$value"
		fi
	done < <(awk '
		BEGIN {
			names[0]="" # needed so awk knows name is an array
			sectionName="'"$sectionName"'"
			if (sectionName) sectFlag="1"
			if (sectionName==".") sectionName=""
		}

		# match section start lines
		$0~"^[[:space:]]*[[]" {
			curSect=$0
			sub("^[[:space:]]*[[][[:space:]]*","", curSect)
			sub("[[:space:]]*[]][[:space:]]*$","", curSect)
		}

		# match parameter setting lines
		$0~"^[^#]*=" {
			if (sectFlag && sectionName!=curSect)
				next
			name=$0; sub("^[[:space:]]*","",name); sub("[[:space:]]*=.*$","",name)
			value=$0; sub("^[^=]*=[[:space:]]*","",value);
			if (value ~ "^\"") {
				sub("^\"","",value)
				sub("\".*$","",value)
			}
			else if (value ~ "^'\''") {
				sub("^'\''","",value)
				sub("'\''.*$","",value)
			}
			else {
				sub("#.*$","",value)
			}
			if (name) {
				if (!sectFlag && curSect) name=curSect"."name
				data[name]=value
				maxLen=(maxLen<length(name)) ? length(name) : maxLen
				names[length(names)]=name
			}
		}

		END {
			print "__ReT_info__  " maxLen
			for (i=1; i<length(names); i++) {
				print names[i] " " data[names[i]]
			}
		}
	' "$iniFile")
}

# usage: _getIniParamMultipleFiles <inifile> (sectionName | . ) paramName [ defaultValue ]
# this is a private helper function for getIniParam.
# It implements the multiple <inifile> search feature by separating the inifiles and calling back
# getIniParam for each one as needed.
function _getIniParamMultipleFiles()
{
	local inifiles="$1"
	local sectionName="$2"
	local paramName="$3"
	local defaultValue="$4"

	local inifile value="#$%__DEF__"
	for inifile in ${inifiles//,/ }; do
		value=$(getIniParam $inifile "$sectionName" "$paramName" "#$%__DEF__")
		if [ "$value" != "#$%__DEF__" ]; then
			echo "$value"
			return
		fi
	done
	echo "$defaultValue"
}


# usage: bgsed [-p] <sedOptionsAndParameters>
# This is a wrapper over the linux utility sed. It adds several features
#   1) if -i is given and the user does not have permission to write to the file, it will use sudo
#   2) if -i is given, it will create the file if it does not exist
#   3) if -i is given and the user can write to the file but not the folder to create the temporary file,
#      it will edit the file in the /tmp folder and then move it back into the destination file.
# Options:
#     -p   : if this is the first parameter, it is not passed on to sed and if -i is given, its taken
#            that the parent folder should be created if needed so that the file can be created in it
function bgsed()
{
	local noDashI mkdirFlag
	if [ "$1" == "-p" ]; then
		mkdirFlag="-p"
		shift
	fi
	local -a origCmdLine=("$@")
	local iniFile="${@: -1}"
	if [[ "$@" =~ -i\  ]]; then
		local sudoOpts; bgsudo --makeOpts sudoOpts -w "$iniFile" -p "modifying $iniFile [sudo]: "
		local parentFolder="${iniFile%/*}"

		if [ ! -d "$parentFolder" ]; then
			[ ! "$mkdirFlag" ] && assertError "the folder that contains the <inifile> does not exist. use -p to forces its creation. '$iniFile'"
			bgsudo -O sudoOpts mkdir -p "$parentFolder"
		fi

		# we need to be able to write to the parent folder as well to use "sed -i ..."
		# we test this separately b/c if we can write to the file without sudo but cant make the temp file in the parent folder,
		# this function will do the temp file logic itself instead of using -i
		bgsudo -O sudoOpts test -w "$parentFolder" || noDashI="1"

		# make sure the file exists and has at least on line
		if [ ! -s "$iniFile" ]; then
			# the idea behind this line is that any config file that this function creates will have the default policy that
			# local admins can modify it. It should not effect existing files and if something specifically sets the access policy
			# this will not override it b/c it only sets the policy if the file does not exist
			[ ! -f "$iniFile" ] && grep -q "adm:" /etc/group &>/dev/null && which aaaTouch &>/dev/null && aaaTouch -d "" "$iniFile" group:adm:writable

			# sed does not work on a truely empty file so give it a empty line
			bgsudo -O sudoOpts bash -c "echo > \"$iniFile\""
		fi

		if [ "$noDashI" ]; then
			local tmpFile="$(bgsudo -O sudoOpts mktemp)"
			bgsudo -O sudoOpts cp "$iniFile" "$tmpFile"
			bgsudo -O sudoOpts sed "${origCmdLine[@]//$iniFile/$tmpFile}"
			local result=$?
			bgsudo -O sudoOpts cat "$tmpFile" | bgsudo -O sudoOpts tee "$iniFile" >/dev/null
			bgsudo -O sudoOpts rm "$tmpFile"
			return $result
		fi
	fi

	local sudoOpts; bgsudo --makeOpts sudoOpts -r "$iniFile" -p "reading $iniFile [sudo]: "
	bgsudo -O sudoOpts sed "$@"
}



# usage: setIniParam [-q1] [-q2] [-p] [-c <comment>] [-S statusVarName] [-x] <inifile> sectionName paramName paramValue
# replaces the existing value for the named sectionName:paramName with the new value
# * When a value is replaced, it preserves the position of the param in the file
# * When a value is replaced, it preserves end of line comments that could exist after the value
# Parameters:
#   <inifile> :
#       the file to modify.
#       * if the file does not exist, it will be created
#       * if the parent folder of the file does not exist, it will only be created if the -p option is specified
#       * if the user does not have permission to modify or create the file, sudo will be used which may prompt the user
#   sectionName :
#       The INI style section heading that the paramName will be placed it
#       Use '.' or "" as the sectionName to indicate parameters in the beginning of a file, outside any section
#       * if the section does not exist, it will be added at the end of the file.
#   paramName :
#       The left hand side of the parameter/setting assignment. e.g. "paramName=paramValue"
#   paramValue :
#       The right hand side of the parameter/setting assignment. e.g. "paramName=paramValue"
#       an empty value will leave the param in the file with an empty right hand side. This is means that
#       the value is the empty string. Use removeIniParam to remove it completely which means that the paramName
#       is not set. The default value of the getIniParam function will only be used if the paramName is not set
# Options:
#   -q1 : put single quotes around the value. Some foriegn config files require this
#   -q2 : put double quotes around the value. Some foriegn config files require this
#   -p  : this works like mkdir -p. If the parent folder of <inifile> does not exist it will attempt to create it
#   -S <statusVarName> : statusVarName is a output variable. Pass in the string name of the variable to return
#         the status of whether or not iniffile was changed. If the value set in the <inifile> is already set to the
#         specified value, it will return without modifying the file and statusVarName will also, not be changed.
#         if the <inifile> gets changed, statusVarName will be set to "changed". The reason statusVarName is not explicitly
#         set to indicated that its not changed is a typical pattern is for the caller to initialize statusVarName=""
#         and then pass it to multiple setIniParam calles. At the end, it can check to see if any of the calls
#         resulted in the <inifile> being changed.
#   -c <comment> : place this comment after the assignment like "name=value # comment"
#   -x  : suppress section padding. don't add space around the section name when adding a section. This support compatibility to foreign formats
#         that need [user] instead of [ user ]
#   -s  : depriciated. does nothing. used to indicate that sudo should be used by now that is automatic
function setIniParam() { iniParamSet "$@"; }
function iniParamSet()
{
	local quoteMode=""
	local comment=""
	local statusVarName=""
	local sectPad=" "
	local flag; while getopts  "isq:c:pS:x" flag; do
	case $flag in
		p) mkdirFlag="-p" ;;
		q) quoteMode=$OPTARG ;;
		c) comment=$OPTARG ;;
		S) statusVarName=$OPTARG ;;
		x) sectPad="" ;;
	esac; done; shift $((OPTIND-1)); unset OPTIND

	local iniFile="$1"
	local sectionNameRaw="$2"
	local sectionName="${2//\//\\/}" # replace all "/" with "\/"
	local paramNameRaw="$3"
	local paramName="${3//\//\\/}" # replace all "/" with "\/"
	local paramValueRaw="$4"
	local paramValue="${4//\\/\\\\}" # replace all "\" with "\\"
	paramValue="${paramValue//\//\\/}" # replace all "/" with "\/"

	if [[ ! "$quoteMode" =~ ^[12]*$ ]]; then
		assertError "setIniParam -q requires a parameter of '1' or '2' like -q1 ro -q2. found '-q$quoteMode'"
	fi

	case $quoteMode in
		1) 	paramValue="${paramValue//\'/\'\\\\\'\'}"
			paramValue="${paramValue//\`/\\\\\`}"
			paramValue="'$paramValue'"
			;;
		2) 	paramValue="${paramValue//\`/\\\\\`}"
			paramValue="${paramValue//\"/\\\\\"}"
			paramValue="\"$paramValue\""
			;;
	esac

	assertNotEmpty paramName

	assertValidFilename iniFile
	[ -d "$iniFile" ] && assertError "inifile '$inifile' is a directory"


	local startLinePattern=""
	if [ ! "$sectionName" ] || [ "$sectionName" == "." ]; then
		startLinePattern="1{/[ \t]*[[]/q}; 1"
	else
		startLinePattern="/^[ \t]*[[ \t]*$sectionName[ \t]*][ \t]*$/"
	fi
	local endLinePattern="/^[ \t]*\[.*\][ \t]*$/"


	local existTestVal="|!@#NOTEXISTS#@!|"
	local existingValue
	getIniParam -R existingValue "$iniFile" $sectionNameRaw $paramNameRaw "$existTestVal"

	# TODO: try writing this with awk using modern techniques developed for the awkData builders
	#       the awk script could place the lines in existing files better taking into account comments
	#       it might also be faster, but if its not slower it would be worth it

	# case where there is nothing to do becuase the value is already set
	if [ "$existingValue" == "$paramValueRaw" ]; then
		# we don't explicitly set statusVarName to nochange because if one thing has changed, then
		# overall something has changes. e.i. the caller may be calling multiple setIniParam calls
		# with the same statusVarName and at the end checks to see if anything has changed.
				return

	# case to replace an existing line in the file
	elif [ "$existingValue" != "$existTestVal" ]; then
		# the format of the sed command is...
		# /StartLinePattern/,/EndLinePattern/ s/regExForLineWithNameSaved/SavedName $paramValue/
		# The startLinePattern matches the sectionName start line
		# The EndLinePattern matches all section lines which includes the next section line that ends our section
		bgsed $mkdirFlag -i -e " \
			$startLinePattern,$endLinePattern s/^\([ \t]*$paramName[ \t]*=\)[ \t]*\\\"*\([^\\\"#]*\)\\\"*\([ \t]*#.*\)*$/\1$paramValue\3/ \
		" "$iniFile"

	# case to add a line to the top section (before the first "[ sectionName ]" line)
	elif [ ! "$sectionName" ] || [ "$sectionName" == "." ]; then
		bgsed $mkdirFlag -i -e " \
			1 i$paramName=$paramValue" "$iniFile"

	# case to add a line in an existing section
	elif [ "$(grep "^[ \t]*[[ \t]*$sectionName[ \t]*][ \t]*$" "$iniFile" 2>/dev/null)" != "" ]; then
		bgsed $mkdirFlag -i -e " \
			$startLinePattern a$paramName=$paramValue" "$iniFile"

	# case to add both the new section and the line at the end of the file
	else
		bgsed $mkdirFlag -i -e "
			$ {
				a
				a[${sectPad}$sectionName${sectPad}]
				a$paramName=$paramValue
			}
		" "$iniFile"
	fi

	# the only case where the file does not get changed, returns from the function so it does not get here
	[ "$statusVarName" ] && eval $statusVarName="changed"
	true
}

# usage: removeIniParam <inifile> sectionName paramName
# removes sectionName:paramName from the file. If the param did not exist, its a NOP
function removeIniParam() { iniParamRemove "$@"; }
function iniParamRemove()
{
	local iniFile="$1"
	local sectionNameRaw="$2"
	local sectionName="${2//\//\\/}" # replace all "/" with "\/"
	local paramNameRaw="$3"
	local paramName="${3//\//\\/}" # replace all "/" with "\/"

	if [ "$paramName" == "" ]; then
		echo "error: removeIniParam requires three parameters -- <inifile> sectionName paramName " >&2
		exit 15
	fi

	# if its not in the file, there is nothing for us to do
	iniParamExists "$iniFile" "$sectionNameRaw" "$paramNameRaw" || return 0

	local startLinePattern=""
	if [ ! "$sectionName" ] || [ "$sectionName" == "." ]; then
		startLinePattern="1{/[ \t]*[[]/q}; 1"
	else
		startLinePattern="/^[ \t]*[[ \t]*$sectionName[ \t]*][ \t]*$/"
	fi
	local endLinePattern="/^[ \t]*\[.*\][ \t]*$/"

	if [ ! -s $iniFile ]; then
		return
	fi

	# the format of the sed command is...
	# /StartLinePattern/,/EndLinePattern/ s/regExForLineWithNameSaved/SavedName $paramValue/
	# The startLinePattern matches the sectionName start line
	# The EndLinePattern matches all section lines which includes the next section line that ends our section
	bgsed -i -e " \
		$startLinePattern,$endLinePattern {/^\([ \t]*$paramName[ \t]*=\)[ \t]*\\\"*\([^\\\"#]*\)\\\"*\([ \t]*#.*\)*$/d} \
	" "$iniFile"
}

# usage: cr_iniParamSet <filename> sectionName paramName paramValue [ acceptableValueRegEx ]
# declares that the ini parameter should be set
# if acceptableValueRegEx is specified, any value that matches the regex is acceptable
# otherwise, the value must match paramValue
# apply sets the value to paramValue
function cr_iniParamSet()
{
	case $objectMethod in
		objectVars) echo 'opts= filename sectionName paramName paramValue acceptableValueRegEx' ;;
		construct)
			while [[ "$1" =~ ^- ]]; do
				case $1 in
					-q) shift; opts="$opts -q$1" ;;
					-q*) opts="$opts $1" ;;
				esac
				shift
			done
			filename="$1"
			sectionName="$2"
			paramName="$3"
			paramValue="$4"
			acceptableValueRegEx="${5:-^$paramValue$}"
			;;

		displayName)
			local sectDisplay=""
			[ "$sectionName" ] && [ "$sectionName" != "." ] && sectDisplay="[$sectionName]"
			echo "$filename:${sectDisplay}$paramName should be $acceptableValueRegEx"
			;;

		check)
			local value="$(getIniParam "$filename" "$sectionName" "$paramName")"
			[[ "$value" =~ $acceptableValueRegEx ]]
			;;

		apply)
			setIniParam -i $opts "$filename" "$sectionName" "$paramName" "$paramValue"
			;;

		*) 	cr_baseClass "$@" ;;
	esac
}

# usage: cr_iniParamNotSet <filename> sectionName paramName
# declares that the ini parameter should not be set. This means that it is not in the file
# an ini parameter can be set to the empty string and that is still 'set'
# apply removes the paramName
function cr_iniParamNotSet()
{
	case $objectMethod in
		objectVars) echo "filename sectionName paramName" ;;
		construct)
			filename="$1"
			sectionName="$2"
			paramName="$3"
			;;

		displayName)
			local sectDisplay=""
			[ "$sectionName" ] && [ "$sectionName" != "." ] && sectDisplay="[$sectionName]"
			echo "$filename:${sectDisplay}$paramName should not be set"
			;;

		check)
			! iniParamExists -q "$filename" "$sectionName" "$paramName"
			;;

		apply)
			removeIniParam "$filename" "$sectionName" "$paramName"
			;;

		*) cr_baseClass "$@" ;;
	esac
}








##################################################################################################################
### Name/Value Pair config format functions
# Name/Value pairs are similar to INI Parameter line format but without enforcing the separator and quoting conventions
# These should work with any line format where a name appears first and then some form of separator and then the
# rest of the line is a value.

# usage: configNameValueGet [-d <separator>] [-s <iniSection>] <filename> <name>
# Options:
#    -d : delimeter (aka separator). default is whitespace. Defines what separates the name and value.
#    -s : iniSection. operate only on <name> found in this section.
#    -m : multipleValueFlag. The name can have multiple values, either on the same line or in multiple <name> lines
#         This probably needs options to support different ways but for not -m returns the value of each found <name> line as differnent lines
#         without -m it will return the first value found but the number found as the exit code (false)
# Exit Code:
#    0  : success. found <name> as expected. The value may or may not be empty.
#    1  : sudo was required but sudo returned an error. could be the user did not enter the password or sudo permissions are not granted
#    2  : did not find <name>
#    >2 : when -m is not specified and multiple <name> lines match this is the number of matched lines+1 (+1 because 2 is used b/c sudo).
function configNameValueGet()
{
	local sep=" " iniSection
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s*) bgOptionGetOpt val: iniSection "$@" && shift ;;
		-d*) bgOptionGetOpt val: sep "$@" && shift ;;
		-m)  multipleValueFlag="-m" ;;
	esac; shift; done
	local filename="$1"; [ $# -gt 0 ] && shift
	local name="$1"; [ $# -gt 0 ] && shift

	assertNotEmpty name
	assertNotEmpty filename
	assertEmpty iniSection "the -s <iniSection> support has not yet been wrritten. Add it to\n\tpackage:bg-lib\n\tlibrary:bg_ini.sh\n\tfunction:configNameValueGet() "

	# for retrieving a setting its not an assertError if the file does not exist
	[ -f "$filename" ] || return 1

	local preCmd=""; [ ! -r "$filename" ] && preCmd="sudo "

	$preCmd awk -F "$sep" '
		BEGIN {
			multipleValueFlag="'"$multipleValueFlag"'"
		}
		$1=="'$name'" {
			found++
			if (multipleValueFlag || found<=1)
				print $2
		}
		END {
			if (!multipleValueFlag && found>1) exit (found+1)
			exit (found) ? 0 : 2
		}
	' "$filename"
	local result=$?

	if [[ "$preCmd" =~ sudo ]] && [ $result -eq 1 ]; then
		assertError "sudo could not execute the command"
	fi
}


# usage: cr_configNameValue [-m] <filename> <name> <value> [ <valueRegEx> ]
# declare the the config file contains name value attribute line that matches name and valueRegEx using the first
# whitespace (see note for -d opt) as the delim between name and value.
# If valueRegEx is not specified, it will be created from <value> by adding expressions that ignore leading
# and trailing whitespace
#
# Apply follows this algorithm
#    1) if a line for <name> is found in the file that has been commented out, that line will be un-commented by
#         removing the leading # character(s)
#    2) if a line for <name> exists, its value will be replaced with <value>
#       if it does not exist, name value pair will be appended to the end of the file
#
# Params:
#    filename:   file to check for the presence of a line of text
#    name:       the first white space separated token on the line
#    value:      the reset of the line excluding the name and leading space
#    valueRegEx: optional regex expression for value that will match any compliant line
#                if not specified a compliant line must match value exactly except for leading and trailing whitespace
# Options:
#    -d NOTE: this cr statement does not yet implement the -d option. Since it was a significant change to implement -d
#             and the name/value line matching has some tricky cases. I implemented the -d algorithm in a new cr statement
#             called cr_configNameValueEq. That one make the -d default to '='. New code should use this if the delimiter
#             is whitespace and cr_configNameValueEq for delimiter '=' and cr_configNameValueEq if it needs to use -d
#             to specify a different delimiter.
#             Eventually, we will test to make sure that cr_configNameValueEq -d " " is exactly the same as cr_configNameValue
#             and then replace this algorithm with the one in cr_configNameValueEq and make cr_configNameValueEq a wrapper
#             over cr_configNameValue that changes the -d default to =.
#    -d <delimiter> : not yet implemented here. See cr_configNameValueEq
#    -m : multipleValueFlag. <value> is interpreted as a list of values. If the first character is not a delimeter (not a letter)
#         then the list is taken as the absolute, complete list that the value should have -- no more no less.
#         Otherwise, if the value does begin with a delimiter (any non-letter) then the list is taken as a list of values
#         that should be included, but there may be others too.
#         When needed, we can enhance this function to support values preceeded by a - to indicate that they should not be
#         in the list
function cr_configNameValue()
{
	case $objectMethod in
		objectVars) echo "filename name value valueRegEx multipleValueFlag delim" ;;
		construct)
			while [[ "$1" =~ ^- ]]; do case $1 in
				-m) multipleValueFlag="-m" ;;
			esac; shift; done

			filename="$1"
			name="$2"
			value="$3"
			if [ "$4" ]; then
				valueRegEx="$4"
			else
				valueRegEx="$3"
			fi

			# if multipleValueFlag is set and the fist char is a delimeter, we treat the value as a list to merge
			# if the first is not a delim, then we overwrite any existing value and we write it the same as if is was a single value
			if [ "$multipleValueFlag" ] && [[ ! ${value:0:1} =~ [a-zA-Z] ]]; then
				delim=${value:0:1}
				value=${value:1}
			else
				multipleValueFlag=""
			fi

			local filenameShort nameShort valueShort
			strShorten -R filenameShort 16 "$filename"
			strShorten -R nameShort 13 "$name"
			strShorten -R valueShort 40 "$value"
			displayName="name/value '$filenameShort:$nameShort' should be '$valueShort'"
			;;

		check)
			[ -f "$filename" ] || return 1
			if [ ! "$multipleValueFlag" ]; then
				grep -q "^[[:space:]]*$name[[:space:]][[:space:]]*${valueRegEx}" "$filename"
			else
				local valueParse=$value
				while [ "${valueParse// }" ]; do
					local v=${valueParse%%${delim}*}
					local valueParse=${valueParse#*${delim}}
					grep -q "^[[:space:]]*$name[[:space:]].*\b${v}\b" "$filename" || return 1
					[[ ! "${valueParse}" =~ $delim ]] && valueParse=""
				done
				return 0
			fi
			;;

		apply)
			[ ! -s "$filename" ] && bash -c "echo  >> \"$filename\""

			# remove the # (comment) if present
			if [ "$(grep  "^#*[[:space:]]*$name[[:space:]]" "$filename" | wc -l)" == "1" ]; then
				sed -i -e 's/^#*[ \t]*\('"$name"'[ \t].*\)$/\1/' "$filename"
			fi

			# if the name does not exist, add it
			if ! grep -q "^[[:space:]]*$name[[:space:]]" "$filename"; then
				sed -i -e '$ a\'"$name"' '"${value//\//\\/}" "$filename"

			# otherwise, update the value
			else
				if [ ! "$multipleValueFlag" ]; then
					sed -i -e 's/^[ \t]*\('"${name//\//\\/}"'[ \t]\).*$/\1 '"${value//\//\\/}"'/' "$filename"
				else
					local valueParse=$value
					while [[ "${valueParse// }" ]]; do
						local v=${valueParse%%${delim}*}
						local valueParse=${valueParse#*${delim}}
						if ! grep -q "^[[:space:]]*$name[[:space:]].*\b${v}\b" "$filename" 2>/dev/null; then
							sed -i -e 's/^[ \t]*'"${name//\//\\/}"'[ \t].*$/&'"${delim//\//\\/}${v//\//\\/}"'/' "$filename"
						fi
						[[ ! "${valueParse}" =~ $delim ]] && valueParse=""
					done
					return 0
				fi
			fi
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_configNameValueEq [-m] <filename> <name> <value> [ <valueRegEx> ]
# NOTE: This function is a newer superset of cr_configNameValue. The -d opt can specify whether the delim is space or = or something else
#       despite the name, this function can be used for lines that use any delimiter by specifying the -d option. -d" " should be equivalent
#       to cr_configNameValue but it has not been well tested yet. After testing, we can replace the algorithm in cr_configNameValue wiht
#       this one and make this cr_configNameValueEq be a wrapper that jst changes the default -d value.
# declare the the config file contains name value attribute line that matches name and valueRegEx using = as the
# delim between name and value.
# If valueRegEx is not specified, it will be created from <value> by adding expressions that ignore leading
# and trailing whitespace
#
# Apply follows this algorithm
#    1) if a line for <name> is found in the file that has been commented out, that line will be un-commented by
#         removing the leading # character(s)
#    2) if a line for <name> exists, its value will be replaced with <value>
#       if it does not exist, name value pair will be appended to the end of the file
#
# Param:
#    filename:   file to check for the presence of a line of text
#    name:       the left side of the equal sign
#    value:      the right side of the equal sign
#    valueRegEx: optional regex expression for value that will match any compliant line
#                if not specified a compliant line must match value exactly except for leading and trailing whitespace
#
# Options:
#    -d <delimiter> : This is a single character that is the delimiter between name and value. If <delimiter> is " "
#         then runs of tabs and spaces are treated like one delimter. Whitespace between name and <delimiter> is allowed
#         but when this function adds a new line, it does not put a space between name and <delimeter> nor between
#         <delimeter> and value. Normally whitespace is allowed and ifnored between <delimeter> and value but that could
#         be changed by specifying valueRegEx.
#    -m : multipleValueFlag. <value> is interpreted as a list of values. If the first character is not a delimeter (not a letter)
#         then the list is taken as the absolute, complete list that the value should have -- no more no less.
#         Otherwise, if the value does begin with a delimiter (any non-letter) then the list is taken as a list of values
#         that should be included, but there may be others too.
#         When needed, we can enhance this function to support values preceeded by a - to indicate that they should not be
#         in the list
function cr_configNameValueEq()
{
	case $objectMethod in
		objectVars) echo "filename name value valueRegEx multipleValueFlag delim delimRegEx valListDelim" ;;
		construct)
			delim="=" delimRegEx="="
			while [[ "$1" =~ ^- ]]; do case $1 in
				-m) multipleValueFlag="-m" ;;
				-d*) bgOptionGetOpt val: delim "$@" && shift
					 delimRegEx="$delim"
					 [ "$delimRegEx" == " " ] && delimRegEx="[[:space:]]"
					 ;;
			esac; shift; done

			filename="$1"
			name="$2"
			value="$3"
			if [ "$4" ]; then
				valueRegEx="$4"
			else
				valueRegEx="${value//[[]/\\[}"
				valueRegEx="${valueRegEx//$/\\$}"
				valueRegEx="${valueRegEx//\^/\\^}"
				valueRegEx="${valueRegEx//\*/\\*}"
				valueRegEx="${valueRegEx//\./\\.}"
				valueRegEx="${valueRegEx//+/[+]}"
				valueRegEx="[[:space:]]*${valueRegEx}[[:space:]]*"
			fi

			# if multipleValueFlag is set and the fist char is a delimeter, we treat the value as a list to merge
			# if the first is not a delim, then we overwrite any existing value and we write it the same as if is was a single value
			if [ "$multipleValueFlag" ] && [[ ! ${value:0:1} =~ [a-zA-Z] ]]; then
				valListDelim=${value:0:1}
				value=${value:1}
			else
				multipleValueFlag=""
			fi

			local filenameShort nameShort valueShort
			strShorten -R filenameShort 16 "$filename"
			strShorten -R nameShort 13 "$name"
			strShorten -R valueShort 40 "$value"
			displayName="name/value '$filenameShort:$nameShort' should be '$valueShort'"
			;;

		check)
			[ -f "$filename" ] || return 1
			if [ ! "$multipleValueFlag" ]; then
				grep -q "^[[:space:]]*$name[[:space:]]*${delimRegEx}${valueRegEx}\(#.*\)*$" "$filename"
			else
				local valueParse=$value
				while [ "${valueParse// }" ]; do
					local v=${valueParse%%${valListDelim}*}
					local valueParse=${valueParse#*${valListDelim}}
					grep -q "^[[:space:]]*$name[[:space:]]*${delimRegEx}.*\b${v}\b" "$filename" || return 1
					[[ ! "${valueParse}" =~ $valListDelim ]] && valueParse=""
				done
				return 0
			fi
			;;

		apply)
			[ ! -s "$filename" ] && bash -c "echo  >> \"$filename\""

			# remove the # (comment) if a commented out line for name is present
			# but only if there is exactly one matching line for this name with or without a comment
			if [ "$(grep  "^#*[[:space:]]*$name[[:space:]]*${delimRegEx}" "$filename" | wc -l)" == "1" ]; then
				sed -i -e 's/^#*[ \t]*\('"${name//\//\\/}"'[[:space:]]*'"${delimRegEx}"'.*\)$/\1/' "$filename"
			fi

			# if the name does not exist, add it
			if ! grep -q "^[[:space:]]*$name[[:space:]]*${delimRegEx}" "$filename"; then
				sed -i -e '$ a\'"${name//\//\\/}"''"${delim}"''"${value//\//\\/}" "$filename"

			# otherwise, update the value
			else
				if [ ! "$multipleValueFlag" ]; then
					sed -i -e 's/^\([ \t]*'"${name//\//\\/}"'[ \t]*'"${delimRegEx}"'\).*$/\1'"${value//\//\\/}"'/' "$filename"
				else
					local valueParse=$value
					while [[ "${valueParse// }" ]]; do
						local v=${valueParse%%${valListDelim}*}
						local valueParse=${valueParse#*${valListDelim}}
						if ! grep -q "^[[:space:]]*$name[[:space:]]*${delimRegEx}.*\b${v}\b" "$filename" 2>/dev/null; then
							sed -i -e 's/^[ \t]*'"${name//\//\\/}"'[ \t]*'"${delimRegEx}"'.*$/&'"${valListDelim//\//\\/}${v//\//\\/}"'/' "$filename"
						fi
						[[ ! "${valueParse}" =~ $valListDelim ]] && valueParse=""
					done
					return 0
				fi
			fi
			;;

		*) cr_baseClass "$@" ;;
	esac
}



# usage: cr_configNameNotExists [-c] <filename> <name>
#     filename:   file to check for the presence of a line of text
#     name:       the first white space separated token on the line
#
# declare the the config file does not contain a line where <name> is the first token.
# If a matching line is found, apply will either remove it (default) or add a # comment character to its start(-c)
#
# Options:
#    -c : comment the line if found instead of removing it from the file completely
function cr_configNameNotExists()
{
	case $objectMethod in
		objectVars) echo "filename name commentFlag" ;;
		construct)
			while [[ "$1" =~ ^- ]]; do case $1 in
				-c) commentFlag="-c" ;;
			esac; shift; done
			filename="$1"
			name="${2%[:=]}"

			local filenameShort nameShort valueShort
			strShorten -R filenameShort 25 "$filename"
			strShorten -R nameShort 20 "$name"
			displayName="config '${filename}:$name' should not exist"
			displayName="${filename}:$name config setting should not exist"
			;;

		check)
			creqLog3 "! grep -q \"^[[:space:]]*$name\b\" \"$filename\""
			[ ! -s "$filename" ] && return 0
			! grep -q "^[[:space:]]*$name\b" "$filename" 2>/dev/null
			;;

		apply)
			[ ! -s "$filename" ] && return 0

			# remove the # (comment) if present
			if [ "$commentFlag" ]; then
				sed -i -e 's/^[ \t]*'"$name"'\>.*$/#&/' "$filename"
			else
				sed -i -e '/^[ \t]*'"$name"'\>.*$/d' "$filename"
			fi
			;;

		*) cr_baseClass "$@" ;;
	esac
}








##################################################################################################################
### ConfigLine Functions
# A configLine can be any arbitrary line in a configuration file. It could be a name/value pair or INI param but typically
# its used when the format of the line is not a name/value pair or is not of the form <name> <separator> <value>



# usage: configLineReplace [--match=<type>] [-d] [-a] [-f] [-c] [--check] <filename> <line> [<lineMatchData>]
# This function manages arbitrary lines in a config file. The core algorithm is that it removes all
# lines that matches <mutexLineRegEx> (derived from --match=<type> and <lineMatchData>) and at the first ocurrance
# where a matching line was, or at the end of file if none were found, it adds <line> (or does another operation
# based on the options)
#
# This makes it tolerant of formating that human maintainers may do like changing whitespace or adding
# an end of line comment, preserves the position of existing <line> and ensures that duplicate lines
# do not exist.
#
# It can optionally comment out or uncomment the <line> to temporarily disable a line without loosing
# its position in the file and previous value
#
# How it creates <mutexLineRegEx> can be specified with the --match=<type> option and the optional
# <lineMatchData>. The caller can controll it explicitly by specifying the exact regEx in <lineMatchData>
# or let the function create <mutexLineRegEx> from <line> using a format pattern specified by --match.
#
# If neither --match nor <lineMatchData> is specified, it will match <line> being tolerant of whitespace differences.
# If <lineMatchData> is specified but --match is not specified, it will take <lineMatchData> as the <mutexLineRegEx>
# If --match is specified, it will create <mutexLineRegEx> from <line> according to the <type> specified
#
# TODO: add -s <sectionName> to support limiting the configLine to a INI style section
# TODO: add more control of <valueMatchRegEx> (aka <lineRegExAcceptable>) E.G. ^<name>= identifies mutually exclusive lines, and "=(<val1>|<val2)" identifies if the value is acceptable to leave.
# Algorithm:
#  The algorithm is applied to the file and if it results in the same content as the file already had, the
#  file will not be opened for writing and will not have its timestamp changed.
#    1) remove any line that matches <mutexLineRegEx>
#       if -c is specified, it also removes any commented out lines matching <mutexLineRegEx> without the comment prefix
#    2) determine the operation position. This is the postion of the first matched line, prefering uncommented
#       lines to matching commented lines (if -c is given). If no matches were found, the operation postion
#       is the end of file.
#    3) at the operation position perform the operation that is specified by the options.
#           delete) if the mode is delete (-d) or if <line> is empty, no line is written at the operation
#                   possition which leaves the file with no matching lines.
#           leave)  if there was an existing line at the operation position and it either matches the
#                   acceptable regEx or the mode is -a (any), that line is reinserted there to be
#                   the one matching line.
#           add)    if neither of the above conditions are true, <line> is written at that position
#                   to become the one matching line
# Params:
#    <filename>  : the file to operate on
#    <line>      : the literal line to set if the line needs to be added. Without -a, this literal line will appear
#                  in the file after the function is done. However, if <line> is the empty string, it will not be
#                  inserted and it has a similar effect as the -d (delete) option.
#    <lineMatchData> : this along with the --match=<type> determines the <mutexLineRegEx> expression that will
#                  match all lines that are logically the same mutually exclusive semantic meaning.
#                  The default is to create <mutexLineRegEx> from <line> in a manner that is tolerant of whitespace chagnes.
# Options:
#    -a : any line that matches <mutexLineRegEx> is sufficient. Only use <line> if none already exists.
#         this is used to make sure that the file has this logical line and to set the default as <line>
#         but allows some other process to change the line's value and not have this call change it back
#    -f : force. don't use any acceptability rules to see if the current line is equivalent to <line> but
#         instead always make sure that its exactly <line>. This is related to -a but very different.
#         For example, for --match=nameValueEq, -a will allow the <name> to remain set to any <value>.
#         Without -a, the <name> setting line must have the <value> specified in <line> but it can vary
#         in whitespace like '<name>= <value>' vs '<name>=<value>'.
#         With -f <line> will be set in the file as is.
#    -d : delete. remove the specified line. This is the same as setting line to "" and specifying mutexLineRegEx,
#         but this option allows you to provide only line and have mutexLineRegEx get created from line.
#         If line contains regex characters, its cumbersome to create the regex
#         -d can be added to any valid call to reserve its affect
#    -c : consider commented lines that match and matching also. This will remove old commented versions
#         of the line. It also means that the new line will be set in the same file location as the
#         first occurance of the matching commented line. To preserve the file order, lines can be
#         commented and uncommented instead of removed and re-added.
#    --commentOut : if there is an active line, disable it by prefixing it with "# ". It there is no active line
#         do nothing. Implies -c
#    --commentBackIn : if there is a commented line, remove the comment prefix to make it active. If there
#         is an existing active line, leave it. If there is none, add <line> to the end. Implies -c
#    --check : alias for --isAlreadySet. dont change the file. return true (0) if the file already contains the correct content
#    --isAlreadySet : alias for --check that makes it easier to know that true means that its already set this way.
#    --wouldChangeFile : alias for --check but inverts the return code. this makes scripts easier to read.
#    --returnTrueIfAlreadySet  : (default) this makes scripts read easier because you know what it means
#                                if it exits true (no change was made to the file because this <line> is already set)
#    --returnTrueIfChanged     : inverts the normal return code so that it reads true if the operation changed the
#                                file and false if no change was needed
#    --returnTrueIfSuccessful  : true(0) if the operation is succesful and the file is now compliant
#    --match=<type> : this determines how the regex expression that matches lines will be created from the
#                      <line> and how <mutexLineRegEx> will be interpretted.
#        ignoreWhitespace : (default if <lineMatchData> is empty). whitespace at the start or end is optional and
#                           each run of whitespace in the interior of <line> will match one or more whitespace characters
#        custom           : (default if <lineMatchData> is not empty). <lineMatchData> is taken as <mutexLineRegEx> unchanged.
#        exact            : any regex special characters in <line> are escaped but other than that no modifications
#                           are made so that only the exact, literal string is matched
#        nameValueEq      : match only the '^<name>=' part of <line>. whitespace is optional on both sides of <name>
#                           Example: "color = blue"
#        nameValueColon   : match only the '^<name>:' part. whitespace is optional on both sides of <name>
#                           Example: "color : blue"
#        nameValueSpace   : match only the '^<name> ' part where <name> is the first whitespace delimited word
#                           Example: "color blue"
#    --debug-script : debug flag. print the awk script to stdout instead of running it
#    --debug-output : debug flag. launch a comparison app to show the differences that would be introduced
# Exit Codes:
#     0 (true)  : if the <line> was already set in compliance with the options
#     1 (false) : if the file was cahnged to add <line> or otherwise make it compliant.
# Note that these options explicitly state which way will return true/false and whether the operation will be
# performed if needed or if its just checking.
#    --isAlreadySet            : check only (never change the file)  : true(0) means no change needed
#    --wouldChangeFile         : check only (never change the file)  : true(0) means file would change
#    --returnTrueIfAlreadySet  : change the file if needed           : true(0) means no change needed
#    --returnTrueIfChanged     : change the file if needed           : true(0) means file did change
function configLineReplace()
{
	local filename deleteFlag forceFlag debugFlag anyFlag commentFlag matchIgnoreSpacesFlag matchMode mutexLineRegEx valueMatchRegEx
	local bgAwkOpMode="--returnTrueIfChanged" returnTrueIfSuccessful commentAction
	while [ $# -gt 0 ]; do case $1 in
		-a) anyFlag="-a" ;;
		-c) commentFlag="-c" ;;
		-d) deleteFlag="-d" ;;
		-f) forceFlag="-f" ;;
		--commentOut)    commentAction="commentOut";    commentFlag="-c" ;;
		--commentBackIn) commentAction="commentBackIn"; commentFlag="-c" ;;
		--match*) matchMode="${1#*=}"  ;;
		--debug-script) debugFlag="-d" ;;
		--debug-output) debugFlag="-d -i" ;;
		--checkOnly|--check)      bgAwkOpMode="--isAlreadySet" ;;
		--isAlreadySet)           bgAwkOpMode="$1" ;;
		--wouldChangeFile)        bgAwkOpMode="$1" ;;
		--returnTrueIfChanged)    bgAwkOpMode="$1" ;;
		--returnTrueIfAlreadySet) bgAwkOpMode="$1" ;;
		--returnTrueIfSuccessful) returnTrueIfSuccessful="1" ;;
		*) bgOptionsEndLoop --firstParam filename "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local line="$1"
	local lineMatchData="$2"

	if [ ! "$matchMode" ]; then
		[ "$lineMatchData" ] && matchMode="custom" || matchMode="ignoreWhitespace"
	fi

	case $matchMode in
		custom)
			mutexLineRegEx="$lineMatchData"
			valueMatchRegEx="<NEVERMATCH{0,1000}>" # for a user regex, we don't know how to match a value speparately
			;;
		exact)
			mutexLineRegEx="$line"
			stringEscapeForRegex mutexLineRegEx
			valueMatchRegEx="" # "" allways matches. Any line that exactly matches matches the specifiec value too
			;;
		ignoreWhitespace)
			mutexLineRegEx="$line"
			stringTrim -m -i mutexLineRegEx
			stringEscapeForRegex mutexLineRegEx
			mutexLineRegEx="^[[:space:]]*${mutexLineRegEx// /'[[:space:]]+'}[[:space:]]*$"
			valueMatchRegEx="" # "" allways matches. Any line that matches, matches the specifiec value too
			;;
		nameValueEq)
			mutexLineRegEx="$line"
			[[ ! "$mutexLineRegEx" =~ = ]] && assertError -v filename -v line "line needs to contain a = when the mode is nameValueEq"
			mutexLineRegEx="${mutexLineRegEx%%=*}"
			mutexLineRegEx="^[[:space:]]*${mutexLineRegEx//[[:space:]]}[[:space:]]*="

			# name/value lines can have a separate notion of matching to see if the value is the same
			# even if it does not exactly match because of whitespace changes. We could also allow <lineMatchData>
			# to contain a regex that mathes other values that are aceptable
			valueMatchRegEx="$line"
			valueMatchRegEx="${valueMatchRegEx#*=}"
			valueMatchRegEx="=[[:space:]]*${valueMatchRegEx//[[:space:]]}[[:space:]]*$"
			;;
		nameValueColon)
			mutexLineRegEx="$line"
			[[ ! "$mutexLineRegEx" =~ : ]] && assertError -v filename -v line "line needs to contain a : when the mode is nameValueColon"
			mutexLineRegEx="${mutexLineRegEx%%:*}"
			mutexLineRegEx="${mutexLineRegEx//[[:space:]]}"
			mutexLineRegEx="^[[:space:]]*${mutexLineRegEx/=/'[[:space:]]*:'}"

			# name/value lines can have a separate notion of matching to see if the value is the same
			# even if it does not exactly match because of whitespace changes. We could also allow <lineMatchData>
			# to contain a regex that mathes other values that are aceptable
			valueMatchRegEx="$line"
			valueMatchRegEx="${valueMatchRegEx#*:}"
			valueMatchRegEx=":[[:space:]]*${valueMatchRegEx//[[:space:]]}[[:space:]]*$"
			;;
		nameValueSpace)
			mutexLineRegEx="$line"
			stringTrim -l -i mutexLineRegEx
			[[ ! "$mutexLineRegEx" =~ \  ]] && assertError -v filename -v line "line needs to contain a space when the mode is nameValueSpace"
			mutexLineRegEx="${mutexLineRegEx%% *}"
			assertNotEmpty mutexLineRegEx -v filename -v line "invalid line value. nameValueSpace mode could not find the name"
			mutexLineRegEx="^[[:space:]]*${mutexLineRegEx}[[:space:]]"

			# name/value lines can have a separate notion of matching to see if the value is the same
			# even if it does not exactly match because of whitespace changes. We could also allow <lineMatchData>
			# to contain a regex that mathes other values that are aceptable
			valueMatchRegEx="$line"
			valueMatchRegEx="${valueMatchRegEx#* }"
			valueMatchRegEx=" [[:space:]]*${valueMatchRegEx//[[:space:]]}[[:space:]]*$"
			;;
	esac

	# make a regex that will match commented version of matching lines
	local commentedMutexLineRegEx="${mutexLineRegEx//^/^#}"
	if [[ ! "$commentedMutexLineRegEx" =~ \^ ]]; then
		commentedMutexLineRegEx="^#${commentedMutexLineRegEx}"
	fi

	# in delete mode we just set the line to the empty string so that when it finds a match it will
	# remove it and not replace it with anything. The $line var has already been used to create mutexLineRegEx
	[ "$deleteFlag" ] && line=""

	# if commented inclusion is on, first do a scan to see if a non-commented line exists somewhere in the file.
	# in the real pass, if a commented line is encountered first, this will determine if that position should be
	# used or if it should be delted because a better one is coming up later in the file
	local knownToContainAMatchingLine="unknown"
	if [ "$commentFlag" ]; then
		knownToContainAMatchingLine="$(awk -v mutexLineRegEx="$mutexLineRegEx" '$0~mutexLineRegEx {f=1; print "yes"; exit} END{if (!f) print "no"}' "$filename")"
	fi


	#bgtraceVars -w35 line mutexLineRegEx commentedMutexLineRegEx valueMatchRegEx anyFlag deleteFlag forceFlag commentFlag commentAction knownToContainAMatchingLine
	bgawk ${debugFlag:--i} $bgAwkOpMode -n \
		-v mutexLineRegEx="$mutexLineRegEx" \
		-v valueMatchRegEx="$valueMatchRegEx" \
		-v line="$line" \
		-v commentedMutexLineRegEx="$commentedMutexLineRegEx" \
		-v anyFlag="$anyFlag" \
		-v commentFlag="$commentFlag" \
		-v deleteFlag="$deleteFlag" \
		-v forceFlag="$forceFlag" \
		-v commentAction="$commentAction" \
		-v knownToContainAMatchingLine="$knownToContainAMatchingLine" \
		"$awkDataLibrary"'

		# when the algorithm has choosen that its at the file position that the line should be, it
		# calls this function to write it out. This function does one of 3 actions
		#    1) write nothing if the line is being deleted
		#    2) write the original line ($0) if it is compliant and should stay
		#    3) write the input <line>
		# Params:
		#   <currentLineType> : indicates what type of line we are on when we decided to write the line.
		#      "active": its an existing active line that may be overwritten or left
		#      "comment": its an existing commented out line that could be left, replaced, or commented out.
		#      "EOF":     we go to the end of file without finding a place to put the line so append it or leave it missing.
		function writeTheLineHere(currentLineType) {
			#bgtrace("writeTheLineHere  currentLineType="currentLineType"  NR="NR)
			# dont write the line more than once in the file
			if (alreadyWritten) return

			# line being empty is our indicator that the line is being removed / delete. By doing nothing
			# the line will not be in the output stream -- i.e. skipped, aka deleted
			if (line=="" || deleteFlag) {
				# noop. if we are deleting the line, we just dont print any line at this moment

			# handle case to un-comment out the line we are at
			} else if (commentAction=="commentBackIn") {
				selectedLine=$0
				switch (currentLineType) {
					case "comment": sub("^[[:space:]]*#[[:space:]]*","", selectedLine); break
					case "active" : selectedLine=$0;   break
					case "EOF"    : selectedLine=line; break
				}
				print selectedLine

			# handle case to comment out the line we are at
			} else if (commentAction=="commentOut") {
				selectedLine=$0
				switch (currentLineType) {
					case "comment": break
					case "active" : selectedLine="# "selectedLine;   break
					case "EOF"    : selectedLine="# "line; break
				}
				print selectedLine

			# if the options and/or patterns say we can keep this line as it is, we just write $0
			} else if (!forceFlag && currentLineType=="active" && (anyFlag || $0~valueMatchRegEx) ) {
				print $0

			# if no case above was true, the default and most common action is to write input
			# <line> at this position, either replacing an active or commented lne or appending it at EOF
			} else {
				print line
			}

			# record that the line has been written/deleted so that any other mutexLineRegEx matching lines can
			# be removed
			alreadyWritten=1
		}

		$0~mutexLineRegEx {
			if (!alreadyWritten) {
				writeTheLineHere("active")
			}
			next
		}

		commentFlag && $0~commentedMutexLineRegEx {
			if (!alreadyWritten) {
				switch (knownToContainAMatchingLine) {
					# YES: we know that a non-comment match is coming so go ahead and remove this one without
					#     making this the lines position (dont call writeTheLineHere)
					case "yes": break;

					# NO: we know that there will not be a non-comment match coming so make this the
					#     lines position
					case "no":
						writeTheLineHere("comment")
						break

					# UNKNOWN: we did not pre scan so we dont know if an active match is coming up
					#     generally, if comment inclusion is on, we will know, but if not, we need to
					#     balance two things.
					#        1) if we make this the lines position, we may change the value of an active
					#           line later, whose value is differennt from <line> but acceptable
					#        2) if we dont make this the lines position, we may move the line to the
					#           end of the file and loose this position that is more organized.
					#     So the condition below is designed to match the cases where its not likely
					#     that an active line later on would have a different value that we would keep.
					#     Remember that as long as the code above does the extra scan to fill in
					#     knownToContainAMatchingLine, this unknown case wont come into play.
					#     there could be performance reasons where we choose to skip that scan.
					#     Also, in either case, it will tend to stabalize becauseevery time we run
					#     we remove duplicates. A case like this will only come up through manual
					#     file edits.
					case "unknown":
						if (!anyFlag || commentAction) {
							writeTheLineHere("comment")
						}
						break
				}
			}
			next
		}

		# if either the active or commented line match, this line will be skipped via calling next
		{print $0}

		END {
			if (!alreadyWritten) {
				# if we got to the end without making any position the lines position, append it
				writeTheLineHere("EOF")
			}
		}
	' "$filename"
	local result=$?

	# if nothing asserted an error, its sucessful. ignore $result which indicates whether the file
	# was changed. this case is not interested in that.
	[ "$returnTrueIfSuccessful" ] && return 0

	# return whether the file was or would be changed. The sense of the boolean is determined by
	# $bgAwkOpMode
	return "$result"
}

# usage: cr_configLine [<options>] <filename> <line> [ <lineRegEx> ]
# declare that the config file contains exactly one line that matches lineRegEx and is currenly set to <line>.
# This uses configLineReplace to do the work. The command line syntax is exactly the same as configLineReplace
#
# Params:
#   See configLineReplace for more details on the parameters
#   <filename> : file to check for the presence of a line of text
#   <line>     : the literal line of text that will be added if needed
#   <lineRegEx>: this is typically left blank which causes the function to generate it from <line>
#                 See the --match=<type> option of configLineReplace for options to control it
#
# Options:
#   See configLineReplace for more details on the options
#       any of the configLineReplace options are suportted that do not control the check/apply mode and the
#       meaning of the exit code (ie. not --debug-script --debug-output --checkOnly --isAlreadySet --wouldChangeFile
#                                 --returnTrueIfChanged --returnTrueIfAlreadySet --returnTrueIfSuccessful )
#   -a  : any mode. treat <line> like an initial default that is ok to change. It will only set
#         <line> if there are no matching lines. duplicate matching lines are still removed
#   -c  : consider commented out lines that would match if the comment prefix were removed for the
#         purpose of placement location and removing duplicates
#   -d  : delete the <line>. ignore <line> (except for the purpose of creating <lineRegEx>) and remove
#         all matching lines.
#   --match=<type> : determine how <lineRegEx> is created from <line>
#         ignoreWhitespace : whitespace at the start or end is optional and each run of whitespace in the interior
#                          of <line> will match one or more whitespace characters
#         exact          : any regex special characters are escaped but other than that no modifications are made
#                          so that only the exact, literal string is matched
#         nameValueEq    : match only the '^<name>=' part. whitespace is optional on both sides of <name>
#                          Example: "color = blue"
#         nameValueColon : match only the '^<name>:' part. whitespace is optional on both sides of <name>
#                          Example: "color : blue"
#         nameValueSpace : match only the '^<name> ' part where <name> is the first whitespace delimited word
#                          Example: "color blue"
#
# See Also:
#    configLineReplace
#    cr_configLineNotExist
function cr_configLine()
{
	case $objectMethod in
		objectVars) echo "passThruOpts filename line lineRegEx" ;;
		construct)
			while [[ "$1" =~ ^- ]]; do case $1 in
				-d|--debug-script|--debug-output|--checkOnly|--isAlreadySet|--wouldChangeFile|--returnTrueIfChanged|--returnTrueIfAlreadySet|--returnTrueIfSuccessful) assertError "this configLineReplace option '$1' is not valid for use in this creq" ;;
				-*) passThruOpts+=("$1") ;;
			esac; shift; done
			filename="$1"
			line="$2"
			lineRegEx="$3"

			local lineShort; strShorten -R lineShort 35 "$line"
			displayName="config line '$lineShort' in '$filename'"
			;;

		check) configLineReplace "${passThruOpts[@]}" --isAlreadySet           "$filename" "$line" "$lineRegEx" ;;
		apply) configLineReplace "${passThruOpts[@]}" --returnTrueIfSuccessful "$filename" "$line" "$lineRegEx" ;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_configLineNotExist <filename> <lineRegEx>
# declare that the config file does not contain any line matching the <lineRegEx>.
# This is the complementary cr_statement to cr_configLine. Both use configLineReplace to do the real work.
# The command line syntax is the same as cr_configLine except this cr_statement adds the -d option to
# configLineReplace to reverse its meaning -- i.e. to delete the line.
# See Also:
#    cr_configLine
#    configLineReplace
function cr_configLineNotExist()
{
	case $objectMethod in
		objectVars) echo "passThruOpts filename line lineRegEx" ;;
		construct)
			while [[ "$1" =~ ^- ]]; do case $1 in
				-d|--debug-script|--debug-output|--checkOnly|--isAlreadySet|--wouldChangeFile|--returnTrueIfChanged|--returnTrueIfAlreadySet|--returnTrueIfSuccessful) assertError "this configLineReplace option '$1' is not valid for use in this creq" ;;
				-*) passThruOpts+=("$1") ;;
			esac; shift; done
			filename="$1"
			line="$2"
			lineRegEx="$3"

			local lineShort; strShorten -R lineShort 35 "$line"
			displayName="line '$lineShort' should not exist in '$filename'"
			;;

		check) configLineReplace "${passThruOpts[@]}" -d --isAlreadySet           "$filename" "$line" "$lineRegEx" ;;
		apply) configLineReplace "${passThruOpts[@]}" -d --returnTrueIfSuccessful "$filename" "$line" "$lineRegEx" ;;

		*) cr_baseClass "$@" ;;
	esac
}














##################################################################################################################
### General Config Functions
# Functions that operate on general properties of a config file that is not dependant on the format of the content
# Typically this is empty lines and comment lines


# usage: configDropinCntr [-ext <dropinExt>] [--copyMode] [-s] [-S <changeStateVar>] <enabledFolder> <availFolder> <dropin> <command>
# Configuration dropins is the pattern where a configuration file includes all the files 'dropped'into
# a particular folder. Instead of editing the base config file, packages or admin can create snipits
# of configuration in a dropin file that they can control independent of the rest of the config. We
# can enable or disable that dropin config by adding or removing the file. Often, a differnt folder
# adjacent to the dropin folder will contain all the potential dropin files provided from multiple sources
# and we can enable them by creating a symlink from the real folder to the dropin in the adjacent folder.
# Implementations:
#     The implementation is chosed based on the folder names. If the availFolder is the enabledFolder.disable
#     the CopyMode is the default.
#     a sysadmin can set the mode directly by creating eihter a .dropinModeSymlink or .dropinModeCopy
#     file in the availFolder. That file can be empty.
#  Symlink (default) : this is the pattern where the availFolder contains all the actual dropin files
#       and the enabledFolder conatins symlinks just to the dropins that are enabled. This is prefered
#  CopyMode : this is the pattern where the enabledFolder contains the actual files that are enabled
#       and the availFolder is used as a place to store disabled plugins. The name is still somewhat
#       correct because these are disabled dropins that are *available* to enable.
#       This pattern is not as good because it opens the possibililty that the dropin could exist in
#       both places with different content. This is supported because some dropin folders from existing
#       projects like apt sources.d and sudo sudoers.d do not track disabled dropin files and its less
#       intrusive to only create a new .disabled folder to keep track of disabled dropins and leave
#       enabled dropins to be actual files that those projects and admins familiar with them expect.
# Params:
#     <enabledFolder> : the folder that contains links for any enabeled dropin
#     <availFolder>   : the folder that conatins all available dropin files
#     <dropin>        : the name of the dropin file
#     <command>  : enable|disable|status|edit|list
#         list   : list in a table. first column is enable|disable and second column is the dropin name
#         status -q : set exit code to indicate if the dropin exists and is enabled. without -q also prints a description
#                     0 : exists and is enabled
#                     1 : exists and is disabled
#                     2 : does not exist
#         edit   : open the config file in the user's configured editor
#         enable : change to enabled
#         disable : change to disabled
# Options:
#    --type <pluginType> : a short name for the type. This is used to display the plugin name and is useful when $dropin is not
#          descriptive wihout the context of what type of config it is. Example: apt, http, etc...  Common types will be gleaned
#          from the enableFolder
#    --ext <dropinExt> : a comma separated list of extentions for plugins in this folder. Typically none or one ext
#    -t <dropinExt>    : alias for --ext
#    -s  : status. don't make any change but set the return code to 1 if a change would be make
#          note that the status *command*'s exit code always reflects 0(true) as enabled. This option
#          reflects whether the dropin is already in the state specified in $command. This is used to
#          check to see if the command would do anything if it is called without the -s
#    -S <changeStateVar> : if a change is made, set the variable named <changeStateVar> to "1"
#    -e  : edit. open the dropin file in the user's prefered editor (see getUserEditor and getUserCmpApp)
# Exit Code:
#   enable|diable (whithout -s)
#      0 : a change was successfully made. In this case the caller knows that the config state is now
#          different that is was before the call was made.
#      1 : no change was needed so nothing was done. the config was already in the state specified
#   enable|diable when -s is specified
#      0 : true. the dropin is in the specified state by <command>
#      1 : false. the dropin is not in the speciied state by <command>
#   status:
#      0 : true.  dropin exists and is enabled
#      1 : false. dropin exists but is disabled
#      2 : false. dropin does not exist
# See Also:
#    configDropinCntrCopyMode
#    cr_configDropinCntr
function configDropinCntr()
{
	local cmdLine=("$@")
	local changeStateVar statusFlag editFlag dropinExt dropinType
	while [[ "$1" =~ ^- ]]; do case $1 in
		-s)    statusFlag="-s" ;;
		-S*)   bgOptionGetOpt val: changeStateVar "$@" && shift ;;
		-e)    editFlag="-e" ;;
		--ext) dropinExt="$2"; shift ;;
		-t*)   bgOptionGetOpt val: dropinExt "$@" && shift ;;
		--type*) bgOptionGetOpt val: dropinType "$@" && shift ;;
	esac; shift; done
	local enabledFolder="$1"
	local availFolder="$2"
	if [[ "$3" =~ ^((list)|())$ ]] && [ ! "$4" ]; then
		local dropin=""
		local command="${3:-list}"
	else
		local dropin="$3"
		local command="${4:-enable}"
	fi

	dropinType="${dropinType:-$(configDropinGleanTypeFromFolder "$enableFolder" "$availFolder" "$dropin")}"

	# set the dropinMode based on the folder convention and the presense of an override file
	local dropinMode="symlink"; [ "$availFolder" == "${enabledFolder}.disabled" ] && dropinMode="copy"
	[ -f "${enabledFolder}/.dropinModeCopy" ] && dropinMode="copy"
	[ -f "${enabledFolder}/.dropinModeSymlink" ] && dropinMode="symlink"

	local dropinDispName="${dropinType}:${dropin}"

	case $command:$dropinMode in
		list:*)
			local dropinFilterTerm=""; [ "${dropinExt}" ] && dropinFilterTerm="-name *.${dropinExt}"

			local dropinName; while read -r dropinName; do
				local state="disabled"; [ -f "$enabledFolder/${dropinName}${dropinExt:+.}${dropinExt}" ] && state="enabled"
				printf "%-8s %s\n" "$state" "$dropinName"
			done < <(find -H "$enabledFolder" "$availFolder" -maxdepth 1  \( -type f -or -type l \) $dropinFilterTerm -printf "%P\n" | sed 's/'"${dropinExt:+.}${dropinExt}"'$//' | sort -u) \
			| sort
			true
			;;
		status:*)
			# call ourselves with the -s option and 'enable' command to do a dry run, setting the exit code
			configDropinCntr -s "$enabledFolder" "$availFolder" "${dropinName}" "enable"
			local result="$?"
			if [ ! "$quietFlag" ]; then case $result in
				0) echo "dropin '$dropinName' is enabled" ;;
				1) echo "dropin '$dropinName' is disabled" ;;
				2) echo "dropin does not exist" ;;
			esac; fi
			return "$result"
			;;

		# symlinkMode implementation
		enable:symlink)
			if [ ! -e "$enabledFolder/$dropin" ]; then
				setReturnValue "$changeStateVar" "1"
				if [ "$statusFlag" ]; then
					[ -f "$availFolder/$dropin" ] && return 1 || return 2
				fi
				assertFileExists "$availFolder/$dropin" "Could not enable dropin '$dropin' because '$availFolder/$dropin' does not exist"
				bgsudo -w "$enabledFolder/$dropin" -p "enabling config '$dropinDispName' [sudo]:" \
					ln -s -f "$(pathGetRelativeLinkContents "$enabledFolder/$dropin" "$availFolder/$dropin")"  "$enabledFolder/$dropin"
				return 0
			fi
			return 1
			;;
		disable:symlink)
			if [ -e "$enabledFolder/$dropin" ]; then
				setReturnValue "$changeStateVar" "1"
				[ "$statusFlag" ] && return 1
				if [ -h "$enabledFolder/$dropin" ]; then
					bgsudo -w "$enabledFolder/$dropin" -p "disabling config '$dropinDispName' [sudo]:" \
						rm -f "$enabledFolder/$dropin"
					return 0

				else
					# it should not be a file but we can still fix this by moving it to the available folder
					if [ -e "$availFolder/$dropin" ] && fsIsDifferent "$availFolder/$dropin" "$enabledFolder/$dropin"; then
						bgsudo -w "$availFolder/" -p "disabling config '$dropinDispName' [sudo]:" \
							mv "$availFolder/$dropin" "$availFolder/$dropin.bak$(date +"%Y%m%d%H%M")"
					fi
					bgsudo -w "$enabledFolder/" -w "$availFolder/" -p "disabling config '$dropinDispName' [sudo]:" \
						mv "$enabledFolder/$dropin" "$availFolder/$dropin"
					return 0
				fi
				return 1
			elif [ -h "$enabledFolder/$dropin" ]; then
				# its disabled because the link does not point to an existing file but still, there is a bad
				# link so we removed it.
				[ "$statusFlag" ] && return 0
				bgsudo -w "$enabledFolder/$dropin" -w "$availFolder/" -p "disabling config '$dropinDispName' [sudo]:" \
					rm -f "$enabledFolder/$dropin"
			fi
			;;
		edit:symlink)
			bgsudo -w "$availFolder/$dropin" -w "$availFolder/" -p "edit config '$dropinDispName' [sudo]:" \
				$(getUserEditor) "$availFolder/${dropin}"
			;;


		# copyMode implementation
		enable:copy)
			if [ ! -e "$enabledFolder/$dropin" ]; then
				setReturnValue "$changeStateVar" "1"
				if [ "$statusFlag" ]; then
					[ -f "$availFolder/$dropin" ] && return 1 || return 2
				fi
				assertFileExists "$availFolder/$dropin" "Could not enable dropin '$dropin' because '$availFolder/$dropin' does not exist"
				bgsudo -w "$enabledFolder/" -w "$availFolder/" -p "enable config '$dropinDispName' [sudo]:" \
					mv "$availFolder/$dropin"  "$enabledFolder/$dropin" || assertError "mv failed"
				return 0
			fi
			return 1
			;;
		disable:copy)
			if [ -e "$enabledFolder/$dropin" ]; then
				setReturnValue "$changeStateVar" "1"
				[ "$statusFlag" ] && return 1

				# there should not be a file in the availFolder also so we have to deal with that
				# before moving the droping to the availFolder. if its not different, we can just
				# overwrite it but it its different, we save a backup
				if [ -e "$availFolder/$dropin" ] && fsIsDifferent "$availFolder/$dropin" "$enabledFolder/$dropin"; then
					bgsudo -w "$availFolder/" -p "disable config '$dropinDispName' [sudo]:" \
						mv "$availFolder/$dropin" "$availFolder/$dropin.bak$(date +"%Y%m%d%H%M")"
				fi
				bgsudo -w "$enabledFolder/"  -p "disable config '$dropinDispName' [sudo]:" \
					mkdir -p "$availFolder/" || assertError "mkdir failed"
				bgsudo -w "$enabledFolder/" -w "$availFolder/" -p "disable config '$dropinDispName' [sudo]:" \
					mv "$enabledFolder/$dropin" "$availFolder/$dropin" || assertError "mv failed"
				return 0
			fi
			return 1
			;;
		edit:copy)
			if [ -f "$availFolder/${dropin}" ] && [ "$enabledFolder/${dropin}" ]; then
			 	if fsIsDifferent "$availFolder/${dropin}" "$enabledFolder/${dropin}"; then
					confirm "
						the source dropin file exists in both the enable and disable folder with different content
						a diff editor will be opened to compare them. If you resolve the differences, the disabled one will be removed
						continue? y/n
					" || return
					bgsudo -r "$availFolder/${dropin}" -w "$enabledFolder/${dropin}"  -p "edit '$dropinDispName' [sudo]:" \
						$(getUserCmpApp) "$availFolder/${dropin}" "$enabledFolder/${dropin}"
				fi
				if ! fsIsDifferent "$availFolder/${dropin}" "$enabledFolder/${dropin}"; then
					bgsudo -w "$availFolder/" -p "fixing $dropinDispName [sudo]:" \
						rm "$availFolder/${dropin}"
				fi

			elif [ "$enabledFolder/${dropin}" ]; then
				bgsudo -w "$enabledFolder/${dropin}" -p "edit '$dropinDispName' [sudo]:" \
					$(getUserEditor) "$enabledFolder/${dropin}"

			elif [ -f "$availFolder/${dropin}" ]; then
				bgsudo -w "$availFolder/${dropin}" -p "edit '$dropinDispName' [sudo]:" \
					$(getUserEditor) "$availFolder/${dropin}"

			else
				assertError "no configuration found for '$dropinDispName'"
			fi
			;;
		view:copy)
			if [ -f "$availFolder/${dropin}" ] && [ "$enabledFolder/${dropin}" ]; then
				confirm "
					the source dropin file exists in both the enable and disable folder. Typically it should be in only one of those
					and currently '$availFolder/${dropin}' is not currently being used and can be removed but you should confirm that
					the version of the config that is currently enabled is the version you want to keep.
					continue? y/n
				" || return
			fi

			if [ "$enabledFolder/${dropin}" ]; then
				bgsudo -r "$enabledFolder/${dropin}"  -p "view '$dropinDispName' [sudo]:" \
					$(getUserPager) "$enabledFolder/${dropin}"
			elif [ -f "$availFolder/${dropin}" ]; then
				bgsudo -r "$availFolder/${dropin}"  -p "view '$dropinDispName' [sudo]:" \
					$(getUserPager) "$availFolder/${dropin}"
			else
				assertError "no configuration found for '$dropinDispName'"
			fi

			;;
		*) 	assertError -v enabledFolder -v availFolder -v dropin -v command -v dropinMode "unknown command"
	esac

	return
}


# usage: configDropinGleanTypeFromFolder <typeVar> <enabledFolder> [<availFolder> [<dropin> ]]
function configDropinGleanTypeFromFolder()
{
	case $2 in
		*/apt/*)  returnValue "apt" "$1" ;;
		*/http/*) returnValue "http" "$1" ;;
		*nginx*)  returnValue "nginx" "$1" ;;
		*apache*) returnValue "apache" "$1" ;;

	esac
}





# usage: cr_configDropinCntr <enabledFolder> <availFolder> <dropin> <targetState>
# declare that the <dropin> config file is either enabled or disabled.
# A dropin file is a config file that is copied to a folder where all compliant files in that folder
# are included in some program's configuration. (like /etc/apache2/sites-enabled/sites-available)
# Params:
#     <enabledFolder> : the folder that contains links for any enabeled dropin
#     <availFolder>   : the folder that conatins all available dropin files
#     <dropin>        : the name of the dropin file
#     <targetState>   : enable|disable. the state of the dropin the dropin should be in after this call
# See Also:
#    configDropinCntr
function cr_configDropinCntr()
{
	case $objectMethod in
		objectVars) echo "enabledFolder availFolder dropin targetState" ;;
		construct)
			enabledFolder="$1"
			availFolder="$2"
			dropin="$3"
			targetState="$4"
			case $targetState in
				enable)  displayName="dropin '$dropin' should be enabled" ;;
				disable) displayName="dropin '$dropin' should be disabled" ;;
				*) assertError -v enabledFolder -v availFolder -v dropin "expected enable|disable. got '$targetState'"
			esac
			;;

		check) configDropinCntr -s "$enabledFolder" "$availFolder" "$dropin" "$targetState" ;;

		apply) configDropinCntr "$enabledFolder" "$availFolder" "$dropin" "$targetState" ;;

		*) cr_baseClass "$@" ;;
	esac
}



# usage: cr_configNoEmptyLines [-b] [-m] [-e]  <filename>
# declare that the file has no blank lines. Default is no blank lines. Any combination of -b -m and -e can be used to
# alter that
# Params:
#    <filename> : the file to check
# Options:
#    -b : beginning. remove blank lines at the beginning of the file
#    -m : middle. remove blank lines in the middle of the file (separating non-blank lines)
#    -e : ending. remove blank lines at the end of the file. (also makes sure the file ends with a linefeed)
function cr_configNoEmptyLines()
{
	case $objectMethod in
		objectVars) echo "filename places" ;;
		construct)
			places=""
			local flag; while getopts  "bme" flag; do case $flag in
				b) places="${places}${places:+ }doBeg" ;;
				m) places="${places}${places:+ }doMid" ;;
				e) places="${places}${places:+ }doEnd" ;;
			esac; done; shift $((OPTIND-1)); unset OPTIND
			places="${places:-doBeg doMid doEnd}"
			filename="$1"
			;;

		check)
			[ ! -f "$filename" ] && return 0

			# enable the exit jump for each place we are looking for
			local begExit=""; [[ "$places" =~ doBeg ]] && begExit='abort=1; res=1; exit 1'
			local midExit=""; [[ "$places" =~ doMid ]] && midExit='abort=1; res=1; exit 1'
			local endExit=""; [[ "$places" =~ doEnd ]] && endExit='abort=1; res=1; exit 1'

			# if we are only looking for beginning lines, and we encounter a non-blank line at the start, return true immediately
			local trueOnFirstNonBlankLine=""; [ "$places" == "doBeg" ] && trueOnFirstNonBlankLine='/[^ \t]/   {abort=1; res=0; exit 0}'

			awk '
				BEGIN      {beg=1; begFound=0; midFound=0; endFound=0}
				'"$trueOnFirstNonBlankLine"'
				/^[ \t]*$/ {blank=1; if (beg) { begFound=1; '"$begExit"' } else midOrEndSeen=1}
				/[^ \t]/   {blank=0; beg=0; if (midOrEndSeen) { midFound=1; '"$midExit"'} }
				END        {
					if (abort) exit res
					if (blank) { endFound=1; '"$endExit"'}
				}
			' "$filename"
			;;

		apply)
			local begInclude="1"; [[ "$places" =~ doBeg ]] && begInclude='0'
			local midInclude="1"; [[ "$places" =~ doMid ]] && midInclude='0'
			local endInclude="1"; [[ "$places" =~ doEnd ]] && endInclude='0'
 			bgawk -i -n '
				BEGIN      {beg=1; mid=0}

				# collect blank lines
				/^[ \t]*$/ {blanks[blanksCount++]=$0}

				# print non-blank lines, conditionally flushing the previous blank lines first
				/[^ \t]/ {
					# the the collected blanks lines should be included, print them
					if ((beg && '"$begInclude"') || (mid && '"$midInclude"'))
						for (i=1; i<=blanksCount; i++) print blanks[i]

					# regardless of whether we printed them, remove them from our buffer
					blanksCount=0

					# always include/print non-blank lines

					print $0
				}

				/[^ \t]/   {beg=0; mid=1}
				END {
					if ('"$endInclude"')
						for (i=1; i<=blanksCount; i++) print blanks[i]
				}
			' "$filename"
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_configNoCommentLines [-w] <filename>
# declare that the file has no comment lines starting with #.
# Params:
#    <filename> : the file to check
# Options:
#    -w : whitespace. also do not include any blank lines
function cr_configNoCommentLines()
{
	case $objectMethod in
		objectVars) echo "filename whiteSpaceFlag" ;;
		construct)
			whiteSpaceFlag=""
			local flag; while getopts  "w" flag; do case $flag in
				w) whiteSpaceFlag="-w" ;;
			esac; done; shift $((OPTIND-1)); unset OPTIND
			filename="$1"
			;;

		check)
			[ ! -f "$filename" ] && return 0

			# add whitespace checking if called for
			local whiteSpaceClause=""; [ "$whiteSpaceFlag" ] && whiteSpaceClause='/^[ \t]*$/ {exit 1}'

			awk '
				/^[ \t]*#/ {exit 1}
				'"$whiteSpaceClause"'
			' "$filename"
			;;

		apply)
			# add whitespace checking if called for
			local whiteSpaceClause=""; [ "$whiteSpaceFlag" ] && whiteSpaceClause='/^[ \t]*$/ {next}'

			bgawk -i -n '
				/^[ \t]*#/ {next}
				'"$whiteSpaceClause"'
				{print $0}
			' "$filename"
			;;

		*) cr_baseClass "$@" ;;
	esac
}
