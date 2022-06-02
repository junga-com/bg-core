
# Library bg_coreSysRuntime.sh
#######################################################################################################################################
### System Runtime Functions.
# System Runtime is about the filesystem organization and package management of the target OS.  How does code find its installed
# data files such as templates, access system configuration files, etc...  This module provides mechanisms for composing file based
# information from multiple packages that may or may not be integrated with similar standards and mechanisms provided by the host's
# OS
#
# If the $packageName vaiable is set before this script is sourced, it will declare a family of pkg*[File|Folder] variables that
# contain the paths to various package/project specific files and folders.
#
# Sometimes a package wants to operate on data that may originate from itself (like default templates) but also may come from other
# packages that override or extend the first package's functionality or from system specific changes made by the sysadmin or user.
# When a domData is installed on a host this information may come from it. The findInPaths function is the core of this mechanism
# that allows the information that a package's code has access to to come from any of these sources and provide an algorithm for
# overriding or combining the information.


# usage: findInPaths [<options>] <fileSpec> [-r <relativePaths>] <searchPaths1> [...[-r <relativePaths>] <searchPathsN>]
# Find all files matching <fileSpec> in the specified search paths. The order of search paths is significant
# because the default is to return only the first occurrence of each unique filename that matches <fileSpec>.
#
# This function is the basis for OS packaging features that allow multiple package to cooperate in providing
# and overriding information in a flexible way.
#
# Search Algorithm:
# The algorithm employed can be thought of as combining "which <fileSpec>" and "ls <fileSpec>". In each
# search path, in order, it expands any wildcards making a list of unqiue base filenames and merging
# that list into its return results.
# The command allows the caller to flexibly build the search path list, including sub folders that will
# be checked wrt to some search paths but not necessarily all of them. Options allow determining how
# files found in multiple places are merged into the result set and where the result set contain full
# paths or just the logical names.
#
# Results:
# By default each returned filename(s) will be absolute and will exist. If no files are found, nothing
# is returned and it is not an error.
# If --return-relative is specified then each returned filename(s) will be relative to the search path
# where it was found. This is not enough information to access the file but this is usefull to expand
# wiildcard <fileSpec> to get a list of available filenamees of a particular type.
#
# Params:
#   <fileSpec>     : the filename to find. can include wildcards. all multiple matching unique filenames are returned.
#   <searchPathsN> : default is "$PATH": a list of paths separated by ":". multiple parameters <searchPaths> are combined
#
# Options:
#   -R <retVar> : return the first value found in this  variable name
#   -A <arrayVar> : return every value found by appending to this array variable name
#   -r <relativePaths> : this option can appear anywhere on the command line and it effects only the
#        <searchPathsN> parameters that follow it up until the next -r is encountered.
#        <relativePaths> is a : separated list of paths similar to <searchPathsN>
#        Each of the relativePaths in effect will be searched under each of the paths from <searchPathsN>.
#        if the root of <searchPathsN> should be searched also, a leading or trailing : should be added
#        to <relativePaths>. -r "" will make it search only the root of each path in <searchPathsN>
#   -d : allow duplicates. if a matching filename exists in more than one path, this causes all occurrences
#        to be returned instead of only the first found.
#   --no-scriptFolder : normally the folder that the script is in is added to the front of the search paths. This suppresses that.
#   --debug : instead of returning the matching files, print the processed search paths and the find
#        command that would be exected. This is useful in test cases.
#   --return-relative : instead of returning the fully qualified absolute paths, return just the file
#        names relative to the search path where it is found. This is useful when using wildcards to
#        find out which file names are available to use.
# See Also:
#    bg-plugins   : uses this function
#    templateFind : uses this function
#    import <scriptName> ;$L1;$L2  : this is how libraries and scripts source libraries they need
#    import --getPath <scriptName> : returns the path without sourcing it
#    findInPaths : this is a much more flexible algorithm for finding various types of installed files
function findInPaths()
{
	local allowDupes addScriptFolderFlag="1" debug relativePaths=("") tmpPaths allPaths singleValueFlag listPathsFlag
	local posCwords=1 fileSpec preCmd findPrintFmt="%p" retVar
	local retArgs=("--echo")

	# this is an atypical option processing loop because we want to allow -r to appear anywhere and
	# effect only the paths that follow it. So this loops over options and positional params
	while [ $# -gt 0 ]; do case "$1:$posCwords" in
		# handle options.
		-r*) if [ "$1" == "-r" ]; then
				tmpPaths=("$2"); shift
			else
				tmpPaths=("${1#-r}")
			fi
			IFS=":" read -r -a relativePaths <<<"$tmpPaths"
			[[ "$tmpPaths" =~ :$ ]] && relativePaths=( "${relativePaths[@]}" "" )
			[ "$tmpPaths" == "" ] && relativePaths=( "" )
			;;
		-d:*)  allowDupes="-d" ;;
		--no-scriptFolder:*) addScriptFolderFlag="" ;;
		--listPaths:*) listPathsFlag="--listPaths" ;;
		--debug:*)           debug="1"; preCmd="echo " ;;
		--return-relative:*) findPrintFmt="%P" ;;
		-R*|--retVar*)   bgOptionGetOpt val: retVar "$@" && shift; retArgs=(); singleValueFlag="1" ;;
		-A*|--retArray*) bgOptionGetOpt val: retVar "$@" && shift; retArgs=(--append --array "$retVar") ;;

		# first positional param is the filespec
		[^-]*:1) fileSpec="$1"; ((posCwords++))
			;;

		# the rest are searchPath terms. Add them to the allPaths array, expanding with the relativePaths
		# that is in effect
		[^-]*:*)
			IFS=":" read -r -a tmpPaths <<<"$1"
			[ "$addScriptFolderFlag" ] && tmpPaths=( "$scriptFolder" "${tmpPaths[@]}" ) && addScriptFolderFlag=""
			local path; for path in "${tmpPaths[@]}"; do
				path="${path%/}"
				# SECURITY: each place that sources a script library needs to enforce that only system paths -- not vinstalled paths are
				#           searched in non-development mode
				# TODO: check the path with a white list of all acceptable system paths. we done know if its code or data so the white list needs to include all.
				#       note that it not ok to check whether the user can write to the folder because a non-root user can make a folder they can not write to.
				# if [ "$bgProductionMode" != "development" ] ; then
				#
				# fi

				local rpath; for rpath in "${relativePaths[@]}"; do
					allPaths+=("${path}${rpath:+/}${rpath}")
				done
			done
			((posCwords++))
			;;
	esac; shift; done

	if [ ! "$fileSpec" ]; then
		type -t assertError &>/dev/null && assertError "fileSpec is a required parameter to findInPaths()"
		echo "error: fileSpec is a required parameter to findInPaths()" >&2
		exit 45
	fi

	if [ ! "${allPaths[0]+exists}" ]; then
		IFS=":" read -r -a allPaths <<<"$PATH"
		[ "$addScriptFolderFlag" ] && allPaths=( "$scriptFolder" "${allPaths[@]}" ) && addScriptFolderFlag=""
	fi

	if [ "$debug" ]; then
		printfVars fileSpec allPaths
		return
	fi

	if [ "$listPathsFlag" ]; then
		printfVars templatFolders:allPaths
		return
	fi

	# since we allow wildcards in <fileSpec>, we could be returning multiple matching files even if
	# the allowDupes option was not specified so the awk filter is needed to remember which fileSpecs
	# have been seen and suppress outputting subsequent fileSpecs.
	local count=0
	while IFS="" read -r -d$'\b' _line; do
		((count++))
		varSetRef "${retArgs[@]}"  "$retVar" "$_line"
		[ "$singleValueFlag" ] && return 0
	done < <(find "${allPaths[@]}" -maxdepth 1 -type f -name "$fileSpec" -printf "${findPrintFmt}\0" 2>/dev/null \
		| awk -v RS='\0' -F"/" -v allowDupes="$allowDupes" '
		{
			# $NF is the basename -- the last field separated by -F"/"
			# allowDupes refers to the same basename in different folders. In any case, we do not return the same full path twice
			dupToken = (allowDupes) ? $0 : $NF
			if (!seen[dupToken]) {
				seen[dupToken]=1
				printf("%s\b", $0)
			}
		}
	')
	[ ${count:-0} -gt 0 ]
}


