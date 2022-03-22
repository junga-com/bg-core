
# Library bg_coreSemVer.sh
# This library provides functions to compare and manipulate semantic verion numbers.


# usage: versionCompare <versionStr1> <versionStr2>
# See definition of Semantic Versions on wikipedia.
# Format:
#    <major>.<minor>.<patch>[<devTag>]
#    e.g. 1.0.23
# Exit Codes:
#     0   : equal. <versionStr1> and <versionStr2> refer to the same exact version number
#     1   : less than,    differ only in patch level. <versionStr1> patch level is a lower version than <versionStr2> patch level
#     2   : greater than, differ only in patch level. <versionStr1> patch level is a greater version than <versionStr2> patch level
#     11  : less than,    differ in minor level. <versionStr1> minor level is a lower version than <versionStr2> minor level
#     12  : greater than, differ in minor level. <versionStr1> minor level is a greater version than <versionStr2> minor level
#     101 : less than,    differ in major level. <versionStr1> major level is a lower version than <versionStr2> major level
#     102 : greater than, differ in major level. <versionStr1> major level is a greater version than <versionStr2> major level
#     201 : less than,    differs only in devTag. This indicates that changes have been made to the a.b.c version but we dont know
#           if those changes will increment patch, minor, or major when released
#     202 : greater than, differs only in devTag. This indicates that changes have been made to the a.b.c version but we dont know
#           if those changes will increment patch, minor, or major when released
function versionCompare()
{
	local lVersion="$1"
	local rVersion="$2"
	local rematch

	match "$lVersion" "^([0-9]+)([.]([0-9]+)([.]([0-9]+)[.-]?(.*))?)?$" rematch || assertError -v lVersion "lVersion is not a valid semver format"
	local lMajor=${rematch[1]:-0}
	local lMinor=${rematch[3]:-0}
	local lPatch=${rematch[5]:-0}
	local lDevTag=${rematch[6]}

	match "$rVersion" "^([0-9]+)([.]([0-9]+)([.]([0-9]+)[.-]?(.*))?)?$" rematch || assertError -v rVersion "rVersion is not a valid semver format"
	local rMajor=${rematch[1]:-0}
	local rMinor=${rematch[3]:-0}
	local rPatch=${rematch[5]:-0}
	local rDevTag=${rematch[6]}

	(( lMajor < rMajor )) && return 101
	(( lMajor > rMajor )) && return 102

	(( lMinor < rMinor )) && return 11
	(( lMinor > rMinor )) && return 12

	(( lPatch < rPatch )) && return 1
	(( lPatch > rPatch )) && return 2

	(( lDevTag < rDevTag )) && return 201
	(( lDevTag > rDevTag )) && return 202

	return 0;
}


# usage: versionEq <versionStr1> <versionStr2>
# success (true) if <versionStr1> is logically equal to <versionStr2>
# Format:
#    major.minor.revision
#    e.g. 1.0.23
# Exit Codes:
#     0   : equal. <versionStr1> and <versionStr2> refer to the same logical version number
#     1   : not equal
function versionEq()
{
	versionCompare "$@"
	[ $? -eq 0 ]
}

# usage: versionLt <versionStr1> <versionStr2>
# success (true) if <versionStr1> is less than <versionStr2>
# Format:
#    major.minor.revision
#    e.g. 1.0.23
# Exit Codes:
#     0   : equal. <versionStr1> and <versionStr2> refer to the same logical version number
#     1   : not equal
function versionLt()
{
	versionCompare "$@"
	local result="$?"
	[ $result -eq 1 ] || [ $result -eq 11 ] || [ $result -eq 101 ] || [ $result -eq 201 ]
}

# usage: versionGt <versionStr1> <versionStr2>
# success (true) if <versionStr1> is greater than <versionStr2>
# Format:
#    major.minor.revision
#    e.g. 1.0.23
# Exit Codes:
#     0   : equal. <versionStr1> and <versionStr2> refer to the same logical version number
#     1   : not equal
function versionGt()
{
	versionCompare "$@"
	local result="$?"
	[ $result -eq 2 ] || [ $result -eq 12 ] || [ $result -eq 102 ] || [ $result -eq 202 ]
}

# usage: versionIncrement [--major|--minor|--patch] <versionStr> [<retVal>]
# increment the version number according to semver
# major.minor.revision
# e.g. versionIncrement --patch 1.0.23 -> will return 1.0.24
# e.g. versionIncrement --minor 1.0.23 -> will return 1.1.0
# e.g. versionIncrement --major 1.0.23 -> will return 2.0.0
# Options:
#    --major : inc major part to indicate a non-backward compatible change
#    --minor : inc minor part to indicate new, backward compatible functionality
#    --patch : inc major part to indicate a non-backward compatible change
#    --keepDevTag : if the input version has a devTag suffix, it is normally dropped with all types of increments.
function incrementRevision() { versionIncrement "$@"; }
function versionIncrement()
{
	local mode="patch"
	local keepDevTag
	while [ $# -gt 0 ]; do case $1 in
		--major)  mode="major" ;;
		--minor)  mode="minor" ;;
		--patch)  mode="patch" ;;
		--keepDevTag) keepDevTag="--keepDevTag" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local version=$1
	local rematch

	match "$version" "^([0-9]+)([.]([0-9]+)([.]([0-9]+)[.-]?(.*))?)?$" rematch || assertError -v version "version is not a valid semver format"
	local major=${rematch[1]:-0}
	local minor=${rematch[3]:-0}
	local patch=${rematch[5]:-0}
	local devTag=${rematch[6]}

	case $mode in
		patch) ((patch++))  ;;
		minor) ((minor++)); patch=0 ;;
		major) ((major++)); minor=0; patch=0 ;;
	esac

	[ ! "$keepDevTag" ] && devTag='';

	returnValue "${major}.${minor}.${patch}${devTag:--}${devTag}" "$2"
}
