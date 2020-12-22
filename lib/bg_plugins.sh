#!/bin/bash

import bg_strings.sh  ;$L1;$L2
import bg_awkDataSchema.sh  ;$L1;$L2
import bg_awkDataBuildersAPI.sh  ;$L1;$L2
import bg_awkDataQueries.sh  ;$L1;$L2

# usage: local pluginType pluginID; _pluginsPreamble "$@" && shift; shift; assertNotEmpty pluginType; assertNotEmpty pluginID
# This can be used at the top of plugin method functions that require a specific plugin to operate on (like a this pointer).
# It allows the plugin to be specified one of two ways and will consume either one or two positional params as required.
#    1) <pluginType>::<pluginID> ...    (one position)
#    2) <pluginType> <pluginID>  ...    (two positions)
function _pluginsPreamble()
{
	if [[ "$1" =~ :: ]]; then
		pluginType="${1%%::*}"
		pluginID="${1#*::}"
		return 1
	else
		pluginType="$1"
		pluginID="$2"
		return 0
	fi
}

# usage: plugin_bcPluginKey <cur>
# Perform cmdline completion on a <pluginType>::<pluginID> identifier
function completePluginKey() { plugin_bcPluginKey "$@"; }
function plugin_bcPluginKey()
{
	local cur="$1"
	echo "<pluginID> "
	if [[ ! "$cur" =~ :: ]]; then
		echo "\$(suffix:%3A)"
		local pluginTypes="$(plugins_list --short pluginType)"
		if strSetIsMember "$pluginTypes" "$cur"; then
			echo "${cur}::"
			strSetRemove "$pluginTypes" "${cur}"
		else
			echo "$pluginTypes"
		fi
	else
		local pluginType="${cur%::*}"
		echo "\$(cur:${cur#*::})"
		plugins_list --short "$pluginType"
	fi
}

# usage: plugin_bcPluginAttribute <pluginKey> <cur>
# Perform cmdline completion on an attribute name of a plugin
function completePluginAttribute() { plugin_bcPluginAttribute "$@"; }
function plugin_bcPluginAttribute()
{
	local pluginKey="$1"; shift
	local cur="$1"
	echo "<attributeName> "
	local -A pluingAttribs; plugins_get "$pluginKey" pluingAttribs || { echo "<invalidPluginID>"; return; }
	for i in "${!pluingAttribs[@]}"; do
		[[ ! "$i" =~ ^_ ]] && echo "$i"
	done
}

# usage: plugins_list [-R <retArrayVar>] [<pluginType>]
# list the names of the plugins of the given type that are installed on the host. 
# If <pluginType> is not specified, list all plugins and include their type in the output.
# Params:
#    <pluginType> : only list the names of installed plugins of this type
# Options:
#    -R <retArrayVar>  : an array that receives the results
#    --short           : return just the pluginID for each plugin
#    --full            : return pluginType:pluginID for each plugin
function plugins_list()
{
	local returnVar fullyQualifiedFlag="--full"
	while [[ "$1" =~ ^- ]]; do case $1 in
		--full)      fullyQualifiedFlag="--full" ;;
		--short) fullyQualifiedFlag="" ;;
		-R*) bgOptionGetOpt val: returnVar "$@" && shift ;;
	esac; shift; done
	local pluginType="$1"

	local filterTerm="${pluginType:+pluginType:$pluginType}"

	local _pl_resultsValue=()  pluginType pluginID

bgtrace 1
bgtrace 2
bgtrace 3


	while read -r pluginType pluginID; do
bgtrace 4
		_pl_resultsValue+=("${fullyQualifiedFlag:+$pluginType::}$pluginID")
bgtraceVars _pl_resultsValue
done < <(bgtrace "yoyoy"; awkData_lookup -n me:installedPlugins "pluginType pluginID" $filterTerm)

	if [ "$returnVar" ]; then
		setReturnValue --array "$returnVar" "${_pl_resultsValue[@]}"
	else
		printf "%s\n" "${_pl_resultsValue[@]}"
	fi
}


# usage: plugins_isReadyToUse <pluginType> <pluginID>
# returns 0 (true) or (1) false to indicate if this plugin is installed on this host and loaded.
# The <pluginID> will be loaded if it has not already been loaded as a side effect of this function.
# Note that 'loaded' is an internal term meaning that the we have done the work to locate the plugin
# on the host. 'loaded' may mean that we found that it does not exist and therefore there is no point
# in looking for it again.
# Params:
#    <pluginType> : the type of plugin. Typically its the extension of the plugin file and the plugin file
#          registers attributes with this pluginType when it loads
#    <pluginID> : the name of a particular plugin. When a plugin file loads, it registers its attributes
#          with the key <pluginType>:<pluginID>
# Exit Code:
#    0 : true. the plugin is installed on this host and is now loaded
#    1 : false. the plugin is not available on this host -- probably because its package is not installed.
function plugins_isReadyToUse()
{
	local pluginType="$1"          ; assertNotEmpty pluginType
	local pluginID="$2"            ; assertNotEmpty pluginID

	# this returns quickly if this type has already been loaded or attempted to be loaded
	plugins_load "$pluginType" "$pluginID"

	[ "${_plugins_pluginRegistry[_$pluginType:$pluginID:ReadyToUse]+exits}" ]
}



