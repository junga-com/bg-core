#!/bin/bash

# usage: cr_symlinkExists <targetPath> <symlinkPath>
# declare that the symlink should exist with the specified target
DeclareCreqClass cr_symlinkExists
function cr_symlinkExists::construct() {
	targetPath="$1"
	symlinkPath="$2"
}
function cr_symlinkExists::check() {
	[ -h "$symlinkPath" ] && [ "$(readlink "$symlinkPath")" == "$targetPath" ]
}
function cr_symlinkExists::apply() {
	ln -sf "$targetPath" "$symlinkPath"
}



# usage: cr_fileExists <filename> [ <contents> ]
# declare that a file should exist.
# Apply will create the file and initialize it with <content> if provided or an empty file if not.
# Params:
#    <filename>  : the target file that should exist
#    <contents>  : the optional contents to create <filename> with if apply is performed. The first word deliminated with a ':'
#                  determines the type of <contents> as follows. If none of these prefix match, and <contents> is not empty, the
#                  literal value of the second parameter will be written to the file. If no second parameter is specified, fsTouch
#                  will be used to create an empty file
#            file:<sourceFilename>    : copy <sourceFilename> into <filename>
#            template:<templateName>  : use the template system to locate and expand <templateName> into <filename>
#            templateStr:..           : use the template system to expand the remainder of the argument as a template string into
#                                       <filename>
#            string:...               : write the remainder of the argument as a literal string into <filename>
DeclareCreqClass cr_fileExists "
	passMsg: file %filename% exists
	failMsg: file %filename% is missing
	appliedMsg: created %filename% %contentType%
	maxContentSize: 40
