#!/bin/bash


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

	# make a mutableCols Map member var so that setAttribute can easily check
	local mutableColsString="${static[mutableCols]}"
	$static[mutableCols]=new Map
	local -n mutableCols="$(GetOID "${static[mutableCols]}")"
	for attribName in $mutableColsString; do
		mutableCols[$attribName]="1"
	done

	$Plugin::register "PluginType:$pluginType" "$static"
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

# usage: $Plugins::list [<outputOptions>] [--short] [<pluginNameSpec>]
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
	local retOpts shortFlag
	while [ $# -gt 0 ]; do case $1 in
		--short) shortFlag="--short" ;;
		--full)  shortFlag="" ;;
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
	done < <(manifestGet --pkg="${packageOverride:-.*}" "plugin" "$pluginNameSpec")

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
	fi
	local pluginKey="$pluginType:$pluginID"

	# <retVar> can be passed in the -R option or as the last parameter
	[ ! "$retVar" ] && retVar="$1"

	if [ ! "${loadedPlugins[$pluginKey]+exists}" ]; then
		# ensure that this plugin's pluginType is loaded first
		[ "$pluginType" != "PluginType" ] && static::Plugin::get -q "PluginType:$pluginType"

		# get the filename that implements this plugin from the manifest
		local pkg scrap filename
		read -r pkg scrap scrap filename < <(manifestGet  plugin "$pluginType:$pluginID")
		assertNotEmpty filename "could not find assetType:plugin assetName:'$pluginType:$pluginID' in host manifest"

		local fileTypeInfo="$(file "$filename")"
		if [[ "$fileTypeInfo" =~ Bourne-Again ]]; then
			# this is the initially typical case where the plugin is implemented as a bash script
			import "$filename" ;$L1;$L2
		else
			# this is the case where the plugin is implemented in a different language. It could be a php or python script or a binary
			# The executable should respond to the 'getAttributes' command by returning its attributes in the deb control file syntax
			[ -x "$filename" ] || assertError "could not load plugin file '$filename' because it is not a bash script and not an executable"
			DeclarePlugin "$pluginType" "$pluginID" "$($filename getAttributes)"
		fi

		[ "${loadedPlugins[$pluginKey]+exists}" ] || assertError "failed to load plugin '$pluginKey'"

		local -n plugin; GetOID "${loadedPlugins[$pluginKey]}" plugin
		plugin[package]="$pkg"
	fi

	if [ "$quietFlag" ]; then
		return 0
	else
		returnObject "${loadedPlugins[$pluginKey]}" "$retVar"
	fi
}



function Plugin::__construct()
{
	local pluginType="$1"; shift
	local pluginID="$1"; shift

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
	this[key]="${newTarget[name]}:$pluginID"
	this[pluginKey]="${newTarget[name]}:$pluginID"

	# normalize tags attribute (if it exists)
	this[tags]="${this[tags]//[,:]/ }"

	local -n mutableCols="$(GetOID "${newTarget[mutableCols]}")"
	for attribName in "${!mutableCols[@]}"; do
		this[$attribName]="$(PluginConfigGet "${this[key]}" "$attribName" "${this[$attribName]}")"
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
		PluginConfigSet "${this[key]}" "$name" "${this[$name]}"
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


function PluginConfigGet()
{
	iniParamGet /etc/bgPlugins.conf "$1" "$2" "$3"
}

function PluginConfigSet()
{
	iniParamSet /etc/bgPlugins.conf "$1" "$2" "$3"
}


























#
#
# ##### Alt1
#
# DeclarePlugin CollectPlugin osBase "
# 	cmd_collect: collect_osBase
# 	runSchedule: 4/10min
# 	description: collect the basic linux OS host information
# 	 * osBase/lsb_release
# 	 * osBase/uname
# 	 * /etc/passwd
# 	 * /etc/group
# 	 * /etc/hostname
# 	 * /etc/cron.d/*
# 	 * /etc/apt/sources.list.d/*
# 	 * /etc/ssh/*.pub
# 	 ...
# "
#
# function collect_osBase()
# {
# 	collectPreamble || return
#
# 	lsb_release -a  2>/dev/null | collectContents osBase/lsb_release
# 	uname -a       | collectContents osBase/uname
# 	dpkg -l | sort | collectContents osBase/dpkg
#
# 	collectFiles "/etc/passwd"
# 	collectFiles "/etc/group"
# 	collectFiles "/etc/hostname"
# 	collectFiles "/etc/cron.d/*"
# 	collectFiles "/etc/apt/sources.list"
# 	collectFiles "/etc/apt/sources.list.d/*"
# 	collectFiles "/etc/ssh/*.pub"
# 	collectFiles "/etc/bg-*"
# 	collectFiles "/etc/at-*"
# }
#
# ###### Alt2
#
# DeclareClass OSBase extends CollectPlugin "
# 	cmd_collect: collect_osBase
# 	runSchedule: 4/10min
# 	description: collect the basic linux OS host information
# 	 * osBase/lsb_release
# 	 * osBase/uname
# 	 * /etc/passwd
# 	 * /etc/group
# 	 * /etc/hostname
# 	 * /etc/cron.d/*
# 	 * /etc/apt/sources.list.d/*
# 	 * /etc/ssh/*.pub
# 	 ...
# "
#
# function OSBase::collect()
# {
# 	collectPreamble || return
#
# 	lsb_release -a  2>/dev/null | collectContents osBase/lsb_release
# 	uname -a       | collectContents osBase/uname
# 	dpkg -l | sort | collectContents osBase/dpkg
#
# 	collectFiles "/etc/passwd"
# 	collectFiles "/etc/group"
# 	collectFiles "/etc/hostname"
# 	collectFiles "/etc/cron.d/*"
# 	collectFiles "/etc/apt/sources.list"
# 	collectFiles "/etc/apt/sources.list.d/*"
# 	collectFiles "/etc/ssh/*.pub"
# 	collectFiles "/etc/bg-*"
# 	collectFiles "/etc/at-*"
# }
