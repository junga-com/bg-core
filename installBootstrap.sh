#!/usr/bin/env bash

sysLibPath="/usr/lib"

# decide if the user needs sudo to run the commands in this script
preCmd=''; [ ! -w "$sysLibPath" ] && preCmd="sudo "


baseDir="$(dirname "$BASH_SOURCE")"
baseDir="$(cd "$baseDir"; pwd)"


# if there is a bg-uninstallBootstrap installed, call it to remove the last version before we install the current version.
# this makes it clean when we remove or rename files in this library so that we dont leave obsolete files in the system
[ -x "${sysLibPath}/bg-uninstallBootstrap" ] && "${sysLibPath}/bg-uninstallBootstrap"

libsToInstall=$(find -H "$baseDir" -name "bg_*.sh" -printf "%P\n")

sudo bash -c 'cat >"'"${sysLibPath}"'/bg-uninstallBootstrap"  <<EOS
#!/usr/bin/env bash
sysLibPath="/usr/lib"
preCmd=""; [ ! -w "$sysLibPath" ] && preCmd="sudo "
EOS'
$preCmd chmod a+x "${sysLibPath}/bg-uninstallBootstrap"

for libname in ${libsToInstall}; do
	$preCmd cp "${baseDir}/${libname}" "${sysLibPath}/${libname}"
	# record the uninstall command for this libname in the bg-uninstallBootstrap script
	echo "$preCmd rm '${sysLibPath}/${libname}'" | $preCmd tee -a  "${sysLibPath}/bg-uninstallBootstrap" >/dev/null
done
echo "$preCmd rm '${sysLibPath}/bg-uninstallBootstrap'" | $preCmd tee -a  "${sysLibPath}/bg-uninstallBootstrap" >/dev/null
$preCmd chmod a+x "${sysLibPath}/bg-uninstallBootstrap"
