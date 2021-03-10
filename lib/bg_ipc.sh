#!/bin/bash

import bg_bgawk.sh ;$L1;$L2

# usage: msgGet <file> [<retVar>]
# read and remove the first line from <file>. Together with msgPut this is an IPC mechanism similar to named pipes (aka fifo)
# but is buffered and the reader and writer do not synchronize. msgGet will block on exclusive flock access to <file> and return
# either the first line or empty string if <file> is empty. If <file> does not exist, it returns empty string without aquiring
# a lock.
# See Also:
#    man(3) msgPut
function msgGet()
{
	local timeout=5
	local file="$1"; shift

	local _msgFD _mgMsg
	if [ -s "$file" ]; then
		exec {_msgFD}<"$file"
		flock -w$timeout $_msgFD || assertError

		_mgMsg="$(bgawk -i 'NR==1 {print $0 >"/dev/fd/3"; deleteLine()}' "$file")"

		flock -u "$_msgFD"
	fi

	returnValue "$_mgMsg" "$1"
}

# usage: msgPut <file> <msg>
# write <msg> to the last line in <file>. Together with msgGet this is an IPC mechanism similar to named pipes (aka fifo)
# but is buffered and the reader and writer do not synchronize. msgPut will block on exclusive flock access to <file>, creating it
# if required and then append <msg> to the file.
# a lock.
# See Also:
#    man(3) msgPut
function msgPut()
{
	local timeout=5
	local file="$1"; shift
	local _mgMsg="$1"; shift

	local _msgFD
	exec {_msgFD}>>"$file"
	flock -w$timeout $_msgFD || assertError

	echo "$_mgMsg" >&$_msgFD

	flock -u "$_msgFD"
}

# usage incName="$(initIPCCount [initValue])"
# increment an integer stored in a file. This is used to pass a counter from inside a pipe loop (cat f | while read ...) bask to the shell script
# returns a new temp filename which will be used for this IPCCounter. Pass that into incIPCCount. The called must eventually rm that file
# 'iniValue 'is the initial value of the variable
function initIPCCount()
{
	local f=$(mktemp)
	echo "${1:-0}" > $f
	echo $f
}

# usage incIPCCount filename
# increment an integer stored in a file. This is used to pass a counter from inside a pipe loop (cat f | while read ...) bask to the shell script
# it is not meant to be a thread safe count -- multiple writers maybe loose or gain counts
function incIPCCount()
{
	local quiet=""
	[ "$1" == "-q" ] && { quiet=1; shift; }
	local c=$(cat $1 2>/dev/null)
	c="${c:-0}"
	(( c++ ))
	echo $c > $1
	if [ ! "$quiet" ] && [ "$2" != "-q" ]; then
		echo $c
	fi
}

# usage decIPCCount filename
# decrement an integer stored in a file. This is used to pass a counter from inside a pipe loop (cat f | while read ...) back to the shell script
# it is not meant to be a thread safe count -- multiple writers maybe loose or gain counts
function decIPCCount()
{
	local quiet=""
	[ "$1" == "-q" ] && { quiet=1; shift; }
	local c=$(cat $1 2>/dev/null)
	c="${c:-0}"
	(( c-- ))
	echo $c > $1
	if [ ! "$quiet" ] && [ "$2" != "-q" ]; then
		echo $c
	fi
}





##################################################################################################################
# Inter Process Control Functions
##################################################################################################################

#function pidIsDone()  moved to bg_libCore.sh
#function startLock() moved to bg_libCore.sh
#function endLock()   moved to bg_libCore.sh





##################################################################################################################
# inter-machine, network mechanisms
##################################################################################################################