# usage: plugins_get <pluginType> <pluginID> [<pluginArrayVar>]
# Fill in the associative array named in <pluginArrayVar> with the attributes of this plugin
# The <pluginID> will be loaded if needed
# If <pluginID> does not exist as type <pluginType>, no attributes are added to <pluginArrayVar>
# the return code reflects whether the <pluginID> exists
# Params:
#    <pluginType> : the type of plugin. Typically its the extension of the plugin file and the plugin file
#          registers attributes with this pluginType when it loads
#    <pluginID> : the name of a particular plugin. When a plugin file loads, it registers its attributes
#          with the key <pluginType>:<pluginID>
#    <pluginArrayVar> : the name of an associative array (-A) in the callers scope that will be
#          filled in with the plugin's attributes
# Exit Code:
#    0 : true. the plugin is loaded and its attributes were added to <pluginArrayVar>
#    1 : false. the plugin is not available on this host and no attributes were added to <pluginArrayVar>
function plugins_get()
{
	local pluginType pluginID; _pluginsPreamble "$@" && shift; shift; assertNotEmpty pluginType; assertNotEmpty pluginID
	local pluginArrayVar="${1:-_localArrayVar}"; local -A _localArrayVar

	# this returns quickly if this type has already been loaded
	plugins_load "$pluginType" "$pluginID" || return

	# iterate all the registered keys, filter on ones that begin with <pluginType>:<pluginID>,
	# extract the attribute name name part (<pluginType>:<pluginID>:<attrib>" and put it in the caller's
	# return variable associative array
	local key; for key in "${!_plugins_pluginRegistry[@]}"; do
		if [[ "$key" =~ ^$pluginType:$pluginID: ]]; then
			local attrib="${key#$pluginType:$pluginID:}"
			local attributeArrayElementName="$pluginArrayVar[$attrib]"
			printf -v $attributeArrayElementName "%s" "${_plugins_pluginRegistry[$key]}"
		fi
	done
	[ "$pluginArrayVar" == "_localArrayVar" ] && printfVars plugin:_localArrayVar
	return 0
}

# usage: plugins_getAttribute <pluginType> <pluginID> <attribName> [<attribValueVar>]
# returns one attribute of the specified plugin. The plugin will be loaded if its not already loaded.
# If the plugin does not exist, the "" will be returned as the value and the return code will be 1
# Params:
#    <pluginType> : the type of plugin. Typically its the extension of the plugin file
#                   the plugin file registers attributes with this pluginType when it loads
#    <pluginID>   : the name of a particular plugin. When a plugin file loads, it registers with this name
#    <attribName> : the name of the plugin attribute to be retreived. 
#    <attribValueVar> : the variable name that will receive the attribute's value. default is to write to stdout
# Exit Code:
#     0   : success. the attribute was found and returned
#     1   : failure. this plugin/attribute was not found. The empty string was returned as the value  
# See Also:
#     plugins_get: gets all attributes in one call and returns them in an array
function plugins_getAttribute()
{
	local pluginType pluginID; _pluginsPreamble "$@" && shift; shift; assertNotEmpty pluginType; assertNotEmpty pluginID
	local attribName="$1";  assertNotEmpty attribName
	local valueVar="$2"

	local pluginKey="$pluginType:$pluginID"
	local attribKey="$pluginKey:$attribName"

	[ ! "${_plugins_pluginRegistry+exists}" ] && declare -gA _plugins_pluginRegistry
	[ ! "${_plugins_pluginFile+exists}" ]     && declare -gA _plugins_pluginFile
	[ ! "${_plugins_idByType+exists}" ]       && declare -gA _plugins_idByType

	# if its registered, just return it. negative hits are also registered in case they are checked multiple times
	if [ "${_plugins_pluginRegistry[$attribKey]+exists}" ]; then
		local valueValue="${_plugins_pluginRegistry[$attribKey]}"
		if [ "$valueValue" == "<NEG_HIT>" ]; then
			returnValue "" "$valueVar"
			return 1
		else
			returnValue "$valueValue" "$valueVar"
			return 0
		fi
	fi

	# see if we can load this pluginID. This will load the specific pluginID if it can lookup the library file that contains it
	# in installedPlugins.cache. If not, it will load all installed libraries with the extension .<pluginType> which should discover
	# <pluginID> if it is installed on the system
	plugins_load "$pluginType" "$pluginID"

	# TODO: this is a hack that implements a dependency between creqType and creqConfig. Make a declared dependency mechanism.
	#       loading the creqConfig <pluginType> will create on demand some creqType
	#       TODO: maybe we can implement this dependency correctly by adding a creqType_registerBuiltins_creqConfig() hook that loads creqConfigs in order to register creqType on demand
	#             currently, we can have only one creqType_registerBuiltins callback hook
	[ "$pluginType" == "creqType" ] && 	plugins_load creqConfig

	# check again to see if the its registered now
	# now we have done everything we can to load <pluginID> so this result is final
	if [ "${_plugins_pluginRegistry[$attribKey]+exists}" ]; then
		returnValue "${_plugins_pluginRegistry[$attribKey]}" "$valueVar"
		return 0
	fi

	# either the plugin is not installed on this host or the plugin does not declare this attribute.
	# either way, register and return the negative hit.
	_plugins_pluginRegistry[$attribKey]="<NEG_HIT>"
	returnValue "" "$valueVar"
	return 1
}


# usage: plugins_setAttribute <pluginType> <pluginID> <attribName> <attribValue>
# this sets one mutable attribute persistently on the local host. The plugin will be loaded if its not already loaded.
# Typically mutable attributes are settings that the host sysadmin can change to effect whether the plugin is activated 
# and how its activated. The pluginType declares which attributes are mutable. Attempting to set a non-mutable attribute
# is an error.
# After a group of plugins_setAttribute calls, "plugins_buildCaches <pluginType>" should be called so that the installedPlugins-<pluginType> cache reflects the new values
# Params:
#    <pluginType>  : the type of plugin. Typically its the extension of the plugin file
#                    the plugin file registers attributes with this pluginType when it loads
#    <pluginID>    : the name of a particular plugin. When a plugin file loads, it registers with this name
#    <attribName>  : the name of the plugin attribute to be retrieved. 
#    <attribValue> : the attribute's value being set
# Exit Code:
#     0   : success. the mutable attribute was set persistently
#     1   : failure. this plugin is not available on this host. no changes were made. Maybe the plugin's pacakge is not installed.
#     assertError : if the specified attribute is defined non-mutable in the pluginType, an exception is thrown.
# See Also:
#    plugins_registerAttribute : registerAttribute looks similar to setAttribute but is an internal function  
function plugins_setAttribute()
{
	local pluginType pluginID; _pluginsPreamble "$@" && shift; shift; assertNotEmpty pluginType; assertNotEmpty pluginID
	local attribName="$1";  assertNotEmpty attribName
	local value="$2"

	local pluginKey="$pluginType:$pluginID"
	local attribKey="$pluginKey:$attribName"

	[ ! "${_plugins_pluginRegistry+exists}" ] && declare -gA _plugins_pluginRegistry
	[ ! "${_plugins_pluginFile+exists}" ]     && declare -gA _plugins_pluginFile
	[ ! "${_plugins_idByType+exists}" ]       && declare -gA _plugins_idByType

	plugins_load "$pluginType" "$pluginID" || return

	[ "${_plugins_pluginRegistry[$pluginKey:_mutable:$attribName]+exists}" ] || assertError -v pluginType -v pluginID -v attribName -v value "attempting to set an immutable plugin attribute. See man DeclarePlugin. "

	_plugins_pluginRegistry[$attribKey]="$value"
	domConfigSet "$pluginKey" "$attribName" "$value" #noparse

	# TODO: update the installedPlugins-<pluginType> awkData cache file to reflect this new value. This would remove the requirement that "plugins_buildCaches <pluginType>" be called after a set of plugins_setAttribute calls
}



