
# Library bg_coreLibsMisc.sh
# All the libraries that start with bg_core* are mandatory and are sourced by 'source /usr/lib/bg_core.sh'. Other libraries can be
# optionally sourced by scripts with the 'import <libname> ;$L1;$L2' syntax as needed.
#
# This library contains functions that are logically a part of optional libraries but are moved here because they should be available
# unconditionally even when the rest of their logically grouped library has not been sourced. Each library can be thought of as having
# mandatory and optional parts. The mandatory parts go here and the optional parts live in the library file.
#
# In addition to mandatory/optional consideration, this file resolves issues of sourcing order. If two mandatory libraries have
# global initialization code that use functions from each other, those functions can be placed in this file so that they all will
# be available to the initialization code regaurdless of which library is sourced first.
#
# This library is organized in sections named after the libraries where the functions in that section are logically
# associated. If it were not for the fact that these functions are mandatory and possibly used by library initialization code,
# these functions would reside in that library.
#



#######################################################################################################################################
### From bg_manifest.sh

# usage: manifestGet [-p|--pkg=<pkgMatch>] [-o|--output='$n'] <assetTypeMatch> <assetNameMatch>
# query the host manifest file for assets installed on the host from any pkg that participates in the bg-core asset management
# system.
#
# awkDataQuery (and bg-awkData) can be used to query the manifest instead of this function, however, this function has no dependencies
# and be called in bootstrap code where the awdData tools are not available. A manifest.awkDataSchema is provided in bg_core so that
# the awkData system knows about the manifest file.
#
# Manifest File Format:
# The manifest file complies with man(5) bgawkDataFileFormat.
# ### Columns
#    * pkg       : the package name that installs the asset on the host
#    * assetType : the type of asset. By convention '.' separates logical parts of the type. e.g. lib.script.bash is a library asset
#                  which is a script (as opposed to a binary) and written in the bash language. The first part is the primary type
#                  of the asset and then subsequent parts qualify it into sub types.
#    * assetName : the name of the asset is typically unique within its assetType within the domain of packages but dependign on
#                  the asset type, it does not necessarily need to to be.
#    * path      : the installed path of the asset. assets are typically files but can be folders in some cases. The path must be
#                  unique within all packages in a repository.
#
# Compliant Packages:
# If a package installs its manifest in /var/lib/bg-core/<packagename>/hostmanifest, the next time manifestUpdateInstalledManifest
# runs, it will combine that file into a combined /var/lib/bg-core/manifest file. Packages built with the bg-dev tool will
# have this functionality and will call the manifestUpdateInstalledManifest function in the package's postinst script.
#
# Params:
#    <assetTypeMatch> : a regex(gawk) expression to match the assetType field. Default is '' which matches nothing so this parameter must
#                       be specified to get any results. use '.*' to match all assetTypes
#    <assetName>      :  a regex(gawk) expression to match the assetName field. Default is '' which matches nothing so this parameter must
#                       be specified to get any results. use '.*' to match all assetNames
#
# Options:
#    -p|--pkg|--pkgName=<pkgMatch>   : specify a regex(gawk) to match the pkg field. '.*' is the default
#    -o|--output=<outStr>  : specify what is returned for each matching asset record. default is '$0'. This can use the the terms
#                            $1,$2,$3,$4 to refer to the columns of the manifest file respectively. $0 is all colums.
#    --manifest=<file>     : override the path of the manifest file to use.
function manifestGet() {
	local manifestFile
	local pkgMatch=".*" outputStr='$0'
	while [ $# -gt 0 ]; do case $1 in
		-p*|--pkg*|--pkgName*) bgOptionGetOpt val: pkgMatch "$@" && shift ;;
		-o*|--output*) bgOptionGetOpt val: outputStr "$@" && shift ;;
		--manifest*)  bgOptionGetOpt val: manifestFile "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local assetTypeMatch="$1"
	local assetNameMatch="$2"
	[ ! "$manifestFile" ] && manifestGetHostManifest manifestFile

	gawk --sandbox  -v assetTypeMatch="$assetTypeMatch"  -v assetNameMatch="$assetNameMatch" -v pkgMatch="$pkgMatch" '
		$1~"^"pkgMatch"$" && $2~"^"assetTypeMatch"$" && $3~"^"assetNameMatch"$" {print '"$outputStr"'}
	' $manifestFile
}

declare -gx manifestInstalledPath="/var/lib/bg-core/manifest"
declare -gx pluginManifestInstalledPath="/var/lib/bg-core/pluginManifest"

# usage: manifestGetHostManifest
# returns the file path to the prevailing host manifest file. In production this would be "$manifestInstalledPath"
# but vinstalling a sandbox overrides it
function manifestGetHostManifest() {
	if [ "$bgHostProductionMode" == "development" ]; then
		returnValue "${bgVinstalledManifest:-$manifestInstalledPath}" $1
	else
		returnValue "$manifestInstalledPath" $1
	fi
}

# usage: manifestGetHostPluginManifest
# returns the file path to the prevailing host plugin manifest file. In production this would be "$pluginManifestInstalledPath"
# but vinstalling a sandbox overrides it
function manifestGetHostPluginManifest() {
	if [ "$bgHostProductionMode" == "development" ]; then
		returnValue "${bgVinstalledPluginManifest:-$pluginManifestInstalledPath}" $1
	else
		returnValue "$pluginManifestInstalledPath" $1
	fi
}


#######################################################################################################################################
### From bg_outOfBandScriptFeatures.sh

# usage: bgOptionsEndLoop [--firstParam <firstParamVar>] [--eatUnknown] "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"
# usage: see example code below. This is part of an argument parsing pattern
# See man(7) bgBashIdioms for a description of the larger idiom that this function is a part of.
# this supports a pattern of command line parsing that handles all the common option conventions
#    * single letter flags (-a -b ...)
#    * long form options (--my-bFlag) which may or may not have single letter alias
#    * single letter options with arguments (-u<user>)
#    * long form options with arguments with optional = (--user=<user> or --user <user>)
#    * arguments can be with the option (-u<user>) or separate (-u <user>)
#    * options can be combined (-ab == -a -b)
#    * at most one option with an argument can be combined with others and it must be last (-abu<user> or -abu <user>)
# This function assumes that it is called form the standard options processing loop (see Example Code below).
# This means that if "$1" looks like an option it means the the script author did not include a case statement match
# for it therefore it is not a valid option.
#     -<singleCharacter> : there is no other way to interpret this so it must be an option that the author did not
#                       support so its is an unknowOption and will be ignored or assertError dependending on --eatUnknown
#     -<multipleCharacters> : because this was not matched by one of the author cases, this can not be an option with an argument
#                       so we assume that its a set of options combined into one token. We extract the first one into its own
#                       position and leave the rest for futher processing later. If this assumption is not true, the next
#                       loop will process the new option token as an unknown option.
#      --<characters> : because this was not matched by one of the author cases, it can not be a valid long option
#                       so process it as an unknownOption
# Options:
#    --firstParam <firstParamVar> : this signifies that the first positional argument will also be consumed in
#         the options processing loop and its value will be set in <firstParamVar>. The calling scope should declare
#         <firstParamVar> but not assign it. The loop can tell if the variable has been assigned and that is how it
#         tells the difference between the first and subsequent positional arguments that it encounters.
#    --eatUnknown : silently ignore unknown options. without this opotion an error is asserted
# On Complexity and Convention:
# the one disavantage of this pattern is that the defalt case line is very complex and the formatting is
# unconventional. The formatting is conconventional so that the script author who uses the pattern can think of
# this block of code as a line that starts the section, and a line thta ends the section, with their lines inbetween.
# This relagates most of the complexity to that one boiler plate line at the end of the section. The function/script
# author does not touch the preamble line and postamble line(s) (the postamble is two lines so that the 'done' complements
# the while in a more conventional indenting).
#
# The pre and post-amble lines should be copy and pasted from the example below or set by a smart editor.
#
# The code that each function/script author needs to write and maintain are only the case matches for each option
# The pattern to handle options with argument is a lttle complex but it too can be treated as a programming idiom
# which is copied and pasted or set by a smart editor. It not so complex so most bash programmers should be able to
# understand it if they want, but once understood, it can be treated as an idiom.
#The bgOptionGetOpt function extracts the argument value and returns whether the value is in a separate "$@" postion
# that needs to be consumed. There is a standard convention to process options but really, the cases can contain any
# code with the only requirement being that if the option has a value in the "$2" position, shift must be called so
# that it gets consumed.
#     without arg:  -<letter>)  myArg="-<letter>" ;;
#     with arg:     -<letter>*) bgOptionGetOpt val: myArg "$@" && shift ;;
# Example Code:
#    # standard pattern is that first positional param (not -* and not the arg of a -* option) stops the loop.
#    local myAFlag myBFlag myCOptWithArg myDFlag
#    while [ $# -gt 0 ]; do case $1 in
#        -a)  myAFlag="-a" ;;
#        -b | --my-bFlag) myBFlag="-b" ;;
#        -c*) bgOptionGetOpt val: myCOptWithArg "$@" && shift ;;
#        -T*) bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
#        -t)  bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
#        -d)  myDFlag="-d" ;;
#         *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
#     done
#
#    # alternate, nested subCmd pattern where the first positional param is also set and consumed by the loop
#    # This is useful in sub cmd type commands (like bg-git) where options may appear after the first positional param
#    local gitFolder myAFlag myBFlag myCOptWithArg myDFlag
#    while [ $# -gt 0 ]; do case $1 in
#        -a)  myAFlag="-a" ;;
#        -b | --my-bFlag) myBFlag="-b" ;;
#        -c*) bgOptionGetOpt val: myCOptWithArg "$@" && shift ;;
#        -T*) bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
#        -t)  bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
#        -d)  myDFlag="-d" ;;
#         *)  bgOptionsEndLoop --firstParam gitFolder "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
#    done
# See Also:
#    man(7) bgBashIdioms
function bgOptionsEndLoop()
{
	# this block supports functions like bgOptions_DoOutputVarOpts which bundle the handling of multiple options into one option line
	if [ "$bgOptionHandled" ]; then
		bgOptionsExpandedOpts=("$@")
		bgOptionHandled=""
		return 1
	fi

	# extract our options.
	# Note that these do NOT conflict with the script author's options b/c if a case statement exists for
	# one of these and its in the next position that case will match instead of the default case.
	local firstParamVar eatUnknown
	if [ "$1" == "--firstParam" ]; then
		firstParamVar="$2"
		shift 2
	fi
	if [ "$1" == "--eatUnknown" ]; then
		eatUnknown="yes"
		shift
	fi

	# A typical options loop has a case statement for each option that it recognizes so if bgOptionsEndLoop gets called when the
	# next argument looks like a token, it means that the option loop did not recognize it.
	# The bgOptionsOnUnknown and bgOptionsOnUnknownDefault functions handle options that the caller's loop does not. If they do not
	# recognize it, the default bahavior is to throw the unrecognized option exception. The --eatUnknown option changes that to
	# suppress the exception and silently ignore unknown options

	# -- means stop option processing
	# WARNING: this does not work b/c the options loops have been written to only set -- "${bgOptionsExpandedOpts[@]}" when "return 1"
	#          if we change that idiom we can take advantage of this. In the meantime, each loop needs to support --) shift; break ;;
	#          if they need it.
	if [ "$1" == "--" ]; then
		bgOptionsExpandedOpts=("$@:1")
		return 0

	# short and long options ... (e.g. -f or --file*)
	elif [[ "$1" =~ ^[+-].?$ ]] || [[ "$1" =~ ^(--[^-]|\+\+[^+]) ]]; then
		bgOptionsExpandedOpts=("$@")
		local result=1
		if [ "$(type -t bgOptionsOnUnknown)" == "function" ]; then
			bgOptionsOnUnknown "$@"; result="$?"
			[ ${result:-0} -eq 0 ] && return 1
		fi
		[ ${result:-0} -eq 1 ] && bgOptionsOnUnknownDefault "$@" && return 1
		[ ! "$eatUnknown" ] && assertError --frameOffset=2 "unknown option '$1'"

	# maybe its a set of combined options so split of the first one. Note we know that the fist one
	# is not an option with an argument because the scripts author's cases would have matched it.
	# we do not know if the second one has an option or not so we can only separate that first one
	# and let subsequent iterations deal with the rest
	elif [[ "$1" =~ ^[+-][^+-][^+-] ]]; then
		local first="$1"; shift
		# the calling loop will shift the next token so add a "" in front
		bgOptionsExpandedOpts=("" "${first:0:2}" "-${first:2}" "$@")

	# this is the block that recognizes only the first positional argument if that option is in effect
	elif [ "$firstParamVar" ] && [ ! "${!firstParamVar+isset}" ]; then
		setReturnValue $firstParamVar "$1"
		# the calling loop will shift "$1" for us
		bgOptionsExpandedOpts=("$@")

	# if we get here, "$1" does not look like something the options loop should process so
	# return 0(true, end loop)
	# to signal that the loop should end.
	else
		return 0
	fi

	# ensure that all the other cases return 1(false, do not end loop) to keep looping
	return 1
}

# usage: bgOptionsOnUnknownDefault "$@"
# this is called by bgOptionsEndLoop when the caller's case statement does not handle an option token. The user can override this
# by defining the function bgOptionsOnUnknown() which will be called instead of this if it exists.
# Default Global Options:
# These are the global options that are recognized by default.
#    verbosity
#    Only if a variable named 'verbosity' exists, these options will be processed.
#    A function that supports verbosity should typically define it locally like this so that changes only affect that function call.
#    local verbosity="$verbosity"
#       -q|--quiet)   ((verbosity--)); return 0 ;;
#       -v|--verbose) ((verbosity++)); return 0 ;;
#       --verbosity*) bgOptionGetOpt val: verbosity "$@" && bgOptionsExpandedOpts=("" "${@:2}"); return 0 ;;
# bgOptionsOnUnknown:
#    The script author can define the bgOptionsOnUnknown() function in order to change the behaior for unrecognized options.
#    The function should examine "$1" which will be a token starting with '-' and if it recognizes it, process the option and return
#    0(true). If it does not recognize and process the option it can either return 1 to indicate that bgOptionsOnUnknownDefault should
#    get a shot at recognizing the default global options or 2 to indicate that the standard unknown option exception should be raised.
#    If the recognized option consumes the $2 argument, it should set bgOptionsExpandedOpts=("" "${@:2}")
# Params:
#    "$@" are the remaining cmdline arguments. $1 is a token that starts with '-' that this function determined if it recognizes.
#    This function can consume $2 by setting bgOptionsExpandedOpts=("" "${@:2}")
# Return Value:
#    0(true) : the option was recognized and processed
#    1(false): the option was not recognized, try the default global options next
#    2(false): the option was not recognized, do not perform default global options. assert unknown option
#    bgOptionsExpandedOpts  : if it consumes additional tokens, it sets this variable to the remaining tokens (plus one leading token
#             that will be shifted automatically by the calling loop)
function bgOptionsOnUnknownDefault()
{
	# if a variable 'verbosity' has been defined in the script, recognize these options
	# A function that supports verbosity should define it locally, optionally initializing it to the value above it like...
	#    local verbosity="$verbosity"
	if [ "${verbosity+exists}" ]; then
		case $1 in
			-q|--quiet)   ((verbosity--)); return 0 ;;
			-v|--verbose) ((verbosity++)); return 0 ;;
			--verbosity*)
				bgOptionGetOpt val: verbosity "$@" && bgOptionsExpandedOpts=("" "${@:2}")
				return 0
				;;
		esac
	fi
	return 1
}

# usage: bgOptions_DoVerbosityOptions <retVar> <cmdLine...>
# this is used in the bgOptionsLoop of a function that accepts options for verbosity
#
# Note that the verbosity options are recognized in the default options handler function if you define a variable named 'verbosity'
# so you only have to use this function is you need to use a different name
#
# Example:
#    function foo() {
#       local myVerbosity
#       while [ $# -gt 0 ]; do case $1 in
#           *)  bgOptions_DoVerbosityOptions myVerbosity "$@" && shift ;;&
#           *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
#       done
#       [ ${verbosity:-0} -gt 1 ] && echo "hi there"
#    }
#
# Options:
# These options will be supportted by a function that uses this pattern.
#    --verbosity*=<level>  : set the verbosity to a specific number
#    -v                   : decrement verbosity
#    -q                   : increment verbosity
# See Also:
#     man(3) bgOptionsOnUnknownDefault
function bgOptions_DoVerbosityOptions()
{
	local _do_retVar="$1"; shift
	case "$1" in
		--verbosity) bgOptionHandled="1"; bgOptionGetOpt val: "$_do_retVar" "$@" && return 0 ;;
		-v)          bgOptionHandled="1"; (( $_do_retVar++ )) ;;
		-q)          bgOptionHandled="1"; (( $_do_retVar-- )) ;;
		*) return 1 ;;
	esac
}


# usage: bgOptionGetOpt val[:]|opt[:]|valArray: <varName> <cmd line ...>
# usage: bgOptionGetOpt val myoptionName "$@" && shift
# See man(7) bgBashIdioms for a description of the larger idiom that this function is a part of.
# This is part of a pattern for command line argument parsing. See bgOptionsEndLoop.
# This function returns the next option by setting it into the <varName> parameter and returns 0(true)
# if the caller should call an extra shift to consume two $@ positions in this loop iteration or
# 1(false) to indicate that it should not call an extra shift so that the iteration consumes just one.
# The first parameter passed to this function determines whether the option requires an argument and
# how the option is returned.
# Supported Option Syntax:
# When an option requires an argument, the argument can be combined with the option or it can
# be in a separate position.
#    -v             : no argument, single letter
#    --verbose      : no argument, long form
#    -u <user>      : argument,    single letter, two tokens
#    -u<user>       : argument,    single letter, combined in one token
#    --user <user>  : argument,    long form,     two tokens
#    --user=<user>  : argument,    long form,     combined in one token
#
# Parameters:
#     val[:] : return just the value of the argument into <varName>. If it ends in a : the option
#              has a required argument. If it does not have an argument, then the option itself is its value
#     opt[:] : return the option and its argument if any, in one token into the next array position
#              of <varName>. If it ends in a : the option has a required argument.
#     valArray: return only the value but return it into the next array element of the <varName>
#
# Note that the colon(:) convention to denote that an optional argument has a required argumentn is taken from the linux/bash
# getopts function which was traditionally used to process optional arguments.
#
# Exit Code:
#       0(true) : the argument was extracted from $2 and the caller needs to call shift to consume $2
#       1(false): the argument was extracted from $1 so the caller does not need to call an extra shift
#
# Example Code:
#    local myAFlag user
#    while [ $# -gt 0 ]; do case $1 in
#        -a)  myAFlag="-a" ;;
#        -u* | --user*) bgOptionGetOpt val: user "$@" && shift ;;
#        -v)  bgOptionGetOpt  opt  passThruOpts "$@" && shift ;;
#        -f*) bgOptionGetOpt  opt: passThruOpts "$@" && shift ;;
#         *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
#     done
#
# See Also:
#   bgOptionsEndLoop
#   man(7) bgBashIdioms
function bgOptionGetOpt()
{
	local _oga_type="${1}"; shift
	local _oga_varNameVar="${1}"; shift
	[ ! "$1" ] && assertError 'called incorrectly. should be: bgOptionGetOpt val: user "$@" && shift'

	case $_oga_type in
		opt) # return the option w/o arg into the next array position
			arrayAdd "$_oga_varNameVar" "$1"
			return 1
			;;
		opt:) # return the option with arg into the next array position
			# handle --long-opt=<value>
			if [[ "$1" =~ ^(--|\+\+).*= ]]; then
				arrayAdd "$_oga_varNameVar" "$1"
				return 1
			# handle "-o <value>"
			elif [[ "$1" =~ ^[+-].$ ]]; then
				arrayAdd "$_oga_varNameVar" "${1}${2:---}"
				return 0
			# handle "--long-opt <value>"
			elif [[ "$1" =~ ^(--|\+\+) ]]; then
				arrayAdd "$_oga_varNameVar" "${1}=${2}"
				return 0
			# handle "-o<value>"
			else
				arrayAdd "$_oga_varNameVar" "${1}"
				return 1
			fi
			;;
		val) # the value of options w/o arg is the option istelf or "" if the option uses + instead of -
			if [[ "$1" =~ ^- ]]; then
				returnValue "$1" "$_oga_varNameVar"
			else
				returnValue "" "$_oga_varNameVar"
			fi
			return 1
			;;
		val:) # return the option arg as its value
			# handle --long-opt=<value>
			if [[ "$1" =~ ^(--|\+\+)[^=]*= ]]; then
				returnValue "${1#${BASH_REMATCH[0]}}" "$_oga_varNameVar"
				return 1
			# handle "-o <value>"
			elif [[ "$1" =~ ^[+-].$ ]]; then
				[[ "$2" =~ ^- ]] && assertError "options loop error. It seems that the option for '$1' is missing the '*'. Should it be '$1*) ...'?"
				returnValue "$2" "$_oga_varNameVar"
				return 0
			# handle  "--long-opt <value>"
			elif [[ "$1" =~ ^(--|\+\+) ]]; then
				returnValue "$2" "$_oga_varNameVar"
				return 0
			# handle  "-o--". when passing through via opt:  -o "" becomes -o-- so now is the time to put it back
		elif [[ "$1" =~ ^[+-].-- ]]; then
				returnValue "" "$_oga_varNameVar"
				return 1
			# handle "-o<value>"
			else
				returnValue "${1:2}" "$_oga_varNameVar"
				return 1
			fi
			;;
		valArray:) # return the option arg as its value treating _oga_varNameVar as an array
			# handle --long-opt=<value>
			if [[ "$1" =~ ^--.*= ]]; then
				arrayAdd "$_oga_varNameVar" "${1#${BASH_REMATCH[0]}}"
				return 1
			# handle "-o <value>" and "--long-opt <value>"
			elif [[ "$1" =~ ^-.$ ]] || [[ "$1" =~ ^-- ]]; then
				arrayAdd "$_oga_varNameVar" "$2"
				return 0
			# handle  "-o--". when passing through via opt:  -o "" becomes -o-- so now is the time to put it back
		elif [[ "$1" =~ ^[+-].-- ]]; then
				arrayAdd "$_oga_varNameVar" ""
				return 1
			# handle "-o<value>"
			else
				arrayAdd "$_oga_varNameVar" "${1:2}"
				return 1
			fi
			;;
		*) assertError "called incorrectly. first paramter should be one of opt|opt:|val|val: but got '$_oga_type'"
	esac
}






# usage: invokeOutOfBandSystem "$@"
# Scripts authors can add this function call to support some automatic out-of-band features
# like -h* help processing bash command line completion.
#  Supported Mechanisms:
#   * Bash Completion:
#   * Help Processing:
#   * bg-debugCntr reminder Banner:
#   * Sudo Enforcement:
#   * Umask Setting:
# Bash Completion:
# Srcipt authors can provide BC suggestions from inside their script. This promotes including BC support
# from the start of developing the script since its all in one place and its convenient to have BC
# to test the script. Developing scripts like this turns BC into a kind of command line UI where the
# script author can provide interactive feed back about what information is expected from the user and
# the current state of the command line up to that point.
#  Script Author Callbacks:
#    oob_printBashCompletion()    -- return BC suggestions
#  See also man(3) _bgbc-complete-viaCmdDelegation
#  See also man(7) oob_printBashCompletion
#
# Sudo Enforcement:
# The script author can declare that it must be ran as a root or as the loguser or as any arbitrary user
# and group. The script will transparently use sudo to change to the required user and it will fail and
# refuse to run if the user does not have the required sudo permission
#  Script Author Callbacks:
#    oob_getRequiredUserAndGroup()	 -- return the user and group that the command needs to run as.
#        The command line arguments are passed to this function in the same manner as the oob_printOptBashCompletion
#        callback so the they can be inspected to decide what priviledge is required for the particulare
#        operation being invoked.
#
# Help Processing:
# Script authors can provide out-of-band help (-h) processing. The default is to invoke the script's
# man(1) page by the same name as the script command and exit the script. The script author can define
# the oob_helpMode() callback function to customize this. For example a command with sub commands like
# git could invoke the man page for the specific subcommand. This is particularly compelling when combined
# with the funcman feature to automatically create man(3) pages from shell library functions. When the
# oob_helpMode callback is defined the -h option is detected
#  Script Author Callbacks:
#    oob_helpMode() -- respond to -h for example open the appropriate man page give the command line
#    oob_helpMode_endOfLineOption="off" :
#
# Umask Setting:
# The invokeOutOfBandSystem currently sets the group read/write bits in te umask so that any files created
# during the script run will be accesible to the group. This is a common pattern on a domain server.
# There is no script author control at this point. A oob_requiredUmask() callback could be added.
# Trace Check Banner:
# If bgtrace (see man(1) bg-debugCntr) is turned on in the users environment a one line banner is written
# to stderr when the script starts to remind the user. bg-debugCntr can turn that off for the session
# if that is a problem.
#
# Daemon Scripts:
# When a script calls daemonDeclare before invokeOutOfBandSystem, it will operate as a daemon script
# This means that invokeOutOfBandSystem will process status,start,stop,restart,reload, and auto start
# commands and various options. The script body after invokeOutOfBandSystem is typically a continuous
# loop. The script can be invoked directly using stdout with the -F option. It can be started from the
# terminal or it can be installed as a registered systemd,upstart, or svs-V daemon that is auto started
# and managed by one of those systems
#  Script Author Interface and Callbacks:
#     daemonDeclare "$@"  -- calling this before invokeOutOfBandSystem makes the script a daemon.
#     oob_daemonCntr()    -- if defined, the script can augment the standard daemon commands like status
# See Also:
#    bg-sp-addCommand -t sh-<tye> <newCmdName>
#    daemonDeclare
#    daemonInvokeOutOfBandSystem
function invokeOutOfBandSystem() { oob_invokeOutOfBandSystem "$@"; }
function oob_invokeOutOfBandSystem()
{
	# this is the end block from the end of bg_coreImport.sh. When a script calls invokeOutOfBandSystem, it marks the end of initialization
	if [ "$bgImportProfilerOn" ]; then
		bgtimerTrace -T ImportProfiler "bg-lib finished includes"
	fi

	if [[ "$1" =~ ^-h ]]; then
		import bg_outOfBandScriptFeatures.sh ;$L1;$L2
		[ "${daemonDefaultStartLevels+isset}" ] && import bg_coreDaemon.sh ;$L1;$L2

		local cmd="$(basename $0)"
		local cmdFolder="$(dirname $0)"
		local oobOpt="$1"; shift
		case $oobOpt in
			-hb|-hbOOBCompGen)
				local -A _bgbcData=(); arrayFromString _bgbcData "$_bgbcDataStr"
				local -A options=()
				local words=() cword=0 opt="" cur="" prev="" optWords=() posWords=() posCwords=0
				[ "${daemonDefaultStartLevels+isset}" ] && [ "$(type -t daemon_oob_printBashCompletion)" ] && daemon_oob_printBashCompletion "$@"
				local oobFn found; for oobFn in oob_printBashCompletion printBashCompletion; do
					[ "$(type -t "$oobFn")" ] && { "$oobFn" "$@"; found=1; break; }
					# if [ "$(type -t "$oobFn")" ]; then
					# 	"$oobFn" "$@"
					# 	found=1
					# 	break
					# fi
				done
				[ ! "$found" ] && oob_printBashCompletionDefault "$@"
				;;

			-he)
				if [ ! -f $cmdFolder/.$cmd ]; then
					sudo cp $0 $cmdFolder/.$cmd
				fi
				sudo ${EDITOR:-editor} $0
				echo "use -hd to see diffs. -hd -p to make a patch file"
				;;
			-hv) less $0 ;;
			-hd) [ -f $cmdFolder/.$cmd ] && $(getUserCmpApp) "$@" $0 $cmdFolder/.$cmd ;;

			*)  [ "${helpMode+exists}" ]      && { helpMode="-h"; return; }
				[ "$(type -t oob_helpMode)" ] && { oob_helpMode  "$@"; bgExit; }
				man $(basename $0)  ;;
		esac
		bgExit
	fi

	# if the calling script is a daemon script, redirect some of the callback function names
	local userGroupCB="oob_getRequiredUserAndGroup"
	if [ "${daemonDefaultStartLevels+isset}" ]; then
		import bg_coreDaemon.sh ;$L1;$L2
		userGroupCB="daemon_oob_getRequiredUserAndGroup"
	fi


	# if the command script defines the helpMode variable, we pass control to it to handle help and
	# we allow putting the -h at the end of the line as well as at the start of the argumets to make
	# it easier for users to get help on a sub command by tacking a -h at the end. Typically the script
	# will identify the bash function that it would call and then call its man(3) page. This way the
	# user does not need to know how to map the command line to the bash functions they wrap. This is
	# only right for sub command style command scripts that wrap functions in their corresponding library.
	[ "${helpMode+exists}" ]      && [ "${!#}" == "-h" ] && { helpMode="-h"; return; }
	[ "$(type -t oob_helpMode)" ] && [ "${!#}" == "-h" ] && { import bg_outOfBandScriptFeatures.sh ;$L1;$L2; oob_helpMode "$@"; bgExit; }

	# The oob_getRequiredUserAndGroup optional call back function lets the script author
	# tell us which user and group this command should b run as. The group is typically
	# static in the config file and the group check is not for security but rather for
	# convenience to make any files created by the script have the right group owner.
	# The user is typically "root" or "". If its "root" this code will re-run as with
	# sudo.
	# on what parameters are being specified on the command line,
	# give the daemon control code a chance to process
	if [ "$(type -t "$userGroupCB")" ]; then
		import bg_outOfBandScriptFeatures.sh ;$L1;$L2

		declare -A options=()
		local userAndGroup="$($userGroupCB "$@")"
		local reqUser="${userAndGroup%%:*}"
		local reqGroup; [[ ! "$userAndGroup" =~ : ]] && reqGroup="${userAndGroup##*:}"

		local user="$(id -un)"

		if [ "$reqUser" == "notRoot" ] && [ "$user" == "root" ]; then
			confirm "\nwarning: You are root but the author of this command intended it to be ran as regular users. \nDo you want to continue anyway?" >&2 || bgExit 5
			reqUser=""
		fi

		# if the user needs to change, this block will re-invoke this cmd with sudo and not return
		if [ "$reqUser" ] && [ "$reqUser" != "$user" ]; then
			local sudoOpts=()
			# -E allows sudo to not reset the environment. For development its OK to do that. Note that on a production machine
			# the sudo policy should prohibit it so if we did add the -E option here, the sudo $0 execution below would fail.
			[ "$bgDevModeUnsecureAllowed" ] && [ "$bgVinstalledPaths$bgTracingOn" ] && sudoOpts+=("-E"  "PATH=$PATH")

			sudoOpts+=(-u "$reqUser")

			# when elevating to root, keep set the group to our user's default group so that we can preserve group permission
			# strategies
			# SECURITY: is there any vulnerability in running user root with a different group?
			[ "$reqUser" == "root" ] && reqGroup="${reqGroup:-$(id -gn)}"

			# even though setting the group to the default group for the user should do no harm, some sudo policies wont allow an
			# explicit group setting even though it would not change the result so we suppress setting the group in this case
			local defaultGroup="$(id -gn "$reqUser")"
			[ "$reqGroup" == "$defaultGroup" ] && reqGroup=""

			[ "$reqGroup" ] && sudoOpts+=(-g "$reqGroup")

			exec sudo "${sudoOpts[@]}" $0 "$@"
			bgExit
		fi

		# this block is the case where only the group needs to change. If the user is changing also, the previous block will
		# use sudo to change both the user and group and will go down that path without ever getting here.
		local group="$(id -gn)"
		if [ "$reqGroup" ] && [ "$reqGroup" != "$group" ]; then
			groups="$(id -Gn)"
			if [ " $groups " == \ $reqGroup\  ]; then
				sg $reqGroup $0 "$@"
				bgExit
			else
				echo "error: this command requires being run by a user that is in " >&2
				echo "       the group '$reqGroup' but you are not in that group " >&2
				bgExit 5
			fi
		fi
	fi

	# set the umask according to our policy
	# TODO: this was added to make scripts that write files to a domFolder observe the access policy
	#       that users in the same group that owns the domFolder can read and write to it. The group
	#       owndership policy that all the files and folders are owned by a particular group is well
	#       supported by setting the SETGID bit on the top domFolder which propagates down correctly.
	#       But, if the users umask is 0022 (read-only group and read-only world), the group can read
	#       but not write those new files. This code currently is unconditional and makes it so that
	#       any script that sources bg_lib.sh will make the default umask group read-write. If you
	#       are reading this because its causing a bug in your script, consider making a oob_ callback
	#       function for scripts (like oob_getRequiredUserAndGroup above) for the script to specify
	#       the umask requirement it needs.
	local usersUmask="$(umask)"
	if [[ ! "$usersUmask" =~ ??0? ]]; then
		local newMaskPolicy="${usersUmask:0:2}0${usersUmask:3:1}"
		umask "$newMaskPolicy"
	fi

	# if we make it thorugh to the end of this function without exiting,
	# then this is a normal (not OOB) invocation

	# if debug features are enabled, inform the user.
	debugShowBanner

	# if this is a daemon script there are certain subcmds that we can handle instead of making each daemon script handle them
	if [ "${daemonDefaultStartLevels+isset}" ]; then
		daemonInvokeOutOfBandSystem "$@" || bgExit
	fi
}

