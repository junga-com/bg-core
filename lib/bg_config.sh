
import bg_ini.sh  ;$L1;$L2

# Library
# Provides a scoped, system wide configuration system.
# A scoped configuration consists of an ordered list of overlaid layers (aka scopes). The effective value for any particular
# setting is the value present in the scope closest to the top. Values in scopes closer to the top, hide (aka override) any values
# for the same setting in scopes lower down.
#
# The order of the scopes is from the most specific on top to the most general on the bottom. The local configuration of a host
# specific to a particular user may be the top most scope. The scope for an entire domain may be the lowest scope.
#
#

declare -gA configScopes=(
	[0]="user host location global"
	[user]="/home/$USER/.config/bg-core/bgsys.conf"
	[host]="/etc/bgsys.conf"
	[location]="/etc/bgsys.location.conf"
	[global]="/etc/bgsys.global.conf"
)

function configGet()
{
	local passThruOpts _cgTemplateFlag retVar _cgValue
	while [ $# -gt 0 ]; do case $1 in
		-R*|--retVar*) bgOptionGetOpt val: retVar       "$@" && shift ;;
		-t|--expandAsTemplate)  _cgTemplateFlag="-t" ;;
		-d*|--delim*) bgOptionGetOpt opt: passThruOpts "$@" && shift ;;
		-x|--noSectionPad)  bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local ipg_sectionName="$1"
	local ipg_paramName="$2";  assertNotEmpty ipg_paramName
	local ipg_defaultValue="$3"

	local _cgFiles _cgScope
	for _cgScope in $configScopes; do
		_cgFiles+="${configScopes[$_cgScope]},"
	done
	_cgFiles="${_cgFiles%,}"

	iniParamGet "${passThruOpts[@]}" -R _cgValue  "$_cgFiles"  "$ipg_sectionName" "$ipg_paramName" "$ipg_defaultValue"
	local result=$?

	[ "$_cgTemplateFlag" ] && templateExpandStr -R _cgValue "$_cgValue"

	returnValue "$_cgValue" "$retVar"
	return ${result:-0}
}

function configSet()
{
	local passThruOpts verbosity="$verbosity" _csScope="host"
	while [ $# -gt 0 ]; do case $1 in
		-s*|--scope*)       bgOptionGetOpt val: _csScope "$@" && shift ;;

		-S*|--statusVar)    bgOptionGetOpt opt: passThruOpts  "$@" && shift ;;
		-R*|--resultsVar*)  bgOptionGetOpt opt: passThruOpts  "$@" && shift ;;
		-c*|--comment*)     bgOptionGetOpt opt: passThruOpts   "$@" && shift ;;
		--sectionComment*)  bgOptionGetOpt opt: passThruOpts   "$@" && shift ;;
		-qN|--noQuote)      bgOptionGetOpt opt passThruOpts   "$@" && shift ;;
		-q1|--singleQuote)  bgOptionGetOpt opt passThruOpts   "$@" && shift ;;
		-q2|--doubleQuote)  bgOptionGetOpt opt passThruOpts   "$@" && shift ;;
		-d*|--delim*)       bgOptionGetOpt opt: passThruOpts    "$@" && shift ;;
		--commentsStyle*)   bgOptionGetOpt opt: passThruOpts    "$@" && shift ;;
		--paramPad*)        bgOptionGetOpt opt: passThruOpts    "$@" && shift ;;
		--sectPad*)         bgOptionGetOpt opt: passThruOpts    "$@" && shift ;;
		-x|--noSectionPad)  bgOptionGetOpt opt  passThruOpts "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local sectionName="$1"
	local paramName="$2";   assertNotEmpty paramName
	local paramValue="$3"

	local _csFile="${configScopes[$_csScope]}";  assertNotEmpty _csFile -v scope:_csScope -v configScopes "No configuration file is associated with the specified scope"

	iniParamSet -p "${passThruOpts[@]}"  "$_csFile"  "$sectionName" "$paramName" "$paramValue"
	local result=$?
	return ${result:-0}
}

function configRemove()
{
	local passThruOpts statusVarName resultsVarName _crResults
	local verbosity="$verbosity"
	while [ $# -gt 0 ]; do case $1 in
		-S*|--statusVar)    bgOptionGetOpt val: statusVarName  "$@" && shift ;;
		-R*|--resultsVar*)  bgOptionGetOpt val: resultsVarName "$@" && shift ;;
		-d*|--delim*)       bgOptionGetOpt opt: passThruOpts   "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	local sectionName="$1"
	local paramName="$2";   assertNotEmpty paramName

	local _crScope; for _crScope in $configScopes; do
		if iniParamRemove -R _crResults "${passThruOpts[@]}"  "${configScopes[$_crScope]}"  "$sectionName"  "$paramName"; then
			setReturnValue "$resultsVarName" "$_crResults:$_crScope"
			setReturnValue "statusVarName" "changed"
			return 0
		fi
	done
	setReturnValue "$resultsVarName" "nochange"
	return 1
}

function configView()
{
	local _cgFiles _cgScope
	for _cgScope in $configScopes; do
		_cgFiles+="${configScopes[$_cgScope]},"
	done
	_cgFiles="${_cgFiles%,}"
	local -a ipg_iniFiles; fsExpandFiles -f -A ipg_iniFiles ${_cgFiles//,/ }

	bgawk -n \
		--include="bg_ini.awk" '

		BEGIN {
			arrayCreate(settings)
			arrayCreate(fileMap)
		}

		$1=="]###" && $2=="filemap" { iniFile="filemap" }
		iniFile=="filemap" { fileMap[$2]=$1 }

		iniLineType=="setting" {
			if (! (iniParamFullName in settings)) {
				arrayCreate2(settings,iniParamFullName)
				settings[iniParamFullName]["value"]=iniParamName
				settings[iniParamFullName]["file"]=inifile
				scope=fileMap[iniFile]; if (!scope) scope=iniFile
				printf("%-10s %-20s %s\n", scope, iniParamFullName, iniValue)
			}
		}

	' <(
		echo "]### filemap"
		for _cgScope in $configScopes; do
			printf "%s %s\n" "$_cgScope" "${configScopes[$_cgScope]}"
		done
	) "${ipg_iniFiles[@]}"
}