# usage: sshInitOptions [-r] [-a] [-k <known_hostsFile>] [<username>@]<hostFQDN>  <optionsStringVarName>
# usage: ssh $<optionsStringVarName> <username>@<hostFQDN>
# initialize an ssh options string that can be used in subsequent ssh and scp commands taylored for use in scripts.
# The string may contain a reference to a tmp file so sshDeInitOptions should be called when you are done.
# This performs several functions. As we improve our general inter domain communication controls some or all
# of these may become uneccessary.
#      * when the user is 'readUser' it knows how to configure the key for passwordless authentication. This is a
#        temporary solution until we can have all human ans system users authenticated as themselves to all types
#        of devices. In the meantime, a device can grant access to the anonymous readUser if it ensures that the readUser
#        can not change anything or access any secrets or customer data. readUser is used for monitoring and collecting
#        config and operational state data from the device
#      * it uses the domData knownhosts instead of the user's
#      * it allows updating the domData knownhosts file with a new or changed host key
#      * it can configure ssh control socket so that multiuple calls in a script will resuse the same connection
#        this is particularly important when the user has to pasword authenticate so that they don't have to enter
#        their password multiple times.
#      * it knows about some quicks of some types of devices and adds config to work around them
# An principal goal of this function is allow scripts to configure the client side ssh without interfering with the
# user's personal ssh configuration.
# Options:
#   -a : add new device flag. normally the options result in ssh/scp failing if the target is not known in the domData.
#        This can be used to add or update a device in the domData's known hosts file
#        A user should be sure that the device is correct one before doing this. Eventually, the domData known hosts
#        will be signed so that a user will need privilege to add or update a host's key and this will be tied into the
#        procedure of joining a domain
#   -r : reuse the ssh connection. add to the ssh config the options to auto maintain master/slave connections
#   -k : known_host file. specify the knownHosts file to use. the default is to first preper the one in the selected
#        domData if their is one and the user's home folder known_hosts otherwise
function sshInitOptions()
{
	local reuseConnectionMode="" addNewFlag="" knownHostsFile
	while [[ "$1" =~ ^- ]]; do case $1 in
		-r)  reuseConnectionMode="1" ;;
		-a)  addNewFlag="1" ;;
		-k*) knownHostsFile="$(bgetopts "$@")" && shift ;;
	esac; shift; done

	local hostFQDN="$1"
	local optionsStringVar="$2"
	[ "$optionsStringVar" ] && [ "${!optionsStringVar}" ] && return 0
	local username; [[ "$hostFQDN" =~ @ ]] && { username="${hostFQDN%@*}"; hostFQDN="${hostFQDN#*@}"; }

	# if the caller did not specify one, use the selected domData's known_hosts file
	if [ ! "$knownHostsFile" ]; then
		domFolderInit -f
		[ ! -d "$domFolder/ssh/" ] && domTouch "$domFolder/ssh/"
		knownHostsFile="$domFolder/ssh/known_hosts"
	fi

	# normally we only talk to hosts that we know (strictHostCheckFlag="yes")
	# if -a is specified, we will get to know this host (this is a temporary solution -- see function comment)
	local strictHostCheckFlag="yes"
	if [ "$addNewFlag" ]; then
		strictHostCheckFlag="no"

		# remove the old key if it exists. We might be replacing a host or the host might have regenerated its key
		ssh-keygen -R "$hostFQDN" -f "$knownHostsFile" &>/dev/null
		local deviceIP="$(netResolve -1 "$hostFQDN")"
		[ "$deviceIP" ] && ssh-keygen -R "$deviceIP" -f "$knownHostsFile" &>/dev/null
		rm "${knownHostsFile}.old" &>/dev/null
	fi

	local sshConfFile="$HOME/.ssh/cm_socket/sshConf.${username:$USER}.$hostFQDN.$$.$BASHPID"
	aaaTouch -d "" "$sshConfFile"

	cat <<-EOS > $sshConfFile
		StrictHostKeyChecking $strictHostCheckFlag
		HashKnownHosts no
		UserKnownHostsFile $knownHostsFile
	EOS

	# the special readUser domain user has credentials in the domData we can use. This is a temporary construct -- see function comment)
	if [ "$username" == "readUser" ] && [ "$domFolder" ]; then
		local domKeyFile="$domFolder/ssh/readUserKey"
		local usrKeyFile="$HOME/.ssh/readUserKey.${domFolder##*/}"
		if [ ! -f "$usrKeyFile" ] && [ -f "$domKeyFile" ]; then
			cp "$domKeyFile" "$usrKeyFile"
			aaaTouch "$usrKeyFile" owner:$(aaaGetUser):writable,group::none,world:none
		fi
		if [ -f "$usrKeyFile" ]; then
			cat <<-EOS >> $sshConfFile
				IdentityFile $usrKeyFile
				BatchMode yes
			EOS
		fi
	fi

	if [[ "$hostFQDN" =~ ^ras-  ]] && [ "$(lsb_release -rs)" == "14.04" ]; then
		cat <<-EOS >> $sshConfFile
			KexAlgorithms=diffie-hellman-group14-sha1
		EOS
	fi

	if [ "$reuseConnectionMode" ]; then
		cat <<-EOS >> $sshConfFile
			Host *
				ControlMaster auto
				ControlPath $HOME/.ssh/cm_socket/%r@%h:%p
				ControlPersist 3
		EOS
	fi

	local optionsStringValue=" -F $sshConfFile "

	[ "$optionsStringVar" ] && eval $optionsStringVar="\$optionsStringValue" || echo "$optionsStringValue"
}