#' atom syntax highlighting bug


# usage: match <str> <regex> [<rematch>]
# match is an alias for the [[ <str> =~ <regex> ]] condition syntax that returns BASH_REMATCH in the named <rematch> variable
# This avoids the problem of clobbering BASH_REMATCH because many library functions use [[ =~ ]]. Code that uses match can be
# debugged but code that uses [[ =~ ]] can not be stepped through because the debugger code uses many
# Return Value:
#    0 : (success) <str> matches <regex>
#    1 : (failure) <str> does not match <regex>
#    <rematch> : if <regex> contains groups and a variable name is specified for <rematch>, that variable will be populated with
#                the contents of BASH_REMATCH[] array.
function match()
{
	[[ "$1" =~ ${2// /\\ } ]]
	local _result="$?" i
	if [ "$3" ]; then
		# BASH_REMATCH is copied this way to avoid arbitrary code execution if carefully crafted <str> content since <str> will often
		# come from lower proviledge sources. (match will be used to parse arbitrary data)
		for i in "${!BASH_REMATCH[@]}"; do
			printf -v "$3[$i]" "%s" "${BASH_REMATCH[$i]}"
		done
	fi
	return $_result
}

# usage: oob_printBashCompletionDefault <cword> <progrName($0)> [<arg1>..<argN>]
# This is called for a script that includes oob_invokeOutOfBandSystem but does not define oob_printBashCompletion to provide a
# custom completion alorgith. This implementation will glean what ever information it can from the script source to provide BC
function oob_printBashCompletionDefault()
{
	bgBCParse "<glean>" "$@"; set -- "${posWords[@]:1}"

}

#######################################################################################################################################
### From bg_security.sh  (aka bg_auth.sh)

# usage: bgsudo [options] <cmdline ...>
# this is a wrapper over the linux sudo command used in bash scripts.
#
# Least privilege Feature:
# bgsudo has the concept of 4 privilege levels from least privilege(1) to most privilege(4).
#     4 nativeRoot-skipSudo -> AuthUser is root so no sudo needed                    -> `<cmd...>`
#     3 escalate            -> escalate to root                                      -> `sudo <cmd...>`
#     2 skipSudo            -> AuthUser has privilege so no sudo needed              -> `<cmd...>`
#     1 deescalate           -> we are already running escalated, but dont need to be -> `sudo -u<realUser> <cmd...>`
# The privilege level takes into account the current USER and the user who authenticated the current session (aka loguser, aka real user)
# In generall, we start at the least priviledge and test to see if it needs to be higher. This function (and bgsudo) can be called
# multiple times with new information to adjust the privilege further. The current privilege level is passed through to the output
# <sudoOptsVar> array so that when its called multiple times, each call will start at the last privilege.
#
# When the caller uses at least one -r <file>, -w <file>, or -c <file> option, bgsudo will invoke the <cmdline> in a way that gives
# it the least priviledge required to access the specified files. Multiple -r|-w|-c options may be given.
#    1) if the script is already running as root because the user escalated priviledge before running the script, but the
#       loguser (the real user that authenticated the session) has sufficient permissions, sudo -u <loguser> is used to
#       de-escalate priviledge beofore running the <cmdline>
#    2) if the user has sufficient permissions to access the specified files, the <cmdline> will be invoked without sudo
#    3) if the real user is root (i.e. a script running in a cron or other daemon) sudo will not be used to reduce the log
#       noise
#
# Showing the Context why sudo password is being prompted:
# if the user presses cntr-c at the password prompt, the script terminates with an assertion that shows the context that bgsudo
# was being called in. This allows the user to bail out if they have doubts in order to get more information about why they are
# being promtped.
# Also, this aids in debugging permission problems since the goal is for users not to be prompted for their password for typical
# operations. Scripts written to use bgsudo make it easier to tune rbacPermission policies so that a user role will not be
# prompted. Using cntr-c when prompted gives enough information to craft a rbacPermission to allow that sudo invocation without
# a password.
#
# Multiple bgsudo calls in the same context:
# _bgsudoAdjustPriv can be used once at the start of a contxt to prepare a variable with the correct options for bgsudo and then
# bgsudo can be invoked multiple times with those options. This makes scripts more readable since the bgsudo command line options
# can be long and obsure the real <cmdline>. It is also more efficient because the -r and -w least privilege calculation only needs
# be done once.
#
# This is particularly useful because the security nature of sudo requires it to only execute external cmds so there is no way
# to group script cmds into one sudo call (i.e. sudo can not invoke a bash function)
#
# Controversy of Using sudo in Scripts :
# Using sudo inside a script is controversial because the user has to trust that the script is not capturing the password.
# One school of thought is that the user should know that only when they execute the sudo command directly, will they be prompted
# to enter their password. That way they only trust that sudo is secure and can not fall victum to a rogue script prompting for their
# password for malicious purposes. I think that a better line of defense is that users should know that only software in the system path
# that is protected from change by unpriviledged users is trustworthy. If a command is in the system path, it must be from a trusted
# source with an SDLC that would reject any script that misuses the users password.
#
# Options:
#    <most sudo options are passed through>
#    <the following options are processed by this wrapper instead of the base sudo>
#    -O <optVar> : interpret <optVar> as an array containing cmdline options. <optVar> is typically initialized with a previous call
#             to bgsudo --makeOpts <optVar>
#             Note that because the target of sudo must be an external command to prevent privilege escalation, there is no way to
#             group commands inside a script into a single sudo invocation. This pattern is the next best thing so that a script
#             can determine if it needs sudo and then run multiple commands with the <optVar> which will use sudo or not based on
#             the -r and -w options used to create <optVar>
#    --makeOpts <optVar> : instead of running a command, process the options and store the results in <optVar>. Subsequent calls
#             can use -O <optVar> to specify the arguments more compactly and without repeating the work.
#    --defaultAction : one of (nativeRoot-skipSudo|escalate|skipSudo|deescalate) default is deescalate. This is the starting privilege
#         level before any -r|-w|-c <fileN> are considered. The action taken will be either this or a higher privilege level
#    -r <file> : adjust privilege to provide read access to <file>
#    -w <file> : adjust privilege to provide write access to <file>
#    -c <file> : adjust privilege to provide access create or remove <file>. This requires permission on the parent but not necessarily
#                the <file> itself. Note -w will automatically fall back to the permission to create <file> if it does not exist so
#                this is primaily used when you want to remove a file.
#    -nn    : sudo's -n fails instead of prompting for a password. -nn extends that to also supress the error.
function bgsudo()
{
	local options=() suppressSudoErrorsFlag testFiles testFile defaultAction
	while [[ "$1" =~ ^- ]]; do case $1 in
		-O*) local _bs_optVar
			 bgOptionGetOpt val: _bs_optVar "$@" && shift
			 # note that because we are in a loop that shifts at the end, we add an empty $1 for it to shift out
			 shift; eval 'set -- "" "${'"$_bs_optVar"'[@]}" "$@"'
			 ;;
		--makeOpts*)
			local _bs_optVar; bgOptionGetOpt val: _bs_optVar "$@" && shift
			shift # the rest of this option would be shifted at the end of the loop so remove it now before returning
			_bgsudoAdjustPriv --sudoOptsVar "$_bs_optVar" "$@"
			return
			;;
		--defaultAction*) bgOptionGetOpt val: defaultAction "$@" && shift ;;
		-nn) suppressSudoErrorsFlag="-n"
			 options+=("-n")
			 ;;
		-d)  debug="echo " ;;
		-r*|--read)   bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-r$testFile") ;;
		-w*|--write)  bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-w$testFile") ;;
		-c*|--create) bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-c$testFile") ;;
		-o*|--chown*) bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-o$testFile") ;;
		-a*|--attr*)  bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-a$testFile") ;;

		-[paghpuUrtCc]*|--role*|--prompt*|--close-from*|--group*|--user*|--host*|--type*|--other-user*)
			bgOptionGetOpt opt: options "$@" && shift
			;;
		--)  shift; break ;;
		*)  bgOptionGetOpt opt options "$@" && shift ;;
	esac; shift; done

	# if the user passed in -r|-w|-c <fileN> resources to determine the required privilege, use _bgsudoAdjustPriv to do that
	if [ ${#testFiles[@]} -gt 0 ]; then
		# defaultAction may or may not already have a value. pass it in with the (additional) file tests and get the new one
		_bgsudoAdjustPriv --actionVar=defaultAction --defaultAction="$defaultAction" "${testFiles[@]}"
	fi

	# cases where we dont need sudo.
	if [[ "$defaultAction" =~ ^(skipSudo|nativeRoot-skipSudo)$ ]]; then
		"$@" # execute the rest of the params as a command
		return
	fi

	# set up the SIGINT trap and a file to receive stderr
	local tmpErrOutFile="$(mktemp)" bgsudoCanceled=""
	bgtrap -n bgsudo 'bgsudoCanceled="1"' SIGINT

	# run with sudo ...
	local envOpt; [ "$bgProductionMode" == "development" ] && envOpt="-E"
	case ${defaultAction:-escalate} in
		deescalate)
			local realUser; bgGetLoginuid realUser
			$debug sudo $envOpt -u "$realUser" "${options[@]}" "$@" 2>"$tmpErrOutFile"; local exitCode=$?
			;;
		escalate)
			$debug sudo $envOpt                "${options[@]}" "$@" 2>"$tmpErrOutFile"; local exitCode=$?
			;;
		*) assertLogicError ;;
	esac

	# clean up the SIGINT trap and stderr file
	bgtrap -r -n bgsudo SIGINT
	local errOut="$(cat "$tmpErrOutFile")"
	rm -f "'"$tmpErrOutFile"'"

	# if the user hit cntr-c, show them the context that used sudo
	if [ "$bgsudoCanceled" ]; then
		local command="$*"
		local -A stackFrame=(); bgStackFrameGet "1"  stackFrame
		local caller="${stackFrame[frmSummary]}"
		assertError -v options -v command -v caller "sudo canceled by user"
	fi

	# If sudo failed (as opposed to the command being ran with sudo) we assert the error.
	if [ "$exitCode" == "1" ] && [[ "$errOut" =~ ^sudo: ]]; then
		if [ "$suppressSudoErrorsFlag" ]; then
			errOut=""
			exitCode=0
		else
			assertError -v options -v command -v errOut "sudo failed"
		fi
	fi

	# propagate errors that that the command might have returned up to the caller
	[ "$errOut" ] && echo "$errOut" >&2
	return $exitCode
}


