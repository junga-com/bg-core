#!/bin/bash

mysqlDefaultPkg="mariadb-server"

# usage: mysqlInstallPkg [-p <pkgName>]
# Installs mysql and configures it for secure access
# Options:
#   -p <pkgName> : the particular package to install. There are many packages available that provide largely compatible
#        versions of a mysql compatible db server. The current default is mariadb-server-5.5 That can be overridden by
#        the sysadmin by setting and exporting the environment variable AT_MYSQL_DEFAULT_PKG
# BGENV: AT_MYSQL_DEFAULT_PKG : define the default package to use when installing the db server if the script does not specify one
function mysqlInstallPkg()
{
	local pkgName="${AT_MYSQL_DEFAULT_PKG:-$mysqlDefaultPkg}"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-p) pkgName="$(bgetopt "$@")" && shift ;;
	esac; shift; done


	# this will create a random secret if it has not yet been retrieved and then make it persistent
	local rootpw="$(getSecret mysql password)"

	# the (which mysqld) test makes it so that if either mariadb or mydql servers are installed we won't try to
	# change it
	! which mysqld &>/dev/null && pkgInstallIfNeeded  -y -r "$pkgName" <(cat <<-EOS
		mysql-server/root_password $rootpw
		mysql-server/root_password_again $rootpw
		EOS
	)

	mysqlEnableSSOForRoot
}


# usage: mysqlFindRootLogin
# tries the common ways we authenticate as root and returns a connection string for the first successful one found.
# returns empty string if no successful login was found
function mysqlFindRootLogin()
{
	### find the way to connect as root. If we just installed the server, the first one will work. If root SSO is configured
	# the second one will work. After that, just try a few root password guesses.
	local rootpw="$(getSecret mysql password)"
	local preCmd=""; [ "$(id -u)" != "0" ] && preCmd="sudo "
	local -a testConnStrs
	testConnStrs+=("mysql -uroot -p$rootpw ")
	testConnStrs+=("$preCmd mysql ")
	testConnStrs+=("mysql -uroot ")
	testConnStrs+=("mysql -uroot -ps1tar0 ")
	local myRootConn; for myRootConn in "${testConnStrs[@]}"; do
		mysqlTestConnection -q "$myRootConn" && break
		myRootConn=""
	done

	# if we did not find it and we have a terminal, ask the user to provide the root password
	if [ ! "$myRootConn" ] && [ -t 1 ]; then
		askForPassword  "root mysql password: " rootpw
		mysqlTestConnection -q mysql -uroot -p$rootpw && myRootConn="mysql -uroot -p$rootpw "
	fi

	assertNotEmpty myRootConn "could not find a way to connect to the local mysql server as root."
	echo "$myRootConn"
}



# usage: mysqlEnableSSOForRoot
# enables the unix socket plugin and changes root@localhost to use it
# after this, other users can be  created that use SSO from localhost too
function mysqlEnableSSOForRoot()
{
	# find the way to connect as root. $(getSecret mysql password) will be tried first so if we just installed the server, that first one will work.
	local myRootConn
	myRootConn="$(mysqlFindRootLogin)" || exit

	if [ ! "$($myRootConn mysql -e 'select user from user where user="root" and host="localhost" and plugin="unix_socket"')" ]; then
		echo "configuring mysql server root user to have integrated SSO with the linux host"

		local unixSocketStatus="$($myRootConn mysql -ss -e "select PLUGIN_STATUS from information_schema.PLUGINS where PLUGIN_NAME='unix_socket'")"
 		$myRootConn mysql -e "INSTALL PLUGIN unix_socket SONAME 'auth_socket';" &>/dev/null
		local unixSocketStatus2="$($myRootConn mysql -ss -e "select PLUGIN_STATUS from information_schema.PLUGINS where PLUGIN_NAME='unix_socket'")"
		[ "$unixSocketStatus2" == "ACTIVE" ] || assertError "could not activate mysql/mariaDB plugin 'unix_socket'"

 		$myRootConn mysql -e "grant ALL on *.* to root@localhost identified via unix_socket" >/dev/null || assertError "mysql returned error when changing root@localhost to use unix_socket authentication plugin"
		mysqlTestConnection -q  "$preCmd mysql " || assertError "after changing root@localhost to use unix_socket authentication plugin, could not login from root user without a password"
		rootpw="via unix_socket"
		getSecret -s mysql password "$rootpw"
	fi
}


# usage: mysqlTestConnection [-q] <connectionString>
# returns true and echos 'ok' if the connectionString can connect to a mysql server
# Params:
#    <connectionString> : the mysql command line up to but not including the -e. e.g. "mysql ", "sudo mysql ", and "mysql -uroot -p123"
#                          the connectionString should include options that identify the server to connect to and the login credentials
function mysqlTestConnection()
{
	local quietFlag text result
	while [[ "$1" =~ ^- ]]; do case $1 in
		-q) quietFlag="-q" ;;
	esac; shift; done

	local connectionString="$*"
	[ "$connectionString" ] || return 1

	text="$($connectionString -e "show databases" 2>&1)"
	result=$?

	# if the cmd returns success(0), we still don't know if it ran mysql so also check the output
	if [ ${result:-0} -eq 0 ] && ! echo "$text" | grep -q "^Database$"; then
		[ ! "$quietFlag" ] && echo "error: mysql connection string executed w/o error but did not return expected text"
		return 255
	elif [ ${result:-0} -eq 0 ]; then
		[ ! "$quietFlag" ] && echo "ok"
		return 0
	else
		[ ! "$quietFlag" ] && echo "$text"
		return $result
	fi
}

# usage: assertMysqlConnectionWorks <connectionString>
# asserts that the connectionString can connect to a mysql server
function assertMysqlConnectionWorks()
{
	local text
	text="$(mysqlTestConnection -q "$@")" || assertError "mysql connect string ($@) could not connect to server. Error is ($?) '$text'"
}