"
function cr_fileExists::check() {
	filename="$1"
	[ -f "$filename" ]
}
function cr_fileExists::apply() {
	contentTerm="$2"
	if [[ "$contentTerm" =~ ^file: ]]; then
		contentType="from file ${contentTerm#file:}"
		cp "${contentTerm#file:}" "$filename"
	elif [[ "$contentTerm" =~ ^template: ]]; then
		contentType="from template file '${contentTerm#template:}'"
		local templateName="${contentTerm#template:}"
		import bg_template.sh ;$L1;$L2
		templateExpand "$templateName" "$filename"
	elif [ ! "$contentTerm" ]; then
		fsTouch "$filename"
		contentType="with empty content"
	else
		# its a string content that might be a template. If not a template, it may or may not start with 'string:'
		content="$(strRemoveLeadingIndents "${contentTerm#string:}")"
		contentType="from a string"
		if [[ "$content" =~ ^templateStr: ]]; then
			templateStr="${content#templateStr:}"
			contentType="from a template string"
			import bg_template.sh ;$L1;$L2
			templateExpandStr -R content "$templateStr"
		fi
		contentClip="${content:0:${cr_fileExists[maxContentSize]}}"; contentClip="${contentClip//$'\n'/\\n}";
		[ ${#content} -gt ${cr_fileExists[maxContentSize]:-0} ] && contentClip="${contentClip:0:$((${cr_fileExists[maxContentSize]}-3))}..."
		contentType+=" '$contentClip'"
		echo "$content" | bgsudo -w "$filename" tee "$filename" >/dev/null
	fi
}

# usage: cr_fileExistsWithContent <filename> <contents>
# declare that a file should exist and should contain exactly the specied content.
# Apply will write the specified content to the file, overwriting anything that it may have contained before
# The only difference between this and cr_fileExists is that cr_fileExists uses the content only to create the file if it does not
# exist and after that, the content can change to something else. cr_fileExistsWithContent on the other hand uses the content in
# the check function so it will fail if the content gets changed from <contents>
DeclareCreqClass cr_fileExistsWithContent "
	passMsg: %filename% exists with content %contentType%
	failMsg: %filename% does not contain %contentType%
	appliedMsg: created %filename% %contentType%
	maxContentSize: 40
"
function cr_fileExistsWithContent::construct() {
	filename="$1"
	contentTerm="$2"
	if [[ "$contentTerm" =~ ^file: ]]; then
		contentType="from file ${contentTerm#file:}"
		content="$(cat "${contentTerm#file:}")"
	elif [[ "$contentTerm" =~ ^template: ]]; then
		contentType="from template file '${contentTerm#template:}'"
		import bg_template.sh ;$L1;$L2
		content="$(templateExpand "${contentTerm#template:}")"
	elif [ ! "$contentTerm" ]; then
		content=""
		contentType="with empty contents"
	else
		# its a string content that might be a template. If not a template, it may or may not start with 'string:'
		content="$(strRemoveLeadingIndents "${contentTerm#string:}")"
		contentType="from string '%contentClip%'"
		if [[ "$content" =~ ^templateStr: ]]; then
			templateStr="${content#templateStr:}"
			contentType="from template string '%contentClip%'"
			import bg_template.sh ;$L1;$L2
			templateExpandStr -R content "$templateStr"
		fi
		contentClip="${content:0:${cr_fileExists[maxContentSize]}}"; contentClip="${contentClip//$'\n'/\\n}";
		[ ${#content} -gt ${cr_fileExists[maxContentSize]:-0} ] && contentClip="${contentClip:0:$((${cr_fileExists[maxContentSize]}-3))}..."
		contentType+=" '$contentClip'"
	fi
}
function cr_fileExistsWithContent::check() {
	[ -f "$filename" ] && [ "$(cat "$filename")" == "$content" ]
}
function cr_fileExistsWithContent::apply() {
	echo "$content" | bgsudo -w "$filename" tee "$filename" >/dev/null
}




# usage: cr_fileNotExists <filename>
# declare that a file should exist. Apply will 'rm' the file
DeclareCreqClass cr_fileNotExists "
	passMsg: %filename% does not exist
	failMsg: %filename% exists
	appliedMsg: removed %filename%
"
function cr_fileNotExists::check() {
	filename="$1"
	! [ -f "$filename" ]
}
function cr_fileNotExists::apply() {
	bgsudo -c "$filename" rm -f "$filename"
}


# cr_folderExists foldername
# declares that the specified folder should exist
DeclareCreqClass cr_folderExists
function cr_folderExists::check() {
	[ -d "$1" ]
}
function cr_folderExists::apply() {
	bgsudo -c "$1" mkdir -p "$1"
}

# cr_folderNotExits [-f] foldername
# declares that the specified folder should exist
# apply will only remove the folder if its empty unless -f is specified, which will remove its contents and then remove the folder
DeclareCreqClass cr_folderNotExits
function cr_folderNotExits::construct() {
	forceFlag=''
	while [ $# -gt 0 ]; do case $1 in
		-f) forceFlag="-f" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done
	foldername="$1"
}
function cr_folderNotExits::check() {
	! [ -d "$foldername" ]
}
function cr_folderNotExits::apply() {
	[[ "$foldername" =~ ^/[^/]*/{0,1}$ ]] && assertError "the folder passed to 'cr_folderNotExits $foldername' can not be root or a top level folder"
	if [ "$forceFlag" ]; then
		bgsudo -c "$foldername" rm -rf "${opts[@]}" "$foldername"
	else
		bgsudo -c "$foldername" rmdir "$foldername"
	fi
}


# usage: cr_folderContentsCopied <sourceFolder> <destinationFolder> [ insideFlag ]
# declare that the contents of a folder should exist in the destination folder.
# if insideFlag is specified, the contents of each file must also match
# Apply will cp sourceFolder contents (files and dirs) to the
# destinationFolder.
function cr_folderContentsCopied()
{
	case $objectMethod in
		objectVars) echo "sourceFolder destinationFolder insideFlag" ;;
		construct)
			sourceFolder="$1"
			destinationFolder="$2"
			insideFlag="$3"
			;;

		check)
			local allExist="1" i i1 i2 filesToCheck dirsToCheck

			readarray -t dirsToCheck < <(find "$sourceFolder" -mindepth 1 -type d  -printf "%P\n")
			for i in ${!dirsToCheck[@]}; do
				i2="$destinationFolder/${dirsToCheck[$i]}"
				! [ -d "$i2" ] && allExist=""
			done

			readarray -t filesToCheck < <(find "$sourceFolder" -type f -printf "%P\n")
			for i in ${!filesToCheck[@]}; do
				i1="$sourceFolder/${filesToCheck[$i]}"
				i2="$destinationFolder/${filesToCheck[$i]}"
				if [ ! -f "$i2" ]; then
					allExist=""
				elif [ "$insideFlag" ] && [ "$(diff -q "$i1" "$i2")" ]; then
					allExist=""
				fi
			done
			[ "$allExist" ]
			;;

		apply)
			local i i1 i2 filesToCheck dirsToCheck

			readarray -t dirsToCheck < <(find "$sourceFolder" -mindepth 1 -type d  -printf "%P\n")
			for i in ${!dirsToCheck[@]}; do
				i2="$destinationFolder/${dirsToCheck[$i]}"
				! [ -d "$i2" ] && mkdir -p "$i2"
			done

			readarray -t filesToCheck < <(find "$sourceFolder" -type f -printf "%P\n")
			for i in ${!filesToCheck[@]}; do
				i1="$sourceFolder/${filesToCheck[$i]}"
				i2="$destinationFolder/${filesToCheck[$i]}"

				if [ ! -f "$i2" ]; then
					cp "$i1" "$i2"
				elif [ "$insideFlag" ] && [ "$(diff -q "$i1" "$i2")" ]; then
					cp "$i1" "$i2"
				fi
			done
			;;

		*) cr_baseClass "$@" ;;
	esac
}


# usage: cr_folderContentsUntared [-z] <tarFile> <destinationFolder>
# declare that the contents of a tar file should exist in the destination folder.
# Apply will cp sourceFolder contents (files and dirs) to the
# destinationFolder.
function cr_folderContentsUntared()
{
	case $objectMethod in
		objectVars) echo "tarFile destinationFolder parentFolder" ;;
		construct)
			tarFile="$1"
			destinationFolder="$2"
			parentFolder="$(dirname "$destinationFolder")"
			;;

		check)
			[ -d "$destinationFolder" ] && [ ! "$(tar -df "$tarFile" -C "$parentFolder" | grep "No such file or directory")" ]
			;;

		apply)
			tar --keep-old-files -xf "$tarFile" -C "$parentFolder"
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_folderContentsRemoved <sourceFolder> <destinationFolder> [insideFlag]
# declare that the contents of a file should not exist in the destination folder.
# Apply will remove from <destinationFolder> each relative path that exists under <sourceFolder>
# If insideFlag is specified, files will only be removed if the contents are equal to the contents of the corresponding file in
# <sourceFolder>
function cr_folderContentsRemoved()
{
	case $objectMethod in
		objectVars) echo "sourceFolder destinationFolder insideFlag" ;;
		construct)
			sourceFolder="$1"
			destinationFolder="$2"
			insideFlag="$3"
			[ "$insideFlag" ] && assertError "insideFlag option is not yet implemented"
			;;

		check)
			local noneExist="1"
			saveIFS=$IFS
			IFS="|"
			for i in find "$sourceFolder" -type f -exec echo -n \{\}\| \;; do
				i2="${i/$sourceFolder/$destinationFolder}"
				if [ -f "$i2" ]; then
					noneExist=""
				fi
			done
			for i in $(find "$sourceFolder" -mindepth 1 -type d -exec echo -n \{\}\| \;); do
				i2="${i/$sourceFolder/$destinationFolder}"
				if [ -d "$i2" ] && [ ! "$(ls $i2 2>/dev/null)" ]; then
					noneExist=""
				fi
			done
			IFS=$saveIFS
			[ "$noneExist" ]
			;;

		apply)
			saveIFS=$IFS
			IFS="|"
			for i in $(find "$sourceFolder" -type f -exec echo -n \{\}\| \;); do
				i2="${i/$sourceFolder/$destinationFolder}"
				if [ -f "$i2" ]; then
					rm "$i2"
				fi
			done
			for i in $(find "$sourceFolder" -mindepth 1 -type d -exec echo -n \{\}\| \;); do
				i2="${i/$sourceFolder/$destinationFolder}"
				if [ -d "$i2" ] && [ ! "$(ls $i2 2>/dev/null)" ]; then
					rmdir "$i2"
				fi
			done
			IFS=$saveIFS
			;;

		*) cr_baseClass "$@" ;;
	esac
}