# usage: _bgsudoAdjustPriv [--sudoOptsVar=<vname>] [--actionVar=<vname>] [<sudoOptions>] [--defaultAction=<action>] [[-r|-w|-c <file1>]..[-r|-w|-c <fileN>]]
# Note that you typically do not call this function directly anymore. Instead call `bgsudo --makeOpts ...` which is an alias to call
# this command.
#
# This function does two things. First, it calculates --defaultAction=<action> based on the <fileN> and adds it to the <sudoOptsVar>
# array and Second, it passes through options that sudo understands (e.g. -p "<promtMsg") to the <sudoOptsVar> array
#
# The idea of this command is that it can process sudo options and extended bgsudo options and stores them in the <sudoOptsVar>
# array which can be used to pass 0 or more options to a future call to bgsudo. This allows determining the sudo arguments once
# and then invoking multiple commands that will use the same sudo privilege.
#
# Priviledge Adjustments:
# bgsudo has the concept of 4 privilege levels from least privilege(1) to most privilege(4).
#     4  nativeRoot-skipSudo -> AuthUser is root so no sudo needed                    -> `<cmd...>`
#     3  escalate            -> escalate to root                                      -> `sudo <cmd...>`
#     2  skipSudo            -> AuthUser has privilege so no sudo needed              -> `<cmd...>`
#     1  deescalate          -> we are already running escalated, but dont need to be -> `sudo -u<realUser> <cmd...>`
#     "" unknown             -> if no testFiles are given we dont know so use sudo    -> `sudo <cmd...>`
# The privilege level takes into account the current USER and the user who authenticated the current session (aka loguser, aka real user)
# In generall, we start at the least priviledge and test to see if it needs to be higher. This function (and bgsudo) can be called
# multiple times with new information to adjust the privilege further. The current privilege level is passed through to the output
# <sudoOptsVar> array so that when its called multiple times, each call will start at the last privilege.
#
# When calling a group of commands with sudo, the conservative security approach is to not save the sudo options and let each command
# get the privilege that it needs to use based on a bespoke set of -r|-w|-c <file> resources that the command will access. It is
# more convenient and performant, however, to calculate the aggregate privilege of all commands and then calling all commands with
# the same <sudoOptsVar> that will have the highest privilege required by any of the commands (based on the aggregate list of <file>
# resources that will be accessed).
#
# Example:
#     local sudoOpts; bgsudo --makeOpts=sudoOpts -p "modify file (${myFile##*/})[sudo]" "$myFile" -r "$myFile2"
#     bgsudo -O sudoOpts mv "$myFile2" "$myFile"
#     bgsudo -O sudoOpts touch "$myFile"
#     echo "hello" | bgsudo -O sudoOpts tee -a "$myFile" >/dev/null
#
# Param:
#   <sudoOpts>    : the variable name that will receive sudo options. This function will add --defaultAction and pass through
#                   native sudo options.
#
# Options:
#    --role=<role> : Note that the posix sudo supports the short form -r <role> for --role=<role> option but this function only
#             supports --role=<role> since it use -r for its own option which is more typical in this pattern than --role=<role>
#    --defaultAction : one of (nativeRoot-skipSudo|escalate|skipSudo|deescalate) default is deescalate. This is the starting privilege
#         level before any -r|-w|-c <fileN> are considered. The output action will be either this or a higher privilege level
#    -w <file> : the <cmd> will access <file> in write mode so set the privilege adjustment accordingly
#    -r <file> : the <cmd> will access <file> in read mode so set the privilege adjustment accordingly
#    -c <file> : adjust privilege to provide access create or remove <file>. This requires permission on the parent but not necessarily
#                the <file> itself. Note -w will automatically fall back to the permission to create <file> if it does not exist so
#                this is primaily used when you want to remove a file.
#    <other options> : other sudo or bgsudo options can be specified and they will be passed through
# See Also:
#     bgsudo : a wrapper over sudo that supports priviledge adjustment and other additional features "
function _bgsudoAdjustPriv()
{
	local testFiles testFile _sapAction sudoOptsVar actionVar
	while [[ "$1" =~ ^[-+] ]]; do case $1 in
		--sudoOptsVar*)
			# this assumes that if provided, this option is first
			# if sudoOptsVar contains options from a previous call, spread them back into the params with the new ones following
			# so that they will override previous options.
			bgOptionGetOpt val: sudoOptsVar "$@" && shift
			# SECURITY: this varExists check is meant to prevent ACE
			varExists "$sudoOptsVar" || assertError
			shift; eval 'set -- "" "${'"$sudoOptsVar"'[@]}" "$@";  '"$sudoOptsVar"'=()'
			;;
		--actionVar*)   bgOptionGetOpt val: actionVar   "$@" && shift ;;
		--defaultAction*) bgOptionGetOpt val: _sapAction "$@" && shift ;;
		-r*|--read)   bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-r$testFile") ;;
		-w*|--write)  bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-w$testFile") ;;
		-c*|--create) bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-c$testFile") ;;
		-o*|--chown*) bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-o$testFile") ;;
		-a*|--attr*)  bgOptionGetOpt val: testFile "$@" && shift; testFiles+=("-a$testFile") ;;
		-[paghpuUrtCcO]*|--role*|--prompt*|--close-from*|--group*|--user*|--host*|--type*|--other-user*)
			bgOptionGetOpt opt: "$sudoOptsVar" "$@" && shift
			;;
		--)  shift; break ;;
		*)  bgOptionGetOpt opt "$sudoOptsVar" "$@" && shift ;;
	esac; shift; done

	[ $# -gt 0 ] && assertError -v "leftOver:$*" "left over cmdline arguments"

	# if no testFiles were specified, dont adjust the _sapAction
	if [ ${#testFiles[@]} -gt 0 ]; then

		# if the starting point action was not passed in, start at the lowest priviledge
		_sapAction="${_sapAction:-deescalate}"

		# if the user is not root, deescalate is not possible.
		# 2021-02: we dont try to deescalate non-root systemusers to the real user for 2 reasons with about 80% confidence.
		#          1) an arbitrary system user should not have sudo rights to change to a real user
		#          2) if something escalates a real user to a non-root system user, files should probably be owned by them.
		#             if the intention is to track users that create files, use a group instead of escalation.
		local realUser
		if (( EUID != 0 )) && [[ "$_sapAction" =~ ^(deescalate)$ ]]; then
			_sapAction="skipSudo"
		else
			# get the loguser -- the user that authenticated the session
			aaaGetUser realUser

			# if the realUser is root or there is no real user (i.e. cron or other daemon), there is nothing to de-escalate or escalate so
			# just skip sudo. we don't need to process the rest of the options since sudo wont be used
			if { [ ! "$realUser" ] || [ "$realUser" == "root" ]; }; then
				_sapAction="nativeRoot-skipSudo"
			fi
		fi

		# iterate the -r/-w <file> options and adjust the priviledge action as needed to provide sufficient access
		local term; for term in "${testFiles[@]}"; do
			local testMode="${term:0:2}"
			local fileToAccess="${term:2}"
			{ [[ ! "$testMode" =~ ^-[rwcoa]$ ]] || [ ! "$fileToAccess" ]; } && assertLogicError -v testMode -v fileToAccess

			# see if we need to escalate to change the permission attributes of this file
			if [ "$testMode" == "-a" ]; then
				if [ ! -O "$fileToAccess" ]; then
					_sapAction="escalate"
				fi
				continue
			fi

			# see if we need to escalate to change the user or group ownership of this file
			if [ "$testMode" == "-o" ]; then
				local uOwn gOwn; IFS=: read -r fileToAccess uOwn gOwn <<<$"$fileToAccess"
				if [ -e "$fileToAccess" ]; then
					if [[ "$_sapAction" =~ ^(deescalate|skipSudo)$ ]]; then
						local curU curG; IFS=: read -r curU curG <<<$"$(stat -c"%U:%G" "$fileToAccess" 2>/dev/null)"
						# if we are not the owner, we need to escalate to make any change
						if [ "$curU" != "$USER" ]; then
							_sapAction="escalate"
						# if we are changing the user owner to someone else we need to escalate
						elif [ "$uOwn" ] && [ "$uOwn" != "$curU" ]; then
							_sapAction="escalate"
						# if we are changing the group to one that we are not a member of
						elif [ "$gOwn" ] && [ "$gOwn" != "$curG" ]; then
							local memG="$(id -Gn)"
							if [[ ! " $memG " =~ [\ ]$gOwn[\ ] ]]; then
								_sapAction="escalate"
							fi
						fi
					fi
					continue
				fi
			fi

			# handle the case where we need to check the parent's permissions because fileToAccess does not exist or -c was specified
			local path="${fileToAccess%/}"
			if [ ! -e "$path" ] || [ "$testMode" == "-c" ]; then
				# if we are tesing to read or change the ownership and the file does not exist, it might be an error, but its not a
				# permission issue. If the caller is going to create the missing file, it should have specified that it needs write
				# or create access
				[[ "$testMode" =~ ^-[ro] ]] && continue

				# both -w and -c at this point need write access to the parent folder
				testMode=-w

				# if we need to create or remove the file, we need write access to the first existing parent so set the path to it
				# instead of the target file itself
				[[ "$path" =~ / ]] && path="${path%/*}" || path="."
				local found=""; while [ ! "$found" ] && [ "$path" != "." ]; do
					if [ -e "$path" ]; then
						found="1"
					else
						[[ "$path" =~ / ]] && path="${path%/*}" || path="."
					fi
				done
			fi

			# if we are still considering de-escalation, check to see if the realUser can access this file
			if [ "$_sapAction" == "deescalate" ]; then
				# if we find any any file that can not be accessed by the realUser, we need at least the 'skipSudo' level
				sudo -u "$realUser" test $testMode "$path" || _sapAction="skipSudo"
			fi

			# if we are still considering 'skipSudo' check that the current user can access this file
			# note that if _sapAction==deescalate at this point, it passed the realUser access test above
			if [ "$_sapAction" == "skipSudo" ]; then
				test $testMode "$path" || _sapAction="escalate"
			fi
		done
	fi

	[ "$_sapAction" ] && setReturnValue --array --append "$sudoOptsVar" "--defaultAction" "$_sapAction"
	setReturnValue "$actionVar" "$_sapAction"
}


# usage: genRandomKey <keyBitLen> [<waitIfNeeded>]
# generate a new random key by reading from /dev/random or /dev/urandom
# The default is /dev/urandom (non-blocking). if "waitIfNeeded" then /dev/random will be used.
# The difference between the two is that /dev/random is higher quality but will block if there is not
# enough entropy in the PRNG to satisfy the request. Entropy is generated by eternal events happening
# in device drivers so entropy is always being replenished.
# Output:
#    The result is in ascii hex ( [0-9a-f]* ). each character in the string encodes 4 bits so a 256 bit key would
#    be returned in 64 hex characters.
# Params:
#    <keyBitLen>      : default is 128
#    <waitIfNeeded'   : if the second param is not empty, it will cause the fucntion to get the bytes from /dev/random
#                       which is quaranteed to achieve a minimum entropy even if it has to pause and wait for the system to
#                       experience more input for its entropy generator.
#                       normally it gets bytes from /dev/urandom which will never wait but may achieve a lower entropy
# SECURITY: genRandomKey should be reviewed and improved if needed. If a hardware PRNG is avail on the host it should use it.
function genRandomKey()
{
	local keyBitLen="${1:-128}"
	local waitIfNeeded="$2"
	local keyByteLen=$(( keyBitLen / 8 ))
	if [ "$waitIfNeeded" ]; then
		dd if=/dev/random count=${keyByteLen:-1} bs=1 2> /dev/null | xxd -ps | tr -d "\n"
	else
		dd if=/dev/urandom count=${keyByteLen:-1} bs=1 2> /dev/null | xxd -ps | tr -d "\n"
	fi
}


# usage: bgGetLoginuid [-n] [<varname>]
# returns the uid/name of the user who's authority the script is running by. aka the 'real' user.
# This is the user that should be logged. It is also used by _bgsudoAdjustPriv to drop privilege when
# calling external utilities when its able. Files created by this proc should be owned by this uid by
# default.
#
# This function returns the value of /proc/self/loginuid, but as of circa 2018-08, that value is not
# always set so this function compensates by finding a reasonable value if its not already set.
#
# I beleive that loginuid is a bit of a misnomer because it is not necessarily the result of an external
# authentication event (aka login). The purpose of this uid is to be able to make the actions of the
# script accountable to the actor responsible for the script running. The system configuration allows
# for procs to be launched at startup or in response to time passing or other events which do not happen
# in the context of an authenticate user. Those proc can not be an exception to accountability.
# In those cases loginuid should be root or the user that the proc is launched as. The local admins
# with root provileges are responsible for the system configuration that causes the system daemons to
# start and launch other procs so its correct for loginuid to be root for the things they do unless
# They permanantly drop priviledge to run the proc as a different user before passing control to the code.
# The /proc/<pid>/loginuid Mechanism:
#   The kernel initiallizes the value to the value of the value of the parent proc when a proc is created.
#   The default value is 0xFFFFFFFF (aka 32bit -1, aka 4294967295). init(1) and other root daemon procs
#   have the default value. If the value is the default, the proc iteself or root can set it to another
#   value. Once set it can not be changed. root can still change it but there is talk of changing that.
#   That is not a big deal since root can by definition violate any security constraint but since its
#   hard to allow some sudo privilege without allowing the privilege to write to the /proc/self/loginuid
#   file, it would be convenient for the kernel to disallow the value from changing once set even by root.
# How Loginuid Should be set:
# The init(1) proc and other procs whose purpose is to launch other procs, should leave their loginuid
# set to the default value. These should not be allowed to run user code directly.
# Its up to each initial launcher proc to set /proc/<pid>/loginuid on the initial proc it launches.
# There are two cases on linux servers.
#       daemons running due to the configuration of the server causes them to run without an external trigger.
#       processes and daemons running as a result of a login session
# For interactive sessions (sshd, lightdm, etc...) it is straight forward that the loginuid of the launched
# proc should be set to the uid that was authenticated.
# For daemons launched from system configuration (systemd, crond, etc...) for which there is no interactive
# authentication, I believe that loginuid should still be set. It should be set to root unless the configuration
# indicates that the proc will be launched as an unpriviledged user in a way that the launched code can not
# circumvent. In that case loginuid will be set to that user. crond is a good example of this. An unprivileged
# user can mange their crond config to launch procs outside of a login session. Those procs are still
# running under the authority of that user.
# Compenstaion Routine:
# At this time, circa 2018-08, its common to encounter procs that do not have loginuid set. This function
# compensates for that by walking the pid tree back up to init(1) and choosing the first non-root uid
# nearest init(1) or root if there is no other uid. That algorithm will not be 100% correct but it is
# close enough to be useful. If it produces a wrong result in production that is significant, the fix
# should be to configure the host to set loginuid to the correct uid when the root proc is launched
# A significant usecase that this compensation is needed for is Ubuntu 16.04 destop sessions. xterm
# windows launched from the desktop will not have the loginuid set.
# Params:
#    <varname> : if this is specified, the result is returned by setting it to this variable name.
#                If not specified, the result is written to stdout
# Options:
#    -n : numeric. return the numeric uid instead of the username.
function aaaGetUser() { bgGetLoginuid "$@"; }
function bgGetLoginuid()
{
	local numericFlag
	while [ $# -gt 0 ]; do case $1 in
		-n)  numericFlag="-n" ;;
		 *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	 done
	local _glu_varname="$1"
	local _glu_value

	# implement a cache so that we only look it up once in each script run. In the normal case where
	# /proc/self/loginuid is set, this cache is not needed but when its not and the compensation algorithm
	# runs, its 100 times slower. Since this function could be called many times in a script that is
	# significant.
	# SECURITY: a function that uses a global cache variable should only use an associative array b/c
	#           those can not be inherited from the calling process. Otherwise the caller can polute the cache.
	# note that if the self pid varies over different calls (which it should not) it would not matter because
	# any child pid should have the same value of loginuid.
	local -gA _bgauthSystemCache
	_glu_value="${_bgauthSystemCache[loginuid${numericFlag}]}"
	if [ "$_glu_value" ]; then
		returnValue "$_glu_value" "$_glu_varname"
		return 0
	fi

	# if set, /proc/self/loginuid is the most reliable source. typically pam_loginuid should set it
	# on authentication, then the kernel propagates it to each child proc and once set, it can not
	# be changed (execpt by root, which is a bug that should be fixed in the kernel)
	read -r _glu_value < /proc/self/loginuid
	if [[ $_glu_value -ne 0xFFFFFFFF ]]; then
		[ ! "$numericFlag" ] && _glu_value="$(id -un $_glu_value)"
		_bgauthSystemCache[loginuid${numericFlag}]="$_glu_value"
		returnValue "$_glu_value" "$_glu_varname"
		return 0
	fi

	# if /proc/self/loginuid is 0xFFFFFFFF (4294967295, aka -1 32bit number), it means nothing set it yet.
	# A host should be configured so that all luanching daemons set it to the correct value but in the
	# meantime we support hosts that do not by falling back on this compensation algorithm.

	# walk the parent tree back to init(1) and choose the first non-root uid closest to init(1)
	# this idea is that init and other launcher procs run as root and then drop privilege to a non-root
	# user just before execve'ing the launched code so the first non-root user will be the logical
	# loginuid that the launcher should have set.
	local pwalk=$$
	local _glu_value wpid wcomm wstate label wuid theRest
	while [ ${pwalk:-0} -ne 0 ]; do
		read -r label wuid theRest < <(grep "^Uid:" /proc/$pwalk/status)
		[ ${wuid:-0} -ne 0 ] && _glu_value="$wuid"
		read -r wpid wcomm wstate pwalk theRest < /proc/$pwalk/stat
	done

	# if there are no non-root users in the parent tree, set it to root
	_glu_value="${_glu_value:-0}"

	[ ! "$numericFlag" ] && _glu_value="$(id -un $_glu_value)"
	_bgauthSystemCache[loginuid${numericFlag}]="$_glu_value"
	returnValue "$_glu_value" "$_glu_varname"
	return 0
}





#######################################################################################################################################
### From bg_cui.sh

# FUNCMAN_SKIP
# this is a stub function that will load the bg_cui.sh and the real progress function if its called
function progress()
{
	if [[ ! "$progressDisplayType" =~ ^(none|null|off)$ ]]; then
		import -f bg_cuiProgress.sh ;$L1;$L2 || assertError
		progress "$@"
	fi
}
# FUNCMAN_SKIP
function progressCntr()
{
	if [[ ! "$progressCntrDisplayType" =~ ^(none|null|off)$ ]]; then
		import -f bg_cuiProgress.sh ;$L1;$L2 || assertError
		progressCntr "$@"
	fi
}


#######################################################################################################################################
### From bg_unitTest.sh


# usage: utEsc [<p1> ...<pN>]
# usage: cmdline [<p1> ...<pN>]
# this escapes each parameter passed into it by replacing each IFS character with its %nn equivalent token and returns all parameters
# as string with a single IFS character separating each parameter. If that string is subsequently passed to utUnEsc, it will populate
# an array properly with each element containing the original version of the parameter
function cmdline() { utEsc "$@" ; }
function cmdLine() { utEsc "$@" ; }
function utEsc()
{
	if [ "$1" == "-q" ]; then
		shift
		local params=("$@")
		local i; for i in "${!params[@]}"; do
			[[ "${params[$i]}" =~ [\ ] ]] && params[$i]="'${params[$i]}'"
		done
	else
		local params=("$@")
		params=("${params[@]// /%20}")
		params=("${params[@]//$'\t'/%09}")
		params=("${params[@]//$'\n'/%0A}")
		params=("${params[@]//$'\r'/%0D}")
		params=("${params[@]//$'*'/%2A}")
		local i; for i in "${!params[@]}"; do
			[ "${params[$i]}" == "--" ] && params[$i]="%2D%2D"
			params[$i]="${params[$i]:---}"
		done
	fi
	echo "${params[*]}"
}

# usage: utUnEsc <retArrayVar> [<escapedP1> ...<escapedPN>]
# this is the companion function to utEsc. It populates the array variable named in <retArrayVar> with the unescaped versions of
# each of the parameters passed in.
function utUnEsc()
{
	local -n _params="$1"; shift
	_params=("$@")

	local i; for i in "${!params[@]}"; do
		[ "${params[$i]}" == "--" ] && params[$i]=""
		[ "${params[$i]}" == "%2D%2D" ] && params[$i]="--"
	done


	_params=("${_params[@]//%20/ }")
	_params=("${_params[@]//%09/$'\t'}")
	_params=("${_params[@]//%0A/$'\n'}")
	_params=("${_params[@]//%0D/$'\r'}")
	_params=("${_params[@]//%2A/$'*'}")
}



#######################################################################################################################################
### From bg_string.sh

# usage: arrayToString <arrayVarName> [<retVar>]
# convert an array (-a or -A) into a string that can be passed somewhere and then restored  back into an array
# SECURITY: arrayToString. use arrayFromString to safely restore the <contectStr> created with this function.
# Format:
# The format of the string is the format that declare -p uses but only the part that is inside the ()
# For example...
#    local ary=( [one]="blue" [two]="green" )
#    echo "$(arrayToString ary)"  # [one]="blue" [two]="green"
# See Also:
#    arrayFromString
function arrayToString()
{
	local results="$(declare -p "$1" 2>/dev/null)"
	results="${results#*\(}"
	returnValue "${results%\)*}" "$2"
}

# usage: arrayFromString <arrayVarName> <contentStr>
# convert a string created with arrayToString safely back into an array
# Note that declare, local and eval statement can do this in one line but will execute carefully crafted code contained
# in the <contentString>. Since the main reason to serialize and deserialize an array is to transfer it from one bash
# process to another, it is generally unsafe to allow code in the data to be executed. The problem is when a less priviledged
# proccess can change the environment that a more priviledged process (sudo myscript) uses.
# This function parses the <contentStr> reasonably effeciently and sets each element with printf -v
# SECURITY: arrayFromString should be used to restore an array from a <contentStr> to avoid arbitrary code exec and escalation.
# Example Vulnerability:
#    $ cat myScript
#    ...
#    declare -A foo=\( $fooStr \)
#    ...
#    $ fooStr='[one]=1 [two]=2 [exploit]="$(ls)"'
#    $ sudo myScript # runs ls or any other cmd in fooStr as root
# See Also:
#    arrayToString
function arrayFromString()
{
	local arrayVarName="$1"
	local contentStr="$2"

	# the outer loop matches each space seperated [<varName>]="<value>" clause
	# the declare -p syntax typically quotes <value> with double quotes but when <value> contains non-printable, it uses $'<value>'
	# the regex for the main loop recognizes both
	local loopCount=0 loopLimit=300 # CRITICALTODO: rais limiti after debuging
	while [[ "$contentStr" =~ ^[[:space:]]*[[]([^]]*)[]]=('"'([^'"']*)'"'|\$\'([^\']*)\') ]]; do
		local rematch=("${BASH_REMATCH[@]}")
		contentStr="${contentStr#"${rematch[0]}"}"
		# rematch[0]=<entireMatchedElementClause>
		# rematch[1]=<varName>
		# rematch[2]=<valueWithSuroundingQuotes>   # all forms with any quoting
		# rematch[3]=<valueInsideDblQuotes>        # for dbl quotes, this will be the <value> w/o quotes
		# rematch[4]=<valueUsing$''>               # for $'' quotes, this will be the <value> w/o quotes
		# we can tell which style of quoting was matched by whether remtch[3] or rematch[4] is non-empty

		# this inner loop handles emmeded escaped \" (quotes). the outter loop will match the first escaped quote so the inner loop
		# keeps searching for the first unescaped quote, appending what it finds to the rematch structure. Note the inner loop uses
		# rematch2
		while [[ "${rematch[0]}" =~ \\\"$ ]] && [[ "$contentStr" =~ ^([^'"']*)'"' ]]; do
			local rematch2=("${BASH_REMATCH[@]}")
			contentStr="${contentStr#"${rematch2[0]}"}"
			rematch[0]+="${rematch2[0]}"
			rematch[3]="${rematch[3]%\\}"
			rematch[3]+="${rematch2[1]}"
			(( loopCount++ > loopLimit )) && assertLogicError "inner loop infinite loop"
		done
		[ "${rematch[4]}" ] && eval "rematch[3]=\$'"${rematch[4]}"'"  # this is OK b/c we suround rematch[4] in $'' quoting
		printf -v $arrayVarName[${rematch[1]}] "%s" "${rematch[3]}"
		(( loopCount++ > loopLimit )) && assertLogicError "outer loop infinite loop"
	done
	[[ ! "$contentStr" =~ ^[[:space:]]*$ ]] && assertError -v arrayVarName -v contentStr:"$2" -v leftOver:contentStr  "unassigned content was left over"
}

# usage: arrayCopy [-a|--append] <cpFromArrayVar> <cpToArrayVar>
# copy the contents of one associative array to another. If either variable is empty, it is not an error and the function will not
# do anything.
# Options:
#    -a|--append : do not remove existing elements from <cpToArrayVar> before copying
function arrayCopy()
{
	local appendFlag
	while [ $# -gt 0 ]; do case $1 in
		-a|--append) appendFlag="1" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	# if either are empty, it is not an error but there is nothing to do so return
	{ [ ! "$1" ] || [ ! "$2" ]; } && return 0
	local -n cpFromArrayVar="$1"
	local -n cpToArrayVar="$2"

	[ ! "$appendFlag" ] && cpToArrayVar=()
	local _acName; for _acName in "${!cpFromArrayVar[@]}"; do
		cpToArrayVar["$_acName"]="${cpFromArrayVar["$_acName"]}"
	done

	# # this function still support ubuntu 12.04 which does not have the -n ref
	# eval '
	# 	[ ! "'$appendFlag'" ] && '$cpToArrayVar'=()
	# 	local name; for name in "${!'$cpFromArrayVar'[@]}"; do
	# 		'$cpToArrayVar'[$name]="${'$cpFromArrayVar'[$name]}"
	# 	done
	# '
}



#######################################################################################################################################
### From bg_debugTrace.sh

# We dont change the inherited value of bgTracingOn but we make sure that its exported so if something
# in this proc changes it, it will affect child procs too.
declare -xg bgTracingOn

# These two vars are not exported or inherited so we init them each time this library is sourced.
# the optimized path is for the case when bgtrace is not on so we quickly set _bgtraceFile to /dev/null
# and bgTracingOnState to "" to reflect that the current realized state is off.
# if nothing calls a bgtrace* function it will never be realized
declare -g _bgtraceFile="/dev/null"
declare -g bgTracingOnState=""

# usage: bgtraceIsActive
# returns true(0) if bgtracing is turned on and false(1) if its not
# If _bgtraceFile is not realized in this proc it will be realized before returning
function bgtraceIsActive()
{
	# if its off and bgTracingOnState reflects it return 1(false) quickly
	[ ! "$bgTracingOn$bgTracingOnState" ] && return 1

	# when bgtrace is called in a debug trap, import would clear L1 before it can run when stepping over an import if we let it get
	# called here.
	[ ! "${_importedLibraries[lib:bg_debugTrace.sh]+exists}" ] && { import bg_debugTrace.sh ;$L1;$L2; }

	# if its not realized, call bgtraceCntr to make _bgtraceFile reflect bgTracingOn
 	# The value of bgTracingOn is exported/inherited from the parent proc but bgTracingOnState is reset
	# to "" every time this library is sourced. This also picks up any code that changes bgTracingOn
	# directly without calling bgtraceCntr
	[ "$bgTracingOn" != "$bgTracingOnState" ] && bgtraceCntr "$bgTracingOn"

	# set the return value to 0(tracing is on) or 1(tracing is off)
	[ "$bgTracingOn" ]
}

# usage: bgtraceTurnOn [-n] [<destinationFile>|on|on:[<file>]|file:[<file>]]
# This is an alias to bgtraceCntr on:.. that is a core function so that it is always available even when bgtracing is not active.
# bgtraceCntr is a more complicated function that we only load as part of the bg_debugTrace.sh library when bgtracing is active.
# Options:
#     -n : ifNotOnFlag. If tracing is already on, it will leave it going to the current destination file. If not, it will set it to the new, specified tracing file
function bgtraceTurnOn()
{
	import bg_debugTrace.sh ;$L1;$L2

	while [[ "$1" =~ ^- ]]; do case $1 in
		-n) [ "$bgTracingOn" ] && return 0 ;;
	esac; shift; done

	bgtraceCntr "${1:-on}"
}

# OBSOLETE: I think that now we do not tis because after bg_core.sh is sourced, we can rely on $_bgtraceFile being set so we can '<cmd> >$_bgtraceFile'
# usage: bgtraceGetLogFile
# returns the bgtrace logfile or /dev/null if that log file is not set.
function bgtraceGetLogFile()
{
	echo "${_bgtraceFile:-/dev/null}"
}



#######################################################################################################################################
### From bg_debugger.sh

# usage: debuggerIsActive
# returns 0(true) if the debugger has been turned on in this script. It is used to tell if debuggerOn/Off needs to be called.
# The definition of being turned on means that a terminal has be set for the use of the debugger. It does not mean that
# the script is currently stopped in the debugger or the the DEBUG trap is currently set
# See Also:
#    debuggerIsActive   : is there a debugger open for this script (regardless of whether the script is in a break or running)
#    debuggerIsInBreak  : is the script currently stopped in the debugger.
function debuggerIsActive()
{
	[ "$bgDevModeUnsecureAllowed" ] || return 35
	[ "$bgdbtty" ] && [ -t "$bgdbttyFD" ] && return 0
	[ "$bgdbCntrFile" ] && [ -p  "$bgdbCntrFile"  ] && return 0
	return 1
}

# usage: debuggerIsInBreak
# returns 0(true) if the script is currently stopped in the debugger. This means that the debugger UI is active and the script is
# not running, waiting for the debugger to step or resume.
# See Also:
#    debuggerIsActive   : is there a debugger open for this script (regardless of whether the script is in a break or running)
#    debuggerIsInBreak  : is the script currently stopped in the debugger.
function debuggerIsInBreak()
{
	[ "$bgDevModeUnsecureAllowed" ] || return 35
	[ -e "${assertOut}.stoppedInDbg" ]
}





#######################################################################################################################################
### From bg_ipc.sh

# usage: pidIsDone [pid1 ... pidN]
# This is like a non-blocking 'wait' command.  It returns false if any of the specified pids are running (not finished)
# If no pid are specified, the default is $(jobs -p) which is all the children pids
function pidIsDone()
{
	local i; for i in ${@:-$(jobs -p)}; do
		if kill -0 "$i" 2>/dev/null; then
			return 1
		fi
	done
	return 0
}


# usage: startLock [-u <lockVar>] [-w <timeoutSeconds>] [-q] [<lockFile>]
# Uses flock(1) to implement a cooperative serialization mechanism. Scripts or script library code can
# get a lock on a file or directory and know that multiple copies of itself or other scripts that call
# startLock on the same file or directory will be serialized meaning they will wait while another process
# has the lock and then proceed when its their turn. Multiple stripts can be waiting and one will be released
# at a time.
#
# The lock is represented in the script as an open file descriptor. When the script or subshell ends
# any file descriptors openned by startLock within it will be closed and the next waiting process, if
# any will acuire the lock and proceed.
#
# Code can release the lock before the script or subshell ends by calling endLock with a similar command
# line that identifies the same lock.
#
# Possessing the Lock:
# The code after startLock and up until the end of the script or subshell or up until the next endLock
# call is said to possess the lock meaning that in that time it knows that no other process possesses
# that lock so it can have sole access to the resources that are agreed to be protected by that lock.
# The protected code section that access the resources should not run if the lock can not be aquired.
#
# By default, this function will assert an error if it fails to obtain the lock within the <timeoutSeconds>
# period and that prevents the rest of the code in the script or subshell from running. If the -q option
# is specified, it will instead return a non zero exit code if it fails to get the lock so the caller needs
# to check return value and not run that code.
#
# Sharing the Lock:
# The lock mechanism uses flock on a open FD (file descriptor). If two PIDs in the same script share that FD, then they will also
# share the flock on that FD and will not serialize on that lock. Sometimes that is desirable because you want subshells spawned
# while the lock is possessed to not block on acquiring that same lock which would cause a deadlock.
#
# You can explicitly control the sharing of the lock by opening the FD and passing in the FD anyplace that should share the lock.
# The startLock/endLock mechanism also maintains a FD cache so that if you pass in a filename it will reuse the same FD as long
# as its in the cache. The current behavior is that the cache is active only between the startLock/endLock calls so that subshells
# spawned inside the lock section will reuse the same FD when startLock is invoked with the same filename but subshells spawned outside
# the lock section will be independent.
#
# At this time (circa 2021-02), I think that I added the FD cache mechanism (it was a long time ago) to solve a deadlock problem
# when using locks with filenames. Originally, the cache would be persistent past the endLock, but when serializing the debugger
# against subshells in a pipeline fighting over the debugger UI and tty, it rendered the lock ineffective because all the pipeline
# subshells would share the same FD and therefore would all possess the lock. At the end of endLock, it now closes the FD and removes
# the cache entry. This makes it so that when ever the debugger returns, the FD and its cache entry will not exist so that each
# spawned pipeline will open its own, independent FD and possess the lock independently.  I think that this will work in all cases
# but time well tell. If not, the solution could be to add an option to get different behaviors for different situations
#
# Protected Resources:
# The script may or may not actually write to <lockFile>. It might just resprented some other resource.
# If using this to serialize write access to the <lockFile>, remember that it is a cooperative locking
# mechanism meaning that another process will not be prevented from writing to the file unless it uses
# flock to acquire the lock first also. If the resource is only known to your script or set of scripts
# then it works fine.
#
# Example:
#    local mylock
#    startLock -u mylock /etc/bg-lib.conf
#    ... code ...
#    endLock -u mylock
#
#   or
#
#   # putting just startLock with no params will make it so other invocations of the same script will be serialized from that
#   # point to the end of the script
#   startLock
#
# Param:
#    <lockFile> : the default <lockFile> is the script file name ($0) so that only multiple instances of
#                     the script will be serialized in the section that contains the lock .
#                     if the file does not exist the script will touch the file to create it, using sudo if required
#                     the user needs read permission to the file or its an error
# Options:
#    -w <timeoutSeconds> : 0==infinite, default==10 seconds. After <timeoutSeconds> if the lock is still not available
#           it asserts an error.
#    -u <lockVar> : The default file descriptor is 198 which is fine for most use cases. Library code,
#           however can not assume that the script that its being used in is not also locking something
#           so they should not use the default FD. When the -u option is specified, a FD will be dynamically
#           assigned and the variable name <lockVar> will be used to store it so that later endLock can release
#           it. It should be used symetrically in both the startLock and endLock calls. When its used,
#           the -r option can be passed to either the startLock or endLock becuase <lockVar> is used to
#           store all the relavent state from startLock so that it is available in endLock.
#    -q  : quiet. normally it will assert an error if it can not get the lock before timeout. -q makes
#          it quietly return a non-zero exit code instead so the the caller can decide what to do.
# See Also:
#     startLock
#     endLock
#     flock
function startLock()
{
	local sep="|"
	local timeout=10
	local flockFD=198
	local quietFlag flockContextVar
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q)  quietFlag="1" ;;
		-w*) bgOptionGetOpt  val: timeout         "$@" && shift ;;
		-u*) bgOptionGetOpt  val: flockContextVar "$@" && shift
			 flockFD=""
			 ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local lockFile="${1:-$0}"

	declare -gA _bgflockFDCache
	local alreadyOpen
	if [ "$flockFD" ]; then
		local cachedFile="${_bgflockFDCache[$flockFD]}"
		[ "$cachedFile" ] && [ "$lockFile" ] && [ "$cachedFile" != "$lockFile" ] && assertError -v alreadyAllocated:cachedFile -v lockFile -v flockFD "the fd '$flockFD' is already allocated to the file '$cachedFile'"
		[ "$cachedFile" ] && alreadyOpen="1"
	fi
	if [ "$lockFile" ]; then
		local flockFD2="${_bgflockFDCache[$lockFile]}"
		[ "$flockFD2" ] && [ "$flockFD" ] && [ "$flockFD2" != "$flockFD" ] && assertError -v alreadyAllocated:flockFD2 -v requestedFD:flockFD -v lockFile "the lockFile is already assigned the FD '$flockFD2'"
		flockFD="${flockFD:-$flockFD2}"
		[ "$flockFD2" ] && alreadyOpen="1"
	fi

	if [ ! "$alreadyOpen" ]; then
		local execCmd="exec "
		if [ "$flockFD" ]; then
			execCmd+="$flockFD"
		else
			execCmd+="{flockFD}"
		fi

		# the file/folder must exist to use it as a lock
		if [ ! -e $lockFile ]; then
			touch "$lockFile" || assertError
		fi

		# it does not matter to the flock mechanism whether we open the file for reading or writing
		# so we try both to see if we have the permission. If not we have to fail out with an assert.
		if [ -r "$lockFile" ]; then
			eval "${execCmd}<\"$lockFile\""
		elif [ -w $(dirname $lockFile) ]; then
			eval "${execCmd}>>\"$lockFile\""
		else
			assertError "insufficient permissions to use '$lockFile' as a mutex lock"
		fi

		[ "$flockFD" ]  || assertError
		[ "$lockFile" ] || assertError

		# record this (FD,lockFile) association
		_bgflockFDCache[$flockFD]=$lockFile
		_bgflockFDCache[$lockFile]=$flockFD
	fi

	local flockContext="$flockFD:$lockFile"

	# if the -u option was given, store all the context the endLock might need in it
	[ "$flockContextVar" ] && printf -v "$flockContextVar" "%s" "$flockContext"

	# _bgflockStack keeps track of matching startLock and endLock calls
	# flocks are inherited by child procs and we want this stack to mirror that so we can not use an
	# array b/c arrarys are not inheritted by new processes (they are by subshells though)
	declare -gx _bgflockStack
	_bgflockStack="$flockContext${sep}$_bgflockStack"

	# ok, get the flock or die trying.
	if ! flock -w$timeout $flockFD ;then
		local resultCode="$?"
		[ "$quietFlag" ] || assertError -v resultCode -v lockFile -v timeout -v flockFD "could not get lock on $lockFile. Waited $timeout seconds."
		return 2
	fi
	true
}

# usage: endLock [-u <lockVar>] [-r|--remove <lockFile>]
# See startLock for a description.
# if -u option is used in the startLock call, it must be specified the same way in the endLock call.
# <lockFile> is only required if the -r|--remove option is specified to remove the lockFile
# Options:
#    -r|--remove : remove the lockFile after its released. Throws an error if the lockFile can not be determined.
#         if the startLock was  called with -u<lockVar> and <lockFile> specified, then the lockFile name
#         will be stored in the <lockVar> along with <fd> and the -r option if it was specified in the startLock
#         if the startLock is not called that way lockFile can be passed in
# See Also:
#     startLock
#     endLock
#     flock
function endLock()
{
	local sep="|"
	local lockFile flockFD flockContextVar flockContext
	while [[ "$1" =~ ^- ]]; do case $1 in
		-u*) bgOptionGetOpt  val: flockContextVar "$@" && shift
			 flockContext="${!flockContextVar}"
			 IFS=: read -r flockFD lockFile <<<"$flockContext"
			 ;;
		 *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# its ok to call endLock with no parameters which means end the last lock on the stack.
	# its also ok to call it with the same cmd line as the startLock so that the data is provided directly.

	declare -gx _bgflockStack

	[ ! "$_bgflockStack" ] && assertError -v _bgflockStack -v flockFD -v lockFile  "unmatched endLock called. cant end something that's not started. See man startLock."

	local matchByFD="${flockFD:-empty}:[^${sep}]*"
	local matchByLockFile="[^:]*:${lockFile:-empty}"

	# if neither the flockFD nor lockFile was passed in, then pop the first element off the stack  and use its data
	if [ ! "$flockFD$lockFile" ]; then
		flockContext="${_bgflockStack%%${sep}*}"
		_bgflockStack="${_bgflockStack#$flockContext}"; _bgflockStack="${_bgflockStack#$sep}"
		IFS=: read -r flockFD lockFile <<<"$flockContext"

	# if either flockFD or lockFile was specified, find the first entry that matches one or the other b/c maybe both were not provided
	elif [[ "$_bgflockStack" =~ (^|[${sep}])($matchByFD|$matchByLockFile)([${sep}]|$) ]]; then
		local rematch=("${BASH_REMATCH[@]}")
		local newSep=""; [ "${rematch[1]}${rematch[1]}" == "${sep}${sep}" ] && newSep="${sep}"
		_bgflockStack="${_bgflockStack/${rematch[0]}/$newSep}"
		flockContext="${rematch[2]}"

		# merge the values from the stack context we found to fill in things that the caller did not provide
		local flockFD2 lockFile2
		IFS=: read -r flockFD2 lockFile2 <<<"$flockContext"
		flockFD="${flockFD:-$flockFD2}"
		lockFile="${lockFile:-$lockFile2}"

	# if either flockFD or lockFile was specified, but they were not found on the stack, thats an error
	else
		assertError -v _bgflockStack  -v flockFD -v lockFile -v matchByFD -v matchByLockFile "unmatched endLock. The data from a corresponding startLock was not on the stack."
	fi

	# release it
	flock -u "$flockFD" 2>$assertOut || assertError


	# this block closes the FD and prevents the _bgflockFDCache mechanism from caching the open file handles past the endLock call.
	# See the "Sharing the Lock" section of man(3) startLock
	if [ "$flockContextVar" ]; then
		printf -v "$flockContextVar" ""
		unset _bgflockFDCache[$flockFD]
		unset _bgflockFDCache[${lockFile:-empty}]
		exec {flockFD}<&-
	fi
}





#######################################################################################################################################
### From bg_coreProcCntrl.sh

# usage: signalNorm [-l] [-q] <signalSpec> [<retVar>]
# return signalSpec like EXIT HUP TERM INT, etc...
# the trap and kill command allow several different names for each signal. For example, (SIGUSR1, USR1, usr1, and 10) are all the
# same signal. This function returns the canonical name for the signal so that no matter how it is specified, we can determine
# if it is the same signal. It asserts an error if <signalSpec> does not refer to a signal known to 'kill'
# Params:
#     <sigSpec> : can be any token understood by kill. e.g. (SIGUSR1, USR1, usr1, and 10) all refer to signal 10
# Options:
#    -l : list all known SIGNAL names
#    -q : quiet. If <signalSpec> does not exist, return the empty string and return code 1 instead of asserting an error
function signalNorm()
{
	local quietFlag listFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q) quietFlag="-q" ;;
		-l) listFlag="-l" ;;
	esac; shift; done

	if [ ! "${_signalNormData[1]}" ]; then
		declare -gA _signalNormData=(
			[EXIT]=EXIT			[DEBUG]=DEBUG	[RETURN]=RETURN [ERR]=ERR
			[0]=EXIT
			[1]=HUP 		[HUP]=HUP 			[2]=INT 		[INT]=INT
			[3]=QUIT 		[QUIT]=QUIT 		[4]=ILL 		[ILL]=ILL
			[5]=TRAP 		[TRAP]=TRAP 		[6]=ABRT 		[ABRT]=ABRT
			[7]=BUS 		[BUS]=BUS 			[8]=FPE 		[FPE]=FPE
			[9]=KILL 		[KILL]=KILL 		[10]=USR1 		[USR1]=USR1
			[11]=SEGV 		[SEGV]=SEGV 		[12]=USR2 		[USR2]=USR2
			[13]=PIPE 		[PIPE]=PIPE 		[14]=ALRM 		[ALRM]=ALRM
			[15]=TERM 		[TERM]=TERM 		[16]=STKFLT 	[STKFLT]=STKFLT
			[17]=CHLD 		[CHLD]=CHLD 		[18]=CONT 		[CONT]=CONT
			[19]=STOP 		[STOP]=STOP 		[20]=TSTP 		[TSTP]=TSTP
			[21]=TTIN 		[TTIN]=TTIN 		[22]=TTOU 		[TTOU]=TTOU
			[23]=URG 		[URG]=URG 			[24]=XCPU 		[XCPU]=XCPU
			[25]=XFSZ 		[XFSZ]=XFSZ 		[26]=VTALRM 	[VTALRM]=VTALRM
			[27]=PROF 		[PROF]=PROF 		[28]=WINCH 		[WINCH]=WINCH
			[29]=IO 		[IO]=IO 			[30]=PWR 		[PWR]=PWR
			[31]=SYS 		[SYS]=SYS 			[34]=RTMIN 		[RTMIN]=RTMIN
			[35]=RTMIN+1 	[RTMIN+1]=RTMIN+1 	[36]=RTMIN+2 	[RTMIN+2]=RTMIN+2
			[37]=RTMIN+3 	[RTMIN+3]=RTMIN+3 	[38]=RTMIN+4 	[RTMIN+4]=RTMIN+4
			[39]=RTMIN+5 	[RTMIN+5]=RTMIN+5 	[40]=RTMIN+6 	[RTMIN+6]=RTMIN+6
			[41]=RTMIN+7 	[RTMIN+7]=RTMIN+7 	[42]=RTMIN+8 	[RTMIN+8]=RTMIN+8
			[43]=RTMIN+9 	[RTMIN+9]=RTMIN+9 	[44]=RTMIN+10 	[RTMIN+10]=RTMIN+10
			[45]=RTMIN+11 	[RTMIN+11]=RTMIN+11 [46]=RTMIN+12 	[RTMIN+12]=RTMIN+12
			[47]=RTMIN+13 	[RTMIN+13]=RTMIN+13 [48]=RTMIN+14 	[RTMIN+14]=RTMIN+14
			[49]=RTMIN+15 	[RTMIN+15]=RTMIN+15 [50]=RTMAX-14 	[RTMAX-14]=RTMAX-14
			[51]=RTMAX-13 	[RTMAX-13]=RTMAX-13 [52]=RTMAX-12 	[RTMAX-12]=RTMAX-12
			[53]=RTMAX-11 	[RTMAX-11]=RTMAX-11 [54]=RTMAX-10 	[RTMAX-10]=RTMAX-10
			[55]=RTMAX-9 	[RTMAX-9]=RTMAX-9 	[56]=RTMAX-8 	[RTMAX-8]=RTMAX-8
			[57]=RTMAX-7 	[RTMAX-7]=RTMAX-7 	[58]=RTMAX-6 	[RTMAX-6]=RTMAX-6
			[59]=RTMAX-5 	[RTMAX-5]=RTMAX-5 	[60]=RTMAX-4 	[RTMAX-4]=RTMAX-4
			[61]=RTMAX-3 	[RTMAX-3]=RTMAX-3 	[62]=RTMAX-2 	[RTMAX-2]=RTMAX-2
			[63]=RTMAX-1 	[RTMAX-1]=RTMAX-1 	[64]=RTMAX 		[RTMAX]=RTMAX
		)
	fi

	if [ "$listFlag" ]; then
		if ! varExists _signalNormDataDeduped; then
			local -A _tmpDeduper=()
			local i; for i in "${_signalNormData[@]}"; do
				_tmpDeduper[${_signalNormData[$i]}]=1
			done
			declare -g _signalNormDataDeduped=("${!_tmpDeduper[@]}")
		fi
		returnValue "${_signalNormDataDeduped[*]}" "$2"
		return
	fi

	local sn_sigID="${1^^}"
	sn_sigID="${sn_sigID#SIG}"
	sn_sigID="${_signalNormData[${sn_sigID:-emptyStr}]}"
	if [ ! "$sn_sigID" ]; then
		[ ! "$quietFlag" ] && assertError "'$1' is not a signal name known to 'kill'. See 'trap -l' for a list"
		returnValue "" "$2"
		return 1
	fi

	returnValue "$sn_sigID" "$2"
	return 0
}


