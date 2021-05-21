#!/bin/bash

# Library
# Bash script plugins provide a mechanism for multiple packages to collaborate to achieve features.
#
# This library provides a mechanism for 1) defining a PluginType used to implement some feature and 2) define Plugins of that type
# to extend the feature concerned by the PluginType.
#
# Structure:
# PluginTypes and Plugins are both implemented as files that follow a naming convention that identifies them as such. Typically
# the file is part of a package for distributing to target hosts. The file can be implemented in any language as long as it complies
# with the standard defined (TODO: where?). Those that are written in bash are bash script library files that contain a call to
# either DeclarePluginType or DeclarePlugin which defines its attributes.
#
# DeclarePluginType declares a new Class in the bg_objects.sh system that extends the class Plugin. Static and non-static methods
# can be added to the new Class. The PluginType author can define the class so that there are required attributes and methods of
# Plugins defined of that PluginType.
#
# DeclarePlugin creates a new logical instance of the Class that corresponds to the PluginType. The author must define the required
# attributes and methods defined by the PluginType author.
#
# In the bg_objects.sh mechanism, Classes are object instances of class `Class` so in both the case of Plugins and PluginTypes, we
# are dealing with instances of objects. Also, object instances can be extended on the fly without creating a new Class so in both
# cases, the author can define new attributes and methods. The author of the Plugin or PluginType defines the values of attributes
# in the file/library that implements it and in that way, the file is a data source from which the instance can be restored, similar
# to restoring an object instance from attribute values stored in a database or other data source. However, sometimes the values of
# some attributes need to be set and changed to reflect the plugins current state in the context of the host where its installed.
# For example, its common for PluginTypes provided by bg-core to support a notion of being activated or not on the host. The
# PluginType author can declare that some attributes are 'mutable' which means that their value can change on the host and is not
# confined to having the initial value set by the Plugin author.
#
# The values of mutable attributes are stored in the system-wide configurtaion system provided by bg_config.sh. The fully qualified
# Plugin or PluginType name is used as the ini style section name in the config system and each ini style parameter in that section
# defines the current dynamic value of a mutable attribute of that type. Parameter names that do not corespond to a mutable attribute
# name are ignored so that the PluginType author can depend on some values coming from the original Plugin author.
#
# Fully Qualified and Relative Names:
# The names of plugins are heriarchical using the colon (:) as the delimiter. The fully qualified name is often refered to as the
# pluginKey and has the form...
#    <PluginType>:<pluginID>
# The <pluginID> can also be hirarchical. See the Config pluginType for an example of that.
#
# The fully qualified name of a PluginType is `PluginType:<PluginType>` where the left side of the : is the literal string
# "PluginType". Some PluginTypes provided by bg-core are PluginType:Collect, PluginType:Standards, and PluginType:Config.
# PluginTypes are not exactly Plugins, themselves, but that are very close to being Plugins whose PluginType is PluginType.
#
# When <PluginType> is known, for example in the code that implements the PluginType or when using a PluginType in most places,
# the first part of the fully qualified name can be dropped and the second part is sufficient to uniquely identify the particular
# plugin. Outside the context of the plugin system, the fully qualified name must be used if it is expected to stand alone and be
# unique on the host. That is why, for example, the section names in the system configuration use the fully qualified names.
#
# Filenames:
# The Command or library file that contains a Plugin or PluginType is named with the same components as the fully qualified name but
# they are formatted differently in order to comply with long standing conventions for filenames.
#    <pluginID>.<PluginType> or <pluginID>.PluginType
#
# The extension of the filename is the <PluginType> or "PluginType" to indicate the type of thing that the file contains.
#
#

import bg_objects.sh  ;$L1;$L2
import bg_ini.sh  ;$L1;$L2


# usage: DeclarePlugin <pluginType> <pluginID> [<attributes>]
# plugin scripts use this to declare the plugin they provide. Typically the only global scope code in a plugin script is a call to
# this function. The script will typically also contain functions that the plugin attributes refer to.
function DeclarePlugin()
{
	local pluginType="$1"; shift
	local pluginID="$1"; shift
	local pluginInst
	ConstructObject "$pluginType" pluginInst "$pluginType" "$pluginID" "$@"
	$Plugin::register "$pluginType:$pluginID" "$pluginInst"
}