# usage: cr_configRedirected <source> <destination>
# declare that source should be a link to destination .
# Apply will make source be a symlink to destination.
# if source exists and is not a symlink, it will be renamed to source.orig
function cr_configRedirected()
{
	case $objectMethod in
		objectVars) echo "source destination" ;;
		construct)
			source="$1"
			destination="$2"
			;;

		check)
			[ -h "$source" ] && [ "$(readlink "$source")" == "$destination" ]
			;;

		apply)
			if [ -h "$source" ]; then
				ln -f -T  -s "$destination" "$source"
			else
				if [ -e "$source" ]; then
					local suffix=""
					if [ -e "${source}.orig" ]; then
						suffix=".$(date +"%Y-%m-%d-%H-%M-%S")"
					fi
					sudo mv "$source" "${source}.orig$suffix"
				fi
				ln -T --suffix=".orig" -b -s "$destination" "$source"
			fi
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# OBSOLETE: instead wrap service config creqs in 'creqsTrackChangesStart -s <serviceName>' and 'creqsTrackChangesStart <serviceName>'
# usage: cr_serviceRunningCurrentConfig <service> [<restartRequiredFlag>]
# declare that a service is running. The restartRequiredFlag indicates whether
# the service needs to be restarted. It can be "" (no), "1" (yes), or the name of
# a varName used to track changes with  creqsTrackChangesStart
# restartRequiredFlag is typically
function cr_serviceRunningCurrentConfig()
{
	case $objectMethod in
		objectVars) echo "service restartRequiredFlag command" ;;
		construct)
			service="$1"
			restartRequiredFlag="${2}"

			# if the restartRequiredFlag is not "" or "1", then take it as a varName
			if [[ ! "$restartRequiredFlag" =~ ^1*$ ]]; then
				restartRequiredFlag="${creqsChangetrackers[$restartRequiredFlag]}${creqsChangetrackersActive[$restartRequiredFlag]}"
			fi
			command=""
			displayName="serviceRunningCurrentConfig: service '$service'"
			;;

		check)
			# note that many initv scripts are written in a way that sudo is required to run 'status'
			# we can put a sudo config that allows running sudo * status w/o a password
			if ! sudo service $service status >/dev/null; then
				noPassMsg="serviceRunningCurrentConfig: service '$service' is not running"
				command="start"
				return 2
			fi
			if [ "$restartRequiredFlag" ]; then
				noPassMsg="serviceRunningCurrentConfig: service '$service' requires a restart"
				command="restart"
				return 1
			fi
			passMsg="serviceRunningCurrentConfig: service '$service' is running"
			return 0
			;;

		apply)
			echo service $service ${command:-restart}
			if ! service $service ${command:-restart}; then
				failedMsg="serviceRunningCurrentConfig: service '$service' failed to '${command:-restart}'"
				return 1
			else
				appliedMsg="serviceRunningCurrentConfig: service '$service' was ${command:-restart}ed"
			fi
			;;

		*) cr_baseClass "$@" ;;
	esac
}