# usage: bgGetDataFolder [<packageName>]
# get the runtime package data folder for the specified project
# this recognizes virtually installed pacakge projects.
# The path returned may be different for differnt distributions. On debian style systems it is /usr/share/<packagename>
# in bg-scriptprojectdev projects this is the ./data/ folder in its git project
# when a package is installed, that folder and its the contents are copied to the target system
# where commands can reference its data.
function bgGetDataFolder()
{
	local pName=${1:-$packageName}

	# search in bgDataPath to honor virtually installed packages

	local dataFolder; findInPaths -R dataFolder  ".$pName" -r "data" "$bgDataPath" -r "" "/usr/share/$pName"
	dataFolder="${dataFolder%/*}"

	# if no existing folder was found, set it to the system path even if it does not yet exist.
	dataFolder="${dataFolder:-/usr/share/$pName}"

	# returnValue "$dataFolder" "$2" (this function does not depend on any other function libraries)
	if [ "$2" ]; then
		printf -v "$2" "%s" "$dataFolder"
	else
		echo "$dataFolder"
	fi
}


# scripts that are a part of a package typically set the packageName var at the top.
# set the default dataFolder to the top level project the running script belongs to
if [ "$packageName" ]; then
	dataFolder="$(bgGetDataFolder $packageName)"
	confFile="/etc/$packageName"
	# 2020-10 - created new naming standard to group the paths related to the package running the code
	pkgName="${packageName}"
	pkgDataFolder="$dataFolder"
	pkgConfFile="$confFile"
	pkgManifest="/var/lib/bg-core/$packageName"