# usage: mysqlCreateDatabase [-c <mysqlConnectStr>] <dbName>
# create a new database on the local mysql server and configure a user '<dbName>Admin' that has full grants to work on that database
# '<dbName>Admin' is a local user on the host OS and a user in mysql
# This function is idempotent meaning that you can call it multiple times without ill effect. It will fix any missing parts of the '<dbName>Admin' config
# Options:
#   -c <mysqlConnectStr> : connection string. default is "sudo mysql ". Set this to a string that includes the db client
#                 command to connect to the db including the authentication parameters. e.g. "mysql -uroot -p " would connect
#                 as root user, prompting for a password.
function mysqlCreateDatabase()
{
	local mysqlConnectStr="mysql "; [ "$(id -u)" != "0" ] && mysqlConnectStr="sudo $mysqlConnectStr"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-c*) mysqlConnectStr="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	local dbName="$1"
	assertNotEmpty dbName
	local dbAdminUser="${dbName}DBAdmin"
	local groupName="${dbName}DBAdmin"
	creqLog2 "dbAdminUser='$dbAdminUser'"
	creqLog2 "groupName='$groupName'"

	# make sure that the db exists in the local server and that the 'dbAdminUser' exists with the proper grants
	$mysqlConnectStr mysql -e "create database if not exists \`$dbName\`;" || assertError "could not create mysql database '$dbName'"

	if [ ! "$($mysqlConnectStr mysql -e 'select user from user where user="'"$dbAdminUser"'" and host="localhost" and plugin="unix_socket"')" ]; then
		$mysqlConnectStr mysql -e "create user '$dbAdminUser'@'localhost' identified with unix_socket;" || assertError "could not create user $dbAdminUser'@'localhost identified with unix_socket "
	fi
	$mysqlConnectStr mysql -e "grant ALL on \`$dbName\`.* to '$dbAdminUser'@'localhost' identified via unix_socket;"
	$mysqlConnectStr mysql -e "grant grant option on \`$dbName\`.* to '$dbAdminUser'@'localhost' identified via unix_socket;"

	# there should be a local user on the host that matches the db server user that uses 'via unix_socket' auth
	# if we create that user, it will be a system user that can not login directly but we give members of a group with the
	# same name the ability sudo -u<dbAdminUser> .. w/o a password so members of that group can access the db server as
	# that user
	mysqlCreateSSOUser "$dbAdminUser" "$groupName"
}


# usage: mysqlCreateSSOUser [-c <mysqlConnectStr>] <username> [<permissionName>]
# This implements a user that can access the local MariaDB/mysql server using SSO with the host linux OS.
# It is idempotent (can be called multiple times and if something is already done, it won't change it)
# It configures three systems:
#     1) db server: adds the user to the db server's user table if needed
#     2) local users: adds a local linux system user if needed
#     3) sudoers: adds a parameterized permission for members of a group by the same name as the user to sudo mysql as the user.
#                 a parameterized permission is actually a set of permissions named <permissionName>[-<tag>] for each tag
#                 value in /etc/tags
# Params:
#    <username>       : name of the new user to create
#    <permissionName> : name of the linux permission (group name) used for access control. default is the username
# Options:
#   -c <mysqlConnectStr> : connection string. default is "sudo mysql ". Set this to a string that includes the db client
#                 command to connect to the db including the authentication parameters. e.g. "mysql -uroot -p " would connect
#                 as root user, prompting for a password.
function mysqlCreateSSOUser()
{
	local mysqlConnectStr="mysql "; [ "$(id -u)" != "0" ] && mysqlConnectStr="sudo $mysqlConnectStr"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-c*) mysqlConnectStr="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	local username="$1"
	local permissionName="${2:-$username}"
	assertNotEmpty username

	### make sure that the DB user exists and uses the unix_socket plugin
	$mysqlConnectStr mysql -e "create user '$username'@'localhost' identified with unix_socket;" 2>/dev/null
	local usercheck plugin
	read -r usercheck plugin < <($mysqlConnectStr mysql -ss -e 'select user,plugin from user where user="'"$username"'" and host="localhost"')
	[ "$usercheck" == "$username" ] || assertError "failed to create user '$username'@'localhost' identified with unix_socket;"

	if [ "$plugin" != "unix_socket" ]; then
		$mysqlConnectStr mysql -e 'update user set plugin="unix_socket" where user="'"$username"'" and host="localhost"' || assertError "could not change to use unix_socket plugin"
	fi

	# make sure the 'username' exists as a local user with no login possibility
	id "$username" &>/dev/null || sudo useradd -g "nogroup" -d/home/nobody -M -s /bin/false "$username"

	# make sure that a sudoers config exists to allow members of the "permissionName" group to "sudo -u $username mysql ..."
	if [ ! -f "/etc/sudoers.d/${permissionName}Permission" ]; then
		local tmpFile="$(mktemp)"
		local sudoerFile="/etc/sudoers.d/${permissionName}Permission"
		cat >$tmpFile <<-EOS
			### Define the ${permissionName} Group Permission.

			Cmnd_Alias MYSQL_${permissionName^^}_CMDS = \
			/usr/bin/mysql, \
			/usr/bin/mysqldump

			User_Alias ${permissionName^^}_TAGGED_PERMISSION = %${permissionName},dbAdmin

			${permissionName^^}_TAGGED_PERMISSION ALL=($username) NOPASSWD: MYSQL_${permissionName^^}_CMDS

			EOS
		sudo cp "$tmpFile" "$sudoerFile"
		sudo chmod 440 "$sudoerFile"
	fi
}