# usage: cr_stringReplaced <file> <toFind> <toReplace>
# declare that there are no occurrences of 'toFind' in file
# Apply will replace all occurrences with toReplace
function cr_stringReplaced()
{
	case $objectMethod in
		objectVars) echo "file toFind toReplace" ;;
		construct)
			file="$1"
			toFind="$2"
			toReplace="$3"
			;;

		check)
			! grep -q "$toFind" "$file"
			;;

		apply)
			sed -i -e 's/'"${toFind//\//\\\/}"'/'"${toReplace//\//\\\/}"'/g' "$file"
			;;

		*) cr_baseClass "$@" ;;
	esac
}







# cr_initScriptExists initScriptName templateName
# declares that the specified initScriptName should exist
# apply create the init script by expanding the template.
function cr_initScriptExists()
{
	case $objectMethod in
		objectVars) echo "initScriptName templateName" ;;
		construct)
			initScriptName="$1"
			templateName="$2"
			;;

		check)
			[ -f "/etc/init.d/$initScriptName" ]
			;;

		apply)
			expandTemplate "$templateName" "/etc/init.d/$initScriptName"
			chmod a+x "/etc/init.d/$initScriptName"
			update-rc.d $initScriptName defaults
			;;

		*) cr_baseClass "$@" ;;
	esac
}


