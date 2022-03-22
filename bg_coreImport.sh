
# Library bg_coreImport.sh bg_core.sh
# this is the core library script in the bg-core system. It implements the import function and uses it
# to import a standard set of bg-core libraries for the script sourcing it to use.
#
# Typically scripts so not source this library directly. Instead they do 'source /usr/lib/bg_core.sh'
# hard coding the path where to find bg_core.sh. bg_core.sh is a minimal stub that only knows how
# to search the $bgLibPath and source this bg_coreImport.sh library. The idea is that being a minimal file
# means bg_core.sh will hardly ever change so its not important for it to be sourced from vinstalled
# project folders. This library is more complex and may require ocassional improvements, bug fixs and
# debugging so it benefits being found dynamically if the bg-core's source project is virtually installed
# in the terminal.
#
# This library (or bg_core.sh) must be sourced the traditional way. But after that, all additional
# libraries should be sourced with the import statement. See man(3) import.
#
# Full and Minimal Library Sets:
# If sourced with no options passed in, bg_coreImport.sh will source most all of the libraries packaged with
# the bg-core project. This is convenient for the script author since they do not need to import a Library
# before using any function in the bg-core project but it costs about 250 ms (at the time of this writing)
# to source all the libraries at once. If the script author wants to reduce the startup time of the script
# they can pass in --minimal like
#     source /usr/lib/bg_core.sh --minimal
# This causes this library to source far fewer libraries and the author can import exactly the libraries
# with the functions that they need.
#
# Force Reloads:
# The import statement provided by this library will detect if a library has already been sourced and
# skip sourcing it again by default. In special occassions like debugging in a terminal by directly
# sourcing bg_core.sh into the terminal, it might be required to actually re-source all the libraries
# again. This can be acheived by passing the -f option like
#     source /usr/lib/bg_core.sh -f
# This will clear the _importedLibraries array so that all libraries will load again the next time they
# are  imported. Programatically, this and other things can be accomplished with the importCntr function.


#######################################################################################################################################
### Import/Sourcing and System Path Functions


# when bgImportProfilerOn is true, write library profile data to bgtrace destination
# we manually create the ImportProfiler array so that we can record the earliest start time before we have the bgtimerStart function defined
#bgImportProfilerOn="1"
if [ "$bgImportProfilerOn" ]; then
	ImportProfiler[0]="$(date +"%s%N")"
	ImportProfiler[1]="${ImportProfiler[0]}"
	ImportProfiler[2]="${_forkCnt:-0}"
	ImportProfiler[3]="${ImportProfiler[2]}"
fi