# usage: bgkillTree [<sigSpec>]] <pid> [ .. <pid>]
# usage: bgkillTree --endScript [--exitCode] [<ppid>]
# usage: bgkillTree --childrenOnly [<ppid>]
# NOTE: This function may become obsolete or changed a lot. bgKill is now a better way to to the --endScript functionality.
#       The original rationale was to make sure the child scripts die with their parents but this is probably done better with
#       figuring out how asynchronous child are identifiable via the pgid or other job control.
# for each <pid> listed, send <sigSpec> to it and each of its descendants.
# This is similar to kill but additionally sends the signal to all descendants of any PIDs specified on the command line.
# All signals are sent in one kill command with the entire group of processes derived listed on that one command line.
# Mode Options:
#    --endScript : does some special processing to end the script and its children. If running a sourced script function
#                  in a terminal, we dont want to exit $$  because it will close the terminal. Instead we send SIGINT
#    --childrenOnly : don't send SIGINT to the <pid> listed on the cmdline -- only to their children
# See Also:
#    kill -<pid>  : similar but uses the process group concept instead of descendants
#    bgKill <pid> : this replaces the --endScript option
function bgkillTree()
{
	local sig mode exitCode
	while [[ "$1" =~ ^- ]]; do case $1 in
		--endScript)    mode="$1" ;;
		--childrenOnly) mode="$1" ;;
		--exitCode*)    bgOptionGetOpt val: exitCode "$@" && shift ;;
		-*) sig="${1#-}" ;;
	esac; shift; done


	case ${mode:-default} in
		default)
			local pidsToKill
			local pidsToCheck=("$@")
			while [ ${#pidsToCheck[@]} -gt 0 ]; do
				local cpid="${pidsToCheck[*]: -1}"
				pidsToKill=("$cpid" "${pidsToKill[@]}")
				pidsToCheck=($(pgrep -P "$cpid") "${pidsToCheck[@]:0:$((${#pidsToCheck[@]}-1))}")
			done
			kill -${sig:-SIGINT} "${pidsToKill[@]}"
			;;
		--endScript|--childrenOnly)
			local ppid="${1:-$$}" # the parent we are terminating
			local pidsToKill=()   # pidsToKill will be all children of $ppid except us (if we are a child)
			local meToKill        # if we are a child of ppid, this will be set with our pid ($BASHPID)
			local pidsToCheckStr=
			local pidsToCheck=($(exec pgrep -P $ppid))
			while (( ${#pidsToCheck[@]} > 0 )); do
				local cpid="${pidsToCheck[@]:0:1}"; pidsToCheck=("${pidsToCheck[@]:1}")
				[ "$cpid" != "$BASHPID" ] && pidsToKill=("$cpid" "${pidsToKill[@]}") || meToKill="$cpid"
				pidsToCheckStr=($(exec pgrep -P $cpid))
				pidsToCheck+=($pidsToCheckStr)
			done
			# send the children (except me if I am one) a HUP
			(( ${#pidsToKill[@]} > 0 )) && kill -${sig:-SIGINT} "${pidsToKill[@]}"
			if [ "$mode" == "--endScript" ]; then
				#local parentSig="SIGHUP"; [ "$bgLibExecMode" == "terminal" ] && parentSig="SIGINT"
				# We started with SIGHUP but it causes bash to print "hangup" to stdout
				# Then we started using SIGINT unconditionally but then bgsudo calls us from a SIGINT handler which cause kill SIGINT to hang
				# TODO: detect if we are being called from a SIGINT handler to avoid kill hanging
				local parentSig=SIGINT
				kill -$parentSig "$ppid" &>/dev/null
			fi
			if [ "$meToKill" ]; then
				if [ "${sig:-SIGINT}" == "SIGINT" ]; then
					builtin exit ${exitCode:-37}
				else
					kill -${sig:-SIGINT} "$meToKill"
				fi
			fi
			;;
	esac
}


# usage: bgExit --complete [<exitCode>]
# This is a wraper over the builtin exit function to exit the current process. It has several advantages over the builtin in scripts.
#
# It wont accidently exit the users terminal. Sometimes when developing a script library it can be useful to source the library into
# the ineractive bash shell to run functions directly. This will detect that situation and will use the SIGTERM signal to stop running
# instead of closing the terminal window.
#
# It also implements a new --complete option that will exit the script completely even when its called in a subshell. In this situation,
# it sends SIGTERM to each of its parents up to and including $$
#
# When a script or library function uses the builtin exit directly, it can be hard for the user to determine if the script worked or
# not and how to fix it if it did not.
#
# By defining a function exit() { bgtrace "exiting... "; bgExit "$@"; }, a script can override most calls to the builtin exit function
# to find places the exit prematurely.
#
# Options:
#    --complete   : exit the script completely, not just the first subshell that bgExit is running in
#    --msg=<msg>  : write msg to stderr and bgtrace before exitting. This is not meant to replace assertError. assertError uses
#                   bExit --msg="..." if it encounters a problem or detects that its been called recursively.
# Params:
#   <exitCode>    : the exit code set that the calling process can check to see how the process ended
function bgExit()
{
	local exitCompletelyFlag _msg
	while [ $# -gt 0 ]; do case $1 in
		--complete|--completely) exitCompletelyFlag="--complete" ;;
		--msg*)
			bgOptionGetOpt val: _msg "$@" && shift
			bgtrace "bgExit: $_msg"
			echo "bgExit: $_msg" >&2
			;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local exitCode="$1"


	if [ "$$" != "$BASHPID" ] || [ "${FUNCNAME[@]: -1}" == "main" ]; then
		if [ "$exitCompletelyFlag" ] && [ "$$" != "$BASHPID" ]; then
			# pidsToKill will be a list of our parents up to and including $$ which we will send SIGTERM to
			local pidsToKill=()
			local pid="$(ps -o ppid= --pid $BASHPID)"
			while (( pid != 0 )) && (( pid != $$ )); do
				pidsToKill+=("$pid")
				pid="$(ps -o ppid= --pid $pid)"
			done
			(( pid != 0 )) && pidsToKill+=("$pid") # the loop stops at $$ without adding it
			touch "${assertOut}.bgExit"
			kill -SIGTERM "${pidsToKill[@]}"
			kill -SIGINT "${pidsToKill[@]}"
		fi
		builtin exit $exitCode
	else
		touch "${assertOut}.bgExit"
		kill -SIGTERM $BASHPID
		kill -SIGINT "$BASHPID"
	fi
}

# usage: BGTRAPEntry <BASHPID> <signal> <lastBASH_COMMAND> <lastLineno> <lastExitCode>
# Params:
#     <BASHPID>
#     <signal>
#     <lastBASH_COMMAND>
# See Also:
#    bgtrap : documents this function in the header and footer section
declare -g bgBASH_trapStkFrm_signal bgBASH_trapStkFrm_funcDepth bgBASH_trapStkFrm_lastCMD bgBASH_trapStkFrm_LINENO bgBASH_trapStkFrm_exitCode bgBASH_trapStkFrm_setPID
declare -gA bgBASH_handlersByPID=(
	[<UNK>-<UNK>]="
		An interupt is starting.

		BASH does not provide enough information to determine which interupt
		but after you step, you should see the handler code.
	"

)
declare -g bgtrapHeaderRegEx="^BGTRAPEntry[[:space:]]([0-9]*)[[:space:]]([A-Z0-9]*)"
function BGTRAPEntry()
{
	local bgDebuggerPlumbingCode=1
	local pidOfSetTrap="$1"
	local signal="$2";              signalNorm "$signal" signal
	local intrrupttedCmd="$3"
	local intrrupttedLineno="$4";   [ "$4" == "1" ] && intrrupttedLineno=""
	local intrrupttedExitCode="$5"; [[ ! "$signal" =~ ^(ERR|DEBUG)$ ]] && intrrupttedExitCode=""

	local intrrupttedFuncDepth=$(( ${#BASH_SOURCE[@]}-1 ))

	#bgtrace "BGTRAPEntry: $pidOfSetTrap $signal interuptedFrame:lineno=$4|$intrrupttedLineno exitCode=$5|$intrrupttedExitCode cmd=$intrrupttedCmd"

	bgBASH_trapStkFrm_signal=(    "$signal"                "${bgBASH_trapStkFrm_signal[@]}"    )
	bgBASH_trapStkFrm_lastCMD=(   "$intrrupttedCmd"        "${bgBASH_trapStkFrm_lastCMD[@]}"   )
	bgBASH_trapStkFrm_LINENO=(    "$intrrupttedLineno"     "${bgBASH_trapStkFrm_LINENO[@]}"    )
	bgBASH_trapStkFrm_exitCode=(  "$intrrupttedExitCode"   "${bgBASH_trapStkFrm_exitCode[@]}"  )
	bgBASH_trapStkFrm_setPID=(    "$pidOfSetTrap"          "${bgBASH_trapStkFrm_setPID[@]}" )
	bgBASH_trapStkFrm_funcDepth=( "$intrrupttedFuncDepth"  "${bgBASH_trapStkFrm_funcDepth[@]}" )
}

function BGTRAPExit()
{
	local bgDebuggerPlumbingCode=1
	bgBASH_trapStkFrm_funcDepth=( "${bgBASH_trapStkFrm_funcDepth[@]:1}" )
	bgBASH_trapStkFrm_lastSignal="$bgBASH_trapStkFrm_signal"
	bgBASH_trapStkFrm_setPID=(    "${bgBASH_trapStkFrm_setPID[@]:1}")
	bgBASH_trapStkFrm_signal=(    "${bgBASH_trapStkFrm_signal[@]:1}"    )
	bgBASH_trapStkFrm_lastCMD=(   "${bgBASH_trapStkFrm_lastCMD[@]:1}"   )
	bgBASH_trapStkFrm_LINENO=(    "${bgBASH_trapStkFrm_LINENO[@]:1}"    )
	bgBASH_trapStkFrm_exitCode=(  "${bgBASH_trapStkFrm_exitCode[@]:1}"  )
}


# usage: bgtrap [-n <name>]              <script>   SIG1 [.. SIGN]
# usage: bgtrap [-n <name>] -r|--remove [<script>]  SIG1 [.. SIGN]
# usage: bgtrap [-n <name>] -p|--print  [<script>] [SIG1 .. SIGN]
# usage: bgtrap [-n <name>] -g|--get    [<script>]  SIG1 [.. SIGN]
# usage: bgtrap [-n <name>] -e|--exits  [<script>]  SIG1 [.. SIGN]
# usage: bgtrap -c|--clear SIG1 [.. SIGN]
# usage: bgtrap -l|--list
#
# bgtrap is a wrapper over the builtin trap that extends it to allow multiple handlers to coexist. See 'help trap' for the builtin trap command
# Script authors can add and remove their handlers without regard to whether other handlers have been
# installed. This is essential for library code that can not make assuptions about what else might
# use a signal handler.
#
# Since the builtin bash trap function overwrites any previous handler with each new handler, bgtrap
# manages an aggregate script for each SIG that is the combined total of all handlers registered.
# It separates the handler scripts with a separator line so that the each handler can be removed
# individually when needed.
#
# Handlers are identified by the -n <name> option if provided or by the exact handler text if not.
# When neither -n <name> nor <script> is specified, the command operates on the whole, aggrate handler
# however this function refuses to set the aggregate handler to the "" or "-" handler
#
# EXIT Trap Inheritance:
# The way that traps are inherited in subshells can be confusing. DEBUG and RETURN are special and dont work the way described here.
# When an EXIT trap is set, it will be invoked only when the BASHPID that it is set in ends. However, in subshells under that BASHPID,
# trap -p EXIT will show the trap handler script from the parent's BASHPID even though that handler wont be called when the subshell
# ends. If the subshell sets a handler, then that handler will be called when it ends and back in the parent process, its handler
# will still be there as it was after the subshell ends.
#
# bgtrap detetects when the handler returned by trap -p does not belong to the current $BASHPID by setting a header line in each
# aggregate handler which includes the $BASHPID of the process that sets the handler.
#
# bgtrap only merges handlers that it knows are being set in the same $BASHPID. If the handler does not have the header, we only
# know what BASHPID it was set in if BASHPID==$$ otherwise, we make the more conservative assumption that the foriegn handler was
# not set in the current subshell and it will not be merged
#
# Agregate Handler Script Header and Footer:
# bgtrap adds a header and footer line to each trap it manages. There are two reasons for this. One permanent and one that is only
# a debugging and error handling aid. Currently they are both active all the time but in a future version the debugging feature may
# be disabled when not running with bgtracing active.
# The first use is to record the BAHPID where the trap was installed to solve the issue described in the EXIT Trap Inheritance Section.
# The second use is to call the BGTRAPEntry and BGTRAPExit functions to record the trap SIGNAL and stack loction for  the bgStack*
# functions and debugger to represent the most accurate information about the script state. The algorithms have progressed to the point
# where its not misleading without the additional information but some stack frames may indicate that there is ambiguity about what
# exactly is running at that frame.
#
# The BGTRAPEntry function sets its signal name and interupted FUNCNAME stack level in the global stack state which is so far, the
# only way the bgStack can know that information at some times.
#
# Information Available in a Trap Handler About the Interupted Code:
# When a trap handler is signaled, we would like to know about where it interupted the script to construct an accurate stack for error
# handling and debugging. The handler function typically does not care about it but for good development tools we need to know.
#     FUNCNAME[0],BASH_SOURCE[0],etc... : the last bash stack represents the function or script ('main', or 'source') that is being
#            ran at the time of the trap but as the trap handler calls function, the indexes change and its no longer easy to determine
#            which stack entry that was. The handler script can record the funcDepth (the size of the FUNCNAME array) when the interupt
#            started running.
#     LINENO : DEBUG (and ERR?) Trap handlers can copy $((LINENO-1)) in its first line which will indicate the line number within the interrupted
#            function or script that will be executed next. However for all other traps, LINENO is reset to '1' upon entering the trap
#            handler so it contains no information about the interupted function.
#     BASH_COMMAND: bash does not update BASH_COMMAND during a DEBUG Trap and it points to the command that will be executed next in
#            the interupted function or script. In other trap handlers, BASH_COMMAND has the peculular behavior that only on the first
#            simple command of the trap, BASH_COMMAND command is not updated so it points to the previous command in the interupted
#            function that was executed. On the second and subsequent simple commands in the handler, it behaives normally.
#
# Relation to Builtin Trap:
# The syntax is backward compatible with the builtin trap function except for two cases.
#    1) the syntax to set the trap to its default state.
#         trap [-] <signal>
#       This throws an exception because it used mean "remove the handler I installed earlier" but
#       with bgtrap it can not mean that because the caller has not passed enough information to identify
#       which handler. Instead, use
#         bgtrap -r -n<name>|<script> <signal> # to remove a previosly installed handler
#         bgtrap -c <signal>                   # if you really want to clear all handlers
#    2) the syntax to disable BASH's the default handling of the signal
#         trap "" <signal>
#       This throws an exception because in practice, the difference between "" and "-" syntax is not
#       well understood so its often used by script authors to mean "remove the handler I installed earlier"
#       When the intention is to really disable BASH's the default handling without also doing an action do
#         trap "#" <signal>
#       Note that this will not remove other installed handlers but it will only ensure that the dault
#       processing wont happen.
# BGENV: BGTRAP_POSIX_REMOVEALL_COMPAT: change the behavior when scripts call trap with the  incompatible syntax 'trap [""|-] <signal>'
#     BGTRAP_POSIX_REMOVEALL_COMPAT=assert       : default. assert an error explaining the alternate syntax to use
#     BGTRAP_POSIX_REMOVEALL_COMPAT=removeUnamed : remove only the unamed handlers. This works if all bgtrap aware code used named handlers
#     BGTRAP_POSIX_REMOVEALL_COMPAT=ignore       : this will quiet the error but the intention of the call will not be honoured
#
# The builtin bash 'trap' will replace the old handler with the new one, effectively uninstalling the previous one if they are set
# in the same BASHPID subshell. bgtrap combines them instead.
#
# If any code calls the builtin trap to set or reset the handler, all the handlers set by bgtrap will be lost.
#
# To prevent that, this library defines a function called trap() to override the builtin trap for any
# scripts that source it.
#
# This requires scrpt authors to use the alternate syntax to remove a handler and to disable the default
# handling of the signal.
#
# This should not be an issue for scripts written for the bg_core.sh environment but if a script
# includes code from another source, it may result in that code throwing assertions if it uses trap.
# That is what needs to happen, however, because otherwise it would produce the more subtle bug that
# handlers installed by bgtrap aware libraries would have there traps silently removed.
#
# There are two fixes to this situation -- either change the offending code or use BGTRAP_POSIX_REMOVEALL_COMPAT
#
# Examples:
#   bgtrap 'echo "hello world"' EXIT
#   # later when the handler is no longer desired...
#   bgtrap -r 'echo "hello world"' EXIT
#
#   bgtrap -n hello 'echo "hello world '"$somevariable"'"' EXIT
#   # later when the handler is no longer desired...
#   bgtrap -r -n hello EXIT
#
# Note that named handlers will be replaced if you install it a second time but a unamed handler will
# have an additional copy installed. Each time its added another copy will be added and each time its
# removed, one copy will be removed.
#
# Params:
#   <script> : a string that contains bash syntax that will be executed when the interupt fires.
#   <SIGN>   : an interupt/signal ID. use -l to list them. numeric values, and names are accepted
# Options:
#   -r : remove. remove a script that was installed earlier from the specified signals
#        there are two ways to identify the  script. First, you can provide the exact, unchanged
#        script text that was passed in to install the script. Second, you can use the -n <name>
#        option that was also used when the script was installed. When using the the -n option with
#        remove, the script can be passed in or not, but either way it will not be used.
#   -n <name> : pass in a name to identify the script. This can be used to later remove the <script>
#        by passing it to the -r option.
#   -c : clear. remove all scripts from the specified signals. It removes all handlers. Some may have
#        been added by library code that you do not know about. Use with caution
#        This is the replacement for 'trap - <signal>'
#   -l : list. show the available signal IDs
#   -e : exists. return 0(true) or n(false) to indicate whether the handler identified by the -n <name>
#        or <script> exist in the specified signals. If neither -n nor <script> is specified, it reuturns
#        0(true) is any handler is set for the signal. If more that one signal is specified it reutrns
#        true only if it exists in all the specified signals otherwise the exist code is the number of
#        signals check that it does not exist in.
#   -g : get. return the handler script. Similar to -p but returns the plain handler text.
#   -v : verbose. make -g pretty print
#   -A <retVar> : -g will return the individual merged handlers in this array variable
#   -p : print. show the current handler installed. Without -n or <script>, it prints the aggregate
#        script that contains all the independent handlers. With -n <name> or <script> is it prints
#        only the identified handler. If the identified handler is not installed, it prints nothing
#        and sets the exit code to 1.  The format is the same as the builtin trap command which is
#        in the form of a trap cmd line that could be used to install the handler. This is not so useful
#        with the added functionality of bgtrap. See -g (get) for a similar option that reutrns the
#        plain handler script text.
function trap() { bgtrap "$@"; }
function bgtrap()
{
	local cmd="add" name firstParamType arrayRet verboseFlag
	local cmdLine="$*"
	local assertErrorContext="-v cmdLine -v cmd -v name -v script"
	while [ $# -gt 0 ]; do case $1 in
		-r|--remove) cmd="remove" ;;
		-n*|--name*) bgOptionGetOpt val: name "$@" && shift ;;
		-c|--clear)  cmd="clear" ;;
		-p|--print)  cmd="print" ;;
		-g|--get)    cmd="get" ;;
		-v|--verbose)verboseFlag="-v" ;;
		-e|--exists) cmd="exists" ;;
		-l|--list)   builtin trap "$@"; return ;;
		-A*) bgOptionGetOpt  val: arrayRet "$@" && shift ;;
		-)  break ;;
		--) shift; break ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# The original trap command has an ambiguous syntax. The first positional param is sometimes a script
	# and sometime not. Common use-cases make it easy for script authors to make a cmd line that looks right
	# but is not so this block tries to make the decision in a way that will at least lead to an
	# understandable error and not a subtle bug. For example 'trap exit exit' is a valid call where
	# the first 'exit' is a script and the second is a signal. 'trap exit' is a valid call where the
	# first 'exit' is now a signal.
	# The following conditions try to respect the original syntax as much as possible. Some common
	# cases will purposely interpret the parameter in a way that leads to an asserted error so that
	# the script author will get the message and clearify the call parameters

	# clear|list never accepts a script and add|remove requires at least one signal
	if [[ "$cmd" =~ ^(clear)$ ]] || { [ $# -eq 1 ] && [[ "$cmd" =~ ^(add|remove)$ ]]; }; then
		firstParamType="signal"

	# except for the trap legacy one parameter case detected above, 'add' requires a script be passed it
	# "" and "-" are not valid signals and are mentioned in 'man trap' as valid values for the
	# 'actions/command/script' parameter so we must detect them as scripts.
	elif [ "$cmd" == "add" ] || [ "$1" == "" ] || [ "$1" == "-" ]; then
		firstParamType="script"

	# most common cases are matched by the first two conditions above
	elif [ "$1" == "exit" ]; then
		# 'exit' is a valid script and signal so take 'exit' to be a script and only 'EXIT' as a signal
		firstParamType="script"
	elif [ "$1" == "EXIT" ]; then
		# 'exit' is a valid script and signal so take 'exit' to be a script and only 'EXIT' as a signal
		firstParamType="signal"
	elif [ ${#1} -gt 12 ]; then
		# no need to call signalNorm if its longer than 12
		firstParamType="script"
	elif [[ "${1}" =~ ^[A-Z+]{3,12}$ ]]; then
		# if its so ambiguous that it gets here, treat all upper case words as signals
		firstParamType="signal"
	elif  signalNorm -q "$1" >/dev/null; then
		firstParamType="signal"
	else
		firstParamType="script"
	fi

	local script; if [ "$firstParamType" == "script" ]; then
		script="$1"; shift

		# this is an integration with bg_objects.sh
		[ "${script:0:12}" == "_bgclassCall" ] && script="${script/|}"

		# catch errors where a signal is missinterpreted as a script (note exit is a valid and common script)
		[[ ! "$script" =~ ^(|-|exit)$  ]] && signalNorm -q "$script" >/dev/null && assertError "Logic Error: the '$script' parameter on the trap cmd line was interpretted as a script but is a valid signal"

		type -t stringRemoveLeadingIndents &>/dev/null && script="$(stringRemoveLeadingIndents "$script")"
	fi

	# if we are being called to add a script that is "" or "-", its the posix/bash syntax meaning
	# either "remove a previously install handler" or "disable the default signal handling"
	# both are commonly used to remove a previously installed handler but bgtrap can not comply because
	# not enough information was provided to know which previously installed handler to remove.
	if [ "$cmd" == "add" ] && [ ! "$name" ] && [[ "$script" =~ ^(|-)$ ]]; then
		case ${BGTRAP_POSIX_REMOVEALL_COMPAT:-assert} in
			ignore)       return 33 ;;
			removeUnamed) cmd="removeAllUnamed" ;;
			assert|*) assertError -V signals:"$*" -v script "
				Use the -r option to remove a previously installed trap handler. See man bgtrap.
				To supress this error, set export BGTRAP_POSIX_REMOVEALL_COMPAT=1

				trap is being called with no options and no <script> to set. Posix defines that to
				remove the previously handler script and set the signal to either be ignored or default.

				In posix trap that was the only way to uninstall a handler but in bgtrap, you can remove
				just one handler and let any other handlers installed by other code remain.

				This posix syntax does not provide enough information to identify which handler should be
				removed so bgtrap refuses to remove all the handlers.
			"
			;;
		esac
	fi

	local sep1=$'\n#<!:'
	local sep2=$':!>\n'

	# CRITICALTODO: bgtrap: change the algorithm and format for combining handlers to add a header line that is always there including the BASHPID
	# that added the handler. If the BASHPID does not match the current BASHPID, then we can overwrite the old handler knowing that
	# bash will restoring it when the current BASHPID exits and that bash's behavior is that teh parent should not be called while
	# the child is running.

	local scriptMatchRE
	if [ "$name" ]; then
		scriptMatchRE="(^|${sep2%$'\n'}|.)${sep1}${name}${sep2}(.*)${sep1}${name}${sep2}(.|${sep1#$'\n'}|$)"
	elif [ "$script" ]; then
		scriptMatchRE="(^|${sep1}${sep2}|${sep2})(${script})(${sep1}|${sep1}${sep2}|$)"
	fi

	# if the script coincidentally contains a sep1 or sep2, escape them from our routines. Everything
	# uses the escaped version except if we print or return the script in any way, we unescape it
	# Its not likely this will happen but for completeness of predictablity, we do it.
	# sep1 by necesity a comment line so escaping will not chage the execution. sep2 may not but we
	# try to be inconspiculous.
	script="${script//${sep1}/${sep1/'#'/##}}"; script="${script//${sep2}/${sep2/'>'/'> '}}"

	# if print mode but neither -n <name> nor <script> was specified to identify a specific handler
	if [ "$cmd" == "print" ] && { [ ! "$scriptMatchRE" ] || [ $# -eq 0 ]; }; then
		builtin trap -p "$@"
		return
	fi

	if [ "$cmd" == "get" ] && [ $# -eq 0 ]; then
		set -- $(signalNorm -l)
		cmd=getAll
	fi


	# all the cmd syntax that do not require at least one signal have already been processed and returned
	[ $# -eq 0 ] && assertError "no signals specified"

	local multipleSigFlag; [ $# -gt 1 ] && multipleSigFlag="1"


	#bgtraceVars -1 cmd name script -l"$*"
	local result=0
	while [ $# -gt 0 ]; do
		local signal="$1"; shift

		# retrieve any previous trap handler that has been set
		local previousScript;
		previousScript="$(builtin trap -p "$signal" 2>$assertOut)" || assertError -v signal -f assertOut "'$signal' is not a valid trap signal"
		local isDefault=""; [ ! "$previousScript" ] && isDefault="1"
		previousScript="${previousScript#*\'}"
		previousScript="${previousScript%\'*}"
		previousScript="${previousScript//"'\''"/\'}"

		# this is the header that we put at the start of every trap handler we set. It servers two purposes.
		# First it embeds the $BASHPID that set the handler so that we can detect when a trap we read with -p was set in a
		# parent's subshell. (except for DEBUG and RETURN handlers, trap handlers are only called when the PID that set them get
		# the signal but trap -p shows the parent's handler even from a child subshell).
		# Second, it allows the debugger to detect when the DEBUG trap gets called at the start of a trap
		# handler.
		local trapHeader='BGTRAPEntry '"$BASHPID"' '"$signal"' "$BASH_COMMAND" "$LINENO" "$?"'
		local trapFooter='BGTRAPExit  '"$BASHPID"' '"$signal"''


		# get the previousScriptPID from the header.
		# Even if there is no header, if $$==$BASHPID, we know that the it was set in $$. This allows us to merge a foriegn script in that case
		local previousScriptPID; [[ "$previousScript" =~ $bgtrapHeaderRegEx ]] && previousScriptPID="${BASH_REMATCH[1]}"
		[ ! "$previousScriptPID" ] && [ "$$" == "$BASHPID" ] && previousScriptPID="$$"

		# Add the header if needed and overwrite the previousScript if it does not belong in the current $BASHPID
		# there are serveral cases where the PIDs dont match but in any of them we init the current handler without any previousScript
		#    (T) previousScriptPID is empty
		#    (T) previousScriptPID is a script we initialized but in a parent shell BASHPID
		#    (T) previousScriptPID is a foriegn script and $$!=$BASHPID so we dont know the PID where it was set
		# If "$previousScriptPID" == "$BASHPID", it might be a foriegn script so we still need to check and add a header if needed.
		if [ "$previousScriptPID" != "$BASHPID" ]; then
			previousScript="$trapHeader"
		elif [[ ! "$previousScript" =~ $bgtrapHeaderRegEx ]]; then
			previousScript="$trapHeader${sep1}${sep2}$previousScript"
		fi

		# if there is a footer, remove it and we will add it back in the end
		previousScript="${previousScript%$trapFooter}"
		previousScript="${previousScript%${sep1}${sep2}}"

		case $cmd in
			clear)  builtin trap - "$signal" ;;
			add)
				local newScript="$previousScript"
				if [ "$name" ]; then
					if [[ "$previousScript" =~ $scriptMatchRE ]]; then
						# replace the script in place so that it preserves its position. To reorder
						# it, remove and re-add in two steps
						newScript="${newScript/${sep1}${name}${sep2}*${sep1}${name:- }${sep2}/${sep1}${name}${sep2}${script//%signal%/$signal}${sep1}${name}${sep2}}"
					else
						# named scripts get a full <sep1><name><sep2> delimiting line before and after it
						# but if its being added next to another named handler so that the separator lines
						# are back to back, we remove a \n so that there is not a blank link in between them
						newScript="${newScript/%${sep2}/${sep2%$'\n'}}"
						newScript="${newScript}${sep1}${name}${sep2}${script//%signal%/$signal}${sep1}${name}${sep2}"
					fi
				else
					# unamed scripts only need a separator if the previous handler that its being added
					# after is also unamed. If its being added after a named handler, that handler already
					# has a suficient separator line that keeps this unamed handler separate from it.
					[ "$newScript" ] && [[ ! "$newScript" =~ ${sep2}$ ]] && newScript+="${sep1}${sep2}"
					newScript+="${script//%signal%/$signal}"
				fi

				# add the trapFooter
				[[ ! "$newScript" =~ ${sep2}$ ]] && newScript+="${sep1}${sep2}"
				newScript+="${trapFooter}"

				# and now set the trap
				builtin trap -- "$newScript" "$signal"  #"atom highlight fix

				# record the handler for this PID
				bgBASH_handlersByPID[${signal}-${BASHPID}]="$newScript"
				;;

			remove|removeAllUnamed)
				if [ "$cmd" == "removeAllUnamed" ]; then
					local -A _bgt_handlers=()
					local aggregateScript newScript token count
					aggregateScript="${previousScript//${sep2%$'\n'}${sep1}/${sep2}${sep1}}"
					local nextName; while stringConsumeNext script aggregateScript "$sep1"; do
						if [ "$nextName" ] && [ "$script" ]; then
							newScript="${newScript/%${sep2}/${sep2%$'\n'}}${sep1}${nextName}${sep2}${script}${sep1}${nextName}${sep2}"
						fi
						local lastName="$nextName"
						stringConsumeNext nextName aggregateScript "$sep2"
						[ "$lastName" == "$nextName" ] && nextName=""
					done
					if [ "$newScript" ]; then
						if [[ "$newScript" =~ ^${sep1#$'\n'} ]]; then
							newScript="$trapHeader$'\n'${newScript}"
						else
							newScript="$trapHeader${sep1}${sep2}${newScript}"
						fi
					fi

				elif [ "$name" ]; then
					# for named we always know exactly what to search for and remove because there is
					# always a full ${sep1}${name}${sep2} before and after the script.
					# The decision is what to replace the removed handler with to make sure
					# the remaining handlers, if any, are still properly delimited.
					#   ${sep1}${sep2} : use this to prevent two unamed handlers from merging
					#   '\n'           : use this when there is a separator (named or unamed) on one or both sides
					#   ''             : use nothing when a UNAMED handler is meeting up with SOL/EOL
					#        SOL   SEP2    UNAMED
					# EOL    ''    '\n'    ''
					# SEP1   '\n'  '\n'    '\n'
					# UNAMED ''    '\n'    ${sep1}${sep2}
					if [[ "${previousScript}" =~ $scriptMatchRE ]]; then
						local rematch=("${BASH_REMATCH[@]}")
						local delB4="${rematch[1]/"${sep2%$'\n'}"/SEP2}";    [ ${#delB4} -eq 1 ]    && delB4="UNAMED";    delB4="${delB4:-SOL}"
						local delAfter="${rematch[3]/"${sep1#$'\n'}"/SEP1}"; [ ${#delAfter} -eq 1 ] && delAfter="UNAMED"; delAfter="${delAfter:-EOL}"
						local replacement; case $delB4:$delAfter in
							UNAMED:UNAMED)   replacement="${sep1}${sep2}" ;;
							*:SEP1 | SEP2:*) replacement=$'\n' ;;
						esac
						#bgtraceVars "" previousScript name delB4 delAfter replacement ""
						local newScript="${previousScript/${sep1}${name}${sep2}*${sep1}${name}${sep2}/$replacement}"
					fi
				else
					# unamed handlers can be delimitted by SOL/EOL or a half or full separator
					# A full separator ($sep1$sep2 ) happens when an unamed handler is adjacent.
					# A half separator ($sep2 OR $sep1) happens when a named handler is adjacent.
					# We will replace the entire matched substring with the right thing to make the
					# handles or SOL/EOL join together correctly.
					#    logicel regex = (SOL|FULLSEP|SEP2)<script>(SEP1|FULLSEP|EOL)
					# if its a half separator it can be part of a named or unamed separator
					#         EOL      SEP1          FULLSEP
					# SOL     ''       SEP1          ''
					# SEP2    SEP2     SEP2-\n+SEP1  SEP2
					# FULLSEP ''       SEP1          FULLSEP
					if [[ "${previousScript}" =~ $scriptMatchRE ]]; then
						local rematch=("${BASH_REMATCH[@]}")
						local replacement; case ${rematch[1]:-SOL}:${rematch[3]:-EOL} in
							SOL:EOL)               replacement="" ;;
							$sep2:$sep1)           replacement=${sep2%$'\n'}${sep1} ;;
							$sep1$sep2:$sep1$sep2) replacement="${sep1}${sep2}" ;;
							$sep2:*)               replacement=${sep2} ;;
							*:$sep1)               replacement=${sep1} ;;
						esac
						#bgtraceVars "" "" rematch previousScript script delB4 delAfter replacement ""
						local newScript="${previousScript/"${rematch[0]}"/$replacement}"
					fi
				fi

				# add the trapFooter
				[[ ! "$newScript" =~ ${sep2}$ ]] && newScript+="${sep1}${sep2}"
				newScript+="${trapFooter}"

				# if it only consists of the header and footer, make it empty
				if [ "$newScript" == "${trapHeader}${sep1}${sep2}${trapFooter}" ]; then
					newScript=""
				fi

				if [ "$newScript" != "$previousScript" ] && [ "$newScript" ]; then
					builtin trap -- "${newScript}" "$signal"
					# record the handler for this PID
					bgBASH_handlersByPID[${signal}-${BASHPID}]="$newScript"
				elif [ "$newScript" != "$previousScript" ] && [ ! "$newScript" ]; then
					builtin trap - "$signal"
					# record the handler for this PID
					bgBASH_handlersByPID[${signal}-${BASHPID}]="-"
				else
					((result++))
				fi
				;;

			print)
				if [ ! "$scriptMatchRE" ]; then
					[ "$previousScript" ] && echo "trap -- '$previousScript' $signal"
				elif [[ "$previousScript" =~ $scriptMatchRE ]]; then
					script="${BASH_REMATCH[2]}"
					# unescape sep1/sep2 before returning
					script="${script//${sep1/'#'/##}/${sep1}}"; script="${script//${sep2/'>'/'> '}/${sep2}}"
					echo "bgtrap ${name:+-n $name }-- '$script' $signal"
				else
					((result++))
				fi
				;;

			get|getAll)
				if [ ! "$scriptMatchRE" ]; then
					local -A _bgt_handlers=()
					local _bgt_handlerIDs=()
					local aggregateScript script count=0
					aggregateScript="${previousScript//${sep2%$'\n'}${sep1}/${sep2}${sep1}}"
					local nextName; while stringConsumeNext script aggregateScript "$sep1"; do
						if [ "$nextName" ] && [ "$script" ]; then
							_bgt_handlerIDs+=("${multipleSigFlag:+$signal:}$((count)):$nextName")
							_bgt_handlers[${multipleSigFlag:+$signal:}$((count++)):$nextName]="$script"
						elif [ "$script" ]; then
							_bgt_handlerIDs+=("${multipleSigFlag:+$signal:}$((count)):unnamed")
							_bgt_handlers[${multipleSigFlag:+$signal:}$((count++)):unnamed]="$script"
						fi
						local lastName="$nextName"
						stringConsumeNext nextName aggregateScript "$sep2"
						[ "$lastName" == "$nextName" ] && nextName=""
					done
					[ "$arrayRet" ] && arrayCopy _bgt_handlers "$arrayRet"
					if [ ! "$arrayRet" ]; then
						if { [ "$multipleSigFlag" ] && [ ${#_bgt_handlers[@]} -gt 0 ]; } || [ "$cmd" != "getAll" ]; then
							printf "%s: %s\n" "$signal" "${isDefault:+(DEFAULT)}"
							local handlerID; for handlerID in "${_bgt_handlerIDs[@]}"; do
								printf "   %s: '\n      %s'\n" "${handlerID##*:}" "${_bgt_handlers[$handlerID]//$'\n'/$'\n'      }"
							done
						fi
					fi
				elif [[ "$previousScript" =~ $scriptMatchRE ]]; then
					script="${BASH_REMATCH[2]}"
					# unescape sep1/sep2 before returning
					script="${script//${sep1/'#'/##}/${sep1}}"; script="${script//${sep2/'>'/'> '}/${sep2}}"
					echo "$script"
				else
					((result++))
				fi
				;;

			exists)
				if [ ! "$scriptMatchRE" ]; then
					[ ! "$previousScript" ] && ((result++))
				elif [[ ! "$previousScript" =~ $scriptMatchRE ]]; then
					((result++))
				fi
				;;
		esac

		[ "$signal" == "ERR" ] && bgtrap_lastErrHandler="${newScript:-$previousScript}"
	done
	return $result
}


# usage: bgTrapStack peek <sig> [<handlerVar>]
# usage: bgTrapStack pop <sig> [<handlerVar>]
# usage: bgTrapStack push <sig> <handler>
# For some ways the traps are used (particularely DEBUG traps) a different pattern than bgtrap's aggregateScript is called for.
# bgTrapStack implements a pattern of pushing the previous handler onto a global variable stack and replacing it when done.
# There may be complications for subshells so be catious using this.
# See Also:
#      Library bg_debugger.sh -- uses this
#      Library bg_coreAssertError.sh -- uses this
function bgTrapStack()
{
	local action="$1"; shift
	local sig; signalNorm "$1" sig; shift; assertNotEmpty sig

	local stackVar="bgBASH_trapStack$sig"

	case $action in
		peek|pop)
			local handlerVar="$1"
			local handler="${!stackVar}"
			if [ "$action" == "pop" ]; then
				declare -ag $stackVar'=( "${'"$stackVar"'[@]:1}" )'
				# 2020-10 for empty handler changed '-' to ''  (${handler:--} to ${handler})  b/c in test case, Catch was not clearing the DEBUG trap when it called this function
				builtin trap "${handler}" "$sig"
			fi
			returnValue -q "$handler" "$handlerVar"
			;;
		push)
			local newHandler="$1"
			local handler="$(builtin trap -p $sig)"
			handler="${handler#*\'}"
			handler="${handler%\'*}"
			handler="${handler//"'\''"/\'}" # trap -p returns escaped single quotes like 'bob'\''s fine'

			# we push in two steps because handler might have single quotes which would mess up  the array element parsing
			declare -ag $stackVar'=( "" "${'"$stackVar"'[@]}" )'
			printf -v $stackVar[0] "%s" "$handler"
			builtin trap "${newHandler:--}" "$sig"
			;;
	esac
}