# cr_mysqlDBExists mysqlConnection dbName dbDumpfile
# declares that the specified mysql DB should exist
# apply creates the DB from the specified dump file
function cr_mysqlDBExists()
{
	case $objectMethod in
		objectVars) echo "mysqlConnection dbName dbDumpfile" ;;
		construct)
			mysqlConnection="$1"
			dbName="$2"
			dbDumpfile="$3"
			;;

		check)
			mysql $mysqlConnection mysql -e "show  databases" | grep -q "\b$dbName\b"
			;;

		apply)
			mysql $mysqlConnection  mysql -e "create database \`$dbName\`;"  || return
			mysql $mysqlConnection mysql -e "grant all privileges on \`$dbName\`.*   to '$dbUser'@'%' identified by '$dbPassword';" || return
			mysql $mysqlConnection $dbName  < "$dbDumpfile"
			;;

		*) cr_baseClass "$@" ;;
	esac
}


# cr_mysqlDBExists mysqlConnection dbName tableName sqlFilename
# declares that the specified mysql table should exist
# apply creates the table from the specified sqlFilename file
function cr_mysqlTableExists()
{
	case $objectMethod in
		objectVars) echo "mysqlConnection dbName tableName sqlFilename" ;;
		construct)
			mysqlConnection="$1"
			dbName="$2"
			tableName="$3"
			sqlFilename="$4"
			;;

		check)
			mysql $mysqlConnection $dbName -e "show tables" | grep -q "\b$tableName\b"
			;;

		apply)
			mysql $mysqlConnection $dbName < "$sqlFilename"  || assertError "failed to create table in '$dbName' from '$sqlFilename'"
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# cr_mysqlDBIndexExists mysqlConnection dbName tableName sqlFilename
# declares that the specified mysql index should exist
# apply creates a simple, single column index where the name is assumed to be the column name
function cr_mysqlDBIndexExists()
{
	case $objectMethod in
		objectVars) echo "mysqlConnection dbName tableName indexName" ;;
		construct)
			mysqlConnection="$1"
			dbName="$2"
			tableName="$3"
			indexName="$4"
			;;

		check)
			mysql $mysqlConnection $dbName -e "show create table SystemEvents" | grep -q "KEY \`$indexName\`"
			;;

		apply)
			mysql $mysqlConnection $dbName "alter table $tableName add INDEX $indexName($indexName)"
			;;

		*) cr_baseClass "$@" ;;
	esac
}


