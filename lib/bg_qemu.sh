

# Library
# TODO: this first line is the short description of the library's manpage
# The rest of this comment block is the manpage body...
# ...

# this is the default path for images used for development test VMs (freshVM)
freshVM_osImagePath="/home/$USER/.bg/cache/bg-dev_vmImages"



# usage: vmGuest_shutdown <vmName>
function vmGuest_shutdown()
{
	local vmName="${1##*/}"; vmName="${vmName%.qcow2}"
	local vmGuestQMP=${freshVM_osImagePath}/images/${vmName}.qmp
	[ -e "$vmGuestQMP" ] || assertError -v vmName -v vmGuestQMP "vmName is not running. vmGuestQMP does not exist"
	socat <<-EOS - unix:"$vmGuestQMP" >/dev/null
		{ "execute": "qmp_capabilities" }
		{ "execute": "system_powerdown" }
	EOS
}

# bash completion for <vmDisk> which is a list of existing qcow2 files in the $freshVM_osImagePath
function completeVMImageFile()
{
	echo "<vmDiskPath>"
	fsExpandFiles -b $freshVM_osImagePath/images/*.qcow2
	#echo "\$(doFilesAndDirs)"
}

# bash completion for the argument to unmount which is a list of mounted images w/o path
function completeUnmount()
{
	echo "<mountedImage>"
	gawk -F'|' '{print $5}' /tmp/bg-qemu.tmpMntData
}

# usage: qemu_mount <vmDiskPath> <mountPoint>
function qemu_mountStatus()
{
	fsTouch /tmp/bg-qemu.tmpMntData
	gawk -F'|' '
		{printf("%s: %-30s (%s)\n"), $5,$3,$2}
		END {if (NR==0) printf("No images are currently mounted with this command\n")}
	' /tmp/bg-qemu.tmpMntData
}


# usage: qemu_mount <vmDiskName|vmDiskPath> <mountPoint>
# Options:
#    -R|--devRet=<retVar>  : pass in a variable to receive the nbd device path used to mount the disk
#    -M|--mountPoints      : pass in a variable to receive the paths of the the mount points where the image partitions can be
#                            accessed at. The index of the array is the numeric partition number and the value if the folder.
#    -f|--format=<imageFormat> : default is 'qcow2'. if provided, this will be passed through to qemu-nbd to override its detection.
#    -q|--quiet            : dont print informational msgs to stdout
function qemu_mount()
{
	fsTouch /tmp/bg-qemu.tmpMntData
	local devRetVar imageFormat mntPointsRetVar nbdOnly quietFlag
	while [ $# -gt 0 ]; do case $1 in
		-q|--quiet) quietFlag="-q" ;;
		-R*|--devRet*) bgOptionGetOpt val: devRetVar "$@" && shift ;;
		-M*|--mmtPoints*) bgOptionGetOpt val: mntPointsRetVar "$@" && shift ;;
		-f*|--format*)    bgOptionGetOpt val: imageFormat "$@" && shift ;;
		--nbdOnly)        nbdOnly="--nbdOnly" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	# install qemu-utils if needed
	which qemu-img &>/dev/null || creqApply cr_packageInstalled qemu-utils || assertError "abort because the qemu-utils package is required and could not be installed"

	# load the nbd kernel module if needed
	[ -e /dev/nbd0 ] || bgsudo modprobe nbd || assertError "could not load the 'nbd' kernel module"

	# the first case is returning mounts to fixup the possibly partial mounts
	local devicePathBaseValue mountPointBase vmDiskPath
	IFS='|' read -r devicePathBaseValue mountPointBase vmDiskPath < <(gawk -F'|' -v term="${1%p*}" '
		$2==term || $3==term || $4==term || $5==term {
			printf("%s|%s|%s\n", $2,$3,$4)
		}
	' /tmp/bg-qemu.tmpMntData)
	# detect a common failure mode and try to fix it. Probably the mount was partially taken down in the wrong order
	if [ "$devicePathBaseValue" ] && [ ! -e "${devicePathBaseValue}p1" ]; then
		sudo qemu-nbd -d "$devicePathBaseValue" &>/dev/null
	fi

	# The typical path -- connect the image to the nbd device
	if [ ! "$devicePathBaseValue" ] || [ ! -e "${devicePathBaseValue}p1" ]; then
		vmDiskPath="$1"; assertNotEmpty vmDiskPath
		mountPointBase="$2"

		# resolve vmDiskPath if needed
		if [ ! -e "$vmDiskPath" ] && [ -e "$freshVM_osImagePath/images/$vmDiskPath" ]; then
			vmDiskPath="$freshVM_osImagePath/images/$vmDiskPath"
		fi
		[ ! -e "$vmDiskPath" ] && assertError -v vmDiskPath "the specified image file does not exist"

		# create the default mountPoint if needed
		if [ ! "$mountPointBase" ]; then
			mountPointBase="${vmDiskPath}"; [[ "$mountPointBase" =~ [.][^/]*$ ]] && mountPointBase="${mountPointBase%.*}"
		fi

		# loop through nbd devices until we find one we can use.
		local i=0
		while true; do
			# if we have gone through all the nbd devices and none were available
			[ ! -e /dev/nbd${i} ] && assertError -v vmDiskPath -v mountPointBase -v i  "no avaialable /dev/nbd* devices were found to use for mounting the disk image";

			# this assumes that if the device is in use it will have a corresponding partition device. This could produce fals positives
			# so in the loop, if qemu-nbd failes we assume that that device was inuse
			if ! ls /dev/nbd${i}p* &>/dev/null ; then
				if bgsudo qemu-nbd ${imageFormat:+-f $imageFormat} -c /dev/nbd${i} "$vmDiskPath" 2>/dev/null; then
					local j; for ((j=0;j<100;j++)); do [ -e /dev/nbd${i}p1 ] && break; sleep 0.01; done
					if [ ! -e /dev/nbd${i}p1 ]; then
						bgsudo qemu-nbd -d /dev/nbd${i}
						assertError -v vmDiskPath -v mountPointBase "expected that connecting the disk image to the nbd (/dev/nbd${i}) would reveal an partition (/dev/nbd${i}p1) but it did not. The image file is currently connected so you can examine it. Use 'sudo qemu-nbd -d /dev/nbd${i}' to diconnect it."
					fi
					devicePathBaseValue="/dev/nbd${i}"
					printf "|%s|%s|%s|%s|\n" "$devicePathBaseValue" "$mountPointBase" "$vmDiskPath" "${vmDiskPath##*/}" >> /tmp/bg-qemu.tmpMntData
					break;
				fi
			fi
			((i++))
		done
	fi

	setReturnValue "$devRetVar" "$devicePathBaseValue"

	if [ "$nbdOnly" ]; then
		[ ! "$quietFlag" ] && echo "image is now connected to '$devicePathBaseValue'"
		return
	fi

	# do the partition mounts
	[ "$mntPointsRetVar" ] && local -n mntPointsRet="$mntPointsRetVar"
	local j=1
	while [ -e "${devicePathBaseValue}p${j}" ]; do
		# mount the image to our filesystem
		local mountPoint="$mountPointBase"
		[ -e "${devicePathBaseValue}p2" ] && mountPoint+="-p${j}"
		fsTouch -d -p "$mountPoint/"
		local alreadyMounted="$(findmnt -no SOURCE "$mountPoint")"
		[ "$alreadyMounted" ] && [ "$alreadyMounted" != "${devicePathBaseValue}p${j}" ] && assertError -v mountPoint -v alreadyMounted -v desiredDevice:"-l${devicePathBaseValue}p${j}" "the mountPoint is already mounted to something else"
		[ ! "$alreadyMounted" ] && { bgsudo mount "${devicePathBaseValue}p${j}" "$mountPoint" || assertError; }
		[ "$mntPointsRetVar" ] && mntPointsRet[${j}]="$mountPoint"
		((j++))
	done

	[ ! "$quietFlag" ] && echo "the image file's filesystems are now mounted at '$mountPointBase*'"
}