# usage: bgTrapUtils getAll [<retArray>]
# usage: bgTrapUtils [--pid=<setPID>] get <signal> [<retString>]
# usage: bgTrapUtils ...
# This libary provides two patterns for dealing with common trap use cases -- bgtrap and bgTrapStack. This function provides a place to
# put lower level algorithms that manipulate the builtin trap function that may be used by either pattern or system code that
# users neither pattern
function bgTrapUtils()
{
	local setPID
	while [ $# -gt 0 ]; do case $1 in
		--pid*)  bgOptionGetOpt val: setPID "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local cmd="$1"; shift

	case $cmd in
		get)
			local _tu_signal="$1"; shift
			local _tu_handler
			if [ "$setPID" ]; then
				_tu_handler="${bgBASH_handlersByPID[${_tu_signal}-${setPID}]}"
			else
				_tu_handler="$(builtin trap -p $_tu_signal)"
				_tu_handler="${_tu_handler#*\'}"
				_tu_handler="${_tu_handler%\'*}"
				_tu_handler="${_tu_handler//"'\''"/\'}"
			fi

			returnValue "$_tu_handler" "$1"
			;;

		getAll)
			local numLinesFlag
			while [ $# -gt 0 ]; do case $1 in
				-n|--numberedLines) numLinesFlag="-n" ;;
				*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
			done

			local trapString="$(builtin trap -p)"
			local -A _tu_trapHandlers
			local _tu_signal _tu_handler sep line inTrap lineno
			while IFS="" read -r line; do
				if [ ! "$inTrap" ] && [[ "$line" =~ ^(trap[[:space:]][[:space:]]*--[[:space:]][[:space:]]*\') ]]; then
					inTrap="1"
					line="${line#*\'}"
					lineno=1
				fi

				if [ "$inTrap" ] && [[ "$line" =~ (^|[^\'])\'[[:space:]][[:space:]]*([A-Z0-9]*)$ ]]; then
					inTrap=""
					_tu_signal="${BASH_REMATCH[2]}"
					line="${line%\'*}"
					printf -v _tu_handler "%s%s%s" "$_tu_handler" "$sep" "${numLinesFlag:+$((lineno++)): }$line"
					_tu_handler="${_tu_handler//"'\''"/\'}"
					_tu_trapHandlers[${_tu_signal:-exmpty}]="$_tu_handler"
					_tu_signal=""
					_tu_handler=""
					sep=""
				fi

				if [ "$inTrap" ]; then
					printf -v _tu_handler "%s%s%s" "$_tu_handler" "$sep" "${numLinesFlag:+$((lineno++)): }$line"
					sep=$'\n'
				fi
			done  <<<"$trapString"
			returnValue --array _tu_trapHandlers "$1"
			;;

		# this is used by the bgStack code so it can quickly lookup [<trap>:<lineno>] for any trap and lineno
		getAllAsNumberedLines)
			local trapString="$(builtin trap -p)"
			local -A _tu_trapHandlers
			local _tu_signal _tu_handler sep line inTrap lineno
			while IFS="" read -r line; do
				if [ ! "$inTrap" ] && [[ "$line" =~ ^(trap[[:space:]][[:space:]]*--[[:space:]][[:space:]]*\') ]]; then
					inTrap="1"
					line="${line#*\'}"
					lineno=1
				fi

				if [ "$inTrap" ] && [[ "$line" =~ (^|[^\'])\'[[:space:]][[:space:]]*([A-Z0-9]*)$ ]]; then
					inTrap=""
					_tu_signal="${BASH_REMATCH[2]}"
					line="${line%\'*}"
					printf -v _tu_handler "%s%s%s" "$_tu_handler" "$sep" "%CURRENTTRAP%:$((lineno++)): $line"
					_tu_handler="${_tu_handler//"'\''"/\'}"
					_tu_trapHandlers[$_tu_signal]="$_tu_handler"
					_tu_signal=""
					_tu_handler=""
					sep=""
				fi

				if [ "$inTrap" ]; then
					printf -v _tu_handler "%s%s%s" "$_tu_handler" "$sep" "$line"
					sep=$'\n'
				fi
			done  <<<"$trapString"
			returnValue --array _tu_trapHandlers "$1"
			;;
	esac
}


#######################################################################################################################################
### From bg_coreAssertError.sh

# usage: (not called directly -- called by bash when a non-existent command is invoked)
function command_not_found_handle()
{
	local cmdName="$1"
	local cmdline="$*"
	# if [ "${command_not_found_handle}" == "1" ]; then
	# 	assertError -e127 --critical -v cmdline "Command not found -- recursion detected"
	# fi
	export command_not_found_handle=1

	# recognize $foo.something... object syntax where the $foo variable is empty
	if [[ "$cmdName" =~ ^[.[] ]]; then
		local -A exprFrame; bgStackFrameGet  command_not_found_handle:+1 exprFrame

		msg="empty object variable referenced. '${exprFrame[cmdSrc]}'  cmdline='$cmdline'"
#		assertError -e127 --continue  --no-funcname -v "objExpression:exprFrame[cmdSrc]" "empty object variable referenced"
	else
		msg="Command not found. cmdline='$cmdline'"
	#	assertError -e127 --continue --no-funcname --frameOffset=+1 -v cmdline "Command not found"
	fi

	bgtraceStack
	bgtrace "$msg"
	echo "$msg" >&2
}



# usage: assertError [-c] [-e <exitCode>] [-v <var>] [-V [<label>:]<data>] [-f <filename>] <errorDescription>"
# The assertError* family of functions are meant to be called when a script of library function can not complete its intended task.
# It is similar to throwing an exception in other languages.
#
# Family of assertError Functions:
# A script can call assertError directly when it checks some condition and wants to fail if its not true
#    Example:
#          [ $count -gt 100 ] && assertError
#
# There are also a family of assert* functions that check various things. A common pattern is to require
# that a input parameter is provided.
#          local name="$1"; assertNotEmpty name
#
# Error Context:
#   The signature of assertError is designed to make it easy to collect information about the current context where it is called so
#   that the operator can better understand why the script failed and what they might do to correct the situation.
#
#   The <errorDescription> positional parameter allows the script author to say why the script can not proceed. If it is ommitted,
#   one will be generated from the source line that the assertError is on. For example...
#         mkdir -p "$myPath" || assertError
#   will create a <errorDescription> from that line of script and also add $myPath to the -v options so that its value is displayed.
#   In general, an <errorDescription> should be provided for high level asserts that make sense in the concept of the top level script
#   but often not provided in low level library functions that do not know any additional context about how it is being used.
#
#   The call stack of where assertError was called is recorded and provides the valuable context of why low level library functions
#   are beig invoked when they fail. By default, the call stack is written only to the bgtrace output so re-running a command with
#   tracing turned on to stderr will provide additional information about the failure.
#
#   The -v -V -f options pass in context that can be displayed with the error message to help the user
#   understand why they got the error and what to do about it.
#
#   You can set the assertErrorContext at the top of a function to cause any assertErrors called during
#   that function to include that context.
#
#       local assertErrorContext=" -v myVar -f someFile "
#       or
#       assertErrorContext+=" -v myVar -f someFile "
#       or
#       assertErrorContext+=(-v myVar -f "Some File")
#
# .SH Handling or passing on Errors (aka exceptions):
#   assertError can perform one of four actions when it is called.
#        1) abort -- terminate the entire script even if if it is being called in a subshell where the builtin exit function would
#                    only terminate the subshell and not the top level script.
#        2) exitOneShell -- similar to calling the builtin exit function this will just terminate the subshell that it is called in
#                    which will only terminate the script if its not called in a subshell
#        3) continue -- do not alter the script execution. Display the error and continue executing the rest of the script
#        4) catch -- use BASH's DEBUG trap to continue exceution at the first enclosing Catch: statement
#
#   The default behavior is to examine the tryState stack and perform the action specified in the top entry. If the stack is empty
#   perform the 'abort' action. The tryStack is maintained by Try: and Catch: statements in the code so when the code is executing
#   inside a Try:/Catch: block of code the top entry will specify the 'catch' action and information about how to efficiently find
#   the first enclosing Catch: statement.
#
#   The default behavior can be changed either by specifying the the --critical, --exitOneShell, or --continue options. In this case
#   the tryState stack will be ignored.
#
# Try:/Catch: Syntax:
#    Try:
#        <myCode>...
#    Catch: && {
#        <code to exec if anything in <myCode> calls assertError>
#    }
#
# .SH Assert/Exception subclasses:
#   It is common for a library to create a specific assert for a particular condition that is specific to the library. This creates
#   a family of assert* functions. By convention they should be named with assert* (dropping the Error part) and they should shift
#   any parameters specific to what they are checking and then pass the rest of the command line to assertError "$@"
#   Example
#       # usage: assertFileExists <filename> [<options>] [<message>]
#  		function assertFileExists()
#  		{
#  			local filename="$1"; shift
#  			if [ ! -f "$filename" ]; then
#  				assertError -v filename "$@"
#  			fi
#  		}
#       # and is called like this. Note that the assertError options will appear after the parameters specific the the subclass.
#       assertFileExists "$myFile"  -v contexVar1 -v contextVar2 "myFile is missing"
#
# Options:
#    Options that override the default action and the Catch mechanism.
#     --critical     : indicate that a critical error is being raised and the script should abort without consider Try/Catch state
#     --exitOneShell : change the action to be similar to the builtin exit function instead of terminating the entire script.
#     -c|--continue  : change the action to do nothing so that the error is displayed but the script execution continues.
#
#     Options that add Context
#     -e <exitCode>  : set the exitcode that will be used to to terminate the process
#     -v <varName>   : add variable context. display the value of <varName> as additional context to the error message
#                     -v can be specified multiple times to display multiple variables
#     -V <contextData> : like -v except the data value is passed directly.
#                     -V can be specified multiple times to display multiple data
#     -f <filename>  : add file context. display the contents of <filename> as additional context to the error message
#                     -f can be specified multiple times to display multiple variables
#
#     Options that change the way the stack is shown
#     --frameOffset <frameOffset> : the number of stack frames to skip before selecting the one to use in the msg
#
# Params:
#    <errorDescription>  : A statement about why the script is failing. If left empty, the source line will be examined to create
#                     an <errorDescription> and add context variable for any variable reference in that source line
function assertError()
{
	# if varExists _ae_exitCodeLast; then
	# 	[ -w /dev/tty ] && echo "critical error: an assertError was called during an assertError call." >/dev/tty
	# 	bgtrace "critical error: an assertError was called during an assertError call."
	# 	declare -g assertError_EndingScript="1"
	# 	bgExit --complete ${_ae_exitCode:-37}
	# 	[ -w /dev/tty ] && echo "error: logic error. bgExit did not stop this line from executing" >/dev/tty
	# 	bgtrace "error: logic error. bgExit did not stop this line from executing"
	# fi

	local _ae_exitCodeLast="$?"
	local _ae_msg _ae_exitCode=36 _ae_actionOverride _ae_contextVarName _ae_catchAction _ae_catchSubshell _ae_frameOffsetTerm=1
	local -A _ae_dFiles _ae_contextVarsCheck=([empty]=1)
	local _ae_dFilesList _ae_contextVars _ae_contextOutput _ae_noFuncnameFlag _ae_stackSourceFlag _ae_stackDebugFlag
	local _ae_traceCatchFlag _ae_alreadyFrozenFlag

	# TODO: we need to figure out a good way to associate assertErrorContext with the tryStack so that we stop at the right level
	### add any assertErrorContext data to the command line parameters.
	while [ "${assertErrorContext+exists}" ]; do
		# the rational of this line is that assertErrorContext can be assigned as either a simple
		# string (which bash conveniently says assertErrorContext[0] is alias for), or as an array
		# as a string we want to do word splitting to separate the multiple options in the string
		# as an array we want to use "${assertErrorContext[@]}"
		# this allows script authors to use assertErrorContext as a simple string or as an array in
		# a way that coexists
		if varIsA array assertErrorContext; then
			set -- ${assertErrorContext[0]} "${assertErrorContext[@]:1}" "$@"
		else
			set -- $assertErrorContext "$@"
		fi
		unset assertErrorContext
	done

	### process the command line
	while [[ "$1" =~ ^- ]]; do case $1 in
		--alreadyFrozen) _ae_alreadyFrozenFlag="--alreadyFrozen" ;;
		--traceCatch)    _ae_traceCatchFlag="--traceCatch" ;;
		--no-funcname)   _ae_noFuncnameFlag="--no-funcname" ;;
		--sourceInStack) _ae_stackSourceFlag="--source" ;;
		--stackDebug)    _ae_stackDebugFlag="--stackDebug" ;;
		--critical)      _ae_actionOverride="abort" ;;
		-c|--continue)   _ae_actionOverride="${_ae_actionOverride:-continue}" ;;
		--exitOneShell)  _ae_actionOverride="${_ae_actionOverride:-exitOneShell}" ;;
		-e*) bgOptionGetOpt val: _ae_exitCode "$@" && shift
			_ae_exitCode="${_ae_exitCode//[^0-9]}"
			;;
		-V*)
			# the parameter passed is the data to be displayed, not the name of the variable that contains the data
			genRandomIDRef _ae_contextVarName
			bgOptionGetOpt val: _ae_contextVarNameValue "$@" && shift
			if [[ "$_ae_contextVarNameValue" =~ ^([a-zA-Z_][a-zA-Z_0-9]*): ]]; then
				_ae_contextVarName="${BASH_REMATCH[1]}"
				_ae_contextVarNameValue="${_ae_contextVarNameValue#"$_ae_contextVarName:"}"
			fi
			varSetRef "$_ae_contextVarName" "$_ae_contextVarNameValue"
			# TODO: after printfVars supports renamed vars like "<displayVarName>:<varNameWithData>" use that here
			[ ! "${_ae_contextVarsCheck["${_ae_contextVarName:-empty}"]}" ] && _ae_contextVars+=("$_ae_contextVarName")
			_ae_contextVarsCheck["${_ae_contextVarName:-empty}"]=1
			;;
		-v*)
			bgOptionGetOpt val: _ae_contextVarName "$@" && shift
			[ ! "${_ae_contextVarsCheck["${_ae_contextVarName:-empty}"]}" ] && _ae_contextVars+=("$_ae_contextVarName")
			_ae_contextVarsCheck["${_ae_contextVarName:-empty}"]=1
			;;
		-f*)
			local _ae_label _ae_filename dVar
			bgOptionGetOpt val: dVar "$@" && shift
			splitString -d":" "$dVar" _ae_filename _ae_label
			if [ ! "$_ae_label" ] && [ ! -f "$_ae_filename" ] && [[ ! "$dVar" =~ [[:space:]]  ]]; then
				_ae_label="$dVar"
				_ae_filename="${!dVar}"
			fi
			_ae_label="${_ae_label:-$_ae_filename}"
			_ae_dFiles[$_ae_label]="$_ae_filename"
			_ae_dFilesList+=" $_ae_label"
			;;
		--frameOffset*) bgOptionGetOpt val: _ae_frameOffsetTerm "$@" && shift ;;
	esac; shift; done



	##############################################
	### assemble the context

	# this captures the current stack in a set of bgStack* global vars. It detects and adds trap invocations into the stack
	# this is also used to freeze the stack so that when we call functions that operate on it, it wont change like the FUNCNAME
	# and other bash maintained stack vars
	# --logicalStart=0 means that this assertError call will be the first (zero'th) element in the stack
	if [ ! "$_ae_alreadyFrozenFlag" ]; then
		bgStackFreeze --all
	fi

	# this adjusts the message format so that convenient source code formatting of the msg text over multiple lines will produce
	# pretty output for the user.
	# Also, If the msg is empty, it will glean information from the source line to create a meaningful output and add variables
	# that are referenced in the line to the _ae_contextVars array
	assertDefaultFormatter "$@"

	# find the name of the first assert* function that led to this assertError being called. An assert* function might be implemented
	# by calling another assert*  function which ultimately calls this one. The first one will be the most specific that we will
	# attribute this exception to. The _ae_assertFunctionName is used as the exception class for the purpose of choosing a Catch block
	local _ae_stackAssertFnIdx; bgStackFrameFind '^[aA]ssert' _ae_stackAssertFnIdx
	local _ae_assertFunctionName="${bgSTK_cmdName[_ae_stackAssertFnIdx]}"

	# the failing function is the one where the error ocurred. Typically it is the one that called the assertFunctionName we
	# just identified but some library code uses the --frameOffset option to indicate that we should consider a different function
	# on the stack as the failing function.  bgOptionsEndLoop does that because its the function that called bgOptionsEndLoop that
	# contains the error in its options processing loop that lead to bgOptionsEndLoop failing.
	[[ "$_ae_frameOffsetTerm" =~ ^[+-]?[0-9]*$ ]] && _ae_frameOffsetTerm="${_ae_assertFunctionName}:${_ae_frameOffsetTerm:-1}"
	local _ae_stackFailingFnIdx; bgStackFrameFind "$_ae_frameOffsetTerm" _ae_stackFailingFnIdx
	local _ae_failingFunctionName="${bgSTK_cmdName[$_ae_stackFailingFnIdx]}"

	# get the action from the Try/Catch stack. If not being caught, the default action is to abort the script
	# the caller can use the --critical, --exitOneShell, or --continue options to override the action
	local tryStateAction="${bgBASH_tryStackAction[@]:0:1}"; tryStateAction="${tryStateAction:-abort}"
	[ "$_ae_actionOverride" ] && tryStateAction="$_ae_actionOverride"




	##############################################
	### format and write the error message

	# ae_outFD is the FD that we write the error message to. It will be stdout normally or the file $assertOut.catchDescription
	# if we are going to catch the exception.
	local ae_outFD=2; [ "${tryStateAction}" == "catch" ] && exec {ae_outFD}>$assertOut.catchDescription

	echo >&$ae_outFD
	if [ ! "$_ae_noFuncnameFlag" ]; then
		echo -e "error: $_ae_failingFunctionName: $_ae_msg" >&$ae_outFD
	else
		echo -e "error: $_ae_msg" >&$ae_outFD
	fi

	printfVars "    " "${_ae_contextVars[@]}" >&$ae_outFD

	# display any file content that was provided
	local _ae_label; for _ae_label in $_ae_dFilesList; do
		printf "   %s:\n" "$_ae_label" >&$ae_outFD
		[ -f "${_ae_dFiles[$_ae_label]}" ] && awk '
			{printf("   %3s : %s\n", NR, $0)}
		' "${_ae_dFiles[$_ae_label]}"
	done

	# the assertDefaultFormatter sets _ae_contextOutput when the source line redirects to 2>$assertOut
	if [ "$_ae_contextOutput" ] && [ -s "$_ae_contextOutput" ]; then
		printf "    stderr output=\n" >&$ae_outFD
		awk '
			{print "      : "$0}
		' "${_ae_contextOutput}" >&$ae_outFD
	fi

	# write a blank line at the end and close the FD if we openned it.
	# we only write the blank line if bgtrace is not set to stdout because in the next section we write the stack to bgtrace and
	# if they are going to the same place, we dont want to separate them.
	[ "$_bgtraceFile" != "/dev/stderr" ] && echo >&$ae_outFD
	[ ${ae_outFD:-0} -ne 2 ] && exec {ae_outFD}>&-




	##############################################
	### BGTRACE: format and write information bgtrace output
	# we write more information to bgtrace so that an admin can get more information by re-running with bgtrace on

	# write the stack to bgtrace
	# We write the stack to bgtrace even if we are catching the exception b/c a pipeline might cause several
	# exceptions and only the last one will make it into assertOut so bgtrace might be the only place to see some
	# The unit test runner uses bgAssertErrorInhibitTrace to prevent many expected exceptions from spamming the bgtrace output
	[ ! "$bgAssertErrorInhibitTrace" ] \
		&& bgtraceStack $bgErrorStack $_ae_stackSourceFlag $_ae_stackDebugFlag --ignoreFramesCount=$((_ae_stackAssertFnIdx))



	##############################################
	### Perform the script Flow action

	# if this exception is not being caught, check to see if we should invoke the debugger
	if [ "$tryStateAction" != "catch" ] && { { debuggerIsActive && ! debuggerIsInBreak; } || [ "$bgDebuggerStopOnAssert" ]; }; then
		bgtraceBreak
	fi

	# tryStateAction is the top element of the bgBASH_tryStack which indicates the enclosing Try block that we are being
	# called in.
	case ${tryStateAction:-default} in
		continue)
			return ${_ae_exitCode:-36}
			;;

		exitOneShell)
			bgExit ${_ae_exitCode:-36}
			;;

		abort|default)
			declare -g assertError_EndingScript="1"
			bgExit --complete ${_ae_exitCode:-36}
			#bgkillTree --endScript --exitCode=${_ae_exitCode:-36} $$
			echo "error: logic error. bgExit did not stop this line from executing"
			;;

		catch)
			local tryStatePID="${bgBASH_tryStackPID[@]:0:1}"
			local throwingStatePID="$BASHPID"

			if [ "$_ae_traceCatchFlag" ]; then
				bgtrace "!!!throwing exception "
				bgtrace "   PID of throw ='$throwingStatePID'"
				bgtrace "   PID of catch ='$tryStatePID'"
				bgtracePSTree
				declare -g traceCatchFlag="1"
			fi

			## fill in pidsToKill with each pid between where the assert is being thrown (throwingStatePID) and where it will be
			# caught (tryStatePID)
			local pidsToKill=()
			if [ "$throwingStatePID" != "$tryStatePID" ]; then
				local pid="$(ps -o ppid= --pid "$throwingStatePID")"
				while (( pid != 0 )) && (( pid != tryStatePID )) && (( pid != $$ )); do
					pidsToKill+=("$pid")
					pid="$(ps -o ppid= --pid $pid)"
				done
				(( pid != tryStatePID )) && assertError --critical  -v pstreeOfTry:"-l$(bgGetPSTree "$tryStatePID")" -v pstreeOfThrow:"-l$(bgGetPSTree "$throwingStatePID")" "
					Try/Catch Logic Failed. PID of Try block($tryStatePID) is not a parent of PID of asserting exception($BASHPID)"
			fi

			## Record the state at this point that the exception is being raised

			declare -g catch_psTree; bgGetPSTree "$$" catch_psTree
			declare -gx	catch_errorCode="$_ae_exitCode"
			declare -gx	catch_errorClass="$_ae_assertFunctionName"
			declare -gx	catch_errorFn="$_ae_failingFunctionName"
			declare -gx	catch_errorDescription="$(cat $assertOut.catchDescription)"

			## record the state in $assertOut.* files if catch that is receiving this exception is in a different subshell
			if [ "$BASHPID" != "$tryStatePID"  ]; then
				bgStackMarshal "$assertOut.stkArrayRaw"
				echo "$catch_psTree" >"$assertOut.psTree"
				echo "$catch_errorCode $catch_errorClass $catch_errorFn" >>$assertOut.errorInfo
			else
				[ -f "$assertOut.stkArrayRaw" ] && rm "$assertOut.stkArrayRaw"
				[ -f "$assertOut.psTree" ]      && rm "$assertOut.psTree"
				[ -f "$assertOut.errorInfo" ]   && rm "$assertOut.errorInfo"
			fi

			## now throw the exception up to the nearest catch

			# for unitTest framework, disable the ERR trap when we assert
			builtin trap '' ERR

			# the goal is that we want the tryStatePID process to wake up an receive the SIGUSR2 signal.
			# If we are a synchronous child subshell of the tryStatePID, then we, and any subshells inbetween us that tryStatePID
			# must end before it will wake up. We can simply exit but we need to send the intermediate processes a SIGINT.
			# Since bash processes signals inbetween the simple commands that it runs, when we send the signals to our parents
			# they will be queued until we exit which should cause a chain reaction of each parent waking and ending up to the tryStatePID
			# whose SIGUSR2 trap handler will install a DEBUG handler that will skip simple commands until it finds a "Catch".
			# Some bash commands are interuptable by SIGINT but if we are running a bash script, all the parents between us and
			# tryStatePID must be bash subshells stopped on bash functions.
			[ "$_ae_traceCatchFlag" ] && bgtrace "!!! kill -SIGUSR2 $tryStatePID  "
			kill -SIGUSR2 "$tryStatePID"     # this wont return if we are tryStatePID
			(( ${#pidsToKill[@]} > 0 )) && kill -SIGINT "${pidsToKill[@]}"
			[ "$tryStatePID" != "$BASHPID" ] && bgExit  ${_ae_exitCode:-36}
			[ "$_ae_traceCatchFlag" ] && bgtrace "!!! returning normally. this is an error"
			;;

		*)	echo "error: logic error. In assertError the action was computed to be '$tryStateAction' but should be one of catch,abort,continue,exitOneShell"
			bgExit --complete ${_ae_exitCode:-36}
			;;
	esac
}

# usage: Rethrow
# This is used to re-throw the exception caught in a Catch: block. It should only ever be called from inside a Catch block.
# It is similar to calling assertError except that it takes no arguments because it takes the arguments from the assertError call
# that was caught.
function Rethrow()
{
	# get the action from the Try/Catch stack. We should be within a Catch: block, but that means Catch: already finished running
	# so that Try/Catch has already been removed from the stack so that this one will be the next higher Try/Catch if there is one.
	local tryStateAction="${bgBASH_tryStackAction[@]:0:1}"; tryStateAction="${tryStateAction:-abort}"

	echo "$catch_errorDescription" >&2

	# if this exception is not being caught, check to see if we should invoke the debugger
	if [ "$tryStateAction" != "catch" ] && { { debuggerIsActive && ! debuggerIsInBreak; } || [ "$bgDebuggerStopOnAssert" ]; }; then
		bgtraceBreak
	fi

	case ${tryStateAction:-default} in
		continue)
			return ${_ae_exitCode:-36}
			;;

		exitOneShell)
			bgExit ${_ae_exitCode:-36}
			;;

		abort|default)
			declare -g assertError_EndingScript="1"
			bgExit --complete ${_ae_exitCode:-36}
			#bgkillTree --endScript --exitCode=${_ae_exitCode:-36} $$
			echo "error: logic error. bgExit did not stop this line from executing"
			;;

		catch)
			local tryStatePID="${bgBASH_tryStackPID[@]:0:1}"
			local throwingStatePID="$BASHPID"

			if [ "$_ae_traceCatchFlag" ]; then
				bgtrace "!!!Re-throwing exception "
				bgtrace "   PID of throw ='$throwingStatePID'"
				bgtrace "   PID of catch ='$tryStatePID'"
				bgtracePSTree
				declare -g traceCatchFlag="1"
			fi

			## fill in pidsToKill with each pid between where the assert is being thrown (throwingStatePID) and where it will be
			# caught (tryStatePID)
			local pidsToKill=()
			if [ "$throwingStatePID" != "$tryStatePID" ]; then
				local pid="$(ps -o ppid= --pid "$throwingStatePID")"
				while (( pid != 0 )) && (( pid != tryStatePID )) && (( pid != $$ )); do
					pidsToKill+=("$pid")
					pid="$(ps -o ppid= --pid $pid)"
				done
				(( pid != tryStatePID )) && assertError --critical  -v pstreeOfTry:"-l$(bgGetPSTree "$tryStatePID")" -v pstreeOfThrow:"-l$(bgGetPSTree "$throwingStatePID")" "
					Try/Catch Logic Failed. PID of Try block($tryStatePID) is not a parent of PID of asserting exception($BASHPID)"
			fi

			## Record the state at this point that the exception is being raised

			# declare -g catch_psTree; bgGetPSTree "$$" catch_psTree
			# declare -gx	catch_errorCode="$_ae_exitCode"
			# declare -gx	catch_errorClass="$_ae_assertFunctionName"
			# declare -gx	catch_errorFn="$_ae_failingFunctionName"
			# declare -gx	catch_errorDescription="$(cat $assertOut.catchDescription)"

			## record the state in $assertOut.* files if catch that is receiving this exception is in a different subshell
			if [ "$BASHPID" != "$tryStatePID"  ]; then
				bgStackMarshal "$assertOut.stkArrayRaw"
				echo "$catch_psTree" >"$assertOut.psTree"
				echo "$catch_errorCode $catch_errorClass $catch_errorFn" >>$assertOut.errorInfo
			else
				[ -f "$assertOut.stkArrayRaw" ] && rm "$assertOut.stkArrayRaw"
				[ -f "$assertOut.psTree" ]      && rm "$assertOut.psTree"
				[ -f "$assertOut.errorInfo" ]   && rm "$assertOut.errorInfo"
			fi

			## now throw the exception up to the nearest catch

			# for unitTest framework, disable the ERR trap when we assert
			builtin trap '' ERR

			# the goal is that we want the tryStatePID process to wake up an receive the SIGUSR2 signal.
			# If we are a synchronous child subshell of the tryStatePID, then we, and any subshells inbetween us that tryStatePID
			# must end before it will wake up. We can simply exit but we need to send the intermediate processes a SIGINT.
			# Since bash processes signals inbetween the simple commands that it runs, when we send the signals to our parents
			# they will be queued until we exit which should cause a chain reaction of each parent waking and ending up to the tryStatePID
			# whose SIGUSR2 trap handler will install a DEBUG handler that will skip simple commands until it finds a "Catch".
			# Some bash commands are interuptable by SIGINT but if we are running a bash script, all the parents between us and
			# tryStatePID must be bash subshells stopped on bash functions.
			[ "$_ae_traceCatchFlag" ] && bgtrace "!!! kill -SIGUSR2 $tryStatePID  "
			kill -SIGUSR2 "$tryStatePID"     # this wont return if we are tryStatePID
			(( ${#pidsToKill[@]} > 0 )) && kill -SIGINT "${pidsToKill[@]}"
			[ "$tryStatePID" != "$BASHPID" ] && bgExit  ${_ae_exitCode:-36}
			[ "$_ae_traceCatchFlag" ] && bgtrace "!!! returning normally. this is an error"
			;;

		*)	echo "error: logic error. In assertError the action was computed to be '$tryStateAction' but should be one of catch,abort,continue,exitOneShell"
			bgExit --complete ${_ae_exitCode:-36}
			;;
	esac
}



# usage: assertNotEmpty <varToTest> [options] [params]
# assert that the specified variable is not empty
# Note! You pass the name of the variable, not its value i.e. without the '$'
# If the <varToTest> is not defined or empty, this will pass the remainder of the cmdline to assertError
# Params:
#    <varToTest> : the name of a variable to test. (the name of the bash var, not its value)
#    [options]   : any options supported by assertError
#    [params]    : any param supported by assertError
function assertNotEmpty()
{
	if [ ! "${!1}" ]; then
		local varName="$1"
		[ $# -gt 0 ] && shift
		if [ $# -eq 0 ]; then
			 assertError -e39 "the variable '$varName' should not be empty"
		 else
			 assertError -e39 "$@"
		 fi
	fi
}


# usage: Try
# Try: is part of a Try/Catch exception mechanism for bash scripts. It is not appropriate to use this mechanism for everything.
#
# Throwing an Excetion:
# Calling any assertError* family of functions is the same as throwning an exception.  Most library functions are designed to call
# assertError when they can not perform their intended function already. Regardless of whether you are writing code with Try: / Catch:
# blocks in mind, you should write your code to suceed when it can, using reasonable defaults and return states and call an assertError
# function when there is no reasonable sucess path.  The assertError function is designed to make it easy to capture information
# about the context where it is being called to aid the user in understanding what went wrong and possible actions to correct the
# error. In a catch block, that information can be logged or examined to take action. The information given to the assertError*
# function is not yet readily available in the catch block but that will be added in a future version.
#
# Catching an Exception:
# A pair of Try: and Catch lines can appear in the same function or global scope to catch exceptions thrown by the code inbetween
# those lines.
#
# If assertError is called by any code between those lines, regardless of function depth or subshell depth, no further lines in that
# block will be executed and the script will contunue at the simple command immediately following the Catch: simple command.
# The return value of the Catch: simple command will be (0)true if an eception was caught and (1)false in the normal case that no
# excetpions were thrown. This allows separating error reporting and recorvery code from normal code. The true path after the Catch:
# is called the "Catch block". The code between the Try: and Catch: simple commands is called the "Try block" or "Try/Catch block".
#
# Try: blockes can be nested. This happens when a function that includes Try:/Catch: is called directly or indierectly from the code
# inside a Try:/Catch: block.  When an exception is thrown, execution will continue at the first Catch: statement on the stack.
# A Catch: block
#
# How it Works:
# When code invokes the Try: simple command, it records the state of the script by pushing it onto global try state stack implemented in
# some bgBASH_tryStack* variables. These globals can effectively communicate the stack down to subshells since their initial value
# is set in the subshell. Any new entries added by a subshell can not be known to the parent but that is ok because as control is
# returned to each parent, the stack enteries of the child needs to be removed anyway.
#
# When the assertError function is called, only the top bgBASH_tryStack entry is relevent. If there are no bgBASH_tryStack entries,
# then the code is not excuting in any Try/Catch block and assertError terminates the script. If the BASHPID its running in is $$ then
# it only needs to call exit. If not, it sends a SIGINT to $$ and all its children and then exists.
#
# if the bgBASH_tryStack is not empty, it will indicate the BASHPID and function depth where the Catch block is located. Note that
# the Try function does not know exactly where the Catch command will be below it but by design, the Catch block needs to be in the
# same scope as the Try so the Try uses its BASHPID and function depth.
#
# If the assertError is running in the same BASHPID as the target Catch, it uses the DEBUG and RETURN
# DEBUG and RETURN trap features to start skipping script simple commands until it comes to the Catch:. The bgBASH_tryStack includes
# the BASHPID and the function depth of the last Catch so that it can skip more efficiently until it gets back to the function where
# the Catch: block will be found.
#
# Subshels can not change the environment of their parents but it does pass information down to subshells via the initial value of
# the bgBASH_tryStack* variables. In order to communicate back up to the target subshell that an eception was thrown, each Try: call
# sets the USER2 signal handler trap and if the assertError is exceuting in a different BASHPID as the bgBASH_tryStack* data indicates
# that the Catch is in, it will signal that BASHPID with SIGUSR2 and then end.
# Example:
#     function foo()
#     {
#         Try:
#             doThis ...
#             doThat ...
#         Catch: && {
#             echo "doThis or doThat failed"
#         }
#     }
function Try:() { Try --decFuncDepth "$@"; }
function Try()
{
	local funcDepthOffset=1 traceCatchFlag
	while true; do case $1 in
		--traceCatch)   traceCatchFlag='bgtrace "!!!$FUNCNAME | $BASH_COMMAND"' ;;
		--decFuncDepth) funcDepthOffset=2 ;;
		 *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# these globals are used to pass the error to the Catch block. Clear them on Try: so that there is no chance of leaking the last
	# catch info through to another
	catch_errorCode=""
	catch_errorDescription=""
	catch_errorClass=""
	catch_errorFn=""

	# collect the current state
	local tryStatePID="$BASHPID"
	local tryStateFuncDepth="$(( ${#BASH_SOURCE[@]}-funcDepthOffset ))"
	local tryStateTryStatementLocation; local -A stackFrame=(); bgStackFrameGet "$funcDepthOffset" stackFrame; tryStateTryStatementLocation="${stackFrame[cmdLoc]}"
	local tryStateIFS="$IFS"
	local tryStateExtdebug="$(shopt -p extdebug)"
	local debugTrapScript='bgBASH_debugTrapLINENO=$((LINENO))
		'"${traceCatchFlag}"'
		if (( ${#BASH_SOURCE[@]} < '"$tryStateFuncDepth"' )); then
			IFS="$bgWS" # no need to save because we will restore the tryStateIFS copy when we return to user code
			assertError --critical "For Try block located at '"$tryStateTryStatementLocation"' no Catch block was found in the same Function. Check that code in the Try block did not skip the Catch by returning\n" >&2

		elif (( ${#BASH_SOURCE[@]} > '"$tryStateFuncDepth"' )); then
			(exit 2) # set exit code to simulate a return

		elif  [[ ! "$BASH_COMMAND" =~ ^Catch:?([[:space:]]|$) ]]; then
			(exit 1) # set exit code to not run BASH_COMMAND, go to the next command

		else # bingo. BASH_COMMAND == Catch: at this funcDepth
			IFS="$bgWS" # no need to save because we will restore the tryStateIFS copy when we return to user code
			bgTrapStack pop DEBUG

			unset bgBASH_debugTrapLINENO
			IFS="'"$tryStateIFS"'" # return IFS to the value it had at the try statement
			'"$tryStateExtdebug"'  # return the extdebug shopt to the value it had in at the try statement
			bgBASH_tryStackWasThrown[0]="1" # the Catch function will check this to know the context its being called in
			(exit 0) # run BASH_COMMAND and since we restore the DEBUG trap, the script will resume from there
		fi
	'

	# push the tryState values needed by the Catch and assertError functions onto the 'try' block stack
	# when code is running outside any Try block, the bgBASH_tryStack* is empty. Each Try pushes another entry onto the bgBASH_tryStack*
	# and each Catch pops an entry off. The Catch will be called in either the success or exception case.  Try/Catch must be in pairs
	# in the same function
	# The assertError function will examine the [0] entry of the stack to determine what to do. If its empty, it aborts b/c its not
	# running inside a Try/Catch block
	bgBASH_tryStackAction=(   "catch"              "${bgBASH_tryStackAction[@]}"   )
	bgBASH_tryStackPID=(      "$tryStatePID"       "${bgBASH_tryStackPID[@]}"      )
	bgBASH_tryStackFuncDepth=("$tryStateFuncDepth" "${bgBASH_tryStackFuncDepth[@]}")
	bgBASH_tryStackWasThrown=(""                   "${bgBASH_tryStackWasThrown[@]}")

	# install our try block trap
	bgTrapStack push SIGUSR2 '
		builtin trap - SIGUSR2
		bgTrapStack push DEBUG '\'''"$debugTrapScript"''\''
		shopt -s extdebug
		set +o errtrace # extdebug turns this on but unit tests need it off
	'
	[ "$traceCatchFlag" ] && bgtrace "!!! Try: installed SIGUSR2 in pid='$BASHPID'"
	return 0
}

# usage: TryInSubshell [<assertErrorExitCode>]
# This implements a particular type of Try / Catch block where the caller wants to invoke code in a subshell using the subshell to
# catch any errors indicated by the exit code of the subshell. This would actually be the typical expected behavior in a script
# except the default behavior of the assertError function is to abort the entire script by sending $$ the kill signal. By calling
# this function inside the subshell at its start, anything that calls assertError will only exit the subshell instead of aborting
# the entire script.
# Note that there is no corresponding Catch call to this TryInSubshell call because the the actions it takes is automatically undone
# when the subshell exits.
# Note that an alternative to this technique would be to wrap the subshell call (either inside or outside of the subshell) in a Try:
# Catch: block because Try / Catch works accross subshell boundaries by using the USR2 interrupt to pass the exception up.
# Params:
#    <assertErrorExitCode> : default is 163. if assertError is called inside the subshell, it will exit the subshell with this exit
#         code. Specifying it allows the caller to select a code that is not used by other things that might exit the subshell so
#         that they can tell that the shell exited because assert was thrown
function TryInSubshell()
{
	bgBASH_tryStackAction=("exitOneShell"  "${bgBASH_tryStackAction[@]}"   )
	assertErrorContext="-e${1:-163}"
}

# usage: Catch: [<assertFunctionSpec>] && { <errorPathCode...>; }
# Catch: is part of a Try/Catch exception mechanism for bash scripts.
# See man(3) Try and man(3) assertError for more details on the general mechanism.
#
# Params:
#    <assertFunctionSpec> : a quoted glob style specification that matches the name of the assert* function that, when thrown inside
#             the block, should stop on this Catch:
#             Multiple Catch: statements can be placed one after another and when an exception is being thrown inside the try/catch
#             block, the first matching Catch: <spec> will be invoked. If none match at that function level, the coresponding catch
#             stack frame will be popped and the exception will be re-thrown to the next higher level.
#
# The Error Path:
# The <errorPathCode...> in the usage synteax will be executed only when an exception is caught by that Catch:
# Inside this block some global variables starting with catch_* describe the state of the exception being caught.
#    bgSTK_*                : these stack variables are set with the state of the stack at the point where assertError was called
#                             "bgtraceStack" and  "bgStack*" functions operate on those variables
#    catch_errorCode        : the numeric exist code being thrown. If the exception was uncaught, this would be the exit code of the
#                             process
#    catch_errorDescription : The formatted text of the exception. If the exception was uncaught, this would be the text printed to
#                             stderr
#    catch_errorClass       : This is the name of the assert* function that raised the exception. assertError is the most generic
#    catch_errorFn          : This is the name of the function on the stack that contains the error. It is typicaly the function
#                             that invoked the catch_errorFn but that can be changed by using the --frameOffset option.
#    catch_psTree           : a string  containing the pstree output of the script at the point that the assert was raised. This
#                             shows the state of subshells and spawn async commands.
# Exit Code:
#    0: (true) error path. This means that this Catch: statement is catching an error.
#    1: (false) normal path. This Catch: statement is not catching an exception.
#
# Example:
#     function foo()
#     {
#         Try:
#             doThis ...
#             doThat ...
#         Catch: && {
#             echo "doThis or doThat failed"
#         }
#     }
#
# Example With Specific Catching:
# !!!NOTE: this is not implemented but we are close to it.
#   1) option1: make Catch: detect when its being called multiple times on the same Try:
#      if catching is true but assertFunctionName is not ours, reinstall a debug trap to monitor the additional Catch: and act if
#      none match
#   2) options2: (better) in the debgug trap, match the "Catch: assertFileNotFound" so that it only stops on a catch if it matches.
#      we would still need to make catch detect multiple calls for a single Try: so that it pops the stack only once
# (experimental)    function foo()
# (experimental)    {
# (experimental)        Try:
# (experimental)            doThis ...
# (experimental)            doThat ...
# (experimental)        Catch: assertFileNotFound && {
# (experimental)            echo "doThis or doThat failed"
# (experimental)        }
# (experimental)        # expect the exception to continue throwing if its
# (experimental)            echo "doThis or doThat failed"
# (experimental)        }
# (experimental)    }
#
function Catch:() { Catch --decFuncDepth "$@"; }
function Catch()
{
	local funcDepthOffset=1
	while true; do case $1 in
		--decFuncDepth) funcDepthOffset=2 ;;
		 *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# pop the tryState* entry off the bgBASH_tryStack* stack
	local tryStateAction="${bgBASH_tryStackAction[@]:0:1}";       bgBASH_tryStackAction=(    "${bgBASH_tryStackAction[@]:1}"   )
	local tryStatePID="${bgBASH_tryStackPID[@]:0:1}";             bgBASH_tryStackPID=(       "${bgBASH_tryStackPID[@]:1}"      )
	local tryStateFuncDepth="${bgBASH_tryStackFuncDepth[@]:0:1}"; bgBASH_tryStackFuncDepth=( "${bgBASH_tryStackFuncDepth[@]:1}")
	local tryStateWasThrown="${bgBASH_tryStackWasThrown[@]:0:1}"; bgBASH_tryStackWasThrown=( "${bgBASH_tryStackWasThrown[@]:1}")

	# restore the previous SIGUSR2 trap
	bgTrapStack pop SIGUSR2

	# in a development environment, take the time to confirm that we are clearing the matching Try block
	if bgtraceIsActive; then
		local catchStatePID="$BASHPID"
		local catchStateFuncDepth="$(( ${#BASH_SOURCE[@]} -funcDepthOffset ))"

		if     [ ! "$tryStatePID"       == "$catchStatePID"                     ] \
			|| [ ! "$tryStateFuncDepth" == "$catchStateFuncDepth"               ]
		then
			assertError --critical -v tryStatePID -v catchStatePID -v tryStateFuncDepth -v catchStateFuncDepth "missmatched Catch block. The PID and FunctionDepths should be the same for the Try: and Catch:"
		fi
	fi


	# The pattern is Catch: && { <catchCodeBlock>; } so return 0(true) when we caught an exception
	if [ "$tryStateWasThrown" ]; then
		# if the exception was thrown from a subshell, restore the information from the $assertOut.* files into the vars in this PID
		if [ -f $assertOut.stkArrayRaw ]; then
			bgStackUnMarshal "$assertOut.stkArrayRaw"
			declare -g catch_psTree; IFS= read -r -d '' catch_psTree <$assertOut.psTree
			declare -gx	catch_errorCode catch_errorClass catch_errorFn
			read -r catch_errorCode catch_errorClass catch_errorFn <$assertOut.errorInfo
			declare -gx	catch_errorDescription="$(cat $assertOut.catchDescription)"

			# TODO: install a DEBUG trap designed to trigger after the closing '}' of the catch block so that we can execute
			#       cleanup such as bgStackFreezeDone
		fi
 		return 0
	else
		return 1;
	fi
}

# usage: someCommand "$p1" "$p2" &>$assertOut[.$BASHPID] || assertError -v p1 -v p2
# assertOut is a redirect destination that can be used with assertError which allow assertError to
# show the user the output of a command only if the command fails.
# if you launch multiple sub shells that use assertOut or launch nested bash functions that use it,
# they may conflict. In those cases you can add a '.<string>.$BASHPID' to make them unique. Typically
# you will not need to
# The -u option to mktemp makes it not create the file initially to be less intrusive so that simple
# scripts that do not use this feature will not create the tmp file but any line that does 2>>$assertOut
# will cause it to be created even if there is no stderr output so many scripts will create the tmp
# file anyway
assertOut="$(command mktemp -u)"
bgtrap -n "assertOut:$assertOut" 'rm -f '"$assertOut"'*' EXIT

# usage: assertDefaultFormatter <msg>
# This formatter removes leading tabs similar to <<-EOS .. so that assertError msgs can be written in the code with decent
# code formatting but still display well in the assert.
# If <msg> is empty, it will set it to the source file line that called assert
function assertDefaultFormatter()
{
	_ae_msg="$*"
	_ae_msg="${_ae_msg#error:}"

	if [ ! "$_ae_msg" ]; then
		# this case supports the "<cmd> || assertError" syntax that prints information about <cmd> automatically.
		if [ "${BASH_SOURCE[1+1]}" ] && [ "${BASH_LINENO[1]}" ]; then
			_ae_msg="$(awk 'NR=="'"${BASH_LINENO[1]}"'" {sub("^[[:space:]]*",""); print;exit}' "${BASH_SOURCE[1+1]}")"

			# add the captured exitCode from the last command to the _ae_contextVars context
			# This assumes that the standard pattern was used. If its 0, then it was probably called differently
			[ ${_ae_exitCodeLast:-0} -gt 0 ] && _ae_contextVars+=("exitCode:$_ae_exitCodeLast")

			# glean the variables used in the source line and add them to the _ae_contextVars context
			# see extractVariableRefsFromSrc() function which does simlar but does not yet identify >$assertOut separately
			local varExtract="$_ae_msg"
			local count=0
			while [[ "$varExtract" =~ '>'[[:space:]]*[$]([^;|&[:space:]]*)|[$][{]?([]@*[a-zA-Z0-9_]*)[}]? ]] && ((count++ <15)); do
				local _ae_match=("${BASH_REMATCH[@]}")
				varExtract="${varExtract#*"${_ae_match[0]}"}"
				if [ "${_ae_match[1]}" ]; then
					[[ "${_ae_match[1]}" =~ [{]?([][a-zA-Z0-9_]*)[}]?(.*)$ ]]
					local _ae_contextVarName="${BASH_REMATCH[1]}"
					_ae_contextOutput="${!_ae_contextVarName}${BASH_REMATCH[2]//'$BASHPID'/$BASHPID}"
				else
					local _ae_contextVarName="${_ae_match[2]}"
					local _ae_contextVarNameClean="${_ae_contextVarName//'['}"
					_ae_contextVarNameClean="${_ae_contextVarNameClean//']'}"
					[ ! "${_ae_contextVarsCheck[${_ae_contextVarNameClean:-empty}]}" ] && _ae_contextVars+=("$_ae_contextVarName")
					_ae_contextVarsCheck[${_ae_contextVarNameClean:-empty}]=1
				fi
			done
		fi

	elif type -t awk &>/dev/null; then
	 	_ae_msg="$(awk '
			BEGIN {
				# start if off larger than it should ever be
				for (i=1;i<100;i++) leadingTabsToRemove+="\t";
				lineStart=1
			}
			#(seems this is not right) if the first line is empty, skip it when we output
			#NR==1 && $0!~"[^[:space:]]" {lineStart=2}

			{
				data[NR]=$0
			}
			# not the first line and not a empty line (not all whitespace)
			# reduce the leadingTabsToRemove to fit any line with content
			NR!=1 && $0~"[^[:space:]]" && $0!~"^"leadingTabsToRemove {
				leadingTabsToRemove=$0; sub("[^\t].*$","",leadingTabsToRemove)
			}
			# display the content with undesired whitespace removed
			END {
				for (i=lineStart; i<=NR; i++) {
					line=data[i]
					sub("^"leadingTabsToRemove,"",line)
					print line
				}
			}
		' <<< "$_ae_msg")"
	fi
}

# usage: extractVariableRefsFromSrc <srcCode> [<retVar>]
# This is used by error and debug context code to get a list of context variables from the source code. srcCode could be a single
# line or multiple lines.
# 2020-11 the algorithm was copied and modified from a similar one in assertDefaultFormatter but assertDefaultFormatter does not
#         yet use this function becuase it is also concerned with identifying uniquely variables that are used to redirect output
#         like cmd >$assertOut and it will take a bit of work to make this generic enough to proved that separately
function extractVariableRefsFromSrc()
{
	local existsFlag functionName
	while [ $# -gt 0 ]; do case $1 in
		-f*|--func*)  bgOptionGetOpt val: functionName "$@" && shift ;;
		-e|--exists) existsFlag='-e' ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local srcCode="$1"

	if [ ! "$srcCode" ] && [ "$(type -t "$functionName")" == "function" ]; then
		local srcFile srcLine; bgStackGetFunctionLocation "$functionName" srcFile srcLine
		srcCode="$(awk -v srcLine="$srcLine" 'NR>srcLine {print $@} NR>srcLine && /^}\s*$/ {exit} ' "$srcFile")"
	fi

	# this is the term that assertDefaultFormatter would need if it is changed to use this function
	local reRedirectToVar='>[[:space:]]*[$]([^;|&[:space:]]*)'

	# build the re out of components to make it easier to understand
	local reVarWithBr='[$][{][!#]?([a-zA-Z0-9_]+)'
	local reVarWithBrWIdx='[$][{][!#]?([a-zA-Z0-9_]+[[][^]]+[]])'
	local reVarWOBr='[$]([a-zA-Z0-9_]+)'

	# limit the while loop in case a bug makes it infinite
	local count=0

	local -A varNames=()

	local srcLine; while IFS="" read -r srcLine; do
		while [[ "$srcLine" =~ ${reVarWithBr}|${reVarWOBr}|${reVarWithBrWIdx} ]] && ((count++ <150)); do

			local rematch=("${BASH_REMATCH[@]}")
			srcLine="${srcLine#*"${rematch[0]}"}"

			# reVarWithBrWIdx matches might have additional matches inside them like foo[$bar]. We can just push it bash on the front
			# because the ${} has been removed so it wont match the primary again
			[ "${rematch[3]}" ] && srcLine="${rematch[3]} $srcLine"

			# varName can be match by any of the expressions but it ends up in a different rematch locations. There should be exactly
			# 1 non empty element besides [0] and that match can not include whitespace so this assignment works
			local varName="${rematch[1]:-${rematch[2]:-${rematch[3]}}}"

			[ "$existsFlag" ] &&  ! varExists "$varName" && continue

			# older bashes had a problem with array index that contain [...]
			local varNameIndex="${varName//'['/%5B}" #'
			varNameIndex="${varNameIndex//']'/%5D}" #'

			varNames[$varNameIndex]="$varName"
		done
	done <<< $srcCode

	varSetRef --array "$2" "${varNames[@]}"
}

#"  atom syntax highlight bug
#######################################################################################################################################
### From bg_libFile.sh

# usage: fsExists [-F|-D|-E] <fileSpec1> [... <fileSpecN>]
# returns true if at least one file system object of the specified type matches any fileSpec. Checks for files by default
# This can be used to determine if a spec that contains wildcards matches any object before passing it to a command that
# would fail if it does not
# fsExpandFiles is an alternate way to get similar results
# Params:
#    <fileSpecN>  : any type of string that could refer to 0 or more file system objects. wildcards ok.
# Options:
#    -r) recurse. true if a file or folder exists underneath any <fileSpecN>. If <fileSpec> is a file
#        or does not exist it is ignored and is false. If <fileSpec> is a folder it is checked for any
#        fs objects in it or any sub folder.
#    -F) check to see if any match a file object
#    -D|-d) check to see if any match a folder object
#    -E|-e) check to see if any match any type of object
# See Also:
#    fsExpandFiles
function fsExists()
{
	local ftype="-f" recurse findOpt="-type f"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-r) recurse="-r" ;;
		-F) ftype="-f"; findOpt="-type f" ;;
		-D|-d) ftype="-d"; findOpt="-type d" ;;
		-E|-e) ftype="-e"; findOpt="" ;;
	esac; shift; done

	if [ "$recurse" ]; then
		[ "$(find "$@" -mindepth 1 $findOpt -print -quit 2>/dev/null)" ]
		return
	else
		local i; for i in "$@"; do
			[ $ftype "$i" ] && return 0
		done
		return 1
	fi
}


# usage: fsParseContent <contentVar> <contentTypeVar> <contentClip> <content...>
# processes the <content> argument into the three return variables. <content> can either be the content or a term that leads to the
# content.
# Params:
#    <contentVar>     : var that receives the processed content string
#    <contentTypeVar> : var that receives a word that describes the type of the content -- file,template,templateStr,...
#    <contentClip>    : var that receives a short section that represents the content
#    <content...>     : the content passed in. Several types of content are supported
#       file:<filename>   : read contents from <filename>
#       template:<templateName> : <templateName> will be looked up using templateFind and then expanded to produce the content
#       templateStr:...   : the remainder of the <contents> will be expanded as a template to produce the content
#       string:...        : (default) the remainder of the <contents> will be the content
function fsParseContent()
{
	local _fspcMaxContentSize=40
	local contentVar="$1"; shift
	local contentTypeVar="$1"; shift
	local contentClipVar="$1"; shift
	local contentTerm="$*"
	local _fspcContentType _fspcContent _fspcContentClip
	if [[ "$contentTerm" =~ ^file: ]]; then
		_fspcContentType="file"
		_fspcContent="$(cat "${contentTerm#file:}")"
	elif [[ "$contentTerm" =~ ^template: ]]; then
		_fspcContentType="template"
		import bg_template.sh ;$L1;$L2
		_fspcContent="$(templateExpand "${contentTerm#template:}")"
	elif [ ! "$contentTerm" ]; then
		_fspcContent=""
		_fspcContentType="emptyStr"
	else
		# its a string _fspcContent that might be a template. If not a template, it may or may not start with 'string:'
		_fspcContent="$(strRemoveLeadingIndents "${contentTerm#string:}")"
		_fspcContentType="string"
		if [[ "$_fspcContent" =~ ^templateStr: ]]; then
			templateStr="${_fspcContent#templateStr:}"
			_fspcContentType="templateStr"
			import bg_template.sh ;$L1;$L2
			templateExpandStr -R _fspcContent "$templateStr"
		fi
	fi

	_fspcContentClip="${_fspcContent:0:$_fspcMaxContentSize}"; _fspcContentClip="${_fspcContentClip//$'\n'/\\n}";
	[ ${#_fspcContent} -gt ${_fspcMaxContentSize:-0} ] && _fspcContentClip="${_fspcContentClip:0:$(($_fspcMaxContentSize-3))}..."

	setReturnValue "contentTypeVar" "$_fspcContentType"
	setReturnValue "contentClipVar" "$_fspcContentClip"
	returnValue "$_fspcContent" "$contentVar"
}


# usage: fsTouch [-d] [-p]  <fileOrFolder> [<content>]
# This improves the pattern of using 'touch' to make sure a file exists before accessing it.
# If fsTouch ends without asserting an error, it guarantees that <fileOrFolder> exists with all of the attributes that are specified
# in the options.
#
# Parent Folder Creation:
# If the folder that <fileOrFolder> resides in does not exist, it will be created by default as long as the grandparent folder does
# exist. If the -p option is specified, the entire folder chain will be created if needed. Use -p with caution because if the path
# is specified incorrectly, for example leaving the leading / off of a long absolute path, it will silently create the entire
# incorrect path.
#
# File Object Type:
# fsTouch can work with the following file system objects denoted by a single letter.
#       f  : regular file
#       d  : directory (aka folder)
#       p  : named pipe
# The default type is 'f'. If <fileOrFolder> ends in a '/', the type is set to 'd'. It is an error to specify a different type for
# a name that ends with '/' The --typeMode=f|d|p, -d|--directory and --perm=<accessRightStr> can be used to specify the type.
#
# Ownership and Access Rights:
# The -u|--user=<user>, -g|--group=<group>, and --perm=<rwxBits> can be used to specify the access control for <fileOrFolder>
# In the <rwxBits> string all 9 positions are required (rwx for each of user,group,other permissions). Put a '.' in any position
# that you do not wish to specify.
#
# Timestamp:
# Unlike gnu touch, fsTouch does not update the modified timestamp by default. The --updateTime option will make it set the modified
# timestamp to the current time if <fileOrFolder> already exists. If it creates <fileOrFolder> the modification time will naturally
# be set to the current time.
#
# When Sudo is Required:
# If the user executing fsTouch does not have sufficient permission to access <fileOrFolder> in order for it to complete without
# error, sudo will be used on the underlying operations that it performs. This means that the user may be prompted to enter their
# password.
#
# Params:
#    <fileOrFolder>  : the path to a filesystem object that should exist. If it ends in a '/' it implies that typeMode must be 'd'
#    <content>       : if specified, and the file is created, it will be filled with this content. If the (?) option is specified
#       in addition, when the file already exists, if its content does not match <content>, it will be overwritten with <content>
#       Several formats of specifying the content are supportted. If the leading characters of <content> match one of the following
#       it will determine the format. If not <content> will be treated as the literal contents texts.
#            file:<filename>   : read contents from <filename>
#            template:<templateName> : <templateName> will be looked up using templateFind and then expanded to produce the content
#            templateStr:...   : the remainder of the <contents> will be expanded as a template to produce the content
#            string:...        : (default) the remainder of the <contents> will be the content
# Options:
#    --checkOnlyFlag : instead of changing the file attributes, just return true(0) if the file already has the specified attributes
#       or false(>0) if there are changes that would be made if called without this option. The return code reflects the first change
#       that would be required. There may be other changes that would be required after the first change. Note that if --updateTime
#       is specified along with --checkOnlyFlag, it will never return true
#          1 : needs to make the parent folder
#          2 : needs to remove an object of the wrong type at <fileOrFolder>
#          3 : needs to change content to match <content>
#          4 : needs to update the timestamp
#          5 : needs to create the file object
#          6 : needs to change the user or group ownship
#          7 : needs to change the access rights
#    --updateTime    : if <fileOrFolder> already exists, update its modification time to the current time (like gnu touch would)
#    -d|--directory  : alias for --typeMode=d. <fileOrFolder> will be a folder.
#    --typeMode=f|d|p : specify the file system object type that <fileOrFolder> should be.
#       f : regular file
#       d : directory (aka folder)
#       p : named pipe
#    --perm=<rwxBits> : specify UGO permissions that <filename> should or should not have. <rwxBits> is a 10 character string similar
#       to that displayed by `stat -c"%A" <filename>`. A 9 character string is also accepted and is interpretted
#       as the <type> bit being unspecified. Spaces can be added between the clusters of bits to aid in readability. If a position
#       has a '.', it means that that position is unspecified and any value is acceptable. If a position has a '-', it means that
#       that right is not granted or in the case of the type character, it specifies that the type is a regular file.
#          [.fdp-] [.r-][.w-][.xsS-] [.r-][.w-][.xsS-] [.r-][.w-][.x-]
#          <type-> <-----user------> <-----group-----> <----other---->
#          Where s and x share a spot...
#               '-' means '--' niether is set
#               'x' means 'x-' only x,
#               'S' means '-s' only s
#               's' means 'xs' both are set
#    -p|--makePaths : normaly it will create at most one parent folder but -p makes it create the entire parent chain as needed.
#       Its safer to use without -p because it wont blinding create a whole folder hierarchy if you make a mistake in the
#       <fileOrFolder>. For example if you forget the leading / in a well know path, it would recreate that path under the current
#       working directory. Without -p, it would fail and tell you that it cant create that path.
#    -f|--force : without this option, if a different type of file system object exists at <fileOrFolder>, it will result in an error.
#       specifiying this option makes it remove the other object so that it can create the specified type of object. This option is
#       required to make it less likely that an entire folder of data could be accidentally lost.
#    --enforceContent : If the file already exists this option causes its content to be compared with <content> and overwritten
#       with <content> if they are not equal.
#    --prompt=<msg>  : if sudo is required to perform the operation and the user is prompted to enter their password, <msg> provides
#                      context to what operation they are entering a password to complete.
function fsTouch()
{
	local checkOnlyFlag recurseMkdirFlag typeMode permMode forceFlag updateTimeFlag sudoPrompt userOwner groupOwner enforceContentFlag
	while [ $# -gt 0 ]; do case $1 in
		--checkOnly)  checkOnlyFlag="--checkOnly" ;;
		--updateTime) updateTimeFlag="--updateTime" ;;
		-d|--directory) typeMode="d" ;;
		--typeMode*)  bgOptionGetOpt val: typeMode   "$@" && shift ;;
		-u|--user*)   bgOptionGetOpt val: userOwner  "$@" && shift ;;
		-g|--group*)  bgOptionGetOpt val: groupOwner "$@" && shift ;;
		--perm*)      bgOptionGetOpt val: permMode   "$@" && shift
			permMode="${permMode// }"
			[ ${#permMode} -eq 9 ] && permMode=".$permMode" # the caller can leav out the file type bit
			[ "$permMode" ] && [[ ! "$permMode" =~ ^[-fdp.][-r.][-w.][-xsS.][-r.][-w.][-xsS.][-r.][-w.][-x.]$ ]] && assertError "The --perm=<rwxBits> must be a 9 or 10 character string matching [.fdp-]?[.r-][.w-][.x-][.r-][.w-][.x-][.r-][.w-][.x-]"
		;;
		-p|--makePaths) recurseMkdirFlag="-p" ;;
		-f|--force) forceFlag="-f" ;;
		--enforceContent) enforceContentFlag="--enforceContent" ;;
		--prompt*)    bgOptionGetOpt val: sudoPrompt "$@" && shift; sudoPrompt=(-p "$sudoPrompt") ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local fileOrFolder="$1"; shift; assertNotEmpty fileOrFolder

	# if <fileOrFolder> ends in a '/', it indicates that fileMode should be -d
	if [ "${fileOrFolder: -1}" == "/" ]; then
		[ "${typeMode:-d}" != "d" ] && assertError "conflicting types specified. The file object type specified in the --typeMode options conflicts with the fact that <fileOrFolder> ends with a '/' which indicates it is a folder"
		typeMode="d"
	fi
	fileOrFolder="${fileOrFolder%/}"

	# get the fileType from the permMode if specified
	if [ "$permMode" ] && [ "${permMode:0:1}" != "." ]; then
		local typeFromPerm="${permMode:0:1}"; [ "$typeFromPerm" == "-" ] && typeFromPerm="f"
		[ "$typeMode" ] && [ "$typeMode" != "$typeFromPerm" ] && assertError "conflicting types specified. first character of the --perm=<mode> option conflicts with the file object type specified via either the -d, or --typeMode options or <fileOrFolder> ending with a '/' which indicates that it should be a folder"
		typeMode="$typeFromPerm"
		[ "${permMode:0:1}" == "f" ] && permMode="-${permMode:1}"
	fi

	# create the parent folder if needed
	if [ ! -e "$fileOrFolder" ]; then
		local parentFolder="${fileOrFolder%/*}"
		[ ! -d "$parentFolder" ] && {
			[ "$checkOnlyFlag" ] && return 1
			bgsudo "${sudoPrompt[@]}" -w "$parentFolder" mkdir $recurseMkdirFlag "$parentFolder" || assertError
		}
	fi

	# if it aready exists,  check to make sure its the right type
	if [ -e "$fileOrFolder" ]; then
		local curMode="$(stat -L -c"%A" "$fileOrFolder")"
		local curType="${curMode:0:1}"; [ "$curType" == "-" ] && curType=f

		if [ "$typeMode" ] && [ "$curType" != "$typeMode" ]; then
			[ ! "$forceFlag" ] && assertError -v fileOrFolder -v specifiedType:typeMode -v actualType:curType "fsTouch is trying to make a file object of a specified type but a different type of object already exists by that filename. Use the -f|--force option to allow fsTouch to remove the existing object."
			local rmOptions="-f"
			if [ "$curType" == "d" ]; then
				{ [ ! "$fileOrFolder" ] || [[ "$fileOrFolder" =~ ^/[^/]*$ ]]; } && assertError "can not use fsTouch to remove a first level folder"
				rmOptions="-rf"
			fi
			[ "$checkOnlyFlag" ] && return 2
			bgsudo "${sudoPrompt[@]}" -c "$fileOrFolder" rm $rmOptions "${fileOrFolder:-nonExistentName}"  || assertError
		else
			if [ "${typeMode:-f}" == "f" ] && [ "$enforceContentFlag" ]; then
				local content contentType contentClip
				fsParseContent content contentType contentClip "$*"
				if [ "$content" != "$(cat "$fileOrFolder")" ]; then
					[ "$checkOnlyFlag" ] && return 3
					echo "$content" | bgsudo "${sudoPrompt[@]}" -c "$fileOrFolder" tee "$fileOrFolder" >/dev/null || assertError
				fi
			fi

			# update the timestamp
			[ "$updateTimeFlag" ] && [ "$checkOnlyFlag" ] && return 4
			[ "$updateTimeFlag" ] && { bgsudo "${sudoPrompt[@]}" -w "$fileOrFolder" touch "$fileOrFolder" || assertError; }
		fi
	fi

	# this is not an else block b/c if the existing object was the wrong type, it might have been removed so that now it does not exist
	if [ ! -e "$fileOrFolder" ]; then
		local content contentType contentClip
		fsParseContent content contentType contentClip "$*"

		# at this point, we know the parent exists but fileOrFolder does not so create it
		[ "$checkOnlyFlag" ] && return 5
		case ${typeMode:-f}:${content:+c} in
			f:c) echo "$content" | bgsudo "${sudoPrompt[@]}" -c "$fileOrFolder" tee "$fileOrFolder" >/dev/null || assertError ;;
			f*)  bgsudo "${sudoPrompt[@]}" -c "$fileOrFolder" touch   "$fileOrFolder"   || assertError ;;
			d*)  bgsudo "${sudoPrompt[@]}" -c "$fileOrFolder" mkdir   "$fileOrFolder"   || assertError ;;
			p*)  bgsudo "${sudoPrompt[@]}" -c "$fileOrFolder" mkfifo  "$fileOrFolder"   || assertError ;;
			*) assertError -v typeMode "unknown file object type"
		esac
	fi

	if [ "$permMode$userOwner$groupOwner" ]; then
		local curMode="$(stat -L -c"%U:%G:%A" "$fileOrFolder")"
	fi

	if [ "$userOwner$groupOwner" ]; then
		if [[ ! "$curMode" =~ ^${userOwner:-[^:]*}:${groupOwner:-[^:]*}:.*$ ]]; then
			[ "$checkOnlyFlag" ] && return 6
			bgsudo "${sudoPrompt[@]}" --chown "$fileOrFolder:$userOwner:$groupOwner" chown $userOwner:$groupOwner "$fileOrFolder"  || assertError
		fi
	fi

	if [ "$permMode" ]; then
		if [[ ! "$curMode" =~ ^[^:]*:[^:]*:$permMode ]]; then
			local modeStr=""
			case $permMode in
				?r????????) modeStr+=",u+r" ;;&
				?-????????) modeStr+=",u-r" ;;&
				??w???????) modeStr+=",u+w" ;;&
				??-???????) modeStr+=",u-w" ;;&
				???x??????) modeStr+=",u+x,u-s" ;;&
				???s??????) modeStr+=",u+xs"    ;;&
				???S??????) modeStr+=",u+s,u-x" ;;&
				???-??????) modeStr+=",u-xs"    ;;&
				????r?????) modeStr+=",g+r" ;;&
				????-?????) modeStr+=",g-r" ;;&
				?????w????) modeStr+=",g+w" ;;&
				?????-????) modeStr+=",g-w" ;;&
				??????x???) modeStr+=",g+x,g-s" ;;&
				??????s???) modeStr+=",g+xs"    ;;&
				??????S???) modeStr+=",g+s,g-x" ;;&
				??????-???) modeStr+=",g-xs"    ;;&
				???????r??) modeStr+=",o+r" ;;&
				???????-??) modeStr+=",o-r" ;;&
				????????w?) modeStr+=",o+w" ;;&
				????????-?) modeStr+=",o-w" ;;&
				?????????x) modeStr+=",o+x" ;;&
				?????????-) modeStr+=",o-x" ;;&
			esac
			modeStr="${modeStr#,}"

			[ "$checkOnlyFlag" ] && return 7
			bgsudo "${sudoPrompt[@]}" --attr "$fileOrFolder" chmod $modeStr "$fileOrFolder" || assertError
		fi
	fi
}