# usage: cr_packageTypeSetTo <pckCmdPrefix> <type>
# declares that a package should be set to a particular config type
# The package must provide "pckCmdPrefix-setType" and "pckCmdPrefix-status" commands that follow
# the standard pattern. If now, the check method will fail instead of reporting pass/no pass.
function cr_packageTypeSetTo()
{
	case $objectMethod in
		# define the variables used and set there values in the constructor
		objectVars) echo "pckCmdPrefix type cmdSetType cmdStatus" ;;
		construct)
			pckCmdPrefix="$1"
			type="$2"
			cmdSetType="${pckCmdPrefix}-setType"
			cmdStatus="${pckCmdPrefix}-status"
			displayName="cmdSetType should be $type"
			;;

		check)
			if ! which $cmdStatus &>/dev/null; then
				failedMsg="error: '$cmdStatus' command not found"
				echo "error: $failedMsg"
			fi
			[ "$($cmdStatus -t)" == "$type" ]
			;;

		apply)
			if ! which $cmdSetType &>/dev/null; then
				failedMsg="error: '$cmdSetType' command not found"
				echo "error: $failedMsg"
			fi
			$cmdSetType "$type"
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_snmpBaseConfig <requiredTextInSNMPConfig>
# installs the Avature Standard SNMP config file.
# this is its own cr because we need to do some stuff before installing it
function cr_snmpBaseConfig()
{
	case $objectMethod in
		objectVars) echo "requiredTextInSNMPConfig" ;;
		construct)
			requiredTextInSNMPConfig="$1"
			;;

		check)
			[ -f /etc/snmp/snmpd.conf ] && grep -q "$requiredTextInSNMPConfig" /etc/snmp/snmpd.conf 2>/dev/null
			;;
		apply)
			if [ -f /etc/snmp/snmpd.conf ]; then
				cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.bak.authCntr.$(date +"%y-%m-%d-%H%M")
			fi

			export localIPAddress="$(getLocalIP)"
			export location="$(domWhereami 2>/dev/null || echo "undetermined location")"
			expandTemplate $dataFolder/templates/snmpd.conf /etc/snmp/snmpd.conf
			chmod 600 /etc/snmp/snmpd.conf
			creqsDelayedServiceAction snmpd
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_creqActive <creqType> <creqName> [<creqNameRegEx>]
# declare that a creqConfig should be active.
# This is a form of structured programming. In creq terms, using cr_creqActive is like a function call.
# One creqConfig can resuse another by declaring that it should be active. Note that it will not run the nested
# creq statements as a part of its run. This only declares that the other creqConfig should be active and never
# run it in either the check or apply function. If it needs to activate it, it uses the -x option so that it does
# not run. The newly activated creq will be ran like any other creqConfig from then on.
# Params:
#    <creqType> : the creqType to be checked / activated
#    <creqName> : the specific creqConfig that will be activated if needed for the <creqType>.
#    <creqNameRegEx> : a regex that will match any acceptable creqConfig activated for the <creqType>.
#                      The default is exact match of <creqName>
function cr_creqActive()
{
	case $objectMethod in
		objectVars) echo "creqType creqName creqNameRegEx offCreqName" ;;
		construct)
			creqType="$1"; assertNotEmpty creqType
			creqName="$2"; assertNotEmpty creqName
			creqNameRegEx="${3:-"^${creqName}$"}"
			;;

		check)
			local activeCreq="$(awkDataCache_getValue me:installedPlugins-creqType.activatedProfile name:"${creqType}" )"
			[[ "$activeCreq" =~ "$creqName" ]]
			;;
		apply)
			creqType_activate "$creqType" "$creqName"
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_creqNotActive <creqType> <creqName>
# declare that a creqConfig should NOT be active.
function cr_creqNotActive()
{
	case $objectMethod in
		objectVars) echo "creqType creqName" ;;
		construct)
			creqType="$1"
			creqName="$2"
			;;

		check)
			local activeCreq="$(awkDataCache_getValue me:installedPlugins-creqType.activatedProfile name:"${creqType}" )"
			[ "$activeCreq" != "$creqName" ]
			;;
		apply)
			creqType_deactivate "$creqType"
			;;

		*) cr_baseClass "$@" ;;
	esac
}


# usage: cr_serverPortNotActive <port>
# declare that the server is not listening on this port
# apply does not do anything. this is a check onle
function cr_serverPortNotActive()
{
	case $objectMethod in
		objectVars) echo "port" ;;
		construct)
			port="$1"
			;;

		check)
			[ ! "$(ss -f inet -ltn | awk '$4~":'"$port"'"{print $4}')" ]
			;;
		apply) : ;;

		*) cr_baseClass "$@" ;;
	esac
}


