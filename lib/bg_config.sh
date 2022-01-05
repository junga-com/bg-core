
import bg_ini.sh  ;$L1;$L2

# Library
# Provides a scoped, system wide configuration system.
# A scoped configuration consists of an ordered list of overlaid layers (aka scopes). The effective value for any particular
# setting is the value present in the scope closest to the top. Values in scopes closer to the top hide (aka override) any values
# for the same setting in scopes lower down. The sectionName plus the settingName forms the unique key that determines if a setting
# is the same logical setting. Settings that appear first, before any section heading have a canonical section name of '.', but the
# empty string also refers to that top section.
#
# The order of the scopes is from the most specific closest to the front to the most general furthest to the back. The local
# configuration associated with a particular user on the current host is typically most specific scope. The scope for an entire
# domain is typically the most general scope.
#
# Scopes:
#     user     : "/home/$USER/.config/bg-core/bgsys.conf" : changes made to this scope are only seen by this $USER when running
#                commands on this host.
#     host     : "/etc/bgsys.conf" : host specific configuration. changes made to this scope only affect this host.
#     location : "/etc/bgsys.location.conf" : each host can belong to a location who's config file is shared and synchronized
#                between all host in that location. changes made to this scope will affect all hosts in that same location
#     global   : "/etc/bgsys.global.conf" : the global scope config file is synchronized and shared between all hosts in the domain.
#                changes made to this scope potentially affects all hosts in the domain.
#
#


# this data structure defines which scopes are avaiable, their order, and where the local location of each scope's config file.
# The files for the location and global scope are replicated between other hosts.
declare -gA configScopes=(
	[0]="user host location global"
	[user]="/home/$USER/.config/bg-core/bgsys.conf"
	[host]="/etc/bgsys.conf"
	[location]="/etc/bgsys.location.conf"
	[global]="/etc/bgsys.global.conf"
)

# internal helper function to get the comma separated list of config files from configScopes, in order, with caching.
# the expression "${configScopes[orderedFileList]:-$(_configGetScopedFilesList)}" will efficiently resolve to the ordered, comma
# separated list of scope files, suitable to pass to ini* family of functions.
function _configGetScopedFilesList()
{
	local list="${configScopes[orderedFileList]}"
	if [ ! "$list" ]; then
		local _cgScope
		for _cgScope in $configScopes; do
			list+="${configScopes[$_cgScope]},"
		done
		list="${list%,}"
		configScopes[orderedFileList]="$list"
	fi
	echo "$list"
}


# usage configScopeList
# returns a space separated ordered list of scopes in the system wide config system. The most specific scope is first.
function configScopeList()
{
	echo "${!configScopes[0]}"
}


# usage: configGet [-R|--retVar=<retVar>] [-t|--expandAsTemplate] <sectionName> <settingName> [<defaultValue>]
# retrieve the value of a setting from the system wide config.
# Options:
#    -R|--retVar=<retVar> : return the value into the variable name <retVar> instead of writing it to stdout
#    -t|--expandAsTemplate : treat the value as a template string and expand %<varRef>% expressions to the value of the environment
#                            variable named <varRef>
# Params:
#    <sectionName>   : the name of the ini style section (e.g. [ <sectionName> ]) that the setting is in. An empty value or '.'
#                      indicates that the setting is in the top section of the file before any [ <section> ] line is encountered.
#    <settingName>   : the name of the ini style setting to retrieve (e.g. <settingName>=<value>)
#    <defaultValue>  : if the setting is not present in the config, the the <defaultValue> will be returned as the value. If the
#                      setting exists the value from the config will be used even if it is set to the empty string.
# See Also:
#     man(7) bg_config.sh
#     man(1) bg-core-config
function configGet()
{
	local passThruOpts _cgTemplateFlag retVar _cgValue
	while [ $# -gt 0 ]; do case $1 in
		-R*|--retVar*) bgOptionGetOpt val: retVar       "$@" && shift ;;
		-t|--expandAsTemplate)  _cgTemplateFlag="-t" ;;
		# TODO: it seems that -d and -x should not be supportted b/c the format of the system wide config is set
		# -d*|--delim*) bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
		# -x|--noSectionPad)  bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local ipg_sectionName="$1"
	local ipg_paramName="$2";  assertNotEmpty ipg_paramName
	local ipg_defaultValue="$3"

	iniParamGet "${passThruOpts[@]}" -R _cgValue  "${configScopes[orderedFileList]:-$(_configGetScopedFilesList)}"  "$ipg_sectionName" "$ipg_paramName" "$ipg_defaultValue"
	local result=$?

	[ "$_cgTemplateFlag" ] && templateExpandStr -R _cgValue "$_cgValue"

	returnValue "$_cgValue" "$retVar"
	return ${result:-0}
}