# usage: fsExpandFiles|bgfind [<options>] <fileSpec1> ... <fileSpecN> [<findTestExpression>]
# usage:    where <options> are [-f] [-F|-D] [-R|+R] [-A <retArrayVar>] [-S <setName>] [-b] [-B <prefix>]
# usage: awk '...' $(fsExpandFiles -f path/*.ext)
# usage: local -A fileList; fsExpandFiles -A fileList path/*.ext; for file in "${fileList[@]}"; do echo $file; done
# returns a list of files in the filesystem that match the <fileSpec> and the optional match criteria. This solves a problem that
# simple patterns for operating on a set of files often have edge cases that fail but go undetected. You can use this command to
# obtain a list of files to use on a commandline of another command like awk or use it to populate an Array or Set with the filenames
# that you can then iterate in a script without creating a subshell.
#
# Common Idioms:
# 'find' and this command are tricky to get right. Big changes to the output pivot on some subtle input changes.
# Use to get a list of files to operate on...
#    bgfind .    # !anti-idiom!. This is often not what you want. hidden files will be included and its awkward to exclude them.
#                # everything will start with './'  The option -B=./ will remove it in the output, but tests will need to account for './'
#    bgfind * ...        # prefered. filenames are simple with no prefix in tests and output. only non-hidden files/folders
#    bgfind * .[^.]* ... # if you want hidden files, include a <fileSpec> to match them. Note that .* will match . and ..
#    * Note that * could be replaced with any wildcard expression but remember that hidden and non-hidden specs depend on the leading .
#    bgfind -S mySet ... # (or -A) returning the found list in a Set or Array eliminates all the problems with special characters
#                        # in filenames. Many other patterns are ok most of the time, but have edge cases that can bite you.
#    fsExpandFiles ./* -type f -perm /a+x # glob exansion with find's test expression filtering
# Use to run a cmd on a set of files that match a pattern...
#    awk '...' $(fsExpandFiles -f <somePath>*.myExt) # run a cmd on some files without getting an error if there are no files
#    * Note that this will fail for filenames that conatin whitespace. If you need to support those, get the list in an array and loop
# Common find tests...
#    -type f|d|p|l|s|b|c     # f(files),d(folders),p(pipes),l(symlinks),s(sockets),b(blockDevice),c(charDevice)
#    -perm /a+x  # executable files
#    -name "*.exe"     # use globs to match the filename only (no leading path)
#    -path "./foo*/*"  # use globs to match the full name which includes the starting point
#    -regex ".*foo.*"  # use regex to match the full name which includes the starting point
#
# * Think about whether the <fileSpec> expansion is the main workhorse or whether you are specifying a fixed starting point for
#   find's recursive search to be the main workhorse. When using the latter, account for the starting point prefix in tests and outputs
# * fsExpandFiles is an alias for specifying no recursion. Use this when you really are just expanding the <fileSpecN>
# * bgfind is an alias for specifying recursion.
#
# Working Directory:
# The <fileSpecN> and output names will all be relative to the current working directory if they are not absolute. You can change
# where the output names are relative to by using the -b or -B <prefix> options to remove some prefix of the names in the output
# but that does not affect the <fileSpecN> nor -wholename tests. Often, it is helpful to change to a base folder before invoking this
# command so that the <fileSpecN>, tests and output are all relative to that base folder. This command can not build in that feature
# because it relies on the <fileSpecN> parameters being expanded by bash before the command starts.
#
# Specifying * or . as the <fileSpec> both start finding files in the current working directory but are not the same. * will cause
# the shell to expand to a list of non-hidden files and folders in the CWD so that each will be a starting point for find. '.' will
# result in find using the CWD as the single starting point and it will consider all files/folder including hidden ones.
#
# Recursive (-R) vs Non-recursive (+R) Mode:
# The <fileSpecN> parameters on the commandline are always processed by bash to expand them into a list of matching filesystem objects.
# In non-recursive mode only those filesystem objects are considered. In recursive mode, each of those filesystem objects that are
# a directory will be traversed so that its contents are also considered. The test expressions at the end of the commandline are
# applied to the considered list so that any non-matching (and non-existing) entries are removed.
#
# The difference between recursive and non-recusrive mode has a profound impact on how the command is used. Resursive mode works
# like an enhanced version of the gnu find utility and non-recursive mode works more like bash glob expansion. Often when recursive
# mode is used, only a single directory path is specified in <fileSpecN>. When non-recursive mode is used, the <fileSpecN> produce
# the entire list and <findTestExpression> is optionally used to filter the list down.
#
# When this command is invoked via its alias 'bgfind', recusive mode is the default.
# When this command is invoked via its alias 'fsExpandFiles', non-recusive mode is the default.
#
# Calling as bgfind / find:
# This function is available as the alias bgfind which changes the default to -R from +R. The command line is compatible with the
# gnu find utility syntax plus some optional enhancements so its expected that eventually this library will make an alias called 'find'
# so that this implementation will be the default for any use of find in a script that sources this library.
#
# Example -- Invoke awk on any file matching a glob:
#    awk '<script>...' $(fsExpandFiles -f ./*.myext)
#    awk '<script>...' *.myext # if there are no matching files you get "*.myext" not found error. If you suppress it, awk reads from stdin
# Example Compare Two Folders:
#    local newPages=() removedPages=() updatedPages=() unchangedPages=()
#    local -A allPages=()
#    bgfind -B $outputFolder/ -F -S allPages $outputFolder/
#    bgfind -B $tmpFolder/    -F -S allPages $tmpFolder/
#    for manpage in "${!allPages[@]}"; do
#       if [ ! -f "$outputFolder/$manpage" ]; then
#          newPages+=("$manpage")
#       elif [ ! -f "$tmpFolder/$manpage" ]; then
#          removedPages+=("$manpage")
#       elif ! diff -q -wbB "$tmpFolder/$manpage" "$outputFolder/$manpage" &>/dev/null; then
#          updatedPages+=("$manpage")
#       else
#          unchangedPages+=("$manpage")
#       fi
#    done
#    printfVars "allPages:${#allPages[@]}" "newPages:${#newPages[@]}" "removedPages:${#removedPages[@]}" "updatedPages:${#updatedPages[@]}" "unchangedPages:${#unchangedPages[@]}" updatedPages
#
# Test Expressions:
# Just like the gnu find command, the path list on the command line ends when a parameter starting with '-' is encountered.
# See 'man find' for details of the test expresssions. This man page will only discuss the the changes in context that this command
# introduces.
#
# Most find 'Action' expressions (e.g. -print, -exec, etc...) are not allowed. The action of this command is hard coded to return a list
# of found filesystem objects.
#
# -prune and -exit can be used to limit the results efficiently
#
# In non-resursive mode (+R, default when invoked as fsExpandFiles) find is invoked with -maxdepth 0 so that the test expressions
# will only serve to limit the list of files that <fileSpecN> expanded to after glob expansion. This means that
#
# Params:
#    <fileSpecN> : a file spec that bash will expand to 0 or more filesystem object names before the function is invoked. These can
#            be absolute (starting at the filsystem root) or relative to the current working directory.
#            NOTE: files can exist whose names look like options or expressions to find so './*' should be used instead of '*' to
#                  refer to all files in the current directory. That will cause the expanded names to start with './' so that they
#                  can not be mistaken for an option. The option '-B./' could be used to remove the ./ from the results if needed.
# Options:
# These options affect which file obects are in the outputted list
#    -f : force. return at least one fs object which will be "/dev/null" if none other match
#    -F : files only. match only file objects. Note: upper case F b/c -f is force.
#    -D : directories only. match only folder(aka directory) objects. Note upper case for consistency with -F
#    -R : recursive     (default for bgfind alias)        treat each matching <fileSpec> as a startig point to potentially descend
#    +R : not recursive (default for fsExpandFiles alias) only consider the file objects matching <fileSpec>, not their descendants
#    --exclude=<pattern>  : exclude directories and files that match <pattern>. Excluded directories are pruned so they are not
#         entered and its entire sub-tree is skipped. <pattern> is a little bit like that used in gitignore files. A trailing /
#         makes it only match directories and not files. A / in the beginning or middle makes it match against the whole path instead
#         of only the base name (with leading path removed). * and ? are interpreted as glob characters.
#    --gitignore[=<gitignoreFilePath>] : This mostly causes the files that git would skip to be skipped but it wont be perfect because
#         gitignore <patterns> have several extentions that can not be implemented exactly in gnu find. If <gitignoreFilePath> is
#         not specified, it attempts to find a .gitignore file in the common root of the search paths. Regardless of whether a
#         .gitignore file is found, .git/ and .bglocal/ folders are excluded at all levels.
# These options determine how the list of files is returned. Default is standard out, one per line
#    -A <arrayName> : return in Array. instead of writing the matching file system objects to stdout,
#             one per line, add them to the caller's array. This avoids the sub process and also works
#             with names with spaces. <arrayName> is not truncated. the files found by this function
#             are added to the existing elements
#    -S <setName> : return in Set. return the results in the indexes of the associative array var
#             passed in. This has the effect of eliminating duplicates. <setName> is not truncated.
#             the files found by this function are added to the existing elements
# These options affect the paths returned. Default is relative to <fileSpec> so that each name can be used to access that file
#    -b    : base names. remove the path part of the filename before returning
#    -B <prefix> : remove <prefix>. remove <prefix> from the pathname before returning. This is similar to
#            -b but allows more control. Example: fsExpandFiles -B "$tmpFolder/"  $tmpFolder/man3/* returns "man3/*" names
#    -H|-L|-P    : gnu find's symbolic link options. -H(follow only links in <fileSpec>) -L(follow all descendant links) -P(never follow)
#    -D*         : gnu find's debug options. See 'man find'
#    -O*         : gnu find's optimization options. See 'man find'
# See Also:
#     find (the GNU utility)
function bgfind() { fsExpandFiles --findCmdLineCompat -R "$@"; }
function fsExpandFiles()
{
	local outputOpts=()
	local recursiveOpt=("-maxdepth" "0")
	local forceFlag fsef_prefixToRemove fsef_outputVarName fTypeOpt=() findCmdLineCompat findOpts=() findPruneExpr=() excludePaths=()
	local _gitIgnorePath
	local findStartingPoints=()
	while [ $# -gt 0 ]; do case $1 in
		# If any options conflict arise, findCmdLineCompat==true means use the find meaning and findCmdLineCompat==false means use our meaning
		--findCmdLineCompat) findCmdLineCompat="--findCmdLineCompat" ;;

		-f) forceFlag="-f" ;;

		# aliases for -type d|f
		-F) fTypeOpt=(-type f) ;;
		-D|-d) fTypeOpt=(-type d) ;;

		# -R means recurse (dont limit the depth) and +R means dont recurse (apply the find criteria only to the supplied paths)
		-R) recursiveOpt=() ;;
		+R) recursiveOpt=("-maxdepth" "0") ;;

		# how to return the results (see man(3) varOutput)
		-d*|--delim*) bgOptionGetOpt  opt: outputOpts "$@" && shift ;;
		-a|--append)  bgOptionGetOpt  opt  outputOpts "$@" && shift ;;
		--string*)    bgOptionGetOpt  opt: outputOpts "$@" && shift ;;
		-A*|--array*) bgOptionGetOpt  opt: outputOpts "$@" && shift; outputOpts+=(--append) ;; # adding append is legacy we  have to find all places that rely on this and add -a|--append before we can remove it
		-S*|--set*)   bgOptionGetOpt  opt: outputOpts "$@" && shift ;;

		# modify the output
		-b|--baseNames) fsef_prefixToRemove="*/" ;;
		-B*) bgOptionGetOpt  val: fsef_prefixToRemove "$@" && shift ;;

		--gitignore)  _gitIgnorePath="<glean>" ;;
		--gitignore*) bgOptionGetOpt  val: _gitIgnorePath "$@" && shift; _gitIgnorePath="${_gitIgnorePath:-<glean>}" ;;
		--exclude*)   bgOptionGetOpt  valArray: excludePaths "$@" && shift ;;

		# native find (GNU utility) 'real' options
		-H|-L|-P) bgOptionGetOpt  opt  findOpts  "$@" && shift ;;
		-D*|-O*)  bgOptionGetOpt  opt: findOpts  "$@" && shift ;;
		--) shift; break ;;
		 *)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# This cmd, like the gnu find util, has 3 sections of parameters instead of the normal 2 (options + positional)

	# Section1: was the real options parsed by the standard options section above

	# Section2: these are the <fileSpec> positional parameters. Bash will expand any wild cards if they match any paths but will
	# leave them in if they dont match any. We cant pass any non existing paths to find or it will fail with an error. find will
	# interpret each of these as a starting point but if -R is not specified, we will give find the -maxdepth 0 global option that
	# will cause it to only apply the test expressions to the starting points and do no directory traversal.
	while [ $# -gt 0 ]; do case $1 in
		-*) break ;;
		'(') break ;;
		 *)  [ -e "$1" ] && findStartingPoints+=("$1") ;;
	esac; shift; done

	# if none of the starting points exist it will match nothing, but there is nothing we can set findStartingPoints to so that find
	# would exit cleanly without displaying an error so we return here
	if [ ${#findStartingPoints[@]} -eq 0 ]; then
		[ "$forceFlag" ] && varOutput "${outputOpts[@]}" "/dev/null"
		return 1
	fi



	# Section3: /bin/find expressions section. The rest of the command line is interpretted as the find expression
	local findGlobalExpressions=() findExpressions=()
	while [ $# -gt 0 ]; do case $1 in
		# 'global options'
		-maxdepth|-mindepth)
			recursiveOpt=()
			findGlobalExpressions+=("$1" "$2"); shift
			;;
		-depth|-d|-ignore_readdir_race|-noignore_readdir_race|-mount|-xdev|-noleaf)
			findGlobalExpressions+=("$1") ;;
		-help|-version)
			assertError "This global find expression is not allowed ($1)" ;;

		# actions (-quit is alright)
		-delete|-exec|-execdir|-fls|-fprint|-fprint0|-fprintf|-ls|-ok|-okdir|-print|-print0|-printf)
			assertError "Actions find options are not allowed. ($1)" ;;

		-prune)
			[ "$fTypeOpt" ] && assertError "-prune can not be used with either the -D (directories only) or -F (files only). Use -type d|f in your expression with -prune "
			findExpressions+=("$1") ;;

		# assume any other is a valid test expression, operator or positional option. If not, find will fail
		 *) findExpressions+=("$1") ;;
	esac; shift; done

	# if the user supplied more than 1 find test expression, it may contain 'or' logic so enclose it in () so that we can treat it
	# like one and'd filter criteria
	[ "${#findExpressions[@]}" -gt 1 ] && findExpressions=('(' "${findExpressions[@]}" ')')

	local commonPrefix
	if [ "$_gitIgnorePath" ] || [ ${#excludePaths[@]} -gt 0 ]; then
		pathGetCommon -R commonPrefix "${findStartingPoints[@]}"
		[ "$commonPrefix" ] && commonPrefix+="/"
	fi

	# add the gitignore contents to the excludePaths if called for
	if [ "$_gitIgnorePath" ]; then
		excludePaths+=(.git .bglocal)
		[ "$_gitIgnorePath" == "<glean>" ] && _gitIgnorePath="${commonPrefix}.gitignore"
		if [ -r "$_gitIgnorePath" ]; then
			local _line; while read _line; do
				excludePaths+=( "$_line" )
			done < "$_gitIgnorePath"
		fi
	fi

	# build the findPruneExpr if there are any excludePaths
	if [ ${#excludePaths[@]} -gt 0 ]; then
		local _folderEntries=() _anyEntries=()
		local _line; for _line in "${excludePaths[@]}"; do
			local _type="both"
			[[ "$_line" =~ /$ ]] && { _line="${_line%%/}"; _type="d"; }
			local _expr="-name"; [[ "$_line" =~ / ]] && _expr="-path"
			[[ "$_line" =~ ^/ ]] && _line="${commonPrefix}${_line##/}"
			if [ "$_type" == "d" ]; then
				_folderEntries+=( -o "$_expr" "$_line" )
			else
				_anyEntries+=( -o "$_expr" "$_line" )
			fi
		done

		findPruneExpr=( "(" "(" -type d "(" -false "${_folderEntries[@]}" ")" ")" -o  "(" -false "${_anyEntries[@]}" ")"  ")" -prune -o )
		#                (-  (--         (---------------------------------) --)       (------------------------------)   -)
	fi


	# the final findExpressions is composed.
	#    recursiveOpt is a 'global option' that must come first. If the user specified -maxdepth or -mindepth recursiveOpt is cleared
	#    fTypeOpt is ANDed with the rest of the expression.
	findExpressions=("${recursiveOpt[@]}" "${findGlobalExpressions[@]}"  "${findPruneExpr[@]}" "${fTypeOpt[@]}" "${findExpressions[@]}")


	# now invoke the find command
	[ "$fsef_prefixToRemove" ] && fsef_prefixToRemove="#${fsef_prefixToRemove#'#'}"
	local _file _found _appendFlag
	while IFS="" read -r -d$'\b' _file; do
		[ "$fsef_prefixToRemove" ] && _file="${_file/$fsef_prefixToRemove}"
		varOutput "${outputOpts[@]}" $_appendFlag "$_file"
		_found="1"
		_appendFlag="--append"
	done < <(find "${findOpts[@]}" "${findStartingPoints[@]}" "${findExpressions[@]}" -print0 | tr "\0" "\b")

	# if no matching pathes were found but forceFlag was specified, output /dev/null. -f is used when making a cmd line for utils
	# (like awk) that read from stdin if no input files are specified.
	if [ "$forceFlag" ] && [ ! "$_found" ]; then
		varOutput "${outputOpts[@]}" "/dev/null"
	fi

	# set the exit code based on whether any were found
	[ "$_found" ]
}


#######################################################################################################################################
### From bg_coreTimer.sh

# FUNCMAN_SKIP
# this is a stub function that will load the bg_coreTimer.sh and the real bgtimerStart if its called
function bgtimerStart()
{
	[ "$1" == "--stub" ] && {
		(assertError  "could not load bg_coreTimer.sh from libCore stub")
		return
	}
	import -f bg_coreTimer.sh ;$L1;$L2
	bgtimerStart --stub "$@"
}


# usage: timeGetAproximateRelativeExpr <timeInEpoch> [<retVar>]
function timeGetAproximateRelativeExpr() {
	local timeInEpoch="${1:-0}"; shift
	local retVar="$1"; shift
	local nowInEpech="$EPOCHSECONDS"
	local type
	if (( timeInEpoch == nowInEpech )); then
		returnValue "now" "$retVar"; return
	elif (( timeInEpoch < nowInEpech )); then
		local secondsDiff=$((nowInEpech - timeInEpoch))
		type="ago"
	else
		local secondsDiff=$((timeInEpoch - nowInEpech))
		type="from now"
	fi

	local str
	if (( secondsDiff > (60*60*24*365) )); then
		str="over $((secondsDiff / (60*60*24*365) )) year"
		(( (secondsDiff / (60*60*24*365)) > 1 )) && str+="s"
	elif (( secondsDiff > (60*60*24*30) )); then
		str="over $((secondsDiff / (60*60*24*30) )) month"
		(( (secondsDiff / (60*60*24*30)) > 1 )) && str+="s"
	elif (( secondsDiff > (60*60*24*7) )); then
		str="over $((secondsDiff / (60*60*24*7) )) week"
		(( (secondsDiff / (60*60*24*7)) > 1 )) && str+="s"
	elif (( secondsDiff > (60*60*24) )); then
		str="over $((secondsDiff / (60*60*24) )) day"
		(( (secondsDiff / (60*60*24)) > 1 )) && str+="s"
	elif (( secondsDiff > (60*60) )); then
		str="over $((secondsDiff / (60*60) )) hour"
		(( (secondsDiff / (60*60)) > 1 )) && str+="s"
	elif (( secondsDiff > (60) )); then
		str="over $((secondsDiff / (60) )) minute"
		(( (secondsDiff / (60)) > 1 )) && str+="s"
	else
		str="$((secondsDiff)) seconds"
	fi

	returnValue "$str $type" "$retVar"
}


#######################################################################################################################################
### From bg_coreDaemon.sh

# FUNCMAN_SKIP
# this is a stub function that will load the bg_coreDaemon.sh and the real daemonDeclare if its called
function daemonDeclare()
{
	[ "$1" == "--stub" ] && assertError "could not load bg_coreDaemon.sh library from on-demand stub function in bg_coreLibsMisc.sh"
	import bg_coreDaemon.sh ;$L1;$L2
	daemonDeclare --stub "$@"
}


#######################################################################################################################################
### From bg_creqs.sh

# usage: DeclareCreqClass <creqClass> <debconfClassAttributes>
# DeclareCreqClass is the newer, prefered style of writing creqClasses in bash scripts.
#
# Example...
#    DeclareCreqClass cr_fileExists
#    function cr_fileExists::check() { [ -e "$1" ]; }
#    function cr_fileExists::apply() { touch "$1"; }
#
# The ::check() must return 0 if the host configuration complies with the creqStatement and non-zero if it does not. It may write
# to stdout to display information whether or not it returns 0. Typically it might write a message about why the host does not pass.
# It probably should not write to stdout if the check passes but it can if it wnats to. If it is not able to complete the check for
# any reason it should exit or raise an exception by calling an assertError* function. By convention, it should write an error
# message to stderr if its going to exit. The arguments in the creqStatement are passed to the check function.
#
# The ::apply() should attempt to change the host configuarion so that it will comply with the creqStatement. It may produce informative
# output on stdout but does not need to. If it is successful in changing the host to comply, it must return 0. If it is not successfull,
# it must either return non-zero or exit (typically by calling an assertError* function). It is good practice to write an error
# message to stderr if it return non-zero or exits. The ::apply() function will only get called if the ::check() function has been
# called and indicates that the host is not in compliance so the apply algorithm can assume that the host is not yet compliant.
# The arguments in the creqStatement are passed to the check function.
#
# The author can optionally define a ::construct() function which will be called first, once per creqStatement execution.
# The ::construct() function is passed the creqStatement arguments and would typically process and store the results in variables
# that the ::check() and ::apply() functions would then use instead of repeating the work to process the arguments from scratch.
# The entire creqStatement is executed in a subshell so the ::construct(), ::check() and ::apply() functions share a private 'global'
# variable scope that they can use to communicate between each other. This means that as long as the ::construct() function does not
# decalare a variable that it sets as 'local', that variable will be avaialble to the ::check() and ::apply() functions. Because the
# ::check() function is always called before the ::apply() function, the author could use the ::check() function to process the
# arguments instead of dong it in the ::construct() function. Either way, as long as a variable is not declared local in the
# ::construct() or ::check() functions, the ::apply() function can rely on its value.  Also, an associative array named 'this' is
# declared in the execution sub shell so the function may use it to pass variables between each other which some authors may find
# more descriptive -- particularely if they are used to writing bash object methods using 'this'.
#
# CreqStatement Description:
# By default the display version of the creqStatement is the actual `<creqClass> [<arg1>..<argN>]` command line but the author of
# a <creqClass> can override that for its creqStatements.
#
# The default output for each of the non-error outcomes of a cr_fileExists creqClass would look somthing like...
#     PASS:    fileExists /etc/foo.conf
#     FAIL:    fileExists /etc/foo.conf
#     APPLIED: fileExists /etc/foo.conf
# By providing bespoke pass, fail, and applied messages, the output could look like this...
#     PASS:    file /etc/foo.conf exists
#     FAIL:    file /etc/foo.conf is missing
#     APPLIED: created file /etc/foo.conf
#
# In the call to DeclareCreqClass, the author can provide template strings to use or in the ::*() functions, it can set the actual
# message to use. Note that a difference is that when passed to the DeclareCreqClass, it must be a template because those strings
# are constant for all creqStatements but when set in one of the ::*() functions, the statement arguments are available so the code
# can compose the text directly.
#
# The author can provide one msg that will be used as the display text for all <resultState>s or can provide different text for
# the <resultState>s (Pass|Fail|Apply). The ErrorIn* <resultState>s will always use the original creqStatement text since those
# represent an error for which the exact statement should be visible to inspect for errors in the statement.
#
# In one of the functions, the code can set one of these variables which will be taken as-is and NOT expanded as a template
#    msg or this[msg]   : a new default stmText which will be used if a more specific stmText is not set
#    passMsg or this[passMsg] : the stmText to use when the <resultState> is "Pass"
#    failMsg or this[failMsg] : the stmText to use when the <resultState> is "Fail"
#    appliedMsg or this[appliedMsg] : the stmText to use when the <resultState> is "Applied"
#
# The DeclareCreqClass function accepts an optional second parameter that is a deb conf file syntax string containing attribute definitions.
# The following attributes are recognized by the creqShellFnImplStub function as template strings that will be expanded against any
# non-local variables set by the <creqClass>::*() functions to create the statement text.
#     msg     : a template string that will be the default creqStatement text if a more specific msg is not defined.
#     passMsg : template string to use when as the the creqStatement when the check passes
#     failMsg : template string to use when as the the creqStatement when the check does not pass and its running in check mode
#     appliedMsg : template string to use when as the the creqStatement when the apply function suceeds in making the host comply
# The template strings can reference any variables set in either the ::construct() or ::check() functions. Also the variable creqStatement
# can be used in template strings.
#
# Example:
#    DeclareCreqClass cr_fileExists "
#        passMsg: file %filename% exists
#        failMsg: file %filename% is missing
#        appliedMsg: created file %filename%
#    "
#    function cr_fileExists::check() {
#        filename="$1"  # note! no 'local ...'
#        [ -f "$filename" ]
#    }
#    function cr_fileExists::apply() {
#        touch "$filename"
#    }
#
# See Also:
#    man(7) bg_creqs.sh
#    man(3) creqShellFnImplStub
#    man(3) creqLegacyShellFnImplStub  : creq bash stub function for running legacy cr_* functions that use the case statement style
function DeclareCreqClass()
{
	local creqClass="$1"
	[[ "$creqClass" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]] || assertError "invalid creqClass name"
	declare -gA $creqClass='()'
	[ $# -gt 0 ] && parseDebControlFile $creqClass "$@"
	eval '
		function '$creqClass'() {
			creqClass="'"$creqClass"'" creqShellFnImplStub "$@" ;
		}'
}
