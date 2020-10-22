#!/usr/bin/env bash

sysLibPath="/usr/lib"
sysBinPath="/usr/bin"

# decide if the user needs sudo to run the commands in this script
preCmd=''; [ ! -w "$sysLibPath" ] && preCmd="sudo "


baseDir="$(dirname "$BASH_SOURCE")"
baseDir="$(cd "$baseDir"; pwd)"
pkgName="${baseDir##*/}"
uninstScript="${sysLibPath}/bg-uninstall-${pkgName}"


# if there is a $uninstScript installed, call it to remove the last version before we install the current version.
# this makes it clean when we remove or rename files in this library so that we dont leave obsolete files in the system
[ -x "${uninstScript}" ] && "${uninstScript}"

### Start the $uninstScript script
sudo bash -c 'cat >"'"${uninstScript}"'"  <<EOS
#!/usr/bin/env bash
sysLibPath="/usr/lib"
sysBinPath="/usr/bin"
preCmd=""; [ ! -w "$sysLibPath" ] && preCmd="sudo "
EOS'
$preCmd chmod a+x "${uninstScript}"


### Install Libs
libsToInstall=$(find -H "$baseDir" -name "bg_*.sh" -printf "%P\n")
for libname in ${libsToInstall}; do
	$preCmd cp "${baseDir}/${libname}" "${sysLibPath}/${libname}"
	# record the uninstall command for this libname in the $uninstScript script
	echo '$preCmd'" rm '${sysLibPath}/${libname}'" | $preCmd tee -a  "${uninstScript}" >/dev/null
done


### Install Cmds
cmdsToInstall=$(find -H "$baseDir" -name "bg-*" -printf "%P\n")
for cmdname in ${cmdsToInstall}; do
	if [ ! -x "${baseDir}/${cmdname}" ]; then
		echo "warning: command ${cmdname} is not executable. skiping it."
		continue
	fi
	$preCmd cp "${baseDir}/${cmdname}" "${sysBinPath}/${cmdname}"
	# record the uninstall command for this cmdname in the $uninstScript script
	echo '$preCmd'" rm '${sysBinPath}/${cmdname}'" | $preCmd tee -a  "${uninstScript}" >/dev/null
done


### Finish the $uninstScript script
echo '$preCmd'" rm '${uninstScript}'" | $preCmd tee -a  "${uninstScript}" >/dev/null
$preCmd chmod a+x "${uninstScript}"