# usage: configGetAll [-t|--expandValue] [-A <retArrayName>] [-d|--scopeDelim=<delim>] [-f|--fullyQualyfied] [<sectionName>]
# retrieves a set of the ini style settings from the system side config system. If <sectionName> is specified, it returns only
# settings from that section and the setting names will not, by default, be fully qualified with the section name.
# The -f|--fullyQualyfied option forces it to fully qualify the names when a <sectionName> is specified. If the <sectionName> is
# not specified, it returns all settings in the configuration using fully qualified setting names.
#
# The default is to print the output to stdout as lines like "<name>=<value" but the -A option will cause it to return the results
# in the specified associative array variable where <value> is the value of the key <name>. <name> may or may not be fully qualified
# as described above.
#
# Qualifying Names:
# When a fully qualified name is returned, it consists of a <sectionName> and <settingName>. By default, a '.' is used to
# separate the two part like "<sectionName>.<settingName>". Since its possible for either or both of the <sectionName> and <settingName>
# to contain '.', it might be desirable to use a different delimiter which can be specified with the -d|--scopeDelim=<delim> option.
# If <delim> is '[' or ']', the format will be [<sectionName>]<settingName>, otherwise it will be <sectionName><delim><settingName>
#
# Since the <sectionName> of the top section in an ini style config is the empty string, the plain setting name of settings in the
# top section is the fully qualified name. The delimiter in this case will not be present in the fully qualified name.
#
# Params:
#    <sectionName> : If specified, only params in that section will be returned and names will NOT, by default, be fully qualified.
#                    Use '.' to specify the top section before any section header. Use -f to make the returned setting names fully
#                    qualified.
# Options:
#    -f|--fullyQualified : forces the determines if the names returned include the <sectionName>.
#           By default, if <sectionName> is used to specify a single section, the returned names will not be fully qualified
#           This option makes the returned names be fully qualified regardless of whether <sectionName> is specified.
#    -d|--scopeDelim : default is '.'. determines how the <sectionName> and <paramName> are combined to form a fully qualified name
#           '[' or ']'  : use the format [<sectionName>]<paramName>
#           '.'         : (default) use the format <sectionName>.<paramName>
#           ':'         : use the format <sectionName>:<paramName>
#           '<delim>'   : use the format <sectionName><delim><paramName>
#    -t|--expandValue   : expand each value as a template string before returning it
#    -A|--array <retArrayName> : <retArrayName> is the name of an associative array (local -A <retArrayName>)
#          that will be filled in with the settings like <retArrayName>[[sect.]name]=value
# See Also:
#     man(7) bg_config.sh
#     man(1) bg-core-config
function configGetAll()
{
	local passThruOpts
	while [ $# -gt 0 ]; do case $1 in
		-f|--fullyQualified) bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
		-d*|--scopeDelim*)   bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
		-t|--expandValue)    bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
		-A*|--array*)        bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local sectionName="$1"

	iniParamGetAll "${passThruOpts[@]}" "${configScopes[orderedFileList]:-$(_configGetScopedFilesList)}" "$@"
}