# usage: DeclarePluginType <pluginType> <attributes>
function DeclarePluginType()
{
	local pluginType="$1"; shift
	DeclareClass -f "$pluginType" extends Plugin "$@"

	local -n static="$pluginType"

	static[pluginType]="PluginType"
	static[pluginID]="$pluginType"

	# make a mutableCols Map member var so that setAttribute can easily check
	local mutableColsString="${static[mutableCols]}"
	$static[mutableCols]=new Map
	local -n mutableCols="$(GetOID "${static[mutableCols]}")"
	for attribName in $mutableColsString; do
		mutableCols[$attribName]="1"
	done

	$Plugin::register "PluginType:$pluginType" "$static"
	true
}


DeclareClass Plugin

function static::Plugin::__construct()
{
	# create a Map member var to keep track of loaded pllugins
	$static[loadedPlugins]=new Map
}

function static::Plugin::register()
{
	loadedPlugins[$1]="$2"
}

# usage: $Plugin::list [<outputOptions>] [--short] [<pluginNameSpec>]
# list the names of the plugins installed on the host. This queryies the host manifest file and "bg-awkData manifest assetType:plugin"
# can be used to access similar data.
#
# If <pluginNameSpec> is specified, it filters the results to those that match it, otherwise all installed plugins will be included
# in the output.
#
# Params:
#    <pluginNameSpec> : only list the names of installed plugins whose <pluginID> matches this expression.
#         If <pluginNameSpec> is a regEx that is applied to the pluginID (aka assetName) which is in the form <pluginType>:<pluginName>.
#         The regEx must not contain the ^ or $ anchors because they are added automatically so that the regEx will match the full
#         <pluginID> by default. However, if <pluginNameSpec> does not contain any regEx characters ('*','[',']'.'?'), '.*' will
#         be appended so that it will match the leading prefix of the <pluginID>.
#         Example. "collect:" will match all plugins of type "collect"
#
# Options:
#    <outputOptions>   : See man outputValue for supported options which control how the output is returned.
#    --short           : return just the pluginID for each plugin
#    --full            : (default) return pluginType:pluginID for each plugin
#
# See Also:
#   "bg-awkData manifest assetType:plugin" # assetName is of the form <pluginType>:<pluginName>
function static::Plugin::list()
{
	local retOpts shortFlag manifestOpt
	while [ $# -gt 0 ]; do case $1 in
		--short) shortFlag="--short" ;;
		--full)  shortFlag="" ;;
		--manifest*)  bgOptionGetOpt opt: manifestOpt "$@" && shift ;;
		*) bgOptions_DoOutputVarOpts retOpts "$@" && shift ;;&
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local pluginNameSpec="${1}"
	[[ ! "$pluginNameSpec" =~ []*?[] ]] && pluginNameSpec="$pluginNameSpec.*"

	local -a plugins=()
	local pkg scrap pluginID pluginPath
	while read -r pkg scrap pluginID pluginPath; do
		[ "$shortFlag" ] && pluginID="${pluginID#*:}"
		plugins+=($pluginID)
	done < <(manifestGet $manifestOpt --pkg="${packageOverride:-.*}" "plugin" "$pluginNameSpec")

	outputValue -1 "${retOpts[@]}" "${plugins[@]}"
}


# usage:$Plugin::types [<outputOptions>] [<pluginTypeSpec>]
# List the plugin types present on this host.
# Params:
#    <pluginTypeSpec> : only list the names plugin types that match this spec
# Options:
#    <outputOptions>   : See man outputValue for supported options which control how the output is returned.
# See Also:
#   "bg-awkData manifest assetType:plugin" # assetName is of the form <pluginType>:<pluginName>
function static::Plugin::types()
{
	local retOpts
	while [ $# -gt 0 ]; do case $1 in
		*) bgOptions_DoOutputVarOpts retOpts "$@" && shift ;;&
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local pluginTypeSpec="${1}"
	[[ ! "$pluginTypeSpec" =~ []*?[] ]] && pluginTypeSpec="$pluginTypeSpec.*"
	pluginTypeSpec="$pluginTypeSpec:.*"

	local -A types=()
	local pkg scrap pluginID pluginPath
	while read -r pkg scrap pluginID pluginPath; do
		types["${pluginID%%:*}"]="1"
	done < <(manifestGet --pkg="${packageOverride:-.*}" "plugin" "$pluginTypeSpec")

	outputValue -1 "${retOpts[@]}" "${!types[@]}"
}