# usage: importCntr traceOn
# usage: importCntr traceOff
# usage: importCntr getRevNumber|getCount  [<retVar>]
# usage: importCntr bumpRevNumber
# usage: importCntr clearLoadedList
# usage: importCntr reloadAll
# Subcommands:
#   traceOn  : turn tracing on. each import will write a bgtrace line with the load time and the number of forks
#   traceOff : turn off tracing
#   getRevNumber <retVar> : return the number of libraries loaded.
#   bumpRevNumber : increment the context revision so that things that track library loads will know that
#               something has changed. This is done automatically if any import call results in a library
#               being sourced
#   clearLoadedList : remove all the <scriptName> entries from the imported libraries list so that
#               they will be sourced again by the next call to 'import <scriptName>'
#   reloadAll [--init] : reload (aka source again) each library that has been previously importted and whose
#               source file has changed. For efficiency and minimalism, we do not create the temp file
#               that records when the reload is relative to by default. A long lived script application
#               can call this with the --init option at its start. If --init is not called, then the
#               first time reloadAll is called will reload regardless of whether the sources changed
#               but then subsequent reloadAll calls will only reload changed librares
#   list        print a list of imported Libraries
function importCntr()
{
	declare -gA _importedLibraries
	declare -g  _importedLibrariesBumpAdj
	local cmd="$1"; shift
	case $cmd in
		traceOn)   _importedLibraries[_tracingOn]=1 ;;
		traceOff)  _importedLibraries[_tracingOn]="" ;;
		getRevNumber)  returnValue "$((${#_importedLibraries[@]} + _importedLibrariesBumpAdj))" "$1" ;;
		bumpRevNumber) ((_importedLibrariesBumpAdj++)) ;;
		clearLoadedList)
			local i; for i in "${!_importedLibraries[@]}"; do
				if [[ "$i" =~ ^lib: ]]; then
					unset _importedLibraries[$i]
					((_importedLibrariesBumpAdj++))
				fi
			done
			# 2020-10 these seems like it does nothing b/c L1 is an 'import ... ;$L2' thing, not an importCntr thing
			#[ ${_importedLibrariesBumpAdj:-0} -gt 1 ] && L1="source $(import --getPath bg_coreImport.sh)"
			;;
		reloadAll)
			declare -g _importedLibrariesTimeRefTmpFile
			local verboseFlag initFlag
			while [[ "$1" =~ ^- ]]; do case $1 in
				-v) verboseFlag="-v" ;;
				--init) initFlag="--init" ;;
			esac; shift; done

			# get the list of out-of-date libraries
			local -A _libsToReload=()
			local i; [ ! "$initFlag" ] && for i in "${!_importedLibraries[@]}"; do
				if [[ "$i" =~ ^lib: ]] && { [ ! "$_importedLibrariesTimeRefTmpFile" ] || [ "${_importedLibraries[$i]}" -nt "$_importedLibrariesTimeRefTmpFile" ]; }; then
					_libsToReload[${i#lib:}]="${_importedLibraries[$i]}"
				fi
			done

			# touch the semaphore to make everything up-to-date
			[ ! "$_importedLibrariesTimeRefTmpFile" ] && bgmktemp --will-not-release _importedLibrariesTimeRefTmpFile
			[ "$_importedLibrariesTimeRefTmpFile" ] && touch "$_importedLibrariesTimeRefTmpFile"

			# now reload the out-of-date libraries.
			for i in "${!_libsToReload[@]}"; do
				[ "$verboseFlag" ] && echo "reloading '$i'"
				source "${_libsToReload[$i]}"
				((_importedLibrariesBumpAdj++))
			done
			;;
		list)
			declare -g _importedLibrariesTimeRefTmpFile
			local i; for i in "${!_importedLibraries[@]}"; do
				printf "%s\n" "${_importedLibraries[$i]}"
			done
			;;
		*) (assertError -v cmd "unknown command")
	esac
}