# usage: sshDeInitOptions <optionsStringVarName>
# This removes up the tmp ssh config file that sshInitOptions might have made
function sshDeInitOptions()
{
	local optionsStringVar="$1"
	[ "$optionsStringVar" ] || return 0
	local optionsStringValue
	if [[ "$optionsStringVar" =~ -F ]]; then
		optionsStringValue="$optionsStringVar"
		optionsStringVar=""
	else
		optionsStringValue="${!optionsStringVar}"
		[ "$optionsStringValue" ] || return 0
	fi
	local optionsFile="${optionsStringValue#*-F}"
	optionsFile="${optionsFile# }"
	optionsFile="${optionsFile% *}"
	[ -f "$optionsFile" ] && rm "$optionsFile"
	[ "$optionsStringVar" ] && eval $optionsStringVar=\"\"
}



# usage: sshRomoteHostOptsList
function sshRomoteHostOptsList()
{
	local sshUserOptsFile=~/.ssh/config
	while [[ "$1" =~ ^- ]]; do
		case $1 in
			-g) sshUserOptsFile="/etc/ssh/ssh_config" ;;
		esac
	done

	if [ -f "$sshUserOptsFile" ]; then
		awk '
			function printHost() {
				if (hostname) {
					printf("%-20s\n", hostname);
				}
			}
			$1=="Host" {
				printHost();
				hostname=$2
			}
			$1=="Match" {
				printHost();
				hostname=""
			}

			END {printHost()}
		' "$sshUserOptsFile"
	fi
}

# usage: sshConfigLocalConnectionCaching
function sshConfigLocalConnectionCaching()
{
	local sshUserOptsFile=~/.ssh/config
	while [[ "$1" =~ ^- ]]; do
		case $1 in
			-g) sshUserOptsFile="/etc/ssh/ssh_config" ;;
		esac
		shift
	done

	echo "error: function not yet implemented"
	#	cfgSet -s "Host *"
	#Host *
	#	ControlMaster auto
	#	ControlPath ~/.ssh/cachedConnections/%r@%h:%p
	#	ControlPersist 300
}