# usage: $Plugin::get [-R <retVar>] <pluginType> <pluginID>
#        $Plugin::get [-R <retVar>] <pluginType>:<pluginID>
# static Plugin method to get a plugin given its type and name (which is its unique key)
# This returns quickly without doing anything if the plugin is already loaded.
# This function assumes that the plugin is implemented in a library with the assetType:plugin and assetName <pluginType>.>pluginName>
# in the host manifest. If that is not the case, you can source the library that implements it another way and this function wont
# do anything if called because it will already be loaded.
# There is a static member variable of type Map in the Plugin class called loadedPlugins where plugins (and pluginTypes) are registered
# when they are loaded. Code should use the DeclarePlugin and DeclarePluginType functions to create and register plugins or PluginTypes.
function static::Plugin::get()
{
	local retVar quietFlag
	while [ $# -gt 0 ]; do case $1 in
		-q|--quiet) quietFlag="-q" ;;
		-R*) bgOptionGetOpt val: retVar "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	if [[ "$1" =~ : ]]; then
		local pluginType="${1%%:*}"
		local pluginID="${1#*:}"; shift
	else
		local pluginType="$1"; shift
		local pluginID="$1"; shift
		assertNotEmpty pluginID "invalid parameters. should be either '<pluginType>:<pluginID>' '<pluginType> <pluginID>'"
	fi
	local pluginKey="$pluginType:$pluginID"

	# <retVar> can be passed in the -R option or as the last parameter
	[ ! "$retVar" ] && retVar="$1"

	if [ ! "${loadedPlugins[$pluginKey]+exists}" ]; then
		# ensure that this plugin's pluginType is loaded first
		[ "$pluginType" != "PluginType" ] && static::Plugin::get -q "PluginType:$pluginType"

		# get the filename that implements this plugin from the manifest
		local _pg_pkg _pg_scrap _pg_filename
		read -r _pg_pkg _pg_scrap _pg_scrap _pg_filename < <(manifestGet  plugin "$pluginType:$pluginID")
		assertNotEmpty _pg_filename "could not find assetType:plugin assetName:'$pluginType:$pluginID' in host manifest"

		local _pg_fileTypeInfo="$(file "$_pg_filename")"
		if [[ "$_pg_fileTypeInfo" =~ Bourne-Again ]]; then
			# this is the initially typical case where the plugin is implemented as a bash script
			import "$_pg_filename" ;$L1;$L2

		elif [ -x "$_pg_filename" ]; then
			# this is the case where the plugin is implemented in a different language. It could be a php or python script or a binary
			# The executable should respond to the 'getAttributes' command by returning its attributes in the deb control file syntax
			DeclarePlugin "$pluginType" "$pluginID" "$($_pg_filename getAttributes)"
		else
			assertError "could not load plugin file '$_pg_filename' because it is not a bash script and not an executable"
		fi

		[ "${loadedPlugins[$pluginKey]+exists}" ] || assertError "failed to load plugin '$pluginKey'"

		local -n _pg_plugin; GetOID "${loadedPlugins[$pluginKey]}" _pg_plugin
		_pg_plugin[package]="$_pg_pkg"
	fi

	if [ "$quietFlag" ]; then
		return 0
	else
		returnObject "${loadedPlugins[$pluginKey]}" "$retVar"
	fi
}

