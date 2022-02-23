
# Library bg_coreLSBVersions.sh
# This library wraps the lsb_release command and also provides functions to check the version of other common systems or programs
# like bash.  I use lsb* as the prefix for all the functions in this library even if they are not implemented in terms of lsb_release
# because its useful to have a nmemonic to identify the entire family of functions to check the running environment





# usage: lsbLoadInfo [-q]
# This loads the LSB (linux standard base) information about the local host.
# This is called by all the other lsb* functions. The information is cached for each script run so its efficient
# to call the individual lsb* functions as needed, multiple times.
# Options:
#    -q : quiet. if the lsb info is not found, quietly return instead of asserting an error
function lsbLoadInfo()
{
	# if its already loaded the lsb info, just return
	[ "$_lsbDistribID" ] && return

	local quietFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q)  quietFlag="-q" ;;
	esac; shift; done

	declare -g _lsbDistribID _lsbDistribRelease _lsbDistribCodeName _lsbDistribDesc
	declare -gA ubuntuNames ubuntuNumbers
	ubuntuNames["10.04"]="lucid"
	ubuntuNames["11.04"]="natty"
	ubuntuNames["12.04"]="precise"
	ubuntuNames["13.04"]="raring"
	ubuntuNames["14.04"]="trusty"
	ubuntuNames["14.10"]="utopic"
	ubuntuNames["15.04"]="vivid"
	ubuntuNames["15.10"]="wily"
	ubuntuNames["16.04"]="xenial"
	ubuntuNames["16.10"]="yakkety"
	ubuntuNames["17.40"]="zesty"
	local i
	for i in "${!ubuntuNames[@]}"; do { ubuntuNumbers[$i]="$i"; ubuntuNumbers[${ubuntuNames[$i]}]="$i"; }; done
	for i in "${!ubuntuNames[@]}"; do ubuntuNames[${ubuntuNames[$i]}]="${ubuntuNames[$i]}"; done


	# if the file exists, its quickest to just read from it. This has been tested and works in Ubuntu, Other OS might
	# need different cases.
	if [ -f /etc/lsb-release ]; then
		read -r _lsbDistribID _lsbDistribRelease _lsbDistribCodeName _lsbDistribDesc < <(gawk -F"=" '
			BEGIN {id="--"; release="--"; codeName="--"; desc="--"}
			$1=="DISTRIB_ID"          {id=$2}
			$1=="DISTRIB_RELEASE"     {release=$2}
			$1=="DISTRIB_CODENAME"    {codeName=$2}
			$1=="DISTRIB_DESCRIPTION" {desc=$2}
			END{print id" "release" "codeName" "desc}
		' /etc/lsb-release)

	# else if the lsb_release command exists use it to get the info
	elif which lsb_release &>/dev/null; then
		read -r _lsbDistribID _lsbDistribRelease _lsbDistribCodeName _lsbDistribDesc < <(lsb_release -a | awk -F":" '
			BEGIN {id="--"; release="--"; codeName="--"; desc="--"}
			$1=="Distributor ID"  {id=$2}
			$1=="Release"         {release=$2}
			$1=="Codename"        {codeName=$2}
			$1=="Description"     {desc=$2}
			END{print id" "release" "codeName" "desc}
		')
	else
		[ ! "$quietFlag" ] && assertError "unrecognized linux distribution. See man lsbLoadInfo"
	fi
}

# usage: lsbGetDistro [-q]
# The distro (aka distribution) is Ubuntu, etc...
# Options:
#    -q : quiet. if the lsb info is not found, quietly return instead of asserting an error
function lsbGetDistro()
{
	local quietFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q)  quietFlag="-q" ;;
	esac; shift; done

	lsbLoadInfo

	[ ! "$quietFlag" ] && assertNotEmpty _lsbDistribID
	echo "$_lsbDistribID"
}



# usage: lsbGetCodeName [-q]
# The distribution code name is trusty, xenial, etc...
# Options:
#    -q : quiet. if the lsb info is not found, quietly return instead of asserting an error
function ubuntuGetName() { lsbGetCodeName "$@"; }
function lsbGetCodeName()
{
	local quietFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q)  quietFlag="-q" ;;
	esac; shift; done

	lsbLoadInfo

	[ ! "$quietFlag" ] && assertNotEmpty _lsbDistribCodeName
	echo "$_lsbDistribCodeName"
}


# usage: lsbGetVersion [-q]
# The distribution version (aka release) is 12.04, 14.04, etc...
# Options:
#    -q : quiet. if the lsb info is not found, quietly return instead of asserting an error
function lsbGetVersion()
{
	local quietFlag
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q)  quietFlag="-q" ;;
	esac; shift; done

	lsbLoadInfo

	[ ! "$quietFlag" ] && assertNotEmpty _lsbDistribRelease
	echo "$_lsbDistribRelease"
}


# usage: ubuntuVersionAtLeast <targetVersion>
# returns true if the local host is running ubuntu and its the specified version or newer
# .SH See Also:
#   man lsbVersionAtLeast
function ubuntuVersionAtLeast()
{
	lsbVersionAtLeast Ubuntu "$@"
}


# usage: lsbVersionAtLeast <distro> [<targetVersion>]
# returns true if the local host is running <distro> and its the specified version or newer
# if <targetVersion> is not specified any version of <distro> will be acceptable
function lsbVersionAtLeast()
{
	lsbLoadInfo
	local targetDistro="$1"; [ $# -gt 0 ] && shift
	local targetVersion="$1"

	[ "$_lsbDistribID" == "$targetDistro" ] || return 1

	# if targetVersion is not specified we are just checking that its any <distro> version
	[ ! "$targetVersion" ] && return 0

	# translate the codeName if needed
	if [[ ! "${targetVersion//.}" =~ ^[0-9]*$ ]]; then
		case $targetDistro in
			Ubuntu) targetVersion="${ubuntuNumbers[$targetVersion]}" ;;
			*)  [ "$targetVersion" == "$_lsbDistribCodeName" ] && return 0
				assertError "This library only knows Ubuntu distro codenames so far. Use the version number instead until the lsb* functions are enhanced to support codenames for '$targetDistro'"
				;;
		esac

		# if we have not heard of it, assume its newer than anything we know about
		targetVersion=${targetVersion:-10000}
	fi

	# compare them without the '.' This works for now. We may have to do proper version compare someday
	[ ${_lsbDistribRelease//.} -ge ${targetVersion//.} ]
}


# usage: lsbBashVersionAtLeast <version>
function lsbBashVersionAtLeast()
{
	local version="$1"
	local bashVersion="$(bash --version | head -n1 | grep -o "\b[0-9]\+[.][0-9]\+[.][0-9]\+[^ $]*\b")"
	versionGt "$bashVersion" "$version"
}
