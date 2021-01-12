#!/bin/bash

# Library bg_coreSysRuntime.sh
#######################################################################################################################################
### System Runtime Functions.
# System Runtime is about the filesystem organization and package management of the target OS.  How does code find its installed
# data files such as templates, access system configuration files, etc...  This module provides mechanisms for composing file based
# information from multiple packages that may or may not be integrated with similar standards and mechanisms provided by the host's
# OS
#
# If the $projectName vaiable is set before this script is sourced, it will declare a family of pkg*[File|Folder] variables that
# contain the paths to various package/project specific files and folders.
#
# Sometimes a package wants to operate on data that may originate from itself (like default templates) but also may come from other
# packages that override or extend the first package's functionality or from system specific changes made by the sysadmin or user.
# When a domData is installed on a host this information may come from it. The findInPaths function is the core of this mechaism
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
		-A*|--retArray*) bgOptionGetOpt val: retVar "$@" && shift; retArgs=(--append --array ) ;;

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


# usage: bgGetDataFolder [<projectName>]
# get the runtime package data folder for the specified project
# this recognizes virtually installed pacakge projects.
# The path returned may be different for differnt distributions. On debian style systems it is /usr/share/<packagename>
# in bg-scriptprojectdev projects this is the ./data/ folder in its git project
# when a package is installed, that folder and its the contents are copied to the target system
# where commands can reference its data.
function bgGetDataFolder()
{
	local pName=${1:-$projectName}

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


# scripts that are a part of a package typically set the projectName var at the top.
# set the default dataFolder to the top level project the running script belongs to
if [ "$projectName" ]; then
	dataFolder="$(bgGetDataFolder $projectName)"
	confFile="/etc/$projectName"
	# 2020-10 - created new naming standard to group the paths related to the package running the code
	pkgDataFolder="$dataFolder"
	pkgConfFile="$confFile"
	pkgManifest="/var/lib/bg-core/$projectName"
fi


# usage: templateFind [options] <templateNameSpec>
# finds the template file in the system template paths. This is similar to how linux finds a
# command in the system $PATH and has similar security concerns because a template can be used
# as the basis for system configuration.
#
# This is a wrapper over the findInPaths function which hardcodes the serach path to the proper set of system folders.
# <templateNameSpec> can contain wildcards to return all matching templates in the system path. See findInPaths.
#
# The general idea is that packages can provide templates, domain admins can override and add to those templates, the local sysadmin
# can override or add to those templates and the unprivileged user can not override or provide any template.
#
# Naming Convention:
# The naming convention is <baseType>[.<typePart1>.[.<typePart2>...]]
# <baseType>
#    The <baseType> identifies the purpose of the template which typically means what code uses the template.
#    The code that expands the template will typically pick a hard coded <baseType> name that is sufficiently
#    unique to describe its use. All the system template paths use ./<packageName>/ so as to avoid conflicts.
#    with other packages.
# <typePartN>
#    The <typePartN> part of the name is used to allow runtime identification of which template will be used.
#    The code that expands the template can choose to dynamically obtain the value for <typePart1> from a config
#    file or command parameter and append it to the <baseType>. The sysadmin can then specify which <typePart1>
#    value and therefore which template would be used.
#
# Rules:
#    This search order and naming convention results in these rules.
#      Code that uses Templates
#        * a package introduces a <baseType> by including code that calls this function with <baseType> and documenting its use.
#          (For example a package could have a createWebVhost command that uses the <baseType> 'webVhost')
#        * The code that uses the template can require 0 or more <typePartN>  (e.g webVhost.<srvType> where <srvType> is one of [ngix|appache])
#        * After the required <typePartN>, the code that uses the template may support arbitrary names which become options that can
#          be choosen by the user invoking the code. (e.g. webVhost.nginx.myCoolSite)
#      Templates from Packages
#        1) any package can provide a new template name used by its own code or the code in any other package
#        2) a template name provided and used in a package can not be overriden by another package
#        3) virtually installed package are respected on non=production hosts so that template changes can be tested alongside code changes
#      Templates from Admins
#        4) the domain admin can override any template for all servers, those at a location or a particular server or provides a new template
#        5) a host sysadmin can have the last word by putting a template in /etc/bgtemplates/ and override all others
#      Template from Users
#        6) unprivileged users can not provide templates returned by this command (except on development hosts via vinstall)
#
# Example:
#    Code that creates a new web server virtual host from a template could use the web server type (apache2|nginx)
#    as typePart1 and the type of vhost (plain|reverseProxy) as typePart2.
#        vhostConf.<webServerType>.<vhostType>
#    It would select the value for <webServerType> based on which web server is installed on the host
#    and let the sysadmin specify the vhostType.  The sysadmin or other packages could add new templates
#    named with new vhostTypes. The code can present which types are available (for example in a bash completion
#    routine, by calling this function with a wild coard for the type like templateFind vhostConf.*
#
# Default Search Path:
#    This function now uses the manifest file first to find templates and then falls back to this search path if the template was
#    not found in the manifest.  At some point the search paths algorithm may be removed.
#
#    The returned template full path will be the first of the following folders that contain the templateNameSpec
#    The vinstall folders will only be searvhed if the host is not in a production mode and the package is vinstalled
#      # first, a set of sysadmin/domain admin controlled folders will be checked. The admins can override
#        the packages provided by packages and also add new templates to extend features.
#         /etc/bgtemplates/[<packageName>/]
#         /<domFolder>/servers/$(domWhoami)/[<packageName>/]               (if there is a selected domData)
#         /<domFolder>/locations/$(domWhereami)/templates/[<packageName>/] (if there is a selected domData)
#         /<domFolder>/templates/[<packageName>/]                          (if there is a selected domData)
#      # next, the specific folder for the package thats requesting the template (or its vinstalled folder)
#         <virtuallyInstalled_packageName_folder>/data/templates/          (if <packageName> is virtually installed)
#         /usr/share/<packageName>/templates/
#      # and last, any package provided templates
#         <any_virtuallyInstalled_folder>/data/templates/                  (if <packageName> is virtually installed)
#         /usr/share/*/data/templates/                                     (the template folders of other packages)
#
# Comment Tags:
#    Code that uses a template can use several comment tags to help the sysadmin know that the <baseType>
#    template type exists, part <typePartN> can be specified and which variabls can be referenced in the
#    template
#		# TEMPLATETYPE : <baseName>.<typePart1Name>... : <description>...
#		# TEMPLATEVAR : <baseName> : <varName> : <description>...
#
# Params:
#    <templateNameSpec> : the name of the template
#    <searchPathN>  : each is a ":" separated list of folders. More that one can be specified. The order is relevant
#
# Options:
#   -R <retVar> : return the first value found in this  variable name
#   -A <arrayVar> : return every value found by appending to this array variable name
#   -d : allow duplicates. if a matching template exists in more than one path, this causes all occurrences
#        to be returned instead of only the first found.
#   -p <packageName> : limit the default search path to package related templates provided by this package.
#   --debug : instead of returning the matching template(s), print the processed search paths and the find
#        command that would be exected. This is useful in test cases and debugging
#   --return-relative : instead of returning the fully qualified absolute paths, return just the template
#        names relative to the search path where it is found. This is useful when using wildcards to
#        find out which template names are available to use.
# SECURITY: templateFind needs to return only trusted, installed templates by default because they can be used to change system config.
function templateFind()
{
	local type debug allowDupes returnRelative packageOverride retVar retArray listPathsFlag
	local -a retOpts=(--echo -d $'\n')
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d) allowDupes="-d" ;;
		-p*) bgOptionGetOpt val: packageOverride "$@" && shift ;;
		--debug) debug="--debug" ;;
		--listPaths) listPathsFlag="--listPaths" ;;
		--return-relative) returnRelative="--return-relative" ;;
		-A*|--retArray*) bgOptionGetOpt val: retArray "$@" && shift; retOpts=(-A "$retArray") ;;
		-R*|--retVar*)   bgOptionGetOpt val: retVar   "$@" && shift; retOpts=(-R "$retVar") ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local templateNameSpec="$1"; [ $# -gt 0 ] && shift

	local localPkgName="${packageOverride:-${packageName:-$projectName}}"

	### first, try to find the template in the manifest file.

	if [ ! "$listPathsFlag$debug" ]; then
		local -A resultSet=()
		local templatePkg templatePath templateName
		while read -r templatePkg scrap templateName templatePath; do
			if [ ! "${resultSet["$templateName"]}" ] || [ "$templatePkg" == "$localPkgName" ]; then
				resultSet["$templateName"]="$templatePath"
		 	fi
		done < <(manifestGet --pkg="${packageOverride:-.*}" template "$templateNameSpec")

		if [ ${#resultSet[@]} -gt 0 ]; then
			if [ "$returnRelative" ]; then
				outputValue "${retOpts[@]}"  "${!resultSet[@]}"
			else
				outputValue "${retOpts[@]}"  "${resultSet[@]}"
			fi
			return 0
		fi
	fi

	### Next search the filesystem for installed templates. (not sure this will be needed anymore after manifest is well supported)

	# This feature was removed for SECURITY. This function should only return templates it finds in system paths so that the caller
	# can trust that the template is the product of only priviledged access.
	# if [ -f "$templateNameSpec" ]; then
	# 	returnValue "$templateNameSpec" "$retVar"
	# 	return
	# fi

	if [ $# -gt 0 ]; then
		assertError "specifying paths to search for templates has been removed for security concerns -- templateFind will only
			return templates that are under system control and can not be modified by normal users when the host is in production
			mode"

	else
		# the order that the paths are added is the order that they will be searched

		# sysadminFolders will be under an -r <pkgName>: option so that the package specific version will be found first
		local sysadminFolders="/etc/bgtemplates/"

		# we can not guarantee that a domFolder will be available because this code is needed to initialize a new domdata.
		# domResolveDefaultDomFolder -> domContentInit(on local domFolder) -> awkData_lookup -> templateFind
		local domFolder; type -t domGetFolder&>/dev/null && domGetFolder domFolder
		if [ "$domFolder" ]; then
			sysadminFolders+=":$domFolder/servers/me/templates"
			sysadminFolders+=":$domFolder/locations/me/templates"
			sysadminFolders+=":$domFolder/templates/"
			local pathArray=(); fsExpandFiles -A pathArray $domFolder/templates/*/
			local i; for i in "${!pathArray[@]}"; do
				sysadminFolders+=":${pathArray[$i]}/"
			done
		fi

		# add the path for this package taking into account if the package is vinstalled. Note that if it is vininstalled, that
		# overrides the installed content. This allows for a vininstalled package removing a template that may still exist in the
		# last installed version.
		# SECURITY: if in non-development mode, we must not consider the virtually installed folders which non-admins could write to.
		local thisPackageFolder
		if [ "$localPkgName" ]; then
			thisPackageFolder="/usr/share/${localPkgName}/templates/"
		fi
		local bgLibPathsAry;
		if [ ! "$bgSourceOnlyUnchangable" ]; then
			IFS=":" read -a bgLibPathsAry <<<$bgLibPath
			local path; for path in "${bgLibPathsAry[@]}"; do
				[[ "$path" =~ (^|[/])$localPkgName([/]|$) ]] && thisPackageFolder="${path}/data/templates/"
			done
		fi


		[ "$debug" ] && printfVars packageOverride packageName

		# see man(3) findInPaths for explanation of the -r option. It maintains a statefull list of relative paths that are added
		# to each path encountered on the cmd line. When its "", the paths are taken as is. If its a list, each path encountered
		# produces N paths by concatenating it with each of the relative paths. If the -r list contains an empty relative path as
		# well as some relative paths (i.e. the : appears at the start or the end or :: appears in the middle) then the base path
		# will added too.
		if [ "$packageOverride" ]; then
			findInPaths ${retVar:+-R "$retVar"} ${retArray:+-A "$retArray"} $debug $allowDupes $returnRelative $listPathsFlag --no-scriptFolder "${templateNameSpec:-"*"}" \
			 	-r "${packageOverride}${packageOverride:+:}"   "$sysadminFolders"  \
				-r ""                "$thisPackageFolder"
		else
			findInPaths ${retVar:+-R "$retVar"} ${retArray:+-A "$retArray"} $debug $allowDupes $returnRelative $listPathsFlag --no-scriptFolder "${templateNameSpec:-"*"}" \
			 	-r "${localPkgName}${localPkgName:+:}"   "$sysadminFolders" \
				-r ""                "$thisPackageFolder" \
				-r "data/templates/" "${bgLibPathsAry[@]}" \
				-r ""                /usr/share/??-*/templates/
		fi
	fi
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

# usage: bgManifestOfInstalledAssets
# return a list of all the installed bash libraries and bash script commands from any script package
# project. If any virtually installed projects are detected, only virutally installed paths will be
# returned. Otherwise any found in the system pathes /usr/bin/ and /usr/lib are returned.
function bgManifestOfInstalledAssets()
{
	local awkScript outType='{printf("%s\n", $3)}'
	while [ $# -gt 0 ]; do
		awkScript+='$2=="'"$1"'" '"$outType"$'\n'
		shift
	done
	awkScript="${awkScript:-$outType}"

	local manifestFiles=()

	if [ "$bgInstalledPkgNames" ]; then
		findInPaths -R manifestFiles -d -r .bglocal/ manifest "$bgLibPath"
	else
		# TODO: the installer needs to produce an additional manifest with the filenames located in the host
		fsExpandFiles -A manifestFiles /var/lib/bg-core/*/hostmanifest
	fi

	awk '
		@include bg_core.awk
		BEGINFILE {
			prefix=gensub(/.bglocal.manifest/,"","g", FILENAME)
		}
		{if ($3!~/^\//)  $3 = prefix""$3}
		'"$awkScript"'
	' "${manifestFiles[@]:-/dev/null}"
}