# usage: configGet [-R|--retVar=<retVar>] [-t|--expandAsTemplate] <sectionName> <settingName> <value>
# retrieve the value of a setting from the system wide config.
# Options:
#    -s|--scope=<scope>)  : write the <value> at <scope> level in the config system. Writing the value at a specific scope makes
#         it the value for all machines in that scope that do not have the same [<sectionName>]<settingName> set an a more specific
#         scope. You can think of it as the default value at that scrope which may be overriden by a value set in a more specific
#         scope. The default <scope> is 'user' which only affects the configuration of the user on the host that the command is ran on.
#   -R|--resultsVar=<var> : a variable name to receive the result of the operation. It will be one of these words.
#         * nochange : this parameter was already set to the specified value
#         * changedExistingSetting : the value of an existing setting was changed
#         * addedToExistingSection : a new setting/parameter line was added to an existing section
#         * addedSectionAndSetting : a new section containing this setting/parameter line was added
#   -S|--statusVar=<var> : a variable name that will be set to "changed" if the <iniFile> was changed as a result of this command.
#         This is a "one shot" status meaning that this function call may set it to 'changed' but it will not clear it if the file
#         was not changed. This facilitates passing the status variable to multiple function calls and in the end, if any
#         changed the file, this status variable will be set to "changed". Use -R <var> if you want to know the outcome of just this
#         call.
#   -c <comment> : add this comment associated with the setting.
# Params:
#    <sectionName>   : the name of the ini style section (e.g. [ <sectionName> ]) that the setting is in. An empty value or '.'
#                      indicates that the setting is in the top section of the file before any [ <section> ] line is encountered.
#    <settingName>   : the name of the ini style setting to retrieve (e.g. <settingName>=<value>)
#    <value>         : the value to set in this [<sectionName>]<settingName> in the config system
# See Also:
#     man(7) bg_config.sh
#     man(1) bg-core-config
function configSet()
{
	local passThruOpts verbosity="$verbosity" _csScope="user"
	while [ $# -gt 0 ]; do case $1 in
		-s*|--scope*)       bgOptionGetOpt val: _csScope "$@" && shift ;;

		-S*|--statusVar*)   bgOptionGetOpt opt: passThruOpts  "$@" && shift ;;
		-R*|--resultsVar*)  bgOptionGetOpt opt: passThruOpts  "$@" && shift ;;
		-c*|--comment*)     bgOptionGetOpt opt: passThruOpts   "$@" && shift ;;
		# TODO: it seems that the follow options  should not be supportted b/c the format of the system wide config is set
		# -qN|--noQuote)      bgOptionGetOpt opt passThruOpts   "$@" && shift ;;
		# -q1|--singleQuote)  bgOptionGetOpt opt passThruOpts   "$@" && shift ;;
		# -q2|--doubleQuote)  bgOptionGetOpt opt passThruOpts   "$@" && shift ;;
		# -d*|--delim*)       bgOptionGetOpt opt: passThruOpts    "$@" && shift ;;
		# --commentsStyle*)   bgOptionGetOpt opt: passThruOpts    "$@" && shift ;;
		# --paramPad*)        bgOptionGetOpt opt: passThruOpts    "$@" && shift ;;
		# --sectPad*)         bgOptionGetOpt opt: passThruOpts    "$@" && shift ;;
		# -x|--noSectionPad)  bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local sectionName="$1"
	local paramName="$2";   assertNotEmpty paramName
	local paramValue="$3"

	local _csFile="${configScopes[$_csScope]}";  assertNotEmpty _csFile -v scope:_csScope -v configScopes "No configuration file is associated with the specified scope"

	iniParamSet -p "${passThruOpts[@]}"  "$_csFile"  "$sectionName" "$paramName" "$paramValue"
	local result=$?
	return ${result:-0}
}

# usage: configRemove <sectionName> <settingName>
# removes this setting from the system wide configuration. By default, it will remove it only from the most specific scope that the
# setting exists in. This means that after calling this function, the setting may still exist because it revealed the setting at
# a more general scope. To remove it completely from all the scopes that the host belongs to, use the -sALL option.
# Options:
#   -s|--scope=<scope>)  : remove the <value> from <scope> level in the config system. If <scope> is specified as "ALL", it will be
#         removed from all scopes
#   -R|--resultsVar=<var> : a variable name to receive the result of the operation. It will be one of these words.
#         * nochange : this parameter was not present in the file so there was nothing to remove.
#         * changed  : the parameter was found and removed from the file.
#   -S|--statusVar=<var> : a variable name that will be set to "changed" if the <iniFile> was changed as a result of this command.
#         This is a "one shot" status meaning that this function call may set it to 'changed' but it will not clear it if the file
#         was not changed. This facilitates passing the status variable to multiple function calls and in the end, if any
#         changed the file, this status variable will be set to "changed". Use -R <var> if you want to know the actual result.
# Params:
#    <sectionName>   : the name of the ini style section (e.g. [ <sectionName> ]) that the setting is in. An empty value or '.'
#                      indicates that the setting is in the top section of the file before any [ <section> ] line is encountered.
#    <settingName>   : the name of the ini style setting to remove
function configRemove()
{
	local passThruOpts statusVarName resultsVarName _crResults _crScope
	local verbosity="$verbosity"
	while [ $# -gt 0 ]; do case $1 in
		-s*|--scope*)       bgOptionGetOpt val: _crScope "$@" && shift ;;

		-S*|--statusVar*)   bgOptionGetOpt val: statusVarName  "$@" && shift ;;
		-R*|--resultsVar*)  bgOptionGetOpt val: resultsVarName "$@" && shift ;;
		# -d*|--delim*)       bgOptionGetOpt opt: passThruOpts   "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local sectionName="$1"
	local paramName="$2";   assertNotEmpty paramName

	case ${_crScope:-default} in
		default)
			local _crScope; for _crScope in ${configScopes[0]}; do
				if iniParamRemove -R _crResults "${passThruOpts[@]}"  "${configScopes[$_crScope]}"  "$sectionName"  "$paramName"; then
					setReturnValue "$resultsVarName" "$_crResults:$_crScope"
					setReturnValue "statusVarName" "changed"
					return 0
				fi
			done
			setReturnValue "$resultsVarName" "nochange"
			return 1
			;;
		ALL) iniParamRemove -R _crResults "${passThruOpts[@]}"  "${configScopes[orderedFileList]:-$(_configGetScopedFilesList)}"  "$sectionName"  "$paramName"; return ;;
		*)   iniParamRemove -R _crResults "${passThruOpts[@]}"  "${configScopes[$_crScope]}"                                      "$sectionName"  "$paramName"; return ;;
	esac
	assertLogicError
}

