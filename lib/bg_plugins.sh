
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
	local -n pluginInst
	ConstructObject "$pluginType" pluginInst "$pluginType" "$pluginID" "$@"
	$Plugin::register "$pluginType:$pluginID" "$pluginInst"
	pluginInst[package]="$packageName"
}

# usage: DeclarePluginType <pluginType> <attributes>
# This is used to introduce a new type of plugin into the system. <name>.PluginType plugins use this instead of DeclarePlugin.
# Typically a package that includes a <MyNewType>.PluginType will also include commands that use plugins of <MyNewType> to allow
# other packages to extend the functionality of the command.
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
	static[package]="$packageName"
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
#    --pkgName=<pkg> : list plugins that are provided by this package only.
#    --manifest=<file> : list the plugins from this manifest file.  By default, the host's global manifest file or
#                  the virtually installed sandbox's manifest file is used based on the environment.
# See Also:
#   "bg-awkData manifest assetType:plugin" # assetName is of the form <pluginType>:<pluginName>
function static::Plugin::list()
{
	local retOpts shortFlag manifestOpt pkgNameOpt
	while [ $# -gt 0 ]; do case $1 in
		--short) shortFlag="--short" ;;
		--full)  shortFlag="" ;;
		-p*|--pkg*|--pkgName*)   bgOptionGetOpt opt: pkgNameOpt "$@" && shift ;;
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
	done < <(manifestGet $manifestOpt $pkgNameOpt "plugin" "$pluginNameSpec")

	outputValue -1 "${retOpts[@]}" "${plugins[@]}"
}


# usage:$Plugin::types [<outputOptions>] [<pluginTypeSpec>]
# List the plugin types present on this host.
# Params:
#    <pluginTypeSpec> : only list the names plugin types that match this spec
# Options:
#    <outputOptions>   : See man outputValue for supported options which control how the output is returned.
#    --pkgName=<pkg> : list types that are provided by this package only.
#    --manifest=<file> : list the types from this manifest file.  By default, the host's global manifest file or
#                  the virtually installed sandbox's manifest file is used based on the environment.
# See Also:
#   "bg-awkData manifest assetType:plugin" # assetName is of the form <pluginType>:<pluginName>
function static::Plugin::types()
{
	local retOpts manifestOpt pkgNameOpt
	while [ $# -gt 0 ]; do case $1 in
		-p*|--pkg*|--pkgName*)   bgOptionGetOpt opt: pkgNameOpt "$@" && shift ;;
		--manifest*)  bgOptionGetOpt opt: manifestOpt "$@" && shift ;;
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
		if [[ "$pluginID" =~ ^PluginType: ]]; then
			types["${pluginID#PluginType:}"]="1"
		fi
	done < <(manifestGet $manifestOpt $pkgNameOpt "plugin" "$pluginTypeSpec")

	outputValue -1 "${retOpts[@]}" "${!types[@]}"
}


# usage: $Plugin::get [-R <retVar>] <pluginKey>
#        $Plugin::get [-R <retVar>] <pluginType> <pluginID>
# static Plugin method to get a plugin given its type and name (which is its unique key). The parameter passed in the second form
# is also known as the <pluginKey>. The <pluginKey> uniquely identifies the plugin on the host but if two packages containing the
# same <pluginKey> are somehow installed on the same host, the --pkgName= option can be used to resolve the conflict.
#
# This returns quickly without doing anything if the plugin is already loaded. If it is not already loaded, it will attempt to load
# it by using the host manifest to find a library asset with the assetType "plugin" and assetName "<pluginType>.>pluginName>".
# If the --pkgName= option is specified, only plugins provided by that package will be considered.
# It should be noted that you can load a plugin that is not registered in the host manifest by sourcing the library that contains
# it explicitly and then calling $Plugin::get but that would not be secure on a production machine and such code should not be
# accepted into a trusted repository.
# Options:
#    -q|--quiet) : load the plugin without returning a reference to it. Sometimes you just want to make sure the plugin is loaded.
#    --pkgName=<pkg> : normally <pluginKey>s (<pluginType> + <pluginID>) are unique on a host. If that is not the case, this option
#                  can be used to choose which package provided the desired plugin.
#    --manifest=<file> : load the plugin referenced in the specified manifest file. By default, the host's global manifest file or
#                  the virtually installed sandbox's manifest file is used based on the environment.
#    -R <retVar> : <retVar> is the variable that will receive the loaded plugin. If it is an uninitialized -n (reference) variable,
#                  it will be set to point to the plugin's Object OID associaive array. Otherwise, it will be set with the Object's
#                  <objRef> string representation which acts like a pointer to the associative arrary. If this option is not specified
#                  the string <objRef> is printed to stdout. See man(3) returnObject
# Params:
#    <pluginKey>   : the unique identifier for a plugin installed on a host. It consists of the <pluginType> and <pluginID> separated
#                    by a ':' (<pluginType>:<pluginID>)
#    <pluginType>  : the type of the plugin to be returned.
#    <pluginID>    : the name of the plugin to be returned.
# See Also:
#    man(3) returnObject
function static::Plugin::get()
{
	local retVar quietFlag pkgNameOpt manifestOpt
	while [ $# -gt 0 ]; do case $1 in
		-q|--quiet)   quietFlag="-q" ;;
		-p*|--pkg*|--pkgName*)   bgOptionGetOpt opt: pkgNameOpt "$@" && shift ;;
		--manifest*)  bgOptionGetOpt opt: manifestOpt "$@" && shift ;;
		-R*)          bgOptionGetOpt val: retVar "$@" && shift ;;
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
		[ "$pluginType" != "PluginType" ] && static::Plugin::get -q $manifestOpt "PluginType:$pluginType"

		# get the filename that implements this plugin from the manifest
		local _pg_pkg _pg_scrap _pg_filename
		read -r _pg_pkg _pg_scrap _pg_scrap _pg_filename < <(manifestGet $manifestOpt $pkgNameOpt plugin "$pluginType:$pluginID")
		assertNotEmpty _pg_filename "could not find assetType:plugin, assetName:'$pluginType:$pluginID' in host manifest"

		# override the 'context global' packageName var for and DeclarePlugin calls made when sourcing the plugin library. There
		# may be multiple plugins Declared in the library, not just the one we are explicitly 'getting'
		local packageName="$_pg_pkg"

		_pluginLoadContainingLibrary "$pluginKey" "$_pg_filename"

		local -n _pg_plugin; GetOID "${loadedPlugins[$pluginKey]}" _pg_plugin
		[ "${_pg_plugin[package]}" == "$_pg_pkg" ] || assertLogicError
	fi

	if [ "$quietFlag" ]; then
		return 0
	else
		returnObject "${loadedPlugins[$pluginKey]}" "$retVar"
	fi
}