# usage: plugins_invokeMethod <pluginType> <pluginID> <methodAttribName> <cmdLine ...>
# this invokes the plugin callback method (aka an attribute that contains a command line to be executed)
# Note that the <methodAttribName> attribute can contain any command and can include parameters to that command.
# Any <cmdLine ...> passed to this function will be appended to the command and then invoked.
# Its common for the <methodAttribName> to refer to a bash function defined in the plugin script file. The plugin
# is quaranteed to be loaded so any function defined in the plugin script file will be available to call.
# The <methodAttribName> can also refer to external commands.
# Security:
# This function refuses to invoke a <methodAttribName> if it is mutable because that violates the code/data boundary
# because a domConfig setting could be executed.
# Plugins are scripts and therefore already considered executable code that should be reviewed for security standards
# prior to accptance into a repository. Therefore the code in <methodAttribName> is not different from other code in
# a script.
# Params:
#    <pluginType>  : the type of plugin. Typically its the extension of the plugin file
#                    the plugin file registers attributes with this pluginType when it loads
#    <pluginID>    : the name of a particular plugin. When a plugin file loads, it registers with this name
#    <methodAttribName> : the name of the plugin attribute to interpret as a cmd line to execute.
#    <cmdLine ...> : the remainder of the cmd line will passed to the method. 
# Exit Code:
#    202  : the method was not invoked because the plugin did not provide this method attribute. If --req is specified, this case will assert an error instead of returning 202
#     <n> : any other return code will be the result of the cmd line being executed
function plugins_invokeMethod()
{
	local isRequired
	while [[ "$1" =~ ^- ]]; do case $1 in
		--req) isRequired="requiredFn" ;;
	esac; shift; done
	local pluginType pluginID; _pluginsPreamble "$@" && shift; shift; assertNotEmpty pluginType; assertNotEmpty pluginID
	local methodAttribName="$1"; assertNotEmpty methodAttribName; shift

	local methodCmdline; plugins_getAttribute "$pluginType" "$pluginID" "$methodAttribName" methodCmdline

	if [ ! "$methodCmdline" ]; then
		[ "$isRequired" ] && assertError -v pluginType -v pluginID -v methodAttribName "the plugin author is required to provide this callback method attribute"
		return 202
	fi

	# TODO: consider using runPluginCmd to enorce execution security policy. Counterpoint: these only come from plugns installed as packages
	# SECURITY: dynamic code execution. This code shold be safe because the dynamic code should only come from installed plugins. What about plugins_setAttribute to change the command at runtime? That should also require priviledge.
	${methodCmdline:-${!isRequired}} "$@"
}





# usage: plugins_buildCaches all
# usage: plugins_buildCaches <pluginType1>
# usage: plugins_buildCaches <pluginType> <pluginType>
# This loads the specified pluginTypes via the discovery algorithm and creates cache files for them so that they can be loaded
# more effeciently without doing the discovery algorithm.
# The "all" form also creates some additional cache files that can only be created when it knows that its iterating 
# the complete set of known plugins -- namely the installedPlugins cache and the installedPlugins-tags 
#
# Cache Coherency:
#   "plugins_buildCaches all" should be called after any operation that that might change the set of available plugins on the host
#     * postinst of any package with plugins
#     * postrm  of any package with plugins
#     * bg_debugCntr vinstall
#     * bg_debugCntr vuninstall
#     * after the the selected domData changes (because mutable attributes will change)
#   "plugins_buildCaches <pluginTypes..>" should be called after a mutable attribute of any plugin of that type is changed 
#     * after a group of plugins_setAttribute calls
#
# Virtual Installs:
#    The cache files are built in the me: awkData scope. The me: scope folder respects virtual installed environments.
#    This means that when this function is called in a vinstalled terminal, it will not change the files in the global
#    me: scope folder but instaead it will use a temporary me: scope folder.