# usage: cr_noUnauthorizedLocalUserAccounts <authorizedUserlist ...>
# declare that the server does not have any local user accounts that can login in besides the
# ones listed
function cr_noUnauthorizedLocalUserAccounts()
{
	case $objectMethod in
		objectVars) echo "uathorizedUsers" ;;
		construct)
			uathorizedUsers="$*"
			;;

		check)
			local locUsers="$(awk -F":" '$7=="/bin/bash"{print $1}'  /etc/passwd)"
			local unauthUsers="$(strSetSubtract "$locUsers" "$uathorizedUsers")"
			[ ! "$unauthUsers" ]
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_superServersNotIntstalled
# declare that the server does not have the old, insecure super servers daemon installed
function cr_superServersNotIntstalled()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct) : ;;

		check)
			[ ! -d "/etc/xinet" ] && [ ! -d "/etc/inet" ]
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_telnetDeamonNotInstalled
# declare that the server does not have the old, insecure telnet daemon installed
function cr_telnetDeamonNotInstalled()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct) : ;;

		check)
			[ ! -d "/etc/xinet" ] && [ ! -d "/etc/inet" ]
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}



# usage: cr_ipForwardingIsDisabled
# declare that the server does not ip forwarding enabled
function cr_ipForwardingIsDisabled()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct) : ;;

		check)
			[ "$(cat /proc/sys/net/ipv4/ip_forward)" == "0" ]
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}



# usage: cr_fileContains <file> <regEx>
# declare that file contains a matching string
# can not be applied
function cr_fileContains()
{
	case $objectMethod in
		objectVars) echo "file regEx" ;;
		construct)
			file="$1"
			regEx="$2"
			;;

		check)
			[ -f "$file" ] && grep -q "$regEx" "$file"
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}


# usage: cr_noRootSSHAccess
# declare that the server does not allow root to login with ssh
function cr_noRootSSHAccess()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct) : ;;

		check)
			[ "$(awk '/^PermitRootLogin[ \t]/{print $2}' /etc/ssh/sshd_config)" == "no" ]
			;;
		apply)
			sudo sed -i -e 's/^\(PermitRootLogin[ \t][ \t]*\).*$/\1 no/' /etc/ssh/sshd_config
			creqsDelayedServiceAction -s ssh
			;;

		*) cr_baseClass "$@" ;;
	esac
}


# usage: cr_sshBannerInstalled
# declare that the server does not have the old, insecure super servers daemon installed
function cr_sshBannerInstalled()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct) : ;;

		check)
			[ ! -d "/etc/xinet" ] && [ ! -d "/etc/inet" ]
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_sedEnabled
# declare that the server has at least one sed enabled hard drive
function cr_sedEnabled()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct) : ;;

		check)
			: # move to storage package
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_XXXXXX
# declare that the server does not have the old, insecure super servers daemon installed
function cr_XXXXXX()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct) : ;;

		check)
			[ ! -d "/etc/xinet" ] && [ ! -d "/etc/inet" ]
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_XXXXXX
# declare that the server does not have the old, insecure super servers daemon installed
function cr_XXXXXX()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct) : ;;

		check)
			[ ! -d "/etc/xinet" ] && [ ! -d "/etc/inet" ]
			;;
		apply) false ;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_usersInitScriptDoNotContain <lineRegex> [<commentID>]