# usage: _pluginLoadContainingLibrary <pluginKey> <libraryFilename>
# This is an internal helper function to load a plugin library file with the purpose of loading the specified <pluginKey>
# The <libraryFilename> can be a bash script or some opaque executable that implements the plugin libary protocol.
function _pluginLoadContainingLibrary()
{
	local _pl_pluginKey="$1";       shift
	local _pl_libraryFilename="$1"; shift; assertNotEmpty _pl_libraryFilename

	local _pl_fileTypeInfo="$(file "$_pl_libraryFilename")"
	if [[ "$_pl_fileTypeInfo" =~ Bourne-Again ]]; then
		# this is the typical (at least initially) case where the plugin is implemented as a bash script
		import "$_pl_libraryFilename" ;$L1;$L2
	elif [ -x "$_pl_libraryFilename" ]; then
		# this is the case where the plugin is implemented in a different language. It could be a php or python script or a binary
		# The executable should respond to the 'getAttributes' command by returning its attributes in the deb control file syntax
		DeclarePlugin "$pluginType" "$pluginID" "$($_pl_libraryFilename getAttributes)"
	else
		assertError -v libraryFilename:_pl_libraryFilename "could not load plugin library file '$_pl_libraryFilename' because it is not a bash script and not an executable"
	fi

	[ ! "$_pl_pluginKey" ] || [ "${loadedPlugins[$_pl_pluginKey]+exists}" ] || assertError "failed to load plugin '$_pl_pluginKey' contained in file '$_pl_libraryFilename'"
}


# usage: $Plugin::loadAllOfType <pluginType>
# static Plugin method to load all the installed plugins of the given type.
# Options:
#    --manifest=<file> : load the plugins listed in this alternate manifest file.  By default, the host's global manifest file or
#                  the virtually installed sandbox's manifest file is used based on the environment.
function static::Plugin::loadAllOfType()
{
	local manifestOpt
	while [ $# -gt 0 ]; do case $1 in
		--manifest*)  bgOptionGetOpt opt: manifestOpt "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local pluginType="${1:-${static[name]}}"; shift; assertNotEmpty pluginType

	# ensure that this  pluginType is loaded first
	[ "$pluginType" != "PluginType" ] && static::Plugin::get -q "PluginType:$pluginType"

	local  _pg_pkg _pg_type _pg_name _pg_filename;
	while read -r _pg_pkg _pg_type _pg_name _pg_filename; do
		_pluginLoadContainingLibrary "$_pg_name" "$_pg_filename"
	done < <(manifestGet $manifestOpt  plugin "$pluginType:.*")
}

# usage: $Plugin::addNewAsset <subType> <newAssetName>
# This is invoked by the "bg-dev asset plugin.<pluginType> <newAssetName>" command to add a new asset to the current project folder
# of this plugin type.  This default implementation assumes that there is a system template named newAsset.plugin.<pluginType> which it
# expands to make a new asset file at <projectRoot>/plugins/<newAssetName>.<pluginType>.  A particular <pluginType> may override
# this static function to perform different actions if needed.
function static::Plugin::addNewAsset()
{
	local subType="$1"; shift
	local newAssetName="$1"; shift; assertNotEmpty newAssetName

	[ "$subType" == "--" ] && subType=""
	[ "$subType" ] && subType=".$subType"

	local destFile="./plugins/$newAssetName.${static[name]}"
	[ -e "$destFile" ] && assertError "An asset already exists at '$destFile'"

	import bg_template.sh  ;$L1;$L2
	local templateFile; templateFind -R templateFile "newAsset.plugin.${static[name]}$subType"
	[ ! "$templateFile" ] && assertError -v templateName:"-lnewAsset.plugin.${static[name]}$subType" -v subType -v "plugintype:-l${static[name]}" "The template to create a new plugin asset of this type was not found on this host."

	templateExpand "$templateFile" "$destFile"
	echo "A new asset has been added at '$destFile' with default values. Edit that file to customize it."
}