fi


# usage: templateFind [-R|--retVar=<retVar>] [-p|--pkg=<preferedPkg>] [--manifest=<file>] <templateName>
# finds a template file among those installed on the host.
# This is similar to how linux finds a command in the system $PATH and has similar security concerns because a template can be used
# as the basis for system configuration.
#
# When ever a template is expanded, the template filename is passed though this function. If its an absolute path that exists, it
# will be returned without modification. Then the name is looked up in the host manifest file and if found, that path is returned.
# Finally, if it was not found in the manifest, but it is a relative path that exists, that path is returned.
#
# The general idea is that packages can provide templates and privileged admins can override and add to the set of installed templates.
# Domain admins can override or add to templates on a set of hosts and a local sysadmin can override or add to the templates installed
# on that particular host. Unpriviledged users can not add to or modify the set of system templates installed on the host.
#
# Templates have types. Code that uses a template will only look for templates of a particular type. When more than one template of
# the requested type exists, the code may allow the unprivileged user to select among the available installed templates of that type.
#
# Templates are assets that are registered in the host manifest file with the assetType 'template' ro 'template.folder'. Packages
# built with bg-dev will register the assets they contain when they are installed on a host. A system admin can also add assets
# including templates.
#
# Naming Convention:
# The naming convention is <baseType>[.<typePart1>.[.<typePart2>...]]
# <baseType>
#    The <baseType> identifies the purpose of the template which typically means what code uses the template.
#    The code that expands the template will typically pick a hard coded <baseType> name that is sufficiently
#    unique to describe its use.
# <typePartN>
#    The <typePartN> part of the name is used to allow runtime identification of which template will be used.
#    The code that expands the template can choose to dynamically obtain the value for <typePart1> from a config
#    file or command parameter and append it to the <baseType>. The sysadmin can then specify which <typePart1>
#    value and therefore which template would be used.
#
# Overriding Templates:
# The manifest can contain templates with the same assetName as long as the pkg field is different. Every asset must have a unique
# triplet (pkg,assetType,assetName) and since the assetType is 'template[.folder]', templates must have a unique pair (pkg,assetName).
#
# If there are multiple templates with the exact assetName, the pkg fields must be different and there is a ordering of pkg values
# that determines which one is returned.
#
# Pkg fields values have this order for templates with the exact same assetName. The one of these found will be returned.
#    * admin       : a user with local admin priviledge on the host added a template
#    * domainAdmin : a user with domain admin priviledge added a template that is seen by this host
#    * <selfPkg>   : this is the package of the code that is calling findTemplate. i.e. is the code is in myFooPkg, a template
#                    provided by myFooPkg will be prefered over ones provided by other packages.
#    * <otherPkg> ... : if none of the above exist for the assetName but one or more exist from foriegn packages, one is returned
#                    indeterminently.
# Note that it is common that a package that expands a particular template assetName, will provide a template by that name. It is
# not common for the above search to go past <selfPkg>.
#
# Note that the overriding algorithm only kicks in for templates with the exact same assetName. A similar but different concept is
# providing multiple templates from multiple packages of the same base type but different full assetNames.
#
# Template Groups:
# Templates whose asset names share a common prefix are logically groups together. The code that expands the template will hardcode
# one or more parts but can then allow configuration or dynamic variables to specify the remainder of the assetName to match an
# exact assetName.
#
# Example - awkDataQuery:
# For example, the awkDataQuery code uses a template of 'awkDataTblFmt' base type. It exposes two concepts that the caller can
# choose from that will form the complete assetName of the template to use. One is the 'type' of output controlled by the
# --tblFormat=<type> option and the other is the vertical vs horizontal output style determined by the SQL like '\G' query term.
# The full template that it uses will have the assetName 'awkDataTblFmt.<type>[.vert]'. A third party package or a system admin can
# provide a new output type for use with awkDataQuery by adding a new template named 'awkDataTblFmt.<newTypeName>' and optionally
# another named 'awkDataTblFmt.<newTypeName>.vert' if the vertical style is supported.
#
# The bash completion code can query which templates are available to provide suggestions for completing the --tblFormat=<tab><tab>
# option.
#
# Example - Web Server Vhosts:
#    Code that creates a new web server virtual host from a template could use the web server type (apache2|nginx)
#    as typePart1 and the type of vhost (plain|reverseProxy) as typePart2.
#        vhostConf.<webServerType>.<vhostType>
#    It would select the value for <webServerType> based on which web server is installed on the host
#    and let the sysadmin specify the vhostType.  The sysadmin or other packages could add new templates
#    named with new vhostTypes. The code can present which types are available (for example in a bash completion
#    routine, by calling this function with a wild coard for the type like templateFind vhostConf.*
#
# Comment Tags:
#    Code that uses a template can use several comment tags to help the sysadmin know that the <baseType>
#    template type exists, part <typePartN> can be specified and which variabls can be referenced in the
#    template
#		# TEMPLATETYPE : <baseName>.<typePart1Name>... : <description>...
#		# TEMPLATEVAR : <baseName> : <varName> : <description>...
#
# Params:
#    <templateName> : the name of the system template or the path to a template.
#
#
# Options:
#   -R|--retVar=<retVar> : return the value found in this  variable name
#   -p|--pkg=<packageName> : prefer a match from this package over the package that is using the template.
# SECURITY: templateFind needs to return only trusted, installed templates by default because they can be used to change system config.
#           this function only returns files listed as assets in the hostmanifest file which only admins can write to
function templateFind()
{
	local manifestFile retArgs retVar packageOverride result
	local -a retArgs=(--echo -d $'\n')
	while [ $# -gt 0 ]; do case $1 in
		-p*|--pkg*) bgOptionGetOpt val: packageOverride "$@" && shift ;;
		-R*|--retVar*)   bgOptionGetOpt val: retVar   "$@" && shift; retArgs=(-R "$retVar");  ;;
		--manifest*)  bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local templateName="$1"

	# if its already an absolute path, just return it. Note that all assetFile paths in the host manifest must be absolute paths
	# so system templates will always be an absoulte path.
	# Code that takes a template name or path will run it through this function to turn it into a working path.
	if [[ "$templateName" =~ ^/ ]] && [ -e "$templateName" ]; then
		varSetRef "${retArgs[@]}" "$templateName"
		return
	fi

	local localPkgName="${packageOverride:-${packageName}}"
	[ ! "$manifestFile" ] && manifestGetHostManifest manifestFile

	# look it up in the manifest -- exact name matches only
	[ ! "$result" ] && result="$(gawk \
		-v templateName="$templateName" \
		-v packageName="$localPkgName" '
		@include "bg_template.find.awk"
		' "$manifestFile")"

	# support the user expanding local, non system files as long as they are not valid system template names (i.e. found in manifest)
	# if no system template was found, then <templateName> might refer to a local file or folder template.
	# SECURITY: we only fall back to this if <templateName> is not a system template name so that a user can not override an
	#           installed template by using a path to a local template
	[ ! "$result" ] && [ -e "$templateName" ] && result="$templateName"

	# SECURITY: see todo below...
	# TODO: consider if this function should check the permissions on the found path and refuse to return a path to a non-system file?
	#       I think that the default should be to check the permissions, but a flag --allow-user-templates would override it
	[ "$result" ] && varSetRef "${retArgs[@]}" "$result"
}