# Cache List:
#   me:installedPlugins              : (pluginType,pluginID,srcFile)  : contains each plugin and the srcFile that it can be loaded from 
#   me:installedPlugins-tags         : (tag,pluginType,pluginID)      : relates tags to plugins
#   me:installedPlugins-<pluginType> : (columns list specified by pluginType) : pluginType specific cache -- one line per pluginID
function plugins_buildCaches()
{
	bgtimerStartTrace -T plugins_buildCaches

	# if called with no params, make the default the "all" form
	[ $# -eq 0 ] && set -- "all"

	# Get the local server's name to use as an attribute in the awkObj b/c it might be combined into a global scope
	local server; domWhoami -f -r server; [[ "$server" =~ ^$|^localhost$ ]] && server="$(hostname -s)"

	local pluginType pluginID pluginTypes allFlag

	### process the input list of pluginTypes who's cache we will build and load those types
	while [ $# -gt 0 ]; do case $1 in
		all)
			allFlag="1"
			# load any pluginType plugins so we can discover new types provided by other packages
			plugins_load pluginType

			# now load each of the known pluginTypes
			for pluginType in ${_plugins_idByType[pluginType]}; do
				plugins_load "$pluginType"
			done
			;;
		*) 	plugins_load pluginType "$1"
			plugins_load "$1"
 			;;
	esac; shift; done

	bgtimerLapTrace -T plugins_buildCaches "loaded plugins"

	local awkDataBuildFolder; fsMakeTemp -d awkDataBuildFolder

	### make the installedPlugins.cache (typcical columns: server pluginType pluginID file tags)
	if [ "$allFlag" ]; then
		local awkObjData cacheFile schemaFile; awkData_parseAwkDataID --awkObjDataVar=awkObjData "me:installedPlugins" "" "" "" cacheFile schemaFile
		[ ! -f "$schemaFile" ] && templateExpand "installedPlugins.schema" "$schemaFile"
		domTouch -p "$cacheFile"
		local pluginKey; for pluginKey in "${!_plugins_pluginFile[@]}"; do
			stringSplit -d":" "$pluginKey" pluginType pluginID
			local file="${_plugins_pluginFile[$pluginKey]}"
			local tags="${_plugins_pluginRegistry[$pluginType:$pluginID:tags]}"
			awkDataNormRef tags
			echo "${server:-unknownServer} $pluginType $pluginID $file $tags"
		done > >(
			awkDataRunBuilder \
				-v awkDataID="me:installedPlugins" '
				@include "bg_awkDataBuildersAPI.awk"
				BEGIN {
					if (schemas[awkDataID]["keyCol"] != "server@pluginType@pluginID")
						assert("the builder for the "awkDataID" schema requires that keyCol=server@pluginType@pluginID but it is set to "schemas[awkDataID]["keyCol"])
				}
				{
					# this uses the composite key "server pluginType pluginID"
					schemas[awkDataID]["data"][$1","$2","$3]["server"]=$1
					schemas[awkDataID]["data"][$1","$2","$3]["pluginType"]=$2
					schemas[awkDataID]["data"][$1","$2","$3]["pluginID"]=$3
					schemas[awkDataID]["data"][$1","$2","$3]["file"]=$4
					schemas[awkDataID]["data"][$1","$2","$3]["tags"]=$5
				}
				END {schemas_writeOutput()}
			' -
		) || assertError "here 2"
	fi
	bgtimerLapTrace -T plugins_buildCaches "made installedPlugins awkDataID"


	### iterate each pluginType and make a cache specific to it ($columns)
	# also, in the same loop we can build the tag caches
	if [ "$allFlag" ]; then
		local cacheFileTags; awkData_parseAwkDataID "me:installedPlugins-tags" "" "" "" cacheFileTags
		domTouch -p "$cacheFileTags"
		printf "tag pluginType pluginID\n\n"  > "$cacheFileTags"
	fi

	# TODO: this could probably be made more effecient by making it into one awk script. To do that, bg_awkDataSchema.awk needs to
	#       be enhanced to allow us to specify transient schemas for the installedPlugins-<pluginType> caches because those are not
	#       in the <domeFolder>/schema/ folder. (and proably should not be)
	for pluginType in "${!_plugins_idByType[@]}"; do
		# we can only build the cache for pluginTypes that are fully loaded.
		# The key _$pluginType:Loaded gets set only when the full discovery for that pluginType is ran
		[ ! "${_plugins_pluginRegistry[_$pluginType:Loaded]+exists}" ] && continue

		local cacheFilePlugin
		awkData_parseAwkDataID "me:installedPlugins-$pluginType" "" "" "" cacheFilePlugin
		domTouch -p "$cacheFilePlugin"
		local columnsWithWidths="${_plugins_pluginRegistry[pluginType:$pluginType:columns]}"
		columnsWithWidths="${columnsWithWidths//[(]/:}"
		columnsWithWidths="${columnsWithWidths//[)]}"

		printf "%-13s %-18s %-18s " "server" "pluginType" "pluginID" > "$cacheFilePlugin"
		local colTerm; for colTerm in $columnsWithWidths; do
			local col width; stringSplit -d: "$colTerm" col width
			printf "%*s " "${width:--13}" "$col" >> "$cacheFilePlugin"
		done
		printf "\n\n"  >> "$cacheFilePlugin"

		local pluginID; for pluginID in ${_plugins_idByType[$pluginType]}; do
			printf "%-13s %-18s %-18s " "${server:---}" "$pluginType" "$pluginID" >> "$cacheFilePlugin"
			local colTerm; for colTerm in $columnsWithWidths; do
				local col width; stringSplit -d: "$colTerm" col width
				local value="${_plugins_pluginRegistry[$pluginType:$pluginID:$col]}"
				awkDataNormRef value
				printf "%*s " "${width:--13}" "$value" >> "$cacheFilePlugin"
			done
			printf "\n"  >> "$cacheFilePlugin"

			if [ "$allFlag" ]; then
				local tag; for tag in ${_plugins_pluginRegistry[$pluginType:$pluginID:tags]}; do
					printf "%-25s %-25s %s\n" "$tag" "$pluginType" "$pluginID"  >> "$cacheFileTags"
				done
			fi
		done
	done

	fsMakeTemp --release -d awkDataBuildFolder
	bgtimerLapTrace -T plugins_buildCaches "made other awkDataID"
	bgtimerTrace -T plugins_buildCaches "total"
}