# usage: sshInstallSSHFSSupportOnRemote [remoteUser@]remoteHost
# This is a helper function used by sshCmd to implement its -I options to install sshfs folder sharing support
# it connects to the remote host twice
function sshInstallSSHFSSupportOnRemote()
{
	local quietMode confirmInstall="1" sshOptions
	while [[ "$1" =~ ^- ]]; do case $1 in
		--) shift; while [ "$1" != "--" ]; do sshOptions="$sshOptions $1"; shift; done ;;
		-q) quietMode="1" ;;
		-y) confirmInstall="" ;;
		-A) sshOptions="${sshOptions} -A"
	esac; shift; done

	local remoteHost="$1"; [ "$1" ] && shift

	# remoteUser is the user used to log into the remote host
	local remoteUser
	parseURL "$remoteHost" "" remoteUser "" remoteHost
	remoteUser="${remoteUser:-$(id -un)}"

	local pkgName="sshfs"
	local remoteScript="$remoteScript"'
		if ! which sshfs >/dev/null 2>&1; then
			if [ "'"$confirmInstall"'" ]; then
				echo -en "package '"$pkgName"' is required to remote mount your folder. Do you want to install it on $(hostname)? (y/n)"
				read -n1 result; echo ""
				[[ ! "$result" =~ ^y ]] && exit 4
			fi
			if which apt-get >/dev/null 2>&1; then
				sudo apt-get -y install "'"$pkgName"'" >/dev/null
				sudo -p"password for %p to allow other users for fuse mounts on %h:" sed -i -e  '"'"'$auser_allow_other '"'"'  -e '"'"'/[# \t]*user_allow_other/d '"'"'  /etc/fuse.conf
			elif which yum >/dev/null 2>&1; then
				sudo yum install -y install "'"$pkgName"'"
				sudo -p"password for %p to allow other users for fuse mounts on %h:" sed -i -e  '"'"'$auser_allow_other '"'"'  -e '"'"'/[# \t]*user_allow_other/d '"'"'  /etc/fuse.conf
			else
				echo "error: neither apt-get nor yum found on this system"
				exit 6
			fi
		fi
		if ! groups | grep -q "\bfuse\b"; then
			sudo -p"password for %p@%h: to add $USER to fuse group on %h:" addgroup $USER fuse || exit
			exit 42
		fi
		if ! grep -q "^[ \t]*user_allow_other" /etc/fuse.conf 2>/dev/null; then
			sudo -p"password for %p to allow other users for fuse mounts on %h:" sed -i -e  '"'"'$auser_allow_other '"'"'  -e '"'"'/[# \t]*user_allow_other/d '"'"'  /etc/fuse.conf
		fi
	'

	[ ! "$quietMode" ] && remoteScript="$remoteScript"'
		if which sshfs >/dev/null 2>&1 && groups | grep -q "\bfuse\b" && grep -q "^[ \t]*user_allow_other" /etc/fuse.conf 2>/dev/null; then
			echo "sshfs support is configured on $(hostname -s)"
		else
			echo "error: sshfs support is not configured properly on $(hostname -s)"
		fi
	'


	ssh $sshOptions -t "$remoteUser@$remoteHost" "$remoteScript"

	# if we had to add the group, it won't take effect for this session so we have to
	# logout and log back in.
	if [ $? -eq 42 ]; then
		ssh $sshOptions -O stop "$remoteUser@$remoteHost"
		ssh $sshOptions -t "$remoteUser@$remoteHost" "$remoteScript"
	fi
}