# this is the function which is called in the contents of the L2 variable in the import <library> ;$L1;$L2
# its not required to source the <library> but its enables several best effort features.
function _postImportProcessing() {
	local result="$?"

	local scriptName="${_importInProgressStack[@]:0:1}"; _importInProgressStack=("${_importInProgressStack[@]:1}")

	if [ "${scriptName:0:1}" != "#" ]; then
		# support the import -e option which turns on the error stop flag just for the duration of one imported script
		if [ "${scriptName:0:3}" == "-e|" ]; then
			scriptName="${scriptName#-e|}"
			set +e -E
		fi
		#echo "_postImportProcessing stack '${#_importInProgressStack[@]}' '${_importInProgressStack[*]}'"
		if [ "${_importedLibraries[_tracingOn]}" ]; then
			bgtimerLapTrace -T ImportProfiler $scriptName
		fi

		type -t FlushPendingClassConstructions &>/dev/null && FlushPendingClassConstructions
	fi

	L1=""
	[ ${#_importInProgressStack[@]} -eq 0 ] && L2=""
	#echo "(post) L1='$L1' L2='$L2'" >>"/tmp/bgtrace.out"

	return $result
}

function _importSetErrorCode() { return 202; }

# usage: 'import [-f] <scriptName> ;$L1;$L2'
# usage: import --getPath <scriptName> [<returnVar>]
# Source a bash library. Similar to "source <scriptName>" or ". <scriptName>"
#
# Note the unusual usage syntax. The ;$L1;$L2 at the end of the line is needed to allow <scriptName> to be sourced in the global context.
# Sourcing from the context of inside a function is not quite the same for some things (a declare -g <varname> wont be truely global )
#
# There are several advantages of using import over direct sourcing.
#   * it can enforce some security constraints (use a lint in the SDLC to not allow source or . statements in accepted scripts)
#   * the author does not need to know the path of the library -- if the library is 'installed' on the host, it will find it
#   * works with bg-debugCntr vinstall'd projects
#   * it is idempotent by default, meaning that it will not source the same script multple times. This allows library scripts to
#     declare their dependancies on other libraries without having to take into account whether the script or another library has
#     already sourced that dependency.
#   * Libraries sourced with this function automatically work with system development features that will detect when a library file
#     has changed during the run of a script and selectively re-source those changed libraries.
#
# Params:
#    <scriptName> : the simple filename without path. The name is taken relative to system paths so
#                   it will only be found if <scriptName> is found under one of the system paths. It
#                   can contain a relative path under a system path.
#    ;L1;$L2      : these are not parameters but are a part of the required syntax. They are needed
#                   in order to provide features and have the script sourced in the global context
# Options:
#    -f : force sourcing. Even if the script has already been sourced into the environment, do it again.
#    -q : if the library is not found, set the exit code to 202 instead of ending the script with an assert.
#    -e : turn on 'set -e' for the duration of loading this library. Note, that shift exits non-zero if there is nothing to shift
#         so my code generally can not run with set -e on
#    --getPath : This options gives utilities the chance to lookup the path without sourcing it.
# See Also:
#    importCntr  : change settings and get the current state of imported libraries
#    findInPaths : this is a much more flexible algorithm for finding various types of installed files
function import()
{
	declare -gA _importedLibraries
	local forceFlag quietFlag getPathFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-f) forceFlag="-f" ;;
		-e) stopOnErrorFlag="-e" ;;
		-q) quietFlag="-q" ;;
		--getPath) getPathFlag="--getPath" ;;
	esac; shift; done
	local scriptName=$1

	### return quickly when the library is already loaded
	if [ ! "$forceFlag" ] && [ ! "$getPathFlag" ] && [ "${_importedLibraries[lib:$scriptName]}" ]; then
		L1=""
		L2="_postImportProcessing"
		_importInProgressStack=("#$scriptName" "${_importInProgressStack[@]}")
		return 0
	fi

	### look up the library in the system paths

	local foundScriptPath

	local manFile="/var/lib/bg-core/manifest"
	[ "$bgVinstalledManifest" ] && manFile="$bgVinstalledManifest"
	foundScriptPath="$(gawk -v scriptName="$scriptName" -i "bg_manifest.awk" '' "$manFile" )"

	if [ "$foundScriptPath" ]; then
		: echo "import found in manifest" >> "/tmp/bgtrace.out"
	else
		# SECURITY: TODO: refuse to load libraries that are not in the manifest if in productionMode
		echo "import searching paths '$scriptName'" >> "/tmp/bgtrace.out"
		# SECURITY: each place that sources a script library needs to enforce that only system paths -- not vinstalled paths are
		# searched in non-development mode
		if [ "$bgSourceOnlyUnchangable" ]; then
			local includePaths="$scriptFolder:/usr/lib"
		else
			local includePaths="$scriptFolder:${bgLibPath}:/usr/lib"
		fi

		local incPath tryPath
		local saveIFS=$IFS
		IFS=":"
		for incPath in ${includePaths}; do
			incPath="${incPath%/}"
			for tryPath in "$incPath${incPath:+/}"{,lib/,creqs/,core/,coreOnDemand/,plugins/}"$scriptName"; do
				if [ -f "$tryPath" ]; then
					foundScriptPath="$tryPath"
					break
				fi
			done
			[ "$foundScriptPath" ] && break
		done
		IFS=$saveIFS
	fi

	# if we are only asked to get the path, do that and return
	if [ "$getPathFlag" ]; then
		if [ "$2" ]; then
			printf -v "$2" "%s" "$foundScriptPath"
		else
			echo "$foundScriptPath"
		fi
		[ "$foundScriptPath" ]
		return
	fi

	### success path
	if [ "$foundScriptPath" ]; then
		# this is not the real security constraint because a user can edit a file and then make it unwritable by themselves.
		# the real constraint is limiting the search path in the block above. If there are user wrtable scripts in /usr/lib, the
		# host is already compromised
		if [ "$bgSourceOnlyUnchangable" ] && [ -w "$foundScriptPath" ]; then
			echo "error: in this host environment we can not source a writable library in a script that is not writeable by the user" >&2
			echo "   script path  = '$0'" >&2
			echo "   library path = '$foundScriptPath'" >&2
			exit 2
		fi

		L1="source $foundScriptPath"
		L2="_postImportProcessing"
		#echo "(import) L1='$L1'" >>"/tmp/bgtrace.out"
		_importInProgressStack=("${stopOnErrorFlag:+-e|}$scriptName" "${_importInProgressStack[@]}")

		# if we are reloading a lib that had already been sourced, then inc _importedLibrariesBumpAdj
		# the import state ID is the size of the _importedLibraries array plus _importedLibrariesBumpAdj
		# so if either changes other code will know that potentially new code has been added.
		# This is useful for bg_objects that maintains a cache of sourced functions that match the naming
		# convention to be considered a method of a Class. this allows the method definitions to be provided
		# by multiple library files which is typical for Class hierarchies
		[ "${_importedLibraries[lib:$scriptName]}" ] && ((_importedLibrariesBumpAdj++))
		_importedLibraries[lib:$scriptName]=$foundScriptPath
		[ "$stopOnErrorFlag" ] && set -e +E
		#echo "DOING import return '$foundScriptPath'" >>"/tmp/bgtrace.out"
		return 0
	fi


	### library not found path

	# if we are being called early in the initialization process, the real assertError might not be loaded yet so make a simple version
	type -t assertError &>/dev/null || function assertError() { printf "(early import error reporter): $*\n" >&2; exit; }

	# if $quietFlag is specified, we only return the 202 exit code, otherwise we assert an error
	# because of the unusual ;$L1;$L2 pattern, we cant just return the exit code from this function
	if [ "$quietFlag" ]; then
		L1='_importSetErrorCode'
		L2="_postImportProcessing"
		_importInProgressStack=("#$scriptName" "${_importInProgressStack[@]}")
	else
		assertError -v bgLibPath -v scriptName "bash library not found by in any system path. Default system path is '/usr/lib'"
	fi
}