# usage: plugins_load <pluginType> [<pluginID1> [ .. <pluginIDN>]]
# Load the specified <pluginID>s into the in memory registry. If any <pluginID> are specified the me:installedPlugins awkData
# cache table will be consulted to find the associated plugin library script file to source.
# If no <pluginID> are specified, the discovery algorithm will be used to search for and load all plugins of the specified type
# that are installed on the host. Typically, only the plugins_buildCaches function uses that form of this function. 
# If any specified <pluginID> is not found in the cache, the plugin discovery algorithm is invoked to see if the plugin has been
# added to the system since the cache was last made. This behavior may be removed in the future.
# Definition Of "Loaded":
#    This concept of "Loaded" does not imply that the plugin exists. It means that if it exists on the host, its attributes will
#    be in the in-memory registry and its script file will be sourced but if it does not exist, the registry will reflect that
#    that the plugin is not available on the host.
#    The "<pluginType>:<pluginID>:Loaded" means that we have attempted to source and register the plugin regardless of the outcome.
#    The "<pluginType>:<pluginID>:ReadyToUse" means that the plugin was found and is sourced and is ready to use.
# Automatic Discovery of Specific PluginIDs:
#    Note that it would be reasonable to remove the automatic discovery attempt at this time because the me:installedPlugins
#    cache is kept updated sufficiently both is the normal production case of pacakges being installed and in the development
#    case using "bg-debugCntr vinstall". Historically it was needed because we could not rely on the cache coherency and there
#    may still be a few edge cases where its required.
# Plugin Delivery:
#    Plugins are provide in bash script libraries. Typically they are in a library file specific to one plugin or a few related
#    plugins but the <pluginType>_registerBuiltins and <pluginType>_onLoadCallbacks are mechanisms to provide plugins inside
#    general purpose libraries. 
#    Typically these bash libraries that contain plugins are delivered in packages so we can think of plugins as just another
#    asset that can be installed via the distribution package management system.
# Plugin Library Contract:
#    A library script that implements a plugin is responsible for calling DeclarePlugin with the attributes of the plugin it
#    contains to register the plugin and all its attributes in the in-memory plugin registry data structures.
#    It can do that in one of two ways.
#      1) It can call "DeclarePlugin <pluginType> <pluginID> <attributes...>"  at the top level so that its called automatically with 
#         when the library script is sourced into memory.
#      2) It can put the "DeclarePlugin <pluginType> <pluginID> <attributes...>" call in a function that can be called with no
#         parameters and at the top level (that gets executed when its sourced) it can put a line that appends the name of that
#         function to the variable <pluginType>_onLoadCallbacks. 
#    If the plugin is in a file by itself and is only sourced when the plugin is loaded, then the first way is best.
#    If the plugin is defined in a general library file that will be sourced for other purposes, the second way is best so that it
#    does not incur the loading overhead when the plugin is not being used.
#
# Plugin Discovery:
#   On each host, the set of available plugins of a given type is determined by what packages are installed. This function
#   implements a discovery algorithm to determine that set of plugins. 
#   In order for a plugin to be discovered it must be defined in a bash script library file and either...
#      	1) be named with the suffix .<pluginType>
#       2) contain a global assignment statement of the form <pluginType>_onLoadCallbacks+=" <function> "
#
# Plugins AwkData Caches:
#    The set of installed plugins is relatively static on a host.
#    The plugins_buildCaches function is called after package installation/removal. It uses this function to run the discovery
#    algorithm and then writes the results to these awkData cache files. This function uses these cache files to load specific
#    plugins when they are used so that the more expensive discovery does not need to be performed.
#        me:installedPlugins              : (pluginType,pluginID,srcFile, etc...)  : this is used to load plugins directly. 
#        me:installedPlugins-tags         : (tag,pluginType,pluginID)      : relates tags to plugins
#        me:installedPlugins-<pluginType> : (columns list specified by pluginType) : pluginType specific cache -- one line per pluginID
#    A plugin can also have mutable attributes that are set in the domConfig system. Those attributes are also cached. The code
#    that changes those attrubutes should be responsible for calling plugins_buildCaches <pluginType> when its done changing them.
#    Many plugin functions and commands operate on the cache information which is much faster that the discovery method. 
#
# Params:
#    <pluginType>  : The type of the plugin to be loaded. The pluginID is only unique within its pluginType so this is part of the ID
#    <pluginID>    : The plugin to load. if not specified, the Plugin Discovery is invoked which will result in all known plugins
#                    of that type being loaded. More than one <pluginID> can be specified
function plugins_load()
{
	local noDiscoveryFlag server
	while [ $# -gt 0 ]; do case $1 in
		--noDiscovery) noDiscoveryFlag="--noDiscovery" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local pluginType="$1"; shift

	[ ! "${_plugins_pluginRegistry+exists}" ] && declare -gA _plugins_pluginRegistry
	[ ! "${_plugins_pluginFile+exists}" ]     && declare -gA _plugins_pluginFile
	[ ! "${_plugins_idByType+exists}" ]       && declare -gA _plugins_idByType

	local pluginID
	local loadAllFlag; [ $# -eq 0 ] && loadAllFlag="1"

	# load specific plugins if any were specified on the command line
	# if any are not found or "all" is specified, we set the loadAllFlag so that the load all algorithm will be activated below
	# if at any point, we find that we need to do the discovery algorimth (i.e. set loadAllFlag=1) then we do not need to load
	# any more individual plugins.
	for pluginID in "$@"; do
		if [ "$pluginID" == "all" ]; then
			loadAllFlag="1"
			break
		fi
		# if we have already loaded this specific plugin, return without doing any real work
		[ "${_plugins_pluginRegistry[_$pluginType:$pluginID:Loaded]+exists}" ] && continue
		_plugins_pluginRegistry[_$pluginType:$pluginID:Loaded]="true"


		# to load a specific pluginID, it must have been loaded previously by the "all" so that its in the cache
		# we do that in the pkgOnPostInstall and pkgOnPostRemove bg-lib functions that should get called 
		# by every packages install and remove scripts. Also we call it from bg-debugCntr vinstall to handle
		# virtual installs
		local file="$(awkData_getValue me:installedPlugins.file pluginType:$pluginType pluginID:$pluginID)"

		if [[ "$file" =~ :: ]]; then
			local srcFile="${file%%::*}"
			local srcFunction="${file##*::}"
			if ! type -t "$srcFunction" >/dev/null && [ -f "$srcFile" ]; then
				[ "$bgSourceOnlyUnchangable" ] && [ -w "$srcFile" ] && assertError -v productionMode -v srcFile -v pluginLocation:file "In this productionMode, a script can not source a plugin for which the user has write permission over"
				source "$srcFile"
			fi
			$srcFunction
		elif [ -f "$file" ]; then
			[ "$bgSourceOnlyUnchangable" ] && [ -w "$file" ] && assertError -v productionMode -v file "In this productionMode, a script can not source a plugin for which the user has write permission over"
			source "$file"
		elif [ "$file" ]; then
			assertError -v pluginType -v pluginID -v file  "could not load plugin because its file does not exist. try rebuilding the cache with 'bg-plugin -r'"
		elif [ ! "$noDiscoveryFlag" ]; then
			loadAllFlag="1"
		fi
	done


	# this is the discovery algorithm. It searches the system path for files named <something>.<pluginType>
	# it also searches for any installed bash libraries that contain builtin plugin definitions and loads them
	if [ "$loadAllFlag" ]; then
		# if we have already loaded this plugin type, return without doing any real work
		[ "${_plugins_pluginRegistry[_$pluginType:Loaded]+exists}" ] && return
		_plugins_pluginRegistry[_$pluginType:Loaded]="true"

		# even if there turns out not to be any plugins of this type, record that it exists
		# TODO: this should be the gaurd instead of _plugins_pluginRegistry[_$pluginType:Loaded]
		_plugins_idByType[$pluginType]=""

		# Any general library file can declare builtin plugins that are not written in a separate library file
		# This block identifies any that are installed on this host and imports (aka source) them
		# PERFORMANCE: the plugin discovery routine greps all installed libraries. We could do that when a package is built and make the list available at runtime
		# TODO: if this ever becomes a performance issue to grep all the installed libraries, we can do the 
		#       grep when we build packages and create a convention of the package postinst script to update
		#       the list of these files. Actually, if we do that, we might as well detect all the plugins
	  	#       at package build time and have the posinst register its plugins so discovery is never needed.
		#       However, it is nice to be able to simply create a plugin file if needed (without a package)
		#       Also, such a mechanism would have to have a hook in vinstall so that plugins get registered there
		if [ ! "${_plugins_pluginRegistry[_libraries:Loaded]+exists}" ]; then
			_plugins_pluginRegistry[_libraries:Loaded]="true"
			local codeFiles="$(bgListAllInstalledCodeFiles)"
			local libraryFile; while read -r libraryFile; do
				import "$libraryFile" ;$L1;$L2
			done < <(grep -l  "^[[:space:]]*[^#[:space:]].*[^>}]_\(\(onLoadCallbacks\)\|\(registerBuiltins\)\)" $codeFiles)
		fi

		# call _registerBuiltins and onLoadCallbacks hooks.
		# the last block made sure any libraries that contain builtin plugin definitions have been sourced at this point
		# Now invoke the *_registerBuiltins and *_onLoadCallbacks hooks
		# if there is a ${pluginType}_registerBuiltins function, call it
		# if the variable ${pluginType}_onLoadCallbacks contains the names of callback functionscall them
		[ "$(declare -F ${pluginType}_registerBuiltins)" ] && ${pluginType}_registerBuiltins
		local hookFnsVar="${pluginType}_onLoadCallbacks"
		local hookFn; for hookFn in ${!hookFnsVar}; do
			[ "$(declare -F $hookFn)" ] && $hookFn
		done

		# SECURITY: each place that sources a script library needs to enforce that only system paths -- not vinstalled paths are
		# searched in non-develoment mode
		if [ "$bgSourceOnlyUnchangable" ]; then
			local includePaths="$scriptFolder:/usr/lib"
		else
			local includePaths="$scriptFolder:${bgLibPath}:/usr/lib"
		fi

		# now iterate and source all the libraries that have an extension that matches the pluginType
		while IFS="" read -r file; do
			# this is a double check. The real prevention is that bgLibPath is cleared so that file will only be found in in a system path or subfolder of a system path
			[ -w $file ] && [ "$bgSourceOnlyUnchangable" ] && assertError -v file "can not source a file that is writable by the user in production mode"
			source "$file"
		done < <(findInPaths -r "lib:standards:creqs:plugins:${pluginType}${pluginType:+:}"  "*.$pluginType"  "$includePaths")
	fi
}



# usage: DeclarePlugin <pluginType> <pluginID> <debControlFileString> [.. <debControlFileStringN>]
# Creates a new plugin instance. A plugin instance is a wrapper over a script that provides data (attributes) and
# functions (method callbacks). Typically a package will define a PluginType and then other packages can provide
# instances of that PluginType to extend the mechanism provided by the package that introduces the PluginType.
#
# A pluginType is analogous to a Class. A pluginID is analogous to a variable name of an instance of that Class.
# pluginTypes are themselves implemented as plugin instances of pluginType==pluginType. This means that new pluginTypes are
# defined by using "DeclarePlugin pluginType <newPluginTypeName> .."
#
# A pluginID instance is typically defined in a bash library script named with the pluginType as its extension. 
# A plugin script file should call this function in its global scope so that when the script is sourced this function
# registers the plugin. This is part of the contract that makes the plugin discoverable.
#
# Attribute Value Sources:
#    The resulting registered plugin will have attribute values that are derived from several sources.
#        1) pluginType author.     The author of the mechanism that defines the pluginType can set default attribute values that
#           apply to new plugin instances of that type. Just like declaring a Class in an OO language, the pluginType defines what
#           attributes plugins of that type have and optionally their default value and what attributes must be defined by when
#           a new instance is created.
#        2) plugin author.         The author that creates a new plugin instance specifies the values of its attributes. Depending
#           on the type, some attributes are required and some are optional. Additional attributes can be defined.
#        3) sysAdmin,              domDataConfig. Domain wide and host overrides. By default, attributes can not be overridden in
#           the runtime domConfig but when the pluginType declares an attribute as mutable it can be. Also new attributes can be added.
#
# Params:
#   <pluginType> : the type of plug being registered. See the man page for the pluginType to see what attributes the pluginType
#                  and which are optional
#   <pluginID>   : the name of the new plugin. The combination of <pluginType>:<pluginID> name must be unique in the package
#                  repository.
#   <debControlFileString> : This contains the name value pairs that define the plugin formatted to the standard of a debian
#               control file. The control file syntax is expanded slightly to allow indenting. Leading tabs are removed but
#               leading spaces are not. The attributes declared as 'required' in the pluginType must be included. Required
#               attributes are analogous to the parameters in a constructor function. Optional attrubutes can also be include
#               to override the default value provided by the pluginType.
#
# Plugin Type Register Hook:
# The author of a new pluginType mechanism can define a plugin hook function that gets invoked when a plugin of that type
# gets loaded and registers itself. That hook is analogous to a base class constructor defined in the pluginType.
# This hook gets called right after the new pluginID is registered. 
# Name: <pluginType>__onRegisterHook
# The following state is available to the hook function
#    pluginType
#    pluginID
#    pluginKey
#    pluginAttribs[<attribName>]=<attribValue>     # all attributes
#    attribsFromConfig[<attribName>]=<attribValue> # only mutable attributes 
function DeclarePlugin()
{
	local -A defaults 
	local requiredAttribs attribName name value
	local -A mutableAttribs
	local pluginType="$1"; shift; assertNotEmpty pluginType
	local pluginID="$1";   shift; assertNotEmpty pluginID

	# _plugins_pluginRegistry[<pluginType>:<pluginID>:<attributeName>] = <attribValue> 
	# _plugins_pluginFile    [<pluginType>:<pluginID>                ] = <fullPathToSourceFile> 
	# _plugins_idByType      [<pluginType>                           ] = <pluginID1> <pluginID2> ... <pluginIDN>
	[ ! "${_plugins_pluginRegistry+exists}" ] && declare -gA _plugins_pluginRegistry
	[ ! "${_plugins_pluginFile+exists}" ]     && declare -gA _plugins_pluginFile
	[ ! "${_plugins_idByType+exists}" ]       && declare -gA _plugins_idByType

	local -A pluginAttribs=()

	### get the pluginType Metadata if it exists

	# keyCol
	local keyCol; plugins_getAttribute pluginType "$pluginType" keyCol keyCol
	local keyCol="${keyCol:-name}"

	# defaults:
	local metaDefaults; plugins_getAttribute pluginType "$pluginType" defaults metaDefaults
	for attribName in $metaDefaults; do
		stringSplit -d"=" "$attribName" name value
		awkDataDeNormRef value
		defaults[$name]="$value"
	done

	# requiredCols:
	local metaRequired; plugins_getAttribute pluginType "$pluginType" requiredCols metaRequired
	for attribName in $metaRequired; do
		requiredAttribs+=("$attribName")
	done

	# mutableCols:
	local metaMutable; plugins_getAttribute pluginType "$pluginType" mutableCols metaMutable
	for attribName in $metaMutable; do
		mutableAttribs[$attribName]="1"
	done



	### Build the Object


	# set the default values
	for name in "${!defaults[@]}"; do
		pluginAttribs[$name]="${defaults[$name]}"
	done

	# now set the values specified in the input from the plugin Author
	parseDebControlFile pluginAttribs "$@"

	# regardless of what the author provided in the attribute inputs, we have to make sure that these attributes are set
	# the way that the we know
	pluginAttribs[$keyCol]="$pluginID"
	pluginAttribs[pluginID]="$pluginID"
	pluginAttribs[pluginType]="$pluginType"

	# assert that the required attributes where provided. They are required by the plugin author so we check before
	# the additional attributes from the domConfig
	for attribName in "${requiredAttribs[@]}"; do
		[ "${pluginAttribs[$attribName]+exits}" ] || assertError "plugin attribute '$attribName' is required"
	done

	# create the key ( ${pluginAttribs[$keyCol]} will be the value passed in by the plugin author
	local pluginID="${pluginAttribs[$keyCol]}"
	local pluginKey="$pluginType:$pluginID"
	# and record that this specific plugin has been loaded
	_plugins_pluginRegistry[_$pluginType:$pluginID:Loaded]="true"
	# and it actually exits (Loaded may mean that we tried and failed to load it)
	_plugins_pluginRegistry[_$pluginType:$pluginID:ReadyToUse]="true"

	# set the file and Declaration function from the stack. We assume that we can call the function that called
	# us without any parameters. If the function is "source" all we have to do is source that file and it will call us again
	# if we need to register/declare this plugin directly in the future. If its not "source" we assume its a hook onLoad function.
	# If it turns out that there is a reason to nest DeclarePlugin calls deeper, then we can make this smarter be iterating the 
	# stack and looking for the first function with no parameters (or something else) 
	if [[ "${FUNCNAME[1]}" == "source" ]]; then
		# TODO: 2018-11 bobg: noticed a bug in this block but not sure if it still needs to do this so I am not changing it yet.
		#       [1] should probably be [$i] in the loop and maybe in the other lines
		#       but why search for 'source' when this block only happens when [1]=='source'
		local i; for i in "${!FUNCNAME[@]}"; do [ "${FUNCNAME[1]}" == "source" ] && break; done
		pluginAttribs[filePath]="${BASH_SOURCE[1]}"
		pluginAttribs[filename]="${BASH_SOURCE[1]##*/}"
	else
		pluginAttribs[filePath]="${BASH_SOURCE[1]}::${FUNCNAME[1]}"
		pluginAttribs[filename]="${BASH_SOURCE[1]##*/}::${FUNCNAME[1]}"
	fi

	# record the mutable attributes so that setAttribute can easily check to see if an attribute is mutable
	local mutableAttrib; for mutableAttrib in "${!mutableAttribs[@]}"; do
		_plugins_pluginRegistry[$pluginKey:_mutable:$mutableAttrib]="1"
	done

	# normalize tags attribute (if it exists)
	pluginAttribs[tags]="${pluginAttribs[tags]//[,:]/ }"

	# load mutable host values
	# now add the values from the domain and host config. The host config is the most specific domConfig tier so its
	# included in "domConfigGetAll <sectionName>" We use the plugin key as the section name in the config
	local -A attribsFromConfig=()
	domConfigGetAll -A attribsFromConfig "$pluginKey" #noparse
	for attribName in "${!attribsFromConfig[@]}"; do
		# its not an error to try to define an immutable attribute because we don't want the act of adding a domain config
		# variable to have the power to break plugins. So we just ignore them instead
		if [ ! "${pluginAttribs[$attribName]+exists}" ] || [ "${_plugins_pluginRegistry[$pluginKey:_mutable:$attribName]+exists}" ]; then
			pluginAttribs[$attribName]="${attribsFromConfig[$attribName]}"
		fi
	done


	### register the new Plugin Object in our in-memory data structures

	# add the attributes for this pluginKey to the plugin registry
	for attribName in "${!pluginAttribs[@]}"; do
		_plugins_pluginRegistry[$pluginKey:$attribName]="${pluginAttribs[$attribName]}"
	done

	# and register this plugin's filename
	_plugins_pluginFile[$pluginKey]="${pluginAttribs[filePath]}"

	# and index the plugID by type
	[ "$pluginType" ] && _plugins_idByType[$pluginType]+=" $pluginID "

	### 

	local hookFn="${pluginType}_onRegisterHook"
	[ "$(type -t $hookFn)" ] && $hookFn
}

# usage: plugins_registerAttribute [-a] <pluginType> <pluginID> <attribName> <value>
# This is an internal function used by DeclarePlugin. DeclarePlugin is typically what people should use instead of this.
# When a plugin loads, its DeclarePlugin call is made which constructs the the plugin instance by registering its attribute in
# the _plugins_pluginRegistry global associative array. This function can also be used in _onRegisterHook functions which act
# like constructors in OO. Constructors can define new attributes and change the values of existing attributes.
# Params:
#    <pluginType> : the type of plugin. Typically its the extension of the plugin file
#                   the plugin file registers attributes with this pluginType when it loads
#    <pluginID>   : the name of a particular plugin. When a plugin file loads, it registers with this name
#    <attribName> : the plugin's attribute name
#    <value>      : the value of the attribute being set
# Options:
#    -a : append mode. add <value> to the end of the existing value if any, instead of overwritting it.
# See Also:
#    DeclarePlugin  : used to create a new plugin instance and defines its attributes
#    creqConfig_onRegisterHook : example of using this function in a constructor like function.
function plugins_registerAttribute()
{
	local mode="set"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-a) mode="append" ;;
	esac; shift; done

	local pluginType pluginID; _pluginsPreamble "$@" && shift; shift; assertNotEmpty pluginType; assertNotEmpty pluginID
	local attribName="$1";  assertNotEmpty attribName
	local value="$2"

	local pluginKey="$pluginType:$pluginID"
	local attribKey="$pluginKey:$attribName"

	[ ! "${_plugins_pluginRegistry+exists}" ] && declare -gA _plugins_pluginRegistry
	[ ! "${_plugins_pluginFile+exists}" ]     && declare -gA _plugins_pluginFile
	[ ! "${_plugins_idByType+exists}" ]       && declare -gA _plugins_idByType

	case $mode in
		set) _plugins_pluginRegistry[$attribKey]="$value" ;;
		append)
			strSetAdd -d "" -S "_plugins_pluginRegistry[$attribKey]" "$value"
			#[ "$value" ] && _plugins_pluginRegistry[$attribKey]+="${_plugins_pluginRegistry[$attribKey]:+ }$value"
			;;
	esac
}