# usage: $Plugin::_dumpAttributes [--pkgName=<pkgName>] [--manifest=<file>] [<pluginKeySpec>]
# This is a helper function used to build and maintain the plugin awkData table. You specify a set of plugins and it will print to
# stdout all the attributes, one per line of each plugin in the set.
# Each line has the format...
#      <pkgName> <pluginKey> <attributeName> <attributeValue>
# Each token is escaped using the awkData standard.
function static::Plugin::_dumpAttributes()
{
	local pkgNameOpt manifestOpt
	while [ $# -gt 0 ]; do case $1 in
		-p*|--pkg*|--pkgName*) bgOptionGetOpt opt: pkgNameOpt "$@" && shift ;;
		--manifest*)  bgOptionGetOpt opt: manifestOpt "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local pluginKeySpec="$1"

	local pkg scrap pluginKey pluginPath
	local -n plugin
	while read -r pkg scrap pluginKey pluginPath; do
		Try:
			unset -n plugin; local -n plugin; $Plugin::get $manifestOpt --pkgName=$pkg -R plugin "$pluginKey"
			echo "$pkg" "$pluginKey" "pluginKey" "$pluginKey"
			local attribNames=(); $plugin.getAttributes -A attribNames
			local -n mutableCols; $plugin.static.mutableCols.getOID mutableCols
			local attrib; for attrib in "${attribNames[@]}"; do
				if [ ! "${mutableCols[$attrib]+exists}" ]; then
					local value="${plugin[$attrib]}"
					varEscapeContents attrib value
					echo "$pkg"  "$pluginKey" "$attrib" "$value"
				fi
			done
			echo "$pkg" "$pluginKey" "loadable" "loadSuccess"
		Catch: && {
			echo "$pkg" "$pluginKey" "loadable" "loadFail"
			echo "the plugin '$pluginKey' failed to load '$catch_errorDescription'" >&2
			assertError "the plugin '$pluginKey' failed to load"
		}

	done < <(manifestGet $manifestOpt $pkgNameOpt "plugin" "${pluginKeySpec:-.*}")
}

# usage: $Plugin::_assembleAttributesForAwktable [--pkgName=<pkgName>] [<pluginKeySpec>]
# This is a pipe function which reads a stream of one attribute per line, as produced by _dumpAttributes, and outputs to stdout
# an awkdata table with one plugin per line and columns which is a union of all columns used by any of the present plugins.
# Note that there are a handful of hard coded columns that will always be present and appear first (left most). The rest of the
# columns depend on which ones are present in the set of plugin attributes read on stdin.
#
# Some (most) plugins will not have values for every attribute column and those fields will be empty ('--').
function static::Plugin::_assembleAttributesForAwktable()
{
	gawk '
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
		NF!=4 {assert("logic error. The pipe should feed in only lines with four columns : <pkgName> <pluginKey> <attribName> <value>")}
		{
			pkgName=$1; pluginKey=$2; attrib=$3; value=$4
			#bgtrace("   |pluginKey=|"pluginKey"|  attrib=|"attrib"|       |"$0"|")
			if (attrib ~ /^[a-zA-Z]/  && attrib !~ /^(staticMethods|methods|vmtCacheNum|classHierarchy|baseClass|mutableCols)$/) {
				if (attrib=="package" && pkgName != value)
					assert("logic error: the [package] attribute ("value") in plugin "pluginKey" does not match the pkgName from the manifest entry for the plugin ("pkgName") ")
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
	'
}


# usage: $Plugin::buildAwkDataTable [--manifest=<file>]
# This builds an awkData style table of all installed plugins and the union of attribute names that they contain as columns
# Mutable attributes (aka columns) and attributes that start with '_' are not included.
# The output is sent to stdout.  The set of plugins is the entire set contained in a manifest file.  By default it uses the global
# host manifest of the host computer. In a production environment that will be the one in the /var/lib/bg-core/hostmanifest and
# in a vinstalled development environment it will be the one in the vinstalled sandbox's ./.bglocal/hostmanifest.  The --manifest
# option can be used to specify a particular manifest file to use.
# Options:
#    --manifest=<file> : override the prevailing default host manifest (either production or vinstalled) with a specific file.
function static::Plugin::buildAwkDataTable()
{
	local manifestOpt
	while [ $# -gt 0 ]; do case $1 in
		--manifest*)  bgOptionGetOpt opt: manifestOpt "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	static::Plugin::_dumpAttributes $manifestOpt | static::Plugin::_assembleAttributesForAwktable | column -t -e
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