# usage: mysqlGrant [-c <mysqlConnectStr>] <username> <dbName> <permissionList>
# give an existing user access
# Options:
#   -c <mysqlConnectStr> : connection string. default is "sudo mysql ". Set this to a string that includes the db client
#                 command to connect to the db including the authentication parameters. e.g. "mysql -uroot -p " would connect
#                 as root user, prompting for a password.
function mysqlGrant()
{
	local mysqlConnectStr="mysql "; [ "$(id -u)" != "0" ] && mysqlConnectStr="sudo $mysqlConnectStr"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-c*) mysqlConnectStr="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	local username="$1"; [ $# -gt 0 ] && shift
	local dbName="$1"  ; [ $# -gt 0 ] && shift
	assertNotEmpty dbName

	while [ $# -gt 0 ]; do
		local g=${mysqlPrivToGrant[$1]}
		creqLog3 "$mysqlConnectStr mysql -e \"grant $g on ${dbName}.* to '$username'@'localhost';\""
		$mysqlConnectStr mysql -e "grant $g on ${dbName}.* to '$username'@'localhost';"
		shift
	done
}

# usage: cr_packageInstalled_mysql [-p <pkgName>] 
function cr_packageInstalled_mysql()
{
	case $objectMethod in
		objectVars) echo "mysqlConnectStr pkgName quietFlag" ;;
		construct)
			mysqlConnectStr="mysql "; [ "$(id -u)" != "0" ] && mysqlConnectStr="sudo $mysqlConnectStr "
			while [[ "$1" =~ ^- ]]; do case $1 in
				-p) pkgName="$(bgetopt "$@")" && shift ;;
			esac; shift; done
			quietFlag="-q"
			[ ${creqVerbosity:-0} -ge 2 ] && quietFlag=""
			pkgName="${pkgName:-$mysqlDefaultPkg}"
			;;

		check)
			pkgIsInstalled $quietFlag "$pkgName"   || { creqMsg="pkg '$pkgName' is not installed"; return 1; }
			mysqlTestConnection "$mysqlConnectStr" || { creqMsg="could not connect to server using '$mysqlConnectStr -e \"show database\"'"; return 2; }
			[ "$($mysqlConnectStr mysql -e 'select user from user where user="root" and host="localhost" and plugin="unix_socket"')" ] \
													|| { creqMsg="root@localhost is not using the unix_socket plugin"; return 3; }
			;;

		apply)
			mysqlInstallPkg -p "$pkgName"
			;;


		*) cr_baseClass "$@" ;;
	esac
}


# usage: cr_mysqlDatabaseExists <dbName>
function cr_mysqlDatabaseExists()
{
	case $objectMethod in
		objectVars) echo "dbName dbAdminUser runMysqlRoot" ;;
		construct)
			dbName="$1"
			dbAdminUser="${dbName}DBAdmin"
			runMysqlRoot="mysql mysql "
			;;

		check)
			creqLog3 "dbName=$dbName"
			creqLog3 "dbAdminUser=$dbAdminUser"
			$runMysqlRoot -e "show databases" 2>/dev/null | grep -q "^$dbName$" || return
			local dbAdminUserStr="$($runMysqlRoot -ss -e  "select * from db where host='localhost' and user='$dbAdminUser' and Db='$dbName'"|tr "\t" ",")"
			creqLog3 "dbAdminUserStr=$dbAdminUserStr"
			if [ ! "$dbAdminUserStr" ]; then
				echo "the database exists but is missing an admin user ($dbAdminUser) specific to it"
				return 1
			elif [[ ! "$dbAdminUserStr" =~  ^localhost,$dbName,$dbAdminUser(,Y)*$ ]]; then
				echo "the admin user ($dbAdminUser) specific to '$dbName' is lacking some permissions"
				return 2
			fi
			true
			;;

		apply)
			mysqlCreateDatabase "$dbName"
			;;


		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_mysqlTableExists <dbName> <tblName> <sqlCreateScript>