# usage: qemu_umount <mountPoint>|<nbdPath>|<imageFile>
function qemu_umount()
{
	local quietFlag
	while [ $# -gt 0 ]; do case $1 in
		-q|--quiet) quietFlag="-q" ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	fsTouch /tmp/bg-qemu.tmpMntData
	[ ! "$1" ] && assertError "The first argument (vmImage) to this function is required"
	local devicePathBase mountPointBase vmDiskPath
	IFS='|' read -r devicePathBase mountPointBase vmDiskPath < <(gawk -F'|' -v term="${1%p*}" '
		$2==term || $3==term || $4==term || $5==term {
			printf("%s|%s|%s\n", $2,$3,$4)
		}
	' /tmp/bg-qemu.tmpMntData)

	[ ! "$devicePathBase" ] && assertError -v mountPointBase -v devicePathBase -v vmDiskPath -v "term:-l$1" "no existing mount was found for this term."

	local hasErrors=""
	local j=1
	while [ -e "${devicePathBase}p${j}" ]; do
		local mountPoint="$mountPointBase"
		[ -e "${devicePathBase}p2" ] && mountPoint+="-p${j}"
		bgsudo umount "$mountPoint" || hasErrors="yes"
		rmdir "$mountPoint" &>/dev/null
		((j++))
	done

	bgsudo qemu-nbd -d "${devicePathBase}" >/dev/null || hasErrors="yes"

	if [ "$hasErrors" ]; then
		assertError -v mountPointBase -v devicePathBase "Some errors ocurred while un-mounting the image. See the msgs above. You can rerun this command after fixing the situation to clean up whats left. If all else fails, consider rebooting to recover. sorry."
	fi

	bgawk -i -F'|' -v term="${1%p*}" '
		$2==term || $3==term || $4==term || $5==term {
			deleteLine()
		}
	' /tmp/bg-qemu.tmpMntData

	[ ! "$quietFlag" ] && echo "${vmDiskPath##*/} has been completely un-mounted"
}


# usage: qemu_newImage <baseImagePath> <newImagePath>
# create a new vm disk image (<newImagePath>) on top of an existing, generic, readonly cloud image (<baseImagePath>).
# After creating a new qcow2 disk, it sets a new filesystem UUID then updates the root disk image contents with the new UUID
# Mounting:
# This function uses qemu_mount() to connect the image to an available /dev/nbd? device and mount the filsesystems. It leaves the
# image mounted because it is assumed that the the caller will go on to make further changes pursuent to its goals. The caller
# should call 'qemu_umount <newImagePath>' when it is done making its changes.
# Changes:
#    * each partition gets a new UUID
#    * if the partition contains the folders /etc/ and /boot/ all text files are searched to replace the old UUID with the new UUID
# Options:
#    -R|--retVar=<retVar> : <retVar> is the variable name in the caller's scope that will receive the path where the root filesystem
#                           is mounted so that the caller can make further changes.
function qemu_newImage()
{
	local retVar
	while [ $# -gt 0 ]; do case $1 in
		-R*|--retVar*)  bgOptionGetOpt val: retVar "$@" && shift ;;
		*)  bgOptionsEndLoop "$@" && break; set -- "${bgOptionsExpandedOpts[@]}"; esac; shift;
	done

	local baseImagePath="$1"; assertFileExists "$baseImagePath"
	local newImagePath="$2";  assertFileNotExists "$newImagePath"

	which qemu-img &>/dev/null || creqApply cr_packageInstalled qemu-utils || assertError "abort because the qemu-utils package is required and could not be installed"

	# create the image file using the osBaseImage as the backing
	qemu-img create -q -fqcow2 -b "$baseImagePath"  "$newImagePath" || assertError

	local nbdBase
	qemu_mount -q --nbdOnly -R nbdBase "$newImagePath"

	local mountPointBase="${newImagePath}"; [[ "$mountPointBase" =~ [.][^/]*$ ]] && mountPointBase="${mountPointBase%.*}"

	# we loop through and change all the partitions that the image has but we expect that only one will be the root partition
	# containing /boot/ and /etc/ folders that need to be changed. This should work if /boot is on a separate partition but that
	# has not been initially tested.
	# If more than one partition has a /etc/ folder, then the last one iterated will be the the vmRoot returned. We expect that
	# this wont be a problem because there will typically be only one.
	local j=1
	while [ -e "${nbdBase}p${j}" ]; do
		local newUUID="$(uuidgen --time)"
		local fsType oldUUID
		sleep 0.1 # if we call lsblk too quick after connecting the nbd, it fails to return the fsType
		read -r fsType oldUUID < <(lsblk -fs -ln -o FSTYPE,UUID  "${nbdBase}p${j}")
		case $fsType in
			xfs) sudo xfs_admin -U "$newUUID" "${nbdBase}p${j}" >/dev/null || assertError ;;
			*) assertError -v baseImagePath -v fsType "This disk image uses a file system format that is not yet supported. To support it, modify the case statement at '$BASH_SOURCE:$LINENO' to include the command(s) to create and set a new" ;;
		esac

		local mountPoint="$mountPointBase"
		[ -e "${devicePathBase}p2" ] && mountPoint+="-p${j}"

		fsTouch -d -p "$mountPoint/"
		bgsudo mount "${nbdBase}p${j}" "$mountPoint" || assertError -v baseImagePath -v newImagePath -v device:-l"${nbdBase}p${j}" -v mountPoint "could not mount partition's file system"

		# identify the root partition for the caller
		[ -d $mountPoint/etc/ ] && setReturnValue "$retVar" "$mountPoint"

		# change the UUID in the fstab and boot files
		local filename filesToChange
		readarray -t filesToChange < <(sudo grep -rl "$oldUUID"  $mountPoint/{boot,etc})
		[ ${#filesToChange[@]} -gt 0 ] && sudo sed -i 's/'"$oldUUID"'/'"$newUUID"'/g' "${filesToChange[@]}"
		((j++))
	done
}

# usage: vmDisk_makeFreshVMChanges <vmRoot>
# This makes changes to the mounted root filesystem of a VM disk image so that it works with the 'bg-dev tests FreshVMs ...' sub
# system. Note that these changes favor ease of use over security and therefore they are not suitable for using on persistent
# VMs. It is assumed that the resulting disks are deleted and recreated often.
# Changes:
#    * local terminal root login without a password
#    * adds a user on the VM disk which mirrors the user running the command on the host machine. It is assumed that that user is
#      a developer working on packages that will be tested in the new VM.
#      * same name, UID, primaray group and GID
#      * given all sudo right to run sudo without a password
#      * password is empty. supports local terminal login and ssh login.
#    * mounts the $bgVinstalledSandbox folder from the host at the same location inside the VM
#
function vmDisk_makeFreshVMChanges()
{
	local vmName="$1"; assertNotEmpty "vmName"
	local vmRoot="$2"; assertNotEmpty "vmRoot"
	local bgVinstalledSandbox="$3"; assertNotEmpty bgVinstalledSandbox

	vmDisk_addCurrentUserToVM    "$vmRoot"

	# set the hostname
	echo "$vmName"             | bgtee    "${vmRoot:--}/etc/hostname" >/dev/null
	echo "10.0.2.2    devhost" | bgtee -a "${vmRoot:--}/etc/hosts" >/dev/null

	# setup our sandbox to be mounted on guest. (we use nfs instead of p9 because centos does not support 9p)
	fsTouch  -d -u "$USER" -g "$USER"  "$vmRoot/$bgVinstalledSandbox"
	echo '10.0.2.2:'"$bgVinstalledSandbox"' '"$bgVinstalledSandbox"' nfs  defaults,user,exec 0 0' | bgtee -a "${vmRoot:--}/etc/fstab" >/dev/null

	# add the 'ap' alias to $USER's .bashrc to make it easier to start tests
	cat - <<-EOS | bgtee -a "${vmRoot:--}/home/$USER/.bashrc" >/dev/null
		bgDefaultSandbox='$bgVinstalledSandbox'
		alias ap='cd \$bgDefaultSandbox; source ./bg-dev/bg-debugCntr'
		alias apq='cd \$bgDefaultSandbox; source ./bg-dev/bg-debugCntr --quick'
	EOS

	# authorize bg-core development features on this host
	echo "mode=development" | sudo tee "${vmRoot:--}/etc/bgHostProductionMode" >/dev/null

	# the host creates a file .bglocal/${vmName}.booting and we install a startup script on guest that deletes it so the host knows
	# when its safe to call ssh
	vmDisk_addFreshVMReadySignal "$vmName" "$vmRoot" "$bgVinstalledSandbox"
}


function vmDisk_addCurrentUserToVM()
{
	local vmRoot="$1"; assertNotEmpty "vmRoot"

	IFS=: read -r -a userData < <(getent passwd $USER)

	# add the user
	# on centosS9, I could not get the hashed passwords to work consistently accross root/$USER and local terminal and ssh. However,
	# Removing the x from the second field of /etc/passwd worked to allow no pasword logins as long as I
	#     1) turned off SELINUX (it prevented services from starting when there were no password)
	#     2) I enabled sshd to accept a user with no password
	# Also, the ssh key seems correct but its not working on ssh either -- not sur why yet. I will see on other distros
	bgsed -i 's|^root:[^:]*:|root:$1$12345678$xek.CpjQUVgdf/P2N9KQf/:|'                     "${vmRoot:--}/etc/shadow"
	bgsed -i 's|^root:x:|root::|'                                                           "${vmRoot:--}/etc/passwd"
	echo "$USER::${userData[2]}:${userData[2]}:${userData[4]},,,:${userData[5]}:/bin/bash"  | sudo tee -a "${vmRoot:--}/etc/passwd"  >/dev/null
	echo '$USER:$1$12345678$xek.CpjQUVgdf/P2N9KQf/:18421:0:99999:7::'                       | sudo tee -a "${vmRoot:--}/etc/shadow"  >/dev/null
	echo "$USER:x:${userData[2]}:"                                                          | sudo tee -a "${vmRoot:--}/etc/group"   >/dev/null
	echo "$USER ALL=(ALL) NOPASSWD:ALL"                                                     | sudo tee -a "${vmRoot:--}/etc/sudoers" >/dev/null

	# diable SELINUX
	bgsed -i 's/^SELINUX=.*$/SELINUX=disabled/'                                             "${vmRoot:--}/etc/selinux/config"

	# tell sshd to allow empty passwords
	bgsed -i 's/#\?PermitEmptyPasswords.*$/PermitEmptyPasswords yes/'                       "${vmRoot:--}/etc/ssh/sshd_config"

	# make the home folder
	if [ -d "${vmRoot:--}/etc/skel" ]; then
		sudo cp -a "${vmRoot:--}/etc/skel" "${vmRoot:--}/${userData[5]}"
		sudo chown -R $USER:$USER "${vmRoot:--}/${userData[5]}"
	fi
	fsTouch -d -u "${userData[2]}" -g "${userData[2]}"  "${vmRoot:--}/${userData[5]}/"
	fsTouch -d -u "${userData[2]}" -g "${userData[2]}"  "${vmRoot:--}/${userData[5]}/.ssh/"

	if [ ! -f ~/.ssh/identity.pub ]; then
		echo "!!!WARNING: ~/.ssh/identity.pub does not exist so your ssh key is not being set in the vm image"
	else
		cat ~/.ssh/identity.pub >> "${vmRoot:--}/${userData[5]}/.ssh/authorized_keys"
		fsTouch --perm "- rw- --- ---" -u "${userData[2]}" -g "${userData[2]}"  "${vmRoot:--}/${userData[5]}/.ssh/authorized_keys"
	fi
}

# usage: vmDisk_addFreshVMReadySignal <vmName> <vmRoot> <bgVinstalledSandbox>
# the host creates a file .bglocal/${vmName}.booting and this function installs a startup script on guest that deletes it so the
# host knows when its safe to call ssh
function vmDisk_addFreshVMReadySignal()
{
	local vmName="$1"; assertNotEmpty "vmName"
	local vmRoot="$2"; assertNotEmpty "vmRoot"
	local bgVinstalledSandbox="$3"; assertNotEmpty bgVinstalledSandbox

	# add a startup command to rm the semaphore file to signal that the guest is ready
	cat - <<-EOS | bgtee "${vmRoot:--}/etc/systemd/system/signalReadyToDevhost.service" >/dev/null
		[Unit]
		Description=Signal the devhost that we are ready by deleting a file in the $bgVinstalledSandbox
		After=getty.target network-online.target remote-fs.target

		[Service]
		Type=simple
		RemainAfterExit=yes
		ExecStart=/usr/bin/rm "$bgVinstalledSandbox/.bglocal/${vmName}.booting"
		TimeoutStartSec=0

		[Install]
		WantedBy=default.target
	EOS
	fsTouch -d "${vmRoot:--}/etc/systemd/system/default.target.wants"
	bgsudo ln -s  "../signalReadyToDevhost.service"  "${vmRoot:--}/etc/systemd/system/default.target.wants/signalReadyToDevhost.service"

}