#######################################################################################################################################
### Init the very early environment. This code stands alone and does not use any library functions


# process the cmd line arguments that are meant for us (source /usr/lib/bg_core.sh -f|--<bgLibDefaultLibrarySet>)
# -f means force reload of already loaded libraries
# <bgLibDefaultLibrarySet> identifies a set of libraries that will be initially sourced
bgLibDefaultLibrarySet="all"
while [ $# -gt 0 ]; do case $1 in
	-f|--force) importCntr clearLoadedList ;;
	--minimal)  bgLibDefaultLibrarySet="${1#--}" ;;
	*) break ; esac; shift
	#*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
done




# TODO: make a man(7) page to document all the global vars set by the bg-core environment that scripts and libraries can reference
# bgLibExecMode records if we are being sourced in a terminal or in a script
#      script   : normal case of a script file including source /usr/lib/bg_core.sh
#      terminal : a user typed '$ source /usr/lib/bg_core.sh'
function __getScriptExecType() { bgBASH_scriptType="${FUNCNAME[@]: -1}"; }; __getScriptExecType
case "$bgBASH_scriptType:$BASH_SUBSHELL" in
	# normal case of being sourced inside a script
	main:0)
		if [ ! "${bgLibExecMode+exists}" ]; then
			declare -rg bgLibExecMode="script"

			# record the execution cmd. This assumes that the script's 'source /usr/lib/bg_core.sh' either does not specify any parameters or
			# adds "$@" after the parameters so that the $@ of the top level scripts are preserved here
			declare -g bgLibExecCmd=("${0##*/}" "$@")

			# TODO: maybe bgLibExecSrc should be created on demand if needed so we dont need to do this block on every script.
			#        update: the new bg_coreStack.sh code wont use this so we can remove it after that transition.
			declare -g bgLibExecSrc="${0##*/}"
			for _inint_i in "$@"; do
				if [[ "$_inint_i" =~ [[:space:]] ]]; then
					bgLibExecSrc+=" '$_inint_i'"
				else
					bgLibExecSrc+=" $_inint_i"
				fi
			done
			unset _inint_i

			declare -g scriptFolder="${0%/*}"
		fi
		;;

	# case where we are being sourced in a terminal directly by the user
	# this is typically done for debugging and development so we setup up some things to make that
	# a better experience.
	source:0)
		if [ ! "${bgLibExecMode+exists}" ]; then
			declare -rg bgLibExecMode="terminal"

			declare -g bgLibExecCmd=("${0##*/}" "$@")
			declare -g bgLibExecSrc; read -r bgLibExecSrc bgLibExecSrc < <(history 1)
			declare -g scriptFolder="$PWD"
		fi
		;;

	# case where a script that sources us is being sourced in a terminal directly by the user
	# this is the case that "source bg-debugCntr" trips
	source:*)
		if [ ! "${bgLibExecMode+exists}" ]; then
			declare -g bgLibExecMode="terminal"

			scrdFile="${BASH_SOURCE[@]: -1}"
			declare -g bgLibExecCmd=("source:${scrdFile##*/}" "$@")
			declare -g bgLibExecSrc; read -r bgLibExecSrc bgLibExecSrc < <(history 1)
			declare -g scriptFolder="${scrdFile%/*}"
			unset scrdFile
		fi
		;;

	# case where the user invokes "bg-debugCntr sourceCore" as a shortcut to source the libraries into the debug terminal.
	bg-debugCntr:0)
		if [ ! "${bgLibExecMode+exists}" ]; then
			declare -g bgLibExecMode="terminal"

			scrdFile="${BASH_SOURCE[@]: -1}"
			declare -g bgLibExecCmd=("source:${scrdFile##*/}" "$@")
			declare -g bgLibExecSrc; read -r bgLibExecSrc bgLibExecSrc < <(history 1)
			declare -g scriptFolder="${scrdFile%/*}"
			unset scrdFile
		fi
		;;