function cr_mysqlTableExists()
{
	case $objectMethod in
		objectVars) echo "dbName tblName sqlCreateScript runMysqlRoot" ;;
		construct)
			dbName="$1"
			tblName="$2"
			sqlCreateScript="$3"
			runMysqlRoot="mysql "
			;;

		check)
			$runMysqlRoot "$dbName" -ss -e "show tables" 2>/dev/null | grep -q "^$tblName$"
			;;

		apply)
			$runMysqlRoot "$dbName" < "$sqlCreateScript"
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_mysqlColumnExists -r <oldName> <dbName> <tblName> <colName> <colDef>
# declare that the column exists in the database table.
# apply will try to make it exist. If -r (rename) is specified it will try to rename a column <oldName> to <columnName>
# if not, it will try to create a column using <colDef>
# its possible that existing instalations might have more than one old name for the column if the column is renamed and
# some hosts will skip the intermediate version. This could be handled by upgrading hosts to the intermediate version
# and then the current verision or this creq could be modified to accept a list of old names. It would use the first column
# in the list that exists in the schema being operated on. It does not do that now, but it would be easy to add.
# Prarm:
#   dbName  : database name that contains the table
#   tblName : table name to operate on
#   colName : column name
#   colDef  : the column definition. This should be the normailized version meaning that after it is applied, it should
#             be the same text that the "show create table <tblName>" reports for the column. Otherwise the check will never pass
#             even though its logically the same. For example, if you leave out the size like "smallint NOT NULL', it will
#             be set with the default but it will report back as "smallint(6) NOT NULL"
# Options:
#    -r <oldName> : if <colName> does not exist but <oldName> does, <oldName> will be renamed to <colName>. <oldName> can be a space
#             separated list of previous names where the ost recent appears first. The first oldName found will be renamed (but only
#             if colName does not exist)
function cr_mysqlColumnExists()
{
	case $objectMethod in
		objectVars) echo "renameFrom dbName tblName colName colDef runMysqlRoot curColName curColDef" ;;
		construct)
			while [[ "$1" =~ ^- ]]; do case $1 in
				-r*) renameFrom="$(bgetopt "$@")" && shift ;;
			esac; shift; done

			dbName="$1"
			tblName="$2"
			colName="$3"
			colDef="$4"
			runMysqlRoot="mysql "
			;;

		check)
			for curColName in $colName $renameFrom; do
				# this is a case sensitive match which mysql is not so that we can rename case
				curColDef="$($runMysqlRoot "$dbName" -ss -e "show create table $tblName" 2>/dev/null | sed -e 's/\\n/\n/g' | grep "^[[:space:]]*\`$curColName\`")"
				curColDef="${curColDef#*\` }"
				curColDef="${curColDef%,*}"
				curColDef="${curColDef/bigint(20) unsigned NOT NULL AUTO_INCREMENT/SERIAL}"
				[ "$curColDef" ] && break || curColName=""
			done
			creqLog1 "actual: '$curColName $curColDef'"
			creqLog1 "wanted: '$colName $colDef'"
			[ "$curColName" == "$colName" ] && [ "$curColDef" == "$colDef" ]
			;;

		apply)
			if [ ! "$curColDef" ]; then
				creqLog0 "$runMysqlRoot $dbName  -e \"alter table $tblName add column $colName $colDef\""
				$runMysqlRoot          "$dbName" -e  "alter table $tblName add column $colName $colDef"
			else
				creqLog0 "$runMysqlRoot $dbName  -e \"alter table $tblName change column ${curColName:-$colName} $colName $colDef\""
				$runMysqlRoot          "$dbName" -e  "alter table $tblName change column ${curColName:-$colName} $colName $colDef"
			fi
			;;

		*) cr_baseClass "$@" ;;
	esac
}


# usage: cr_mysqlColumnNotExists <dbName> <tblName> <colName>
# declare that the column does not exist in the database table.
# apply will drop the column
function cr_mysqlColumnNotExists()
{
	case $objectMethod in
		objectVars) echo "dbName tblName colName runMysqlRoot curColDef" ;;
		construct)
			dbName="$1"
			tblName="$2"
			colName="$3"
			runMysqlRoot="mysql "
			;;

		check)
			curColDef="$($runMysqlRoot "$dbName" -ss -e "show create table $tblName" 2>/dev/null | sed -e 's/\\n/\n/g' | grep "^[[:space:]]*\`$colName\`")"
			creqLog1 "exits?: '${curColDef:+yes}'"
			[ ! "$curColDef" ]
			;;

		apply)
			creqLog0 "$runMysqlRoot $dbName -e \"alter table $tblName drop column $colName\""
			$runMysqlRoot "$dbName" -e "alter table $tblName drop column $colName"
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: cr_mysqlVariableSetTo <varName> <value>
# declare that the mysql db server has a particular value
# apply set the value
# Note: that these DB server values are global so make sure that your configuration controls the entire server
#       before using this.
function cr_mysqlVariableSetTo()
{
	case $objectMethod in
		objectVars) echo "scope useQuotes varName value runMysqlRoot curValue persistentVal" ;;
		construct)
			while [[ "$1" =~ ^- ]]; do case $1 in
				-q) useQuotes='"' ;;
			esac; shift; done

			varName="$1"
			value="$2"
			runMysqlRoot="mysql "
			scope="GLOBAL"
			;;

		check)
			curValue="$($runMysqlRoot -ss -e "show $scope variables like '$varName'" | awk '{print $2}')"
			persistentVal="$(getIniParam /etc/mysql/conf.d/bg-mysqlPersistentVars.cnf mysqld "$varName")"

			[ "$curValue" == "$value" ] && [ "$persistentVal" == "$value" ]
			;;

		apply)
			local Q=""; [[ ! "$value" =~ ^[0-9][0-9]*$ ]] || [ "$useQuotes" ] && Q='"'
			$runMysqlRoot -ss -e  "set $scope $varName=$Q$value$Q"
			setIniParam -x /etc/mysql/conf.d/bg-mysqlPersistentVars.cnf mysqld "$varName" "$value"
			;;

		*) cr_baseClass "$@" ;;
	esac
}



# usage: cr_mysqlTableIndexExists <dbName> <tblName> <idxName> [<idxColumns>]
# currently, this only handles simple single column, plain indexes where the index name is the column name.
# Prarm:
#   dbName  : database name that contains the table
#   tblName : table name to operate on
#   idxName : the index name that should exist
#   idxColumns : the columns that the index should use. comma separated. default is to assume the idxName is the single col name.
function cr_mysqlTableIndexExists()
{
	case $objectMethod in
		objectVars) echo "keyType dbName tblName idxName idxColumns runMysqlRoot curIdxDef" ;;
		construct)
			keyType="KEY"
			while [[ "$1" =~ ^- ]]; do case $1 in
				-t) keyType="$(bgetopt "$@")" && shift ;;
			esac; shift; done

			dbName="$1"
			tblName="$2"
			idxName="$3"
			idxColumns="${4:-$idxName}"
			runMysqlRoot="mysql "
			;;

		check)
			curIdxDef="$($runMysqlRoot "$dbName" -ss -e "show create table $tblName" | sed -e 's/\\n/\n/g' | awk '$0~"KEY[^(]*`'"$idxName"'`"')"
			local curKeyType="${curIdxDef%%$idxName*}"
			curKeyType="$(trimString "${curKeyType//\`}")"
			local curIdxCols="${curIdxDef#*(}"
			curIdxCols="${curIdxCols%)*}"
			curIdxCols="${curIdxCols//\`}"
			creqLog1 "actual: '$curKeyType'  '$curIdxCols'"
			creqLog1 "wanted: '$keyType'  '$idxColumns'"
			[ "$curIdxCols" == "$idxColumns" ] && [ "$curKeyType" == "$keyType" ]
			;;

		apply)
			[ "$idxName" ] && [ "$curIdxDef" ] && $runMysqlRoot "$dbName" -e "alter table $tblName drop INDEX $idxName"
			$runMysqlRoot "$dbName" -e "alter table $tblName add $keyType $idxName($idxColumns)"
			;;

		*) cr_baseClass "$@" ;;
	esac
}

# usage: mysqlApplyTimeZoneData
# in order to make the CONVERT_TZ(timeReported,'UTC','${TZ:-UTC}') function work, mysql needs to import
# the timezone information from the linux host.
function mysqlApplyTimeZoneData()
{
	mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql mysql
}

# usage: cr_mysqlTimeZoneDataApplied
# in order to make the CONVERT_TZ(timeReported,'UTC','${TZ:-UTC}') function work, mysql needs to import
# the timezone information from the linux host.
function cr_mysqlTimeZoneDataApplied()
{
	case $objectMethod in
		objectVars) echo "useQuotes varName value" ;;
		construct)
			runMysqlRoot="mysql "
			;;

		check)
			local rowCount="$($runMysqlRoot mysql -ss -e "select count(*) from time_zone")"
			[ ${rowCount:-0} -gt 0 ]
			;;

		apply)
			mysql_tzinfo_to_sql /usr/share/zoneinfo | $runMysqlRoot mysql
			;;

		*) cr_baseClass "$@" ;;
	esac
}



declare -a mysqlPrivList=(
	Create_priv
	Drop_priv
	Grant_priv
	Lock_tables_priv
	References_priv
	Event_priv
	Alter_priv
	Delete_priv
	Index_priv
	Insert_priv
	Select_priv
	Update_priv
	Create_tmp_table_priv
	Trigger_priv
	Create_view_priv
	Show_view_priv
	Alter_routine_priv
	Create_routine_priv
	Execute_priv
	File_priv
	Create_user_priv
	Process_priv
	Reload_priv
	Repl_client_priv
	Repl_slave_priv
	Show_db_priv
	Shutdown_priv
	Super_priv
	all
	ALL
)

declare -A mysqlPrivToGrant=(
	[Create_priv]="CREATE"
	[Drop_priv]="DROP"
	[Grant_priv]="GRANT OPTION"
	[Lock_tables_priv]="LOCK TABLES"
	[References_priv]="REFERENCES"
	[Event_priv]="EVENT"
	[Alter_priv]="ALTER"
	[Delete_priv]="DELETE"
	[Index_priv]="INDEX"
	[Insert_priv]="INSERT"
	[Select_priv]="SELECT"
	[Update_priv]="UPDATE"
	[Create_tmp_table_priv]="CREATE TEMPORARY TABLES"
	[Trigger_priv]="TRIGGER"
	[Create_view_priv]="CREATE VIEW"
	[Show_view_priv]="SHOW VIEW"
	[Alter_routine_priv]="ALTER ROUTINE"
	[Create_routine_priv]="CREATE ROUTINE"
	[Execute_priv]="EXECUTE"
	[File_priv]="FILE"
	[Create_user_priv]="CREATE USER"
	[Process_priv]="PROCESS"
	[Reload_priv]="RELOAD"
	[Repl_client_priv]="REPLICATION CLIENT"
	[Repl_slave_priv]="REPLICATION SLAVE"
	[Show_db_priv]="SHOW DATABASES"
	[Shutdown_priv]="SHUTDOWN"
	[Super_priv]="SUPER"
	[all]="ALL"
	[ALL]="ALL"
	[All]="ALL"
	[CREATE]="CREATE"
	[DROP]="DROP"
	[GRANT OPTION]="GRANT OPTION"
	[LOCK TABLES]="LOCK TABLES"
	[REFERENCES]="REFERENCES"
	[EVENT]="EVENT"
	[ALTER]="ALTER"
	[DELETE]="DELETE"
	[INDEX]="INDEX"
	[INSERT]="INSERT"
	[SELECT]="SELECT"
	[UPDATE]="UPDATE"
	[CREATE TEMPORARY TABLES]="CREATE TEMPORARY TABLES"
	[TRIGGER]="TRIGGER"
	[CREATE VIEW]="CREATE VIEW"
	[SHOW VIEW]="SHOW VIEW"
	[ALTER ROUTINE]="ALTER ROUTINE"
	[CREATE ROUTINE]="CREATE ROUTINE"
	[EXECUTE]="EXECUTE"
	[FILE]="FILE"
	[CREATE USER]="CREATE USER"
	[PROCESS]="PROCESS"
	[RELOAD]="RELOAD"
	[REPLICATION CLIENT]="REPLICATION CLIENT"
	[REPLICATION SLAVE]="REPLICATION SLAVE"
	[SHOW DATABASES]="SHOW DATABASES"
	[SHUTDOWN]="SHUTDOWN"
	[SUPER]="SUPER"
)

declare -A mysqlGrantToPriv=(
	[CREATE]="Create_priv"
	[DROP]="Drop_priv"
	[GRANT OPTION]="Grant_priv"
	[LOCK TABLES]="Lock_tables_priv"
	[REFERENCES]="References_priv"
	[EVENT]="Event_priv"
	[ALTER]="Alter_priv"
	[DELETE]="Delete_priv"
	[INDEX]="Index_priv"
	[INSERT]="Insert_priv"
	[SELECT]="Select_priv"
	[UPDATE]="Update_priv"
	[CREATE TEMPORARY TABLES]="Create_tmp_table_priv"
	[TRIGGER]="Trigger_priv"
	[CREATE VIEW]="Create_view_priv"
	[SHOW VIEW]="Show_view_priv"
	[ALTER ROUTINE]="Alter_routine_priv"
	[CREATE ROUTINE]="Create_routine_priv"
	[EXECUTE]="Execute_priv"
	[FILE]="File_priv"
	[CREATE USER]="Create_user_priv"
	[PROCESS]="Process_priv"
	[RELOAD]="Reload_priv"
	[REPLICATION CLIENT]="Repl_client_priv"
	[REPLICATION SLAVE]="Repl_slave_priv"
	[SHOW DATABASES]="Show_db_priv"
	[SHUTDOWN]="Shutdown_priv"
	[SUPER]="Super_priv"
	[ALL]="${!mysqlPrivToGrant[@]}"
	[USAGE]=""

	[Create_priv]="Create_priv"
	[Drop_priv]="Drop_priv"
	[Grant_priv]="Grant_priv"
	[Lock_tables_priv]="Lock_tables_priv"
	[References_priv]="References_priv"
	[Event_priv]="Event_priv"
	[Alter_priv]="Alter_priv"
	[Delete_priv]="Delete_priv"
	[Index_priv]="Index_priv"
	[Insert_priv]="Insert_priv"
	[Select_priv]="Select_priv"
	[Update_priv]="Update_priv"
	[Create_tmp_table_priv]="Create_tmp_table_priv"
	[Trigger_priv]="Trigger_priv"
	[Create_view_priv]="Create_view_priv"
	[Show_view_priv]="Show_view_priv"
	[Alter_routine_priv]="Alter_routine_priv"
	[Create_routine_priv]="Create_routine_priv"
	[Execute_priv]="Execute_priv"
	[File_priv]="File_priv"
	[Create_user_priv]="Create_user_priv"
	[Process_priv]="Process_priv"
	[Reload_priv]="Reload_priv"
	[Repl_client_priv]="Repl_client_priv"
	[Repl_slave_priv]="Repl_slave_priv"
	[Show_db_priv]="Show_db_priv"
	[Shutdown_priv]="Shutdown_priv"
	[Super_priv]="Super_priv"
)



# usage: mysqlLoadUserGrants [-c <mysqlConnectStr>] <userObjVar> [<dbName>]
# Query the db for the grants assigned to the user/dName specified and return them as elements in the userObjVar array/map
# The username is passed into the function as the element ${userObjVar[User]} in the array.
# All the columns of the user or db table are returned as userObjVar[<columnName>]=<value>
# Most of the columns are permissions named like "<name>_priv" with a value of either "Y" or "N"
# Params:
#   <userObjVar> : and associative array variable name declared like 'local|declare -A userObj=([User]="myuser")' and passed in as a string
#                  like mysqlLoadUserGrants "userObj".
#   <dbName>     : the name of the db to return the grants for. if db is ""  then the global grants from the user table
#                  are returned
# Options:
#   -c <mysqlConnectStr> : connection string. default is "sudo mysql ". Set this to a string that includes the db client
#                 command to connect to the db including the authentication parameters. e.g. "mysql -uroot -p " would connect
#                 as root user, prompting for a password.
function mysqlLoadUserGrants()
{
	local mysqlConnectStr="mysql "; [ "$(id -u)" != "0" ] && mysqlConnectStr="sudo $mysqlConnectStr"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-c*) mysqlConnectStr="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	local userObjVar="$1"
	local dbName="$2"
	local host="localhost"
	local script="select * from user where host='$host' and user='$username'\G"
	[ "$dbName" ] && script="select * from db where host='$host' and user='$username' and Db='$dbName'\G"
	creqLog3 "script=$script"

	eval local username=\${$userObjVar[User]}
	eval local host=\${$userObjVar[Host]:-localhost}
	while IFS=":" read -r attrName attrValue; do
		[ "$attrName" ] && eval $userObjVar[\$attrName]=\"\$attrValue\"
	done < <($mysqlConnectStr mysql -e "$script" | tr -d " ")
}


# usage: cr_mysqlLocalUserCanAccessDB <username> <dbName> <sudoPermissionName> <permissionList ...>
# declare that ...
#    1) username should exist as a local linux user and db server user
#    2) it can access the local db server using unix_socket SSO
#    3) it is granted access to dbName with permissionList permissions
function cr_mysqlLocalUserCanAccessDB()
{
	case $objectMethod in
		objectVars) echo "username dbName sudoPermissionName permissionList runMysqlRoot" ;;
		construct)
			username="$1"          ; [ $# -gt 0 ] && shift
			dbName="$1"            ; [ $# -gt 0 ] && shift
			sudoPermissionName="$1"; [ $# -gt 0 ] && shift
			permissionList=("$@")
			runMysqlRoot="mysql "
			;;

		check)
			id "$username" &>/dev/null || { noPassMsg="mysqlLocalUserCanAccessDB: linux user does not exist"; return 1; }

			local -A userGlobalGrants=([User]="$username")
			mysqlLoadUserGrants userGlobalGrants
			if false && [ ${creqVerbosity:-0} -ge 3 ]; then
				for i in "${!userGlobalGrants[@]}"; do
					echo "userGlobalGrants[$i] is '${userGlobalGrants[$i]}'"
				done
			fi

			local -A userDBGrants=([User]="$username")
			mysqlLoadUserGrants userDBGrants "$dbName"
			if false && [ ${creqVerbosity:-0} -ge 3 ]; then
				for i in "${!userDBGrants[@]}"; do
					echo "userDBGrants[$i] is '${userDBGrants[$i]}'"
				done
			fi

			[ "${userGlobalGrants[Host]}" == "localhost" ] ||  { noPassMsg="mysqlLocalUserCanAccessDB: db server user does not exist"; return 2; }
			[ "${userGlobalGrants[plugin]}" == "unix_socket" ] ||  { noPassMsg="mysqlLocalUserCanAccessDB: db server user does not use unix_socket SSO auth"; return 1; }

			if [ "${permissionList[0],,}" == "all" ]; then
				for attrName in "${!userDBGrants[@]}"; do
					[[ "$attrName" =~ _priv ]] || { creqLog3 "skipping '$attrName'"; continue; }
					[ "$attrName" != Grant_priv ] || { creqLog3 "skipping '$attrName'"; continue; }
					[ "${userDBGrants[$attrName]}" == "Y" ] || { noPassMsg="mysqlLocalUserCanAccessDB: user does not have '$attrName'"; return 3; }
				done
			else
				for priv in ${permissionList[@]}; do
					local attrName="${mysqlGrantToPriv[$priv]}"
					[ "${userDBGrants[$attrName]}" == "Y" ] || { noPassMsg="mysqlLocalUserCanAccessDB: user does not have '$attrName'"; return 3; }
				done
			fi
			;;

		apply)
			creqLog3 "mysqlGrant \"$username\" \"$dbName\" \"${permissionList[@]}\""
			mysqlCreateSSOUser "$username" "$sudoPermissionName"
			mysqlGrant "$username" "$dbName" "${permissionList[@]}"
			;;

		*) cr_baseClass "$@" ;;
	esac
}





# usage: fromDBOp <dbOperator>
# converts an SQL comparison operator to the equivalant filter term operator.
# Filter terms are the standard way to specify filter (aka query) terms on a script
# command line to limit the results a command shows. See awkData_lookup for exeample
function fromDBOp()
{
	case ${1} in
		'=')         echo ":" ;;
		'<=>')       echo ":" ;;
		'!=')        echo ":!" ;;
		'<>')        echo ":!" ;;
		like)        echo ":~" ;;
		'not like')  echo ":!~" ;;
		'<')         echo ":<" ;;
		'>')         echo ":>" ;;
		'<=')        echo ":<=" ;;
		'>=')        echo ":>=" ;;
		*)     echo "unknown db operator '$1'" ;;
	esac
}

# usage: toDBOp [-d <defOp>] <filterTermOperator>
# converts a filter term operator to the equivalant SQL comparison operator.
# Filter terms are the standard way to specify filter (aka query) terms on a script
# command line to limit the results a command shows. See awkData_lookup for exeample
# Options:
#     -d <defOp> : the ':' char is used as the filterTerm speparator optionally followed by [-<>~!] to explicitly declare the
#                 operator to use. <defOp> will be the operator if only the ':' is used w/o an additional operator chars.
#                 default = '<=>'
function toDBOp()
{
	local defaultOp="<=>"
	while [[ "$1" =~ ^- ]]; do case $1 in
		-d*) defaultOp="$(bgetopt "$@")" && shift ;;
	esac; shift; done
	case ${1} in
		':')    echo "<=>" ;;
		':=')   echo "<=>" ;;
		':==')  echo "<=>" ;;
		':!')   echo "!=" ;;
		':!=')  echo "!=" ;;
		':<>')  echo "!=" ;;
		':~')   echo "like" ;;
		':!~')  echo "not like" ;;
		':<')   echo "<" ;;
		':>')   echo ">" ;;
		':<=')  echo "<=" ;;
		':>=')  echo ">=" ;;
		*)     echo "unknown($1)" ;;
	esac
}

# usage: sqlRemoveWhereTerm <whereClause> <colToRemove>
# removes the where term that contians the column name <colToRemove> from the <whereClause>
# Example:
#     sqlRemoveWhereTerm "where name='bob' and color='blue' and size>0"  "color"
#     returns:  "where name='bob' and size>0"
function sqlRemoveWhereTerm()
{
	local whereClause="$1"
	local colToRemove="$2"
	if [[ ! "$whereClause" =~ $colToRemove ]]; then
		echo "$whereClause"
		return
	fi
	local t1=${whereClause%%$colToRemove*}; t1="$(trimStringR "$t1")"
	local t2=${whereClause#*$colToRemove} ; t2="$(trimStringL "$t2")"
	if [[ "${t2,,}" =~ ^[[:space:]]*([<>=!])|(like)|(not like)|(between) ]]; then
		local op token
		case ${t2,,} in
			'='*)         op="norm";    t2="${t2:1}" ;;
			'<=>'*)       op="norm";    t2="${t2:3}" ;;
			'!='*)        op="norm";    t2="${t2:2}" ;;
			'<>'*)        op="norm";    t2="${t2:2}" ;;
			'like'*)      op="norm";    t2="${t2:4}" ;;
			'not like'*)  op="norm";    t2="${t2:8}" ;;
			'<'*)         op="norm";    t2="${t2:1}" ;;
			'>'*)         op="norm";    t2="${t2:1}" ;;
			'<='*)        op="norm";    t2="${t2:2}" ;;
			'>='*)        op="norm";    t2="${t2:2}" ;;
			'between'*)   op="between"; t2="${t2:7}" ;;
		esac
		case $op in
			norm) parseOneBashToken t2 token
				;;
			between)
				parseOneBashToken t2 token
				[[ "${t2,,}" =~ ^[[:space:]]*and ]] || assertError "expected 'and' at '${t2,,}'"
				parseOneBashToken t2 token
				parseOneBashToken t2 token
				;;
		esac

		if [[ "${t2,,}" =~ ^[[:space:]]*and ]]; then
			parseOneBashToken t2 token
		else
			parseOneBashToken -r t1 token
		fi
	fi

	echo "$t1 $t2"
}



######################################################################################################################\\
### DB Object Extensions

# usage: $obj.fromSQL <resultSet>
# populate an object's attributes from the results of the given query.
# This can restore the main object's attributes and also complex member objects and arrays also.
#
# The restoreSQL statement should return the attributes of the object where the column names are the attribute names.
# The results should be in vertical (-E aka \G) format where each line is of the form columnName: columnValue. -E could be
# specified for the while session or each statement can end with a \G.
# Rows are delimited by "************************* 1. row **************" where 1 is the row number
# Only one row can be restored into the main object. If a second row is encountered for the main object, it is an error.
#
# By default each column will be added to the main object as this[columnName]=columnValue. When a column name ":objName:"
# is encountered its value indicates a member that the columns that follow will be restored to. if the member
# name ends in a [] then the member will be taken as an array and each row will be poplated into a new array element indexed
# with the row number.
#
# Example:
#	$this.fromSQL "$($dbExec" -ss -E -e '
#           # this statement will return one row that will populate the main object attributes
#			select * from Filters where filterName="'"$ssName"'"\G;
#
#           # this statement declares that the data that follows it will go into a member which is an array called "terms"
#			select "terms[]" as ":objName:"\G;
#           # this statement returns the rows that will populate the this.terms[] array
#			select * from FilterTerms where filterName="'"$ssName"'"\G
#
#           # this statement declares that the data that follows it will go into a member which is an array called "actions"
#			select "actions[]" as ":objName:"\G;
#           # this statement returns the rows that will populate the this.actions[] array
#			select * from FilterActions where filterName="'"$ssName"'"\G
#		')"
function Object::fromSQL()
{
	local _nameCA _valueCA
	local _rowCountCA=0 _objNameCA=""
	while read -r _nameCA _valueCA; do
		_nameCA="${_nameCA%:}"
		if [[ "$_nameCA" =~ [*]{4,40} ]]; then
			_rowCountCA="$((${_valueCA%%.*} -0 ))"
			if [[ "$_objNameCA" =~ \]$ ]]; then
				_objNameCA="${_objNameCA%[*}[${_rowCountCA}]"
			fi
		elif [ "$_nameCA" == :objName: ]; then
			# _valueCA can be "", "this", "[[this].]<attribName>" or "[[this].]<attribName>[]"
			_objNameCA="${_valueCA#this}"
			_objNameCA="${_objNameCA#.}"
			_objNameCA="${_objNameCA:+.}${_objNameCA}"
			if [[ "$_objNameCA" =~ \[\]$ ]]; then
				_objNameCA="${_objNameCA%[*}[${_rowCountCA}]"
			else
				[ $_rowCountCA -gt 1 ] && skip="true"
			fi
		elif [ ! "$skip" ] && [ "$_valueCA" == "NULL" ]; then
			[ "$_nameCA" ] && $this$_objNameCA.$_nameCA.unset
		elif [ ! "$skip" ]; then
			[ "$_nameCA" ] && $this$_objNameCA.$_nameCA="$_valueCA"
		fi
	done <<< "$1"
}

# usage: $obj.toSQL <tableName> <primaryKey> <attribList>
# This creates an SQL statement that embodies the state of the object
# The structure of the table that the object will be saved to is passed into this method.
# Then the obect is queied to provide the values for insert statements.
# It is assumed that the table has a primary key that uniquely identifies the object and the
# SQL consistes of a delete statement that removes the object's corresponding row(s) and then an
# insert that inserts the new state of the object.
# Complex members are mapped to different tables that are related by the primary key.
# The method should be called once for the main object and once for each complex member.
# A complex member array will map to multiple rows in the related table.
function Object::toSQL()
{
	local memberName
	while [[ "$1" =~ ^- ]]; do case $1 in
		-m)  memberName="$(bgetopt "$@")" && shift ;;
	esac; shift; done

	local tableName="$1"
	local primaryKey="$2"
	local attribList="$3"

	local keyValue="${this[$primaryKey]}"
	assertNotEmpty keyValue
	local whereClause=" where $primaryKey='$keyValue' "

	# 'objects' will be a list of objects that we will save to the DB.
	local objects

	# If memberName is not set, we only save the 'this' object
	if [ ! "$memberName" ]; then
		objects="this"

	# If memberName ends in [], we iterate its indexes and add each element to 'objects'
	elif [[ "$memberName" =~ \[\]$ ]]; then
		memberName="${memberName%\[\]}"
		local indx; for indx in $($this.$memberName.getIndexes); do
			objects+=" this.$memberName[$indx]"
		done

	# If memberName is a simple name, we add only that member
	else
		objects="this.memberName"
	fi

	local valuesClause
	local _objectRef; for _objectRef in $objects; do
		local valuesList=""
		local attrib; for attrib in ${attribList//,/ }; do
			local value
			if [ "$attrib" == "$primaryKey" ]; then
				value="$keyValue"
			elif ! ${_objectRef//this/$this}.$attrib.exists; then
				value="NULL"
			else
				value="$(${_objectRef//this/$this}.$attrib)"
			fi
			local SQ="'"; [[ "$value" =~ ^(([0-9][0-9]*)|(NULL)|(null)|(Null))$ ]] && SQ=""
			valuesList="${valuesList}${valuesList:+,}${SQ}$value${SQ}"
		done
		valuesClause+="${valuesClause:+,}"$'\n\t'"($valuesList)"
	done

	local sql="delete from $tableName $whereClause;"$'\n'
	if [ "$valuesClause" ]; then
		sql+="insert into $tableName "$'\n\t'"($attribList) "$'\n\t'"VALUES $valuesClause;"
	fi

	echo "$sql"
}











# commented scraps
true <<EOS

CREATE	Create_priv	databases, tables, or indexes
DROP	Drop_priv	databases, tables, or views
GRANT OPTION	Grant_priv	databases, tables, or stored routines
LOCK TABLES	Lock_tables_priv	databases
REFERENCES	References_priv	databases or tables
EVENT	Event_priv	databases
ALTER	Alter_priv	tables
DELETE	Delete_priv	tables
INDEX	Index_priv	tables
INSERT	Insert_priv	tables or columns
SELECT	Select_priv	tables or columns
UPDATE	Update_priv	tables or columns
CREATE TEMPORARY TABLES	Create_tmp_table_priv	tables
TRIGGER	Trigger_priv	tables
CREATE VIEW	Create_view_priv	views
SHOW VIEW	Show_view_priv	views
ALTER ROUTINE	Alter_routine_priv	stored routines
CREATE ROUTINE	Create_routine_priv	stored routines
EXECUTE	Execute_priv	stored routines
FILE	File_priv	file access on server host
CREATE USER	Create_user_priv	server administration
PROCESS	Process_priv	server administration
RELOAD	Reload_priv	server administration
REPLICATION CLIENT	Repl_client_priv	server administration
REPLICATION SLAVE	Repl_slave_priv	server administration
SHOW DATABASES	Show_db_priv	server administration
SHUTDOWN	Shutdown_priv	server administration
SUPER	Super_priv	server administration
ALL [PRIVILEGES]	 	server administration
USAGE	 	server administration

A little query to write the wide privilege table out in narrower form:

SELECT password, host, user,
CONCAT(Select_priv, Lock_tables_priv) AS selock,
CONCAT(Insert_priv, Update_priv, Delete_priv, Create_priv, Drop_priv) AS modif,
CONCAT(Grant_priv, References_priv, Index_priv, Alter_priv) AS meta,
CONCAT(Create_tmp_table_priv, Create_view_priv, Show_view_priv) AS views,
CONCAT(Create_routine_priv, Alter_routine_priv, Execute_priv) AS funcs,
CONCAT(Repl_slave_priv, Repl_client_priv) AS replic,
CONCAT(Super_priv, Shutdown_priv, Process_priv, File_priv, Show_db_priv, Reload_priv) AS admin
FROM USER ORDER BY user, host;

+-------------------------------------------+-----------+--------+--------+-------+------+-------+-------+--------+--------+
| password                                  | host      | user   | selock | modif | meta | views | funcs | replic | admin  |
+-------------------------------------------+-----------+--------+--------+-------+------+-------+-------+--------+--------+
| *.........                                | localhost | backup | YY     | NNNNN | NNNN | NNN   | NNN   | NN     | NNNNNN |
| *.........                                | localhost | nagios | XX     | NNNNN | NNNN | NNN   | NNN   | NN     | NNNNNN |
| *.........                                | 127.0.0.1 | root   | YY     | YYYYY | YYYY | YYY   | YYY   | YY     | YYYYYY |
| *.........                                | localhost | root   | YY     | YYYYY | YYYY | YYY   | YYY   | YY     | YYYYYY |
|                                           | localhost | wheel  | NY     | NNNNN | NNNN | NNN   | NNN   | NN     | NNNNNY |
+-------------------------------------------+-----------+--------+--------+-------+------+-------+-------+--------+--------+


EOS