# usage: pluginType_registerBuiltins
# This particular hook function bootstraps the pluginType pluginType for the base plugin system
# <pluginType>_registerBuiltins are hook functions that can use DeclarePlugin in a library that is not a dedicated plugin
# library. If the library defined DeclarePlugin in the global scope as is typical in a plugin script, those plugins would be
# created every time the library is sourced even though they might not be needed.
# Typically plugins are defined in separate files in the ./plugins folders of a package project, but the mechanism
# that defines a pluginType might want to provide a few common plugins that are always available. 
# See Also:
#    plugins_load : calls <pluginType>_registerBuiltins hooks
#    ${pluginType}_onLoadCallbacks : the string ${pluginType}_onLoadCallbacks is a similar mechanism that is more extensible
function pluginType_registerBuiltins()
{
	# pluginType:pluginType is the mother of all plugins. It is the thing that describes the sctructure of things
	# that describe the structure of a class of plugins. It follows the same structure that it describes.

	# bootstrap. we have to tell it that pluginType:pluginType is already loaded and pre register some of the attributes so that it
	# won't try loading it as a part of loading itself in order to check to see if it is complaint with itself.
	_plugins_pluginRegistry[_pluginType:pluginType:Loaded]="true"
	plugins_registerAttribute pluginType pluginType keyCol "name"
	plugins_registerAttribute pluginType pluginType defaults ""
	plugins_registerAttribute pluginType pluginType requiredCols "name projectName keyCol columns"
	plugins_registerAttribute pluginType pluginType mutableCols ""


	# the plugins_load function calls pluginType_registerBuiltins() (this function) before it calls any onLoad hook
	# functions in the pluginType_onLoadCallbacks global string variable. Other pluginTypes (creqType, standard, etc..)
	# provided in bg-lib, will append their onLoad function to the pluginType_onLoadCallbacks. By putting pluginType:pluginType
	# here in pluginType_registerBuiltins, we ensure that it gets loaded first

	DeclarePlugin pluginType pluginType "
		projectName: bg-lib
		columns: name(-18) projectName(-18) keyCol(-13) columns defaults requiredCols mutableCols defDisplayCols tags filename filePath description
		keyCol: name
		requiredCols: name projectName keyCol columns 
		optionalCols: defaults requiredCols mutableCols
		defDisplayCols: name keyCol projectName columns
		description: Plugin record that represents a type of plugin. Its a meta thing -- the Class for Class
	"
}