# note that this helper function uses local variables from the sshCmd function. It is not meant
# to be called from any other place
function __sshCmdAddSMBShare()
{
	local useNewConnectFlag="$1"
	local whoToCall connectionsOpts

	if [ ! "$useNewConnectFlag" ]; then
		myRandomPort="$(getIniParam -a $iniUserConfFile sshCmd myRandomPort $(( 22000 + $(rand -M 999) )) )"
		connectionsOpts="ip=127.0.0.1,port=$((myRandomPort+1))"
	fi

	if [ ! "$doSMBInitOnce" ]; then
		# install the required packages if needed. without the -y switch, the user will have a
		# change to abort
		pkgInstallIfNeeded samba || exit
		pkgInstallIfNeeded whois || exit

		# note that everything we create will have unique names so that they
		# can coexist with other instances shared in other terminals
		shareUUID=$(uuidgen | cut -c1-8)

		# this block deals with the user password and host that the remote ssh script will use to
		# connect back to our local share.  The user can specify cbUser on the command line
		if [ ! "$cbUser" ]; then
			cbUser="$(getIniParam "$iniUserConfFile" sshCmd cbUser )"
			cbPassword="$(getIniParam "$iniUserConfFile" sshCmd cbPassword )"
			if [ ! "$cbUser" ] && confirm "do you wnat to create a local samba only user with a unique password?\n\ty=create new user\n\tn=use your user and type pw manually"; then
				cbUser="${localUser}SMB${shareUUID}"
				cbPassword="me${shareUUID}"

				echo "creating a new local samba only user for remote server work '$cbUser'"
				userShareCreateUser "$cbUser" "$localUser" "$cbPassword"

				# record the new user so that we can use it again next time
				setIniParam  "$iniUserConfFile" sshCmd cbUser "$cbUser"
				setIniParam  "$iniUserConfFile" sshCmd cbPassword "$cbPassword"
			fi

			if grep -q "$cbUser" /etc/passwd && [ "$cbPassword" ]; then
				echo "creating a new local samba only user for remote server work '$cbUser'"
				userShareCreateUser "$cbUser" "$localUser" "$cbPassword"
			fi

			# if a better alternative not found, use the localuser and let smbmount prompt for the password
			if [ ! "$cbUser" ]; then\
				cbUser="$localUser"
				cbPassword=""
				setIniParam  "$iniUserConfFile" sshCmd cbUser "$cbUser"
			fi
		fi

		doSMBInitOnce="1"
	fi

	local simpleShareName="$(net usershare list | grep "^remoteCallbackShare-$(basename "$localFolder")-" | head -n1)"
	if [ ! "$simpleShareName" ]; then
		simpleShareName="remoteCallbackShare-$(basename "$localFolder")-${shareUUID}"
		ourShares[${#ourShares[@]}]="$simpleShareName"
	fi
	userShareAdd "$simpleShareName" "$localFolder" "$cbUser:F"

	remoteSharesStartScript="$remoteSharesStartScript"'
		bgFolderMounted="$(mount | grep "'"$remoteFolder"'")"
		if [ ! "$bgFolderMounted" ] && [ "$(find "'"$remoteFolder"'"/ -mindepth 1 -print -quit 2>/dev/null)" ]; then
			echo "error: the folder ("'"$remoteFolder"'") on the remote machine $(hostname -s) is occupied" >&2
			exit 3
		fi
		if [ ! -d "'"$remoteFolder"'" ]; then
			if [ "$bgFolderMounted" ]; then
				sudo -p "sudo unmount ... [sudo] password for %p@%h:" umount "'"$remoteFolder"'"
			else
				mkdir -p "'"$remoteFolder"'" || exit
			fi
		fi
		[ ! "$bgFolderMounted" ] && sudo -p "mount ... [sudo] password for %p@%h:" \
			mount -t cifs "//'"$cbHost"'/'"$simpleShareName"'" "'"$remoteFolder"'" -o username="'"$cbUser"'",password="'"$cbPassword"'",'"${connectionsOpts}"'
	'

	if [ ! "$persistentFolderMode" ]; then
		remoteSharesStopScript="$remoteSharesStopScript"'
			echo "disconnecting shared drive $(basename "'"$remoteFolder"'")"
			sudo -p "sudo unmount ... [sudo] password for %p@%h:" umount "'"$remoteFolder"'"
		'
	fi

}

# note that this helper function uses local variables from the sshCmd function. It is not meant
# to be called from any other place
function __sshCmdAddSSHFSShare()
{
	local useNewConnectFlag="$1"
	local whoToCall

	useAgentForwarding="1"
	if [ "$useNewConnectFlag" ]; then
		whoToCall="$localUser@$cbHost"
	else
		myRandomPort="$(getIniParam -a $iniUserConfFile sshCmd myRandomPort $(( 22000 + $(rand -M 999) )) )"
		whoToCall="-p$myRandomPort $localUser@localhost"
	fi

	remoteSharesStartScript="$remoteSharesStartScript"'
		export '"$remoteFolderName"'="'"$remoteFolder"'"
		bgFolderMounted="$(mount | grep "'"$remoteFolder"'")"
		if [ ! "$bgFolderMounted" ] && [ "$(find "'"$remoteFolder"'"/ -mindepth 1 -print -quit 2>/dev/null)" ]; then
			echo "error: the folder ("'"$remoteFolder"'") on the remote machine $(hostname -s) is occupied" >&2
			exit 3
		fi
		if [ ! -d "'"$remoteFolder"'" ]; then
			if [ "$bgFolderMounted" ]; then
				fusermount -u "'"$remoteFolder"'"
			else
				mkdir -p "'"$remoteFolder"'" || exit
			fi
		fi
		if [ ! "$bgFolderMounted" ]; then
			if ! sshfs -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o reconnect -o allow_other '"$whoToCall"':"'"$localFolder"'" "'"$remoteFolder"'"; then
				echo "error: mounting sshfs -o reconnect -o allow_other '"$whoToCall"':\"'"$localFolder"'\" \"'"$remoteFolder"'\""
				fusermount -u "'"$remoteFolder"'"
				exit 5
			else
				echo "mounted '"$remoteFolder"' from your computer"
			fi
		fi
	'

	if [ ! "$persistentFolderMode" ]; then
		remoteSharesStopScript="$remoteSharesStopScript"'
			echo "disconnecting shared drive $(basename "'"$remoteFolder"'")"
			fusermount -u "'"$remoteFolder"'"
		'
	fi
}


# note that this helper function uses local variables from the sshCmd function. It is not meant
# to be called from any other place
function __sshCmdAddNFSShare()
{
	local useNewConnectFlag="$1"
	local whoToCall

	useAgentForwarding="1"
	if false && [ "$useNewConnectFlag" ]; then
		whoToCall="$cbHost"
	else
		myRandomPort="$(getIniParam -a $iniUserConfFile sshCmd myRandomPort $(( 22000 + $(rand -M 999) )) )"
		whoToCall="localhost"
	fi

	remoteSharesStartScript="$remoteSharesStartScript"'
		bgFolderMounted="$(mount | grep "'"$remoteFolder"'")"
		if [ ! "$bgFolderMounted" ] && [ "$(find "'"$remoteFolder"'"/ -mindepth 1 -print -quit 2>/dev/null)" ]; then
			echo "error: the folder ("'"$remoteFolder"'") on the remote machine $(hostname -s) is occupied" >&2
			exit 3
		fi
		if [ ! -d "'"$remoteFolder"'" ]; then
			if [ "$bgFolderMounted" ]; then
				sudo -p "umount [sudo] password for %p@%h:" umount "'"$remoteFolder"'"
			else
				mkdir -p "'"$remoteFolder"'" || exit
			fi
		fi
		if [ ! "$bgFolderMounted" ]; then
			if ! sudo -p "mount [sudo] password for %p@%h:" mount '"$cbHost"':"'"$localFolder"'" "'"$remoteFolder"'" -o nfsvers=3,noatime; then
				echo "error: mounting nfs mount '"$cbHost"':\"'"$localFolder"'\" \"'"$remoteFolder"'\""
				exit 5
			else
				echo "mounted '"$remoteFolder"' from your computer"
			fi
		fi
	'

	if [ ! "$persistentFolderMode" ]; then
		remoteSharesStopScript="$remoteSharesStopScript"'
			echo "disconnecting shared drive $(basename "'"$remoteFolder"'")"
			sudo -p "umount [sudo] password for %p@%h:" umount "'"$remoteFolder"'"
		'
	fi
}




# usage: sshCmd [-i] [-d] [-A] [-p] [-f localFolder] [-l callbackUser:pw@cbHost] [remoteUser@]remoteHost [remoteCommand]
# wrapper over ssh that adds some features.
# The positional parameters are the same as ssh -- remoteHost with optional remote user and optional remote command
#   -d: debug mode. (aka dry run). Echo the ssh command that would be run.
#   -i: interactive session. Even if a remote command is specified, leave the user in at a prompt on the remote
#   -t: ssh terminal option. use if executing a non-interactive remote cmd that might prompt the user (e.g. sudo password)
#   -f folder: mount the local folder on the remote (in the same place). folder must be in user's home tree
#   -fp: make the folder mounts persistent. Normally they are unmounted when the session exits
#   -fx: end persistent folder shares
#   -p: make the folder mounts persistent. Normally they are unmounted when the session exits
#   -A: enable agent forwarding. Useful with -f so that the sshfs mount does not prompt for a password.
#   -l: specify all or part of the url used to connect back to your host. default is $USER@$(getLocalIP remoteHost)
#   -I) installRemoteShareSupport
#
#   Folder share types:
#      smb:   use smb to share the local folder and connect to it from the remote
#      sshfs: use sshfs. Default is to forward a localhost:22 to a random port on the remote and sshfs back through it
#      sshfsN: use sshfs but create a new connection back to the local machine
function sshCmd()
{
	local -a folders
	local -a ourShares
	local interactiveShellFlag endFolderSeesions callbackHost doSMBInitOnce doSSHFSInitOnce shareUUID sshOptions
	local sshDebugCmd useAgentForwarding installRemoteShareSupport persistentFolderMode myRandomPort
	local remoteSharesStartScript remoteSharesStopScript sshTermFlag tmpKeyFile domMode domAddOpts domOpts
	while [[ "$1" =~ ^- ]]; do
		case "$1" in
			--dom)    domMode="1" ;;
			--domAdd) domMode="1"; domAddOpts="-a" ;;
			-d)  sshDebugCmd="echo " ;;
			-i)  interactiveShellFlag="y" ;;
			-t)  sshTermFlag="1" ;;
			-f*) folders+=("${folders[@]}" "$(bgetopt "$@")") && shift ;;
			-p)  persistentFolderMode="1" ;;
			-fp) persistentFolderMode="1" ;;
			-fx) endFolderSeesions="1"; interactiveShellFlag="n" ;;
			-l*) callbackHost="$(bgetopt "$@")" && shift ;;
			-A)  useAgentForwarding="1" ;;
			-I)  installRemoteShareSupport="1" ;;
			-Ktmp) tmpKeyFile="1" ;;
		esac
		shift
	done
	local remoteHost="$1"; [ "$1" ] && shift
	local remoteCommand="$@"

	# remoteUser is the user used to log into the remote host
	local remoteUser
	parseURL -pssh "$remoteHost" "" remoteUser "" remoteHost
	remoteUser="${remoteUser:-$(id -un)}"


	### Section to build the folder share start and stop scipts
	#
	if [ ${#folders[@]} -gt 0 ] && [ ! "$endFolderSeesions" ]; then
		remoteSharesStartScript=$'function vmSharesStart()\n{\n'

		local localUser="$(id -un)"

		# Iterate over each folder
		for i in ${!folders[@]}; do
			# parse the -f param as a URL using sshfs as the default protocol
			local cbProtocol cbUser cbPassword cbHost localFolder
			parseURL -psshfs "${folders[$i]}" cbProtocol cbUser cbPassword cbHost cbPort localFolder

			cbHost="${cbHost:-$(getLocalIP $remoteHost)}"
			localFolder="$(cd $localFolder; pwd)" # get full path

			local remoteFolderName="bgRemoteShare${i}"
			local remoteFolder="${localFolder//$localUser/$remoteUser}"
			remoteFolder="${remoteFolder//\/home\/root\//\/root\/}"

			case $cbProtocol in
				smb)    __sshCmdAddSMBShare ;;
				smbN)   __sshCmdAddSMBShare newConnection;;
				sshfs)  __sshCmdAddSSHFSShare ;;
				sshfsN) __sshCmdAddSSHFSShare newConnection ;;
				nfs)    __sshCmdAddNFSShare ;;
			esac
		done

		remoteSharesStartScript="${remoteSharesStartScript}"$'\n}\nexport -f vmSharesStart\nvmSharesStart\n'
	fi

	if [ "$endFolderSeesions" ]; then
		remoteSharesStartScript='
			for i in $(mount -t fuse.sshfs | awk '\''{print $3}'\''); do
				echo "unmounting $1"
				fusermount -u "$i"
			done
		'
	fi

	### Now assemble and execute the command

	# decide if we should give the user an interact shell. the expected behavior is to get a shell if you don't
	# give a remote cmd but sometimes we create a remote cmd to do stuff but the user doesn't know and we also
	# allow the user to specify -i to get an interactive shell and specify a remote cmd
	local interactiveBreak=""
	if ( [ "${remoteSharesStartScript}${remoteSharesStopScript}" ] && [ ! "$remoteCommand" ] ) || [ "$interactiveShellFlag" == "y" ]; then
		interactiveBreak="bash"
		sshTermFlag="1"
	fi

	if [ "$interactiveShellFlag" == "n" ]; then
		interactiveBreak=""
	fi

	if [ "$domMode" ]; then
		domOpts="$(sshInitOptions -r $domAddOpts "${remoteUser}${remoteUser:+@}$remoteHost" )" || exit
		sshOptions="${sshOptions} $domOpts"
	fi

	if [ "$sshTermFlag" ]; then
		sshOptions="${sshOptions} -t"
	fi

	if [ "$tmpKeyFile" ]; then
		sshOptions="${sshOptions} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
	fi

	local saveExitCode1 saveExitCode2
	if [ "$remoteCommand" ] && [ "$remoteSharesStopScript" ]; then
		saveExitCode1='sshCmdResult=$?'
		saveExitCode2='exit $sshCmdResult'
	fi

	# ssh will consider a parameter with only whitespace a script so we remove whitespace if its the only content
	local remoteScrpt='
		'"$remoteSharesStartScript"'
		'"$remoteCommand"'
		'"$saveExitCode1"'
		'"$interactiveBreak"'
		'"$remoteSharesStopScript"'
		'"$saveExitCode2"'
		'
	if [[ "$remoteScrpt" =~ ^[$' \t\n']*$ ]]; then
		remoteScrpt=""
	fi
	remoteScrpt="$(echo "$remoteScrpt" | sed -e 's/^\t\t//' -e '/^$/d')"

	[ "$interactiveShellFlag" == "n" ] && remoteScrpt="$remoteScrpt "

	# the user might have specified this or some code along the way might have set it
	[ "$useAgentForwarding" ] && sshOptions="${sshOptions} -A"
	[ "$myRandomPort" ] && sshOptions="$sshOptions -R$myRandomPort:localhost:22"
	[ "$myRandomPort" ] && sshOptions="$sshOptions -R$((myRandomPort+1)):localhost:139"

	if [ "$installRemoteShareSupport" ]; then
		sshInstallSSHFSSupportOnRemote -y -- $sshOptions -- "${remoteUser}${remoteUser:+@}$remoteHost"
	fi

	### This is the real ssh execution
	$sshDebugCmd ssh -q $sshOptions "${remoteUser}${remoteUser:+@}$remoteHost" "$remoteScrpt"
	local remoteExitCode=$?

	if [ ${remoteExitCode:-0} -eq 255 ]; then
		$sshDebugCmd ssh $sshOptions "${remoteUser}${remoteUser:+@}$remoteHost" "$remoteScrpt"

	fi

	if [ ! "$persistentFolderMode" ] && [ "$remoteSharesStartScript" ]; then
		for i in ${!ourShares[@]}; do
			echo "    del ${ourShares[$i]}"
			userShareDelete "${ourShares[$i]}"
		done
	fi

	if [ "$domMode" ]; then
		sshDeInitOptions domOpts
	fi

	return $remoteExitCode
}