# usage: templateList [-A|--retArray=<retArray>] <templateSpec>
# list installed system templates that match <templateSpec>
# System templates are installed from packages or by a user with sufficient loacl host or domain priviledges. Templates are named
# hierarchicly with '.' separating the parts. <templateSpec> is a regex that matches the assetName of assets in the host manifest
# whose assetType is template(.folder)?. A '^' is prepended to <templateSpec> to make it anchored to the start of the assetName.
# Typically, only a prefix is given like "funcman" would match a template "funcman"  and any sub type like "funcman.1.bashCmd"
function templateList()
{
	local manifestFile retArgs retVar name
	local -a retArgs=(--echo -d $'\n')
	while [ $# -gt 0 ]; do case $1 in
		-A*|--retArray*) bgOptionGetOpt val: retVar "$@" && shift; retArgs=(--append --array "$retVar") ;;
		--manifest*)  bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local templateSpec="$1"

	[ ! "$manifestFile" ] && manifestGetHostManifest manifestFile

	while read -r name; do
		varSetRef "${retArgs[@]}" "$name"
	done < <(gawk \
		-v templateSpec="$templateSpec" '
		@include "bg_template.list.awk"
		' "$manifestFile")
}

# usage: templateGetSubtypes <templateSpec>
# return the list of sub types that could be appended to <templateSpec> to make a fully qualified template name.
# Template names are hierarchical with parts separated by '.'. <templateSpec> is typically the base type of the template but
# could also contain additional parts. This function scans all the template names and returns the additional sub types that exist.
function templateGetSubtypes()
{
	local manifestFile retArgs retVar name
	local -a retArgs=(--echo -d $'\n')
	while [ $# -gt 0 ]; do case $1 in
		-A*|--retArray*) bgOptionGetOpt val: retVar "$@" && shift; retArgs=(--append --array "$retVar") ;;
		--manifest*)  bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local templateSpec="$1"

	[ ! "$manifestFile" ] && manifestGetHostManifest manifestFile

	while read -r name; do
		varSetRef "${retArgs[@]}" "$name"
	done < <(gawk \
		-v templateSpec="$templateSpec" \
		-v outFormat="getSubtypes" '
		@include "bg_template.list.awk"
		' "$manifestFile")
}


# usage: templateTree <templateSpec>
# print a tree showing the hierarchy of installed templates.
# Template names are hierarchical with parts separated by '.'. <templateSpec> is typically the base type of the template but
# could also contain additional parts. This function scans all the template names and returns the additional sub types that exist.
function templateTree()
{
	local manifestFile retVar name
	while [ $# -gt 0 ]; do case $1 in
		--manifest*)  bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local templateSpec="$1"

	[ ! "$manifestFile" ] && manifestGetHostManifest manifestFile

	gawk \
		-v templateSpec="$templateSpec" \
		-v outFormat="getSubtypes" '
		@include "bg_template.tree.awk"
	' "$manifestFile"
}


# usage: bgListInstalledProjects
# return a list of all the installed package project. If any virtually installed projects are detected, only virutally installed
# projects will be returned.
function bgListInstalledProjects()
{
	if [ "$bgInstalledPkgNames" ]; then
		echo "${bgInstalledPkgNames//:/$'\n'}"
	else
		fsExpandFiles -B /var/lib/bg-core/ /var/lib/bg-core/* -type d
	fi
}