# usage: $Plugin::buildAwkDataTable
# This builds an awkData style table of all installed plugins and the union of attribute names that they contain as columns
# Mutable attributes (aka columns) and attributes that start with '_' are not included.
# The output is sent to stdout.
function static::Plugin::buildAwkDataTable()
{
	local manifestOpt
	while [ $# -gt 0 ]; do case $1 in
		--manifest*)  bgOptionGetOpt opt: manifestOpt "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local allPlugins; $Plugin::list -A allPlugins $manifestOpt --full '.*'

	local pluginKey
	local -n plugin
	for pluginKey in "${allPlugins[@]}"; do
		Try:
			unset -n plugin; local -n plugin; $Plugin::get -R plugin "$pluginKey"
			echo "$pluginKey" "pluginKey" "$pluginKey"
			local attribNames=(); $plugin.getAttributes -A attribNames
			local -n mutableCols; $plugin.static.mutableCols.getOID mutableCols
			local attrib; for attrib in "${attribNames[@]}"; do
				if [ ! "${mutableCols[$attrib]+exists}" ]; then
					local value="${plugin[$attrib]}"
					varEscapeContents attrib value
					echo "$pluginKey" "$attrib" "$value"
				fi
			done
			echo  "$pluginKey" "loadable" "loadSuccess"
		Catch: && {
			echo  "$pluginKey" "loadable" "loadFail"
			echo "the plugin '$pluginKey' failed to load '$catch_errorDescription'" >&2
			assertError "the plugin '$pluginKey' failed to load"
		}
	done >  >(gawk '
		@include "bg_core.awk"
		function addCol(col) {
			if (!(col in attribs)) {
				attribs[col]=col
				arrayPush(columns, col)
			}
		}
		function addRow(row) {
			if (!(row in plugins)) {
				plugins[row]=row
				arrayPush(rows, row)
			}
		}
		BEGIN {
			arrayCreate(plugins)
			arrayCreate(attribs)
			arrayCreate(columns)
			arrayCreate(rows)
			arrayCreate(values)

			# add the well known column names so that they appear on the left of each line
			addCol("package")
			addCol("pluginKey")
			addCol("loadable")
			addCol("pluginType")
			addCol("pluginID")
			addCol("keyCol")
			addCol("name")

			addCol("requiredCols")
			addCol("cmd_run")
			addCol("cmd_collect")
			addCol("auth")
			addCol("runAsUser")
			addCol("tags")

			addCol("cmd")
			addCol("goal")
			addCol("defDisplayCols")
			addCol("columns")
		}
		NF!=3 {assert("logic error. The pipe should feed in only lines with three columns : <pluginKey> <attribName> <value>")}
		{
			pluginKey=$1; attrib=$2; value=$3
			#bgtrace("   |pluginKey=|"pluginKey"|  attrib=|"attrib"|")
			if (attrib ~ /^[a-zA-Z]/  && attrib !~ /^(staticMethods|methods|vmtCacheNum|classHierarchy|baseClass|mutableCols)$/) {
				addRow(pluginKey)
				addCol(attrib)
				values[pluginKey,attrib]=value
			}
		}
		END {
			# print the header
			for (j in columns)
				printf("%s ", columns[j])
			printf("\n\n")

			# print each row
			for (i in rows) {
				for (j in columns)
					printf("%s ", norm(values[rows[i],columns[j]]))
				printf("\n")
			}
		}
	' | column -t -e)
}



function Plugin::__construct()
{
	this[pluginType]="$1"; shift
	this[pluginID]="$1"; shift

	$this[_contructionParams]=new Array "$@"

	# start by setting the defaults from the pluginType class
	local attribName name value
	for attribName in ${newTarget[defaults]}; do
		stringSplit -d"=" "$attribName" name value
		unescapeTokens value
		this[$name]="$value"
	done
}

function Plugin::postConstruct()
{
	# now set the attributes provided by the plugin author in the plugin DeclarePlugin block
	local -n ctorParams="$(GetOID "${this[_contructionParams]}")"
	[ ${#ctorParams[@]} -gt 0 ] && parseDebControlFile this "${ctorParams[@]}"

	# regardless of what the author provided in the attribute inputs, we have to make sure that these attributes are set
	# the way that they should be
	this[${newTarget[keyCol]:-name}]="$pluginID"
	this[pluginID]="$pluginID"
	this[pluginType]="$pluginType"
	this[pluginKey]="${newTarget[name]}:$pluginID"

	# normalize tags attribute (if it exists)
	this[tags]="${this[tags]//[,:]/ }"

	local -n mutableCols="$(GetOID "${newTarget[mutableCols]}")"
	for attribName in "${!mutableCols[@]}"; do
		configGet -R this[$attribName] "${this[pluginKey]}" "$attribName" "${this[$attribName]}"
	done

	local requiredCol; for requiredCol in ${static[requiredCols]}; do
		[ "${this[$requiredCol]+exits}" ] || assertError  -v this "plugins of this type must declare the attribute/column '$requiredCol'"
	done
}

function Plugin::setAttribute()
{
	local name="$1"; shift
	local value="$1"; shift
	if $static[mutableCols][$name].exists; then
		this[$name]="$value"
		configSet "${this[pluginKey]}" "$name" "${this[$name]}"
	else
		bgtrace "not setting attribute '$name' in plugin '${this[pluginID]}' because its plugin type '${this[pluginType]}' does not declare it as mutable"
	fi
}


# usage: $Plugin.invoke <entryPointName> [<arg1>..<argN>]
# invoke a plugin method. These are not bash object methods because the plugin might be implemented in another language
function Plugin::invoke()
{
	local entryPointName="$1"; shift
	# SECURITY: this invokes the data contents of the <entryPointName> attribute. It relies plugins being installed only from trusted sources
	# if the attribute is not set, the default is to try the <pluginID>::<entryPointName>. This makes declaring bash script plugins
	# support a nicer format.
	# TODO: split up the following line and do better error reporting
	${this[$entryPointName]:-${this[pluginID]}::$entryPointName} "$@"
}