# This declares that none of the user bash init files on this host have lines matching the lineRegex
# Apply will append a comment (#) character in front of each matching line. If commentID is provided
# each added comment character will be followed by that string and another comment character so that
# users can identify what commented out the line.
# The user init files are /etc/skel/.bashrc /home/*/.bashrc
# Params:
#     <lineRegex>  : a regex that matches offending lines that should not be in the files
#     <commentID>  : an identifier that is placed in the comment whne an offending line is commented out
function cr_usersInitScriptDoNotContain()
{
	case $objectMethod in
		objectVars) echo "lineRegex commentID" ;;
		construct)
			lineRegex="$1"
			commentID="$2"
			displayName="usersInitScriptDoNotContain $lineRegex"
			;;

		check)
			local initFile
			for initFile in /etc/skel/.bashrc /home/*/.bashrc; do
		 		if [ -r "$initFile" ] && grep -q "$lineRegex" "$initFile"; then
					return 1
		 		fi
		 	done
			return 0
			;;

		apply)
			local comment="# commented out by ${commentID}\n#${commentID}#"
			local initFile
			for initFile in /etc/skel/.bashrc /home/*/.bashrc; do
				if [ -r "$initFile" ] && grep -q "$lineRegex" "$initFile"; then
					echo "      '$initFile' commenting these lines..."
					grep  "$lineRegex" "$initFile" | sed -e 's/.*/         &/'
					sed -i -e 's/^\('"${lineRegex//\//\\\/}"'[^;#]*\)\(.*\)/'"${comment//\//\\\/}"'&/' "$initFile"
				fi
			done
			return 0
			;;

		 *) cr_baseClass "$@" ;;
	esac
}

# usage: cr_usersInitScriptDoNotContainUndo <commentID>
# This will undo any lines commented out by a previous call to cr_usersInitScriptDoNotContain that uses
# the same <commentID>
# Params:
#     <commentID>  : an identifier that is placed in the comment whne an offending line is commented out
function cr_usersInitScriptDoNotContainUndo()
{
	case $objectMethod in
		objectVars) echo "commentID" ;;
		construct)
			commentID="$1"
			displayName="usersInitScriptDoNotContainUndo $commentID"
			;;

		check)
			local initFile
			for initFile in /etc/skel/.bashrc /home/*/.bashrc; do
		 		if [ -r "$initFile" ] && grep -q "^[[:space:]]*#${commentID}#" "$initFile"; then
					return 1
		 		fi
		 	done
			return 0
			;;

		apply)
			local initFile
			for initFile in /etc/skel/.bashrc /home/*/.bashrc; do
				if [ -r "$initFile" ] && grep -q "^[[:space:]]*#${commentID}#" "$initFile"; then
					echo "      '$initFile' removing comment prefix (uncommenting) from these lines..."
					grep  "^[[:space:]]*#${commentID}#" "$initFile" | sed -e 's/.*/         &/'
					sed -i -e 's/^[[:space:]]*#'"${commentID//\//\\\/}"'#//; /^# commented out by '"${commentID//\//\\\/}"'/d' "$initFile"
				fi
			done
			return 0
			;;

		 *) cr_baseClass "$@" ;;
	esac
}



# usage: cr_rsyslogConfigIsValid
# declare that the rsyslog config should not contain any errors
# apply can not fix it. putting this in a creqConfig just alerts the operator if the config produced
# an invalid rsyslog config. rsyslog (at least on ubuntu) does not provide good feedback in the daemon
# status command. You need to run rsyslogd -N1 to find out if the daemon is not running correctly
# because the config file contains an error
function cr_rsyslogConfigIsValid()
{
	case $objectMethod in
		objectVars) echo "" ;;
		construct)
			;;

		check)
			if ! rsyslogd -N1 &>/dev/null; then
				noPassMsg="run 'rsyslogd -N1' to see config errors"
				failedMsg="rsyslogd config errors must be fixed in the previous statements that create it"
				return 1
			fi
			;;

		apply)
			failedMsg="run 'rsyslogd -N1' to see config errors"
			return 1
			;;

		 *) cr_baseClass "$@" ;;
	esac
}

# usage: cr_hostTimezoneSetTo <timezone>
# declare that the default server timezone is set to <timezone>
function cr_hostTimezoneSetTo()
{
	case $objectMethod in
		objectVars) echo "timezone curTimezone" ;;
		construct)
			timezone="$1"
			curTimezone="$(cat /etc/timezone)"
			;;

		check)
			[ "$timezone" == "$curTimezone" ]
			;;

		apply)
			echo "$timezone" > /etc/timezone
			dpkg-reconfigure --frontend noninteractive tzdata
			;;

		 *) cr_baseClass "$@" ;;
	esac
}