esac


#######################################################################################################################################
### Include the mandatory libraries that define the minimum environment that code can rely on

# bg_coreBashVars.sh provides functions that support patterns of variable use in bash
import bg_coreBashVars.sh ;$L1;$L2

# string manipulation functions
import bg_coreStrings.sh ;$L1;$L2

# bg_libCore.sh contains the core functions from other libraries that should be present even if the whole library is not.
# Also, any function that is used in other bg_core* libraries can be moved to this library so that these functions are available
# regardless of what order the rest of the bg_core* librares are sourced
import bg_coreLibsMisc.sh ;$L1;$L2

# bg_libSysRuntime.sh works with the OS system paths to allow discovery of other installed components (plugins, templates, etc..)
import bg_coreSysRuntime.sh ;$L1;$L2

# bg_coreDebug.sh conditionally includes the bg_debugTracing.sh and bg_debugger.sh libraries based on if the terminal is
# configured to activate them and if not it creates stubs for bgtrace* commands that turn them into noops.
import bg_coreDebug.sh ;$L1;$L2

# we could probably drop bg_coreProcCntrl.sh from the required libraries with some light organization
import bg_coreProcCntrl.sh ;$L1;$L2

# bg_coreAssertError.sh is some general purpose assert* functions. The core error handling functions are donated to bg_libCore.sh
import bg_coreAssertError.sh ;$L1;$L2

# we could probably drop bg_coreFiles.sh from the required libraries with some light organization
import bg_coreFiles.sh ;$L1;$L2

# work with semmantic versions so that we can support conditional code on the versions of deps in the envoronment
import bg_coreSemVer.sh ;$L1;$L2
import bg_coreLSBVersions.sh ;$L1;$L2

# these functions should probably be somewhere else but its not yet clear where. Some could be pruned from the required runtime
import bg_coreMisc.sh ;$L1;$L2

# used when an exception is thrown and debugger. Could be easily made on-demand
import bg_coreStack.sh ;$L1;$L2


# if we are being sourced in a terminal, tell importCntr to record the timestamp used to tell if libraries are newer
# and also import the bgtrace functions assuming that we are being sourced to debug stuff
if [ "$bgLibExecMode" == "terminal" ]; then
	import bg_debugTrace.sh ;$L1;$L2
	importCntr reloadAll --init
fi


#######################################################################################################################################
### End of sourcing essential code. The script may continue to source optional libraries. Typically, when the script calls
#   invokeOutOfBandSystem, it signals that its initialization is over. If import profiling is called for, we start it here and
#   end it in invokeOutOfBandSystem.

# Typically each library will take from 0.004 to 0.040 to load with the average being around 0.012
if [ "$bgImportProfilerOn" ]; then
	import bg_debugTrace.sh ;$L1;$L2
	importCntr traceOn
	bgtimerLapTrace -T ImportProfiler "bg-core loaded mandatory core libraries"
fi

# This block moved to the invokeOutOfBandSystem function
# if [ "$bgImportProfilerOn" ]; then
# 	bgtimerTrace -T ImportProfiler "bg-core finished includes"
# fi