# usage: configView
# display the contents of the system wide config system.
function configView()
{
	local _cgFiles="${configScopes[orderedFileList]:-$(_configGetScopedFilesList)}"
	local -a ipg_iniFiles; fsExpandFiles -f -A ipg_iniFiles ${_cgFiles//,/ }

	# we pipe the fileMap data to the awk script on stdin. the rest of the awk script operates on the files passes on the cmdline
	{
		for _cgScope in $configScopes; do
			printf "%s %s\n" "$_cgScope" "${configScopes[$_cgScope]}"
		done
	} |	bgawk -n \
		--include="bg_ini.awk" \
		--include="bg_cui.awk" '

		BEGIN {
			while ((getline<"/dev/stdin")>0)
				fileMap[$2]=$1

			cuiRealizeFmtToTerm("on")
			arrayCreate(data)
			arrayCreate(orderedNames)
		}

		# collect the data on each settings line we encounter. the first time we encounter a iniParamFullName its the effective value
		# The susequent times we encounter a iniParamFullName are hidden values that would not be visible because they are hidden by the first.
		iniLineType=="setting" {
			scope=fileMap[iniFile]; if (!scope) scope=iniFile
			if (! (iniParamFullName in data)) {
				arrayPush(orderedNames, iniParamFullName)
				arrayCreate2(data,iniParamFullName)
				arrayCreate2(data[iniParamFullName],"scopes")
			}
			arrayPush(data[iniParamFullName]["scopes"], scope)
			data[iniParamFullName"-"scope]=iniValue
		}

		END {
			# iterate the iniParamFullNames in the order we encountered them
			for (i in orderedNames) {
				name=orderedNames[i]
				# now iterate the scopes that this iniParamFullName was found in the order that they were encountered
				for (j in data[name]["scopes"]) {
					scope=data[name]["scopes"][j]
					# The first was is the effective value
					if (j==1)
						printf("%-10s %-40s %s\n", scope, name, data[name"-"scope])
					# the subsequent ones are hidden by the first
					else
						printf(csiFaint"%-10s %-40s %s\n"csiNorm, "", "+hidden:"scope, data[name"-"scope])
				}
			}
		}
	' "${ipg_iniFiles[@]}"
}

# usage: configSectionList [<sectionRegEx>]
# returns the list of section names present in any scope of the system wide config system.
# Params:
#     <sectionRegEx> : limit the output to section names that match this regex
function configSectionList()
{
	local scope
	while [ $# -gt 0 ]; do case $1 in
		-s*|--scope*)       bgOptionGetOpt val: scope "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local files;
	if [ "$scope" ]; then
		iniSectionList "${configScopes[$scope]}" "$@"
	else
		iniSectionList "${configScopes[orderedFileList]:-$(_configGetScopedFilesList)}" "$@"
	fi
}

# usage: configSettingList <sectionName> [<settingsRegEx>]
# returns the list of settings in the specified section of the system wide config system.
# Params:
#     <sectionName>   : The section for which settings will be returned
#     <settingsRegEx> : limit the output to setting names that match this regex
function configSettingList()
{
	local scope
	while [ $# -gt 0 ]; do case $1 in
		-s*|--scope*)       bgOptionGetOpt val: scope "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local files;
	if [ "$scope" ]; then
		iniParamList "${configScopes[$scope]}" "$@"
	else
		iniParamList   "${configScopes[orderedFileList]:-$(_configGetScopedFilesList)}" "$@"
	fi
}
